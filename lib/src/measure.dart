import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Lays its child out under [childConstraints] instead of the incoming
/// ones, sizes itself to the child within what the parent allows,
/// aligns the child by [alignment] when the two differ, and reports
/// the child's laid-out size through [onSize] whenever it changes.
///
/// The report is delivered AFTER the frame that laid the child out,
/// never inside layout: a report typically retargets a spring or
/// rebuilds an owner, and neither is legal mid-layout. Consumers see
/// the size one frame late by construction; the springs they drive
/// with it take many frames, so the lag never shows.
@internal
class MorphContentMeasure extends SingleChildRenderObjectWidget {
  /// Creates the measuring box.
  const MorphContentMeasure({
    super.key,
    required this.childConstraints,
    this.alignment = Alignment.topCenter,
    this.onSize,
    super.child,
  });

  /// The constraints the child is laid out under.
  final BoxConstraints childConstraints;

  /// Where the child sits when its size differs from this box's.
  final AlignmentGeometry alignment;

  /// Receives the child's size after the frame that laid it out, on
  /// every change; null disables reporting.
  final ValueChanged<Size>? onSize;

  @override
  RenderMorphContentMeasure createRenderObject(BuildContext context) {
    return RenderMorphContentMeasure(
      childConstraints: childConstraints,
      alignment: alignment,
      textDirection: Directionality.maybeOf(context),
      onSize: onSize,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMorphContentMeasure renderObject,
  ) {
    renderObject.childConstraints = childConstraints;
    renderObject.alignment = alignment;
    renderObject.textDirection = Directionality.maybeOf(context);
    renderObject.onSize = onSize;
  }
}

/// The render object of [MorphContentMeasure].
@internal
class RenderMorphContentMeasure extends RenderAligningShiftedBox {
  /// Creates the measuring render box.
  RenderMorphContentMeasure({
    required this._childConstraints,
    required super.alignment,
    required super.textDirection,
    this.onSize,
  });

  /// The constraints the child is laid out under.
  BoxConstraints get childConstraints => _childConstraints;
  BoxConstraints _childConstraints;
  set childConstraints(BoxConstraints value) {
    if (_childConstraints == value) {
      return;
    }
    _childConstraints = value;
    markNeedsLayout();
  }

  /// Receives the child's size after the frame that laid it out.
  ValueChanged<Size>? onSize;

  Size? _laidOut;
  Size? _reported;
  bool _reportScheduled = false;

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints, parentUsesSize: true);
    size = constraints.constrain(child.size);
    alignChild();
    _noteChildSize(child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final RenderBox? child = this.child;
    if (child == null) {
      return constraints.smallest;
    }
    return constraints.constrain(child.getDryLayout(_childConstraints));
  }

  void _noteChildSize(Size laidOut) {
    _laidOut = laidOut;
    if (onSize == null || laidOut == _reported || _reportScheduled) {
      return;
    }
    _reportScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _reportScheduled = false;
      final Size? latest = _laidOut;
      if (!attached || latest == null || latest == _reported) {
        return;
      }
      _reported = latest;
      onSize?.call(latest);
    });
  }
}
