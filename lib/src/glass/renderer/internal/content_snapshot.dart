import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// A painted content source shared by the lens copies in one control.
@internal
class GlassContentSnapshot {
  ui.Picture? _picture;
  ui.Image? _image;
  Size _size = Size.zero;

  /// Replays the source without mounting or laying out another subtree.
  void paint(Canvas canvas) {
    if (_picture case final picture?) {
      canvas.drawPicture(picture);
    } else if (_image case final image?) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & _size,
        Paint(),
      );
    }
  }

  void _capture(OffsetLayer layer, Size size, double pixelRatio) {
    _dispose();
    _size = size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    bool replay(ContainerLayer parent) {
      for (
        var child = parent.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        if (child is PictureLayer) {
          if (child.picture case final picture?) canvas.drawPicture(picture);
        } else if (child is OffsetLayer && child.runtimeType == OffsetLayer) {
          canvas.save();
          canvas.translate(child.offset.dx, child.offset.dy);
          final supported = replay(child);
          canvas.restore();
          if (!supported) return false;
        } else {
          return false;
        }
      }
      return true;
    }

    final supported = replay(layer);
    final picture = recorder.endRecording();
    if (supported) {
      _picture = picture;
    } else {
      picture.dispose();
      final offset = layer.offset;
      layer.offset = Offset.zero;
      _image = layer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
      layer.offset = offset;
    }
  }

  void _dispose() {
    _picture?.dispose();
    _picture = null;
    _image?.dispose();
    _image = null;
  }
}

/// Mounts the consumer's content once and records its current paint.
@internal
class GlassContentSource extends SingleChildRenderObjectWidget {
  /// Associates [snapshot] with the single live [child].
  const GlassContentSource({
    required this.snapshot,
    required this.capture,
    required super.child,
    super.key,
  });

  /// The replay source of the lifted lenses.
  final GlassContentSnapshot snapshot;

  /// Whether a lifted lens needs the current paint recorded.
  final bool capture;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderContentSource(
    snapshot,
    MediaQuery.devicePixelRatioOf(context),
    capture: capture,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    final source = renderObject as _RenderContentSource;
    if (!identical(source.snapshot, snapshot)) {
      source.snapshot._dispose();
      source.snapshot = snapshot;
    }
    source.pixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (source.capture != capture) {
      source.capture = capture;
      source.markNeedsCompositingBitsUpdate();
    }
    source.markNeedsPaint();
  }
}

class _RenderContentSource extends RenderProxyBox {
  _RenderContentSource(this.snapshot, this.pixelRatio, {required this.capture});

  GlassContentSnapshot snapshot;
  double pixelRatio;
  bool capture;
  final LayerHandle<OffsetLayer> _capture = LayerHandle<OffsetLayer>();

  @override
  bool get alwaysNeedsCompositing => capture;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!capture) {
      super.paint(context, offset);
      return;
    }
    final captured = _capture.layer ??= OffsetLayer();
    captured.offset = offset;
    context.pushLayer(captured, super.paint, Offset.zero);
    snapshot._capture(captured, size, pixelRatio);
  }

  @override
  void dispose() {
    snapshot._dispose();
    _capture.layer = null;
    super.dispose();
  }
}
