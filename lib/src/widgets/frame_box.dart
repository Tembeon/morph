import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// A child placed, transformed, faded and clipped from state a motion holds,
/// read again on every frame of [frames] without a rebuild.
///
/// The child is built once and sits in a repaint boundary of its own: a
/// frame re-records only this box's layers (opacity, transform, clip) and
/// keeps the child's pictures. A frame whose [size] changed lays the child
/// out again; every other frame only repaints.
///
/// Each callback is read during layout or paint, so it must be a pure
/// read of the motion's current state.
@internal
class MorphFrameBox extends SingleChildRenderObjectWidget {
  /// Creates a box driven by [frames].
  MorphFrameBox({
    required this.frames,
    this.size,
    this.offset,
    this.transform,
    this.opacity,
    this.clip,
    Widget? child,
    super.key,
  }) : super(child: child == null ? null : RepaintBoundary(child: child));

  /// Notifies once per frame the motion advanced.
  final Listenable frames;

  /// The child's size; null gives the child this box's constraints.
  final Size Function()? size;

  /// Where the child's top-left corner sits in this box; null for the
  /// origin.
  final Offset Function()? offset;

  /// A transform applied about the child's top-left corner after [offset];
  /// null for none.
  final Matrix4 Function()? transform;

  /// The child's opacity, 0 to 1; at 0 the child neither paints nor takes
  /// hits. Null for 1.
  final double Function()? opacity;

  /// A rounded rect the child is clipped to, in the child's coordinates;
  /// null for no clip.
  final RRect Function()? clip;

  @override
  RenderMorphFrameBox createRenderObject(BuildContext context) =>
      RenderMorphFrameBox(
        frames: frames,
        size: size,
        offset: offset,
        transform: transform,
        opacity: opacity,
        clip: clip,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMorphFrameBox renderObject,
  ) {
    renderObject.frames = frames;
    renderObject.sizeOf = size;
    renderObject.offsetOf = offset;
    renderObject.transformOf = transform;
    renderObject.opacityOf = opacity;
    renderObject.clipOf = clip;
  }
}

/// The render object of [MorphFrameBox].
@internal
class RenderMorphFrameBox extends RenderProxyBox {
  /// Creates the box.
  RenderMorphFrameBox({
    required this._frames,
    Size Function()? size,
    Offset Function()? offset,
    Matrix4 Function()? transform,
    double Function()? opacity,
    RRect Function()? clip,
  }) : _sizeOf = size,
       _offsetOf = offset,
       _transformOf = transform,
       _opacityOf = opacity,
       _clipOf = clip;

  Listenable _frames;

  /// See [MorphFrameBox.frames].
  Listenable get frames => _frames;
  set frames(Listenable value) {
    if (identical(value, _frames)) return;
    if (attached) {
      _frames.removeListener(_tick);
      value.addListener(_tick);
    }
    _frames = value;
    _tick();
  }

  Size Function()? _sizeOf;

  /// See [MorphFrameBox.size].
  Size Function()? get sizeOf => _sizeOf;
  set sizeOf(Size Function()? value) {
    if (identical(value, _sizeOf)) return;
    _sizeOf = value;
    markNeedsLayout();
  }

  Offset Function()? _offsetOf;

  /// See [MorphFrameBox.offset].
  Offset Function()? get offsetOf => _offsetOf;
  set offsetOf(Offset Function()? value) {
    if (identical(value, _offsetOf)) return;
    _offsetOf = value;
    markNeedsPaint();
  }

  Matrix4 Function()? _transformOf;

  /// See [MorphFrameBox.transform].
  Matrix4 Function()? get transformOf => _transformOf;
  set transformOf(Matrix4 Function()? value) {
    if (identical(value, _transformOf)) return;
    _transformOf = value;
    markNeedsPaint();
  }

  double Function()? _opacityOf;

  /// See [MorphFrameBox.opacity].
  double Function()? get opacityOf => _opacityOf;
  set opacityOf(double Function()? value) {
    if (identical(value, _opacityOf)) return;
    _opacityOf = value;
    markNeedsPaint();
  }

  RRect Function()? _clipOf;

  /// See [MorphFrameBox.clip].
  RRect Function()? get clipOf => _clipOf;
  set clipOf(RRect Function()? value) {
    if (identical(value, _clipOf)) return;
    _clipOf = value;
    markNeedsPaint();
  }

  Size? _laidOut;
  bool? _shown;

  void _tick() {
    final size = _sizeOf?.call();
    if (size != null && size != _laidOut) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
    final shown = _opacity > 0;
    if (shown != _shown) {
      _shown = shown;
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_opacity > 0) super.visitChildrenForSemantics(visitor);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frames.addListener(_tick);
  }

  @override
  void detach() {
    _frames.removeListener(_tick);
    super.detach();
  }

  @override
  void dispose() {
    _opacityLayer.layer = null;
    _transformLayer.layer = null;
    _clipLayer.layer = null;
    super.dispose();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void performLayout() {
    final child = this.child;
    final size = _sizeOf?.call();
    _laidOut = size;
    if (child != null) {
      child.layout(
        size == null ? constraints : BoxConstraints.tight(size),
        parentUsesSize: size == null,
      );
    }
    this.size = size == null && child != null
        ? constraints.constrain(child.size)
        : constraints.biggest;
  }

  // This box's coordinates to the child's: offset, then transform.
  Matrix4 _childTransform() {
    final offset = _offsetOf?.call() ?? Offset.zero;
    final matrix = Matrix4.translationValues(offset.dx, offset.dy, 0);
    final transform = _transformOf?.call();
    if (transform != null) matrix.multiply(transform);
    return matrix;
  }

  double get _opacity => (_opacityOf?.call() ?? 1).clamp(0.0, 1.0);

  final _opacityLayer = LayerHandle<OpacityLayer>();
  final _transformLayer = LayerHandle<TransformLayer>();
  final _clipLayer = LayerHandle<ClipRRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final alpha = Color.getAlphaFromOpacity(_opacity);
    if (alpha == 0) {
      _opacityLayer.layer = null;
      _transformLayer.layer = null;
      _clipLayer.layer = null;
      return;
    }
    void clipped(PaintingContext context, Offset offset) {
      final clip = _clipOf?.call();
      if (clip == null) {
        _clipLayer.layer = null;
        context.paintChild(child, offset);
        return;
      }
      _clipLayer.layer = context.pushClipRRect(
        true,
        offset,
        clip.outerRect,
        clip,
        (PaintingContext context, Offset offset) =>
            context.paintChild(child, offset),
        oldLayer: _clipLayer.layer,
      );
    }

    void transformed(PaintingContext context, Offset offset) {
      _transformLayer.layer = context.pushTransform(
        true,
        offset,
        _childTransform(),
        clipped,
        oldLayer: _transformLayer.layer,
      );
    }

    if (alpha == 255) {
      _opacityLayer.layer = null;
      transformed(context, offset);
      return;
    }
    _opacityLayer.layer = context.pushOpacity(
      offset,
      alpha,
      transformed,
      oldLayer: _opacityLayer.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_childTransform());
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_opacity == 0) return false;
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _childTransform(),
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) {
        final clip = _clipOf?.call();
        if (clip != null && !clip.contains(position)) return false;
        return child.hitTest(result, position: position);
      },
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clipOf?.call().outerRect;
}
