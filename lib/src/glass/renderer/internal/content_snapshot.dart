import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';

/// A painted content source shared by the lens copies in one control.
@internal
class GlassContentSnapshot {
  /// The captures that fell back to a GPU snapshot because the content
  /// holds a layer the replay cannot copy; debug builds only.
  @visibleForTesting
  static int debugImageFallbackCount = 0;

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
      assert(() {
        debugImageFallbackCount++;
        return true;
      }());
      final offset = layer.offset;
      layer.offset = Offset.zero;
      _image = layer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
      layer.offset = offset;
    }
  }

  /// Takes over [other]'s recording, which stays valid until the source's
  /// content repaints.
  void _adopt(GlassContentSnapshot other) {
    _dispose();
    _picture = other._picture;
    _image = other._image;
    _size = other._size;
    other._picture = null;
    other._image = null;
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
    this.live,
    super.key,
  });

  /// Notifies once per frame of a live lens: while [capture] is on, every
  /// notification records the content again, as a rebuild with [capture]
  /// does.
  final Listenable? live;

  /// The replay source of the lifted lenses.
  final GlassContentSnapshot snapshot;

  /// Whether a lifted lens needs the current paint recorded.
  final bool capture;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final source = _RenderContentSource(
      snapshot,
      MediaQuery.devicePixelRatioOf(context),
      capture: capture,
    );
    source.bindLive(live, source._frame);
    return source;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    final source = renderObject as _RenderContentSource;
    if (!identical(source.snapshot, snapshot)) {
      snapshot._adopt(source.snapshot);
      source.snapshot = snapshot;
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (source.pixelRatio != pixelRatio) {
      source.pixelRatio = pixelRatio;
      source.markNeedsPaint();
    }
    if (source.capture != capture || capture) {
      source.capture = capture;
      source.markNeedsPaint();
    }
    source.bindLive(live, source._frame);
  }
}

class _RenderContentSource extends RenderProxyBox with GlassLiveBinding {
  _RenderContentSource(this.snapshot, this.pixelRatio, {required this.capture});

  void _frame() {
    if (capture) markNeedsPaint();
  }

  GlassContentSnapshot snapshot;
  double pixelRatio;
  bool capture;
  final LayerHandle<OffsetLayer> _capture = LayerHandle<OffsetLayer>();

  @override
  bool get isRepaintBoundary => true;

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
