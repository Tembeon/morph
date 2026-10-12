import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/internal/ancestor_clip.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';
import 'package:morph/src/glass/renderer/internal/blur_reach.dart';

/// Whether package chrome composes its backdrop readers in a
/// [GlassBackdropRegion] (prototype, `MORPH_BACKDROP_REGIONS`); off keeps
/// one full-screen backdrop read per reader.
bool debugMorphBackdropRegions = const bool.fromEnvironment(
  'MORPH_BACKDROP_REGIONS',
);

/// One backdrop read for every backdrop reader in [child].
///
/// While [seeded] reports true, the region copies the backdrop inside
/// [clip] into a pass of its own (one read of the whole pass it sits in),
/// and every backdrop filter painted in [child] - a blur, a glass layer -
/// reads that pass instead of the whole screen: its read costs the
/// region's area, not the screen's. Readers inside see what they saw
/// without the region as long as they sample inside [clip].
///
/// Glass in the region drops its backdrop key: a key shared with glass
/// outside would hand it a copy of another pass.
@internal
class GlassBackdropRegion extends SingleChildRenderObjectWidget {
  /// Composes the readers in [child] in one region.
  const GlassBackdropRegion({
    required this.clip,
    required this.seeded,
    required this.repaint,
    required super.child,
    super.key,
  });

  /// The region in the widget's own coordinates, given its size.
  final Rect Function(Size size) clip;

  /// Whether the region takes its read now; asked whenever [repaint]
  /// notifies.
  final bool Function() seeded;

  /// Notifies when [seeded] may have changed.
  final Listenable repaint;

  @override
  RenderGlassBackdropRegion createRenderObject(BuildContext context) =>
      RenderGlassBackdropRegion(clip: clip, seeded: seeded, repaint: repaint);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassBackdropRegion renderObject,
  ) {
    renderObject.clip = clip;
    renderObject.seeded = seeded;
    renderObject.repaint = repaint;
  }
}

/// The render object of [GlassBackdropRegion].
@internal
class RenderGlassBackdropRegion extends RenderProxyBox {
  /// Creates the region.
  RenderGlassBackdropRegion({
    required this._clip,
    required this._seeded,
    required this._repaint,
  });

  /// The nearest region above [node] that takes its read in the current
  /// frame, or null.
  static RenderGlassBackdropRegion? seededAbove(RenderObject node) {
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (parent is RenderGlassBackdropRegion) {
        return parent._active ? parent : null;
      }
    }
    return null;
  }

  Rect Function(Size size) _clip;

  /// See [GlassBackdropRegion.clip].
  Rect Function(Size size) get clip => _clip;
  set clip(Rect Function(Size size) value) {
    if (identical(value, _clip)) return;
    _clip = value;
    if (_active) _repaintReaders();
  }

  /// The region in local coordinates.
  Rect get region => _clip(size);

  bool Function() _seeded;

  /// See [GlassBackdropRegion.seeded].
  bool Function() get seeded => _seeded;
  set seeded(bool Function() value) {
    _seeded = value;
    _sync();
  }

  Listenable _repaint;

  /// See [GlassBackdropRegion.repaint].
  Listenable get repaint => _repaint;
  set repaint(Listenable value) {
    if (identical(value, _repaint)) return;
    if (attached) {
      _repaint.removeListener(_sync);
      value.addListener(_sync);
    }
    _repaint = value;
    _sync();
  }

  bool _active = false;

  final _clipLayer = LayerHandle<ClipRectLayer>();
  final _seedLayer = LayerHandle<BackdropFilterLayer>();

  bool get _wants => debugMorphBackdropRegions && _seeded();

  void _sync() {
    final wants = _wants;
    if (wants == _active) return;
    _active = wants;
    markNeedsCompositingBitsUpdate();
    _repaintReaders();
  }

  // A reader's filter coordinates and key depend on whether the region
  // takes its read, and readers are repaint boundaries of their own.
  void _repaintReaders() {
    markNeedsPaint();
    void visit(RenderObject child) {
      if (child.isRepaintBoundary) child.markNeedsPaint();
      child.visitChildren(visit);
    }

    visitChildren(visit);
  }

  /// The screen origin of the region's pass, which the filters inside see
  /// as their fragment origin: Impeller bounds the pass by [clip] and every
  /// clip above it, rounded out to device pixels.
  Offset passOrigin(double devicePixelRatio) {
    var screen = MatrixUtils.transformRect(getTransformTo(null), region);
    if (screenClipAbove(this) case final above?) {
      screen = screen.intersect(above);
    }
    return Offset(
      (screen.left * devicePixelRatio).floorToDouble() / devicePixelRatio,
      (screen.top * devicePixelRatio).floorToDouble() / devicePixelRatio,
    );
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(_sync);
    _active = _wants;
  }

  @override
  void detach() {
    _repaint.removeListener(_sync);
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _seedLayer.layer = null;
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => _active;

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _active ? region : null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_active) {
      _clipLayer.layer = null;
      _seedLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    final seed = _seedLayer.layer ??= BackdropFilterLayer(
      filter: morphBackdropSeed,
      blendMode: BlendMode.src,
    );
    GlassLayerOwners.note(seed, this);
    _clipLayer.layer = context.pushClipRect(
      true,
      offset,
      region,
      (context, offset) => context.pushLayer(seed, super.paint, offset),
      oldLayer: _clipLayer.layer,
    );
  }
}
