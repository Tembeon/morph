import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
import 'package:meta/meta.dart';

@internal
mixin TransformTrackingRenderObjectMixin on RenderProxyBox {
  @override
  GeometryTransformTrackingLayer? get layer =>
      super.layer as GeometryTransformTrackingLayer?;

  @override
  @nonVirtual
  bool get isRepaintBoundary => false;

  @override
  bool get alwaysNeedsCompositing => true;

  /// Transform compared across frames to decide whether [onTransformChanged]
  /// should fire. Defaults to the world transform.
  Matrix4 trackedTransform() => getTransformTo(null);

  @mustCallSuper
  @override
  void paint(PaintingContext context, ui.Offset offset) {
    setUpLayer(offset);
    context.pushLayer(layer!, (context, offset) {}, offset);
    super.paint(context, offset);
  }

  GeometryTransformTrackingLayer setUpLayer(Offset offset) {
    return (layer ??= GeometryTransformTrackingLayer())
      ..renderObject = this
      ..trackedTransform = trackedTransform
      ..onTransformChanged = () {
        if (attached) _whileCompositing(onTransformChanged);
      }
      ..onCompositing = () {
        if (attached) _whileCompositing(onCompositing);
      };
  }

  bool _compositing = false;

  void _whileCompositing(VoidCallback hook) {
    _compositing = true;
    try {
      hook();
    } finally {
      _compositing = false;
    }
  }

  /// Marks this object for paint; asked for from [onTransformChanged] or
  /// [onCompositing], it also asks for the frame that paints it.
  ///
  /// Those hooks run after the frame's paint, while the scheduler is still
  /// in its persistent callbacks, where a paint request schedules no frame:
  /// without one the request waits for whatever repaints next, and a layer
  /// that asked to show a shape that just joined it shows nothing until
  /// then.
  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    if (_compositing) SchedulerBinding.instance.scheduleFrame();
  }

  void onTransformChanged();

  /// Runs every time this tracking layer is composited, including frames where
  /// the tracked transform is unchanged.
  void onCompositing() {}
}

@internal
class GeometryTransformTrackingLayer extends OffsetLayer {
  GeometryTransformTrackingLayer();

  RenderObject? renderObject;
  Matrix4 Function()? trackedTransform;
  VoidCallback? onTransformChanged;
  VoidCallback? onCompositing;
  Matrix4? _lastTransform;

  @override
  void updateSubtreeNeedsAddToScene() {
    // Resolve retained transforms after layout and paint, but before Flutter
    // propagates retained-rendering dirtiness and submits any engine layers.
    // Updating an effect from addToScene is too late: a containing layer may
    // already have been selected for retained rendering.
    final renderObject = this.renderObject;
    if (renderObject != null && renderObject.attached) {
      final currentTransform =
          trackedTransform?.call() ?? renderObject.getTransformTo(null);
      if (!MatrixUtils.matrixEquals(currentTransform, _lastTransform)) {
        onTransformChanged?.call();
        _lastTransform = currentTransform;
      }
      onCompositing?.call();
    }
    super.updateSubtreeNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    // A glass layer that rendered a matte this frame changed its effect
    // layers, so its subtree is added again and passes through here before
    // the effect that samples the matte; an unchanged subtree is retained
    // and has nothing pending.
    FlutterGpuGeometryRenderer.flushPendingSubmissions();
  }
}

/// Remembers whether a glass layer polled its shapes' transforms while the
/// current frame painted, so its compositing hook can skip a second poll.
///
/// Nothing between paint and compositing in one frame moves a render object,
/// so that poll would only find the transforms paint just recorded.
@internal
class FramePollMarker {
  bool _polled = false;

  /// Whether this frame's paint already polled.
  bool get polledThisFrame => _polled;

  /// Records a poll made during the current frame's paint. Polls outside a
  /// frame, such as `toImage` captures, are not recorded.
  void markPolled() {
    if (_polled ||
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      return;
    }
    _polled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _polled = false);
  }
}
