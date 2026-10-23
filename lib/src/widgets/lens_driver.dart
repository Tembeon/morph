import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/control_host.dart';

import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/typography.dart';

/// The deformed lens outline in [size], mirrored for [rtl].
@internal
RRect morphLensShape(MorphLensMotion motion, Size size, {required bool rtl}) {
  final lensSize = motion.size;
  final width = lensSize.width * motion.scaleX;
  final height = lensSize.height * motion.scaleY;
  final center = rtl ? size.width - motion.center : motion.center;
  return RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(center, size.height / 2),
      width: width,
      height: height,
    ),
    Radius.circular(math.min(width, height) / 2),
  );
}

/// Measures a resolved control label at [scaler], disposing its painter.
@internal
double morphLensLabelWidth(
  String text,
  TextStyle style,
  TextScaler scaler, {
  BuildContext? context,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: MorphTypography.resolve(style, context: context),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  );
  painter.layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The measured widths of a control's labels, kept until an input
/// changes.
@internal
class MorphLabelWidths {
  List<String> _labels = const [];
  List<TextStyle> _styles = const [];
  TextScaler? _scaler;
  bool? _apple;
  List<double> _widths = const [];

  /// The width of each of [labels] at [scaler], the widest over [styles];
  /// measured again only when a label, a style, the scaler or the
  /// platform's system font changes.
  List<double> of(
    List<String> labels,
    List<TextStyle> styles,
    TextScaler scaler, {
    BuildContext? context,
  }) {
    final resolved = [
      for (final style in styles)
        MorphTypography.resolve(style, context: context),
    ];
    final apple = MorphTypography.usesAppleSystemFont;
    if (_scaler == scaler &&
        _apple == apple &&
        listEquals(_labels, labels) &&
        listEquals(_styles, resolved)) {
      return _widths;
    }
    _labels = List.of(labels);
    _styles = resolved;
    _scaler = scaler;
    _apple = apple;
    return _widths = [
      for (final label in labels)
        resolved.fold<double>(
          0,
          (widest, style) =>
              math.max(widest, morphLensLabelWidth(label, style, scaler)),
        ),
    ];
  }
}

/// Drives a [MorphLensMotion] from a [MorphControlHost].
@internal
mixin MorphLensDriver<T extends StatefulWidget> on MorphControlHost<T> {
  /// The motion this state drives; created by the host.
  MorphLensMotion get motion;

  /// Converts a pointer's local position to a coordinate along the track.
  double trackPosition(Offset local);

  @override
  void advanceMotion(double t) => motion.advance(t);

  @override
  bool get motionSettled => motion.isSettled;

  @override
  void settleMotion() => motion.settle();

  /// Reconciles a user selection with the parent's current [selected]
  /// after callbacks and the resulting rebuild have finished.
  void reconcileSelection(int Function() selected) => reconcileAfterFrame(() {
    final index = selected();
    if (motion.selected == index) return false;
    motion.select(clock, index, notify: false);
    setState(() {});
    return true;
  });

  @override
  void onControlDown(double t, PointerDownEvent event) => motion.pointerDown(
    t,
    trackPosition(event.localPosition),
    y: event.localPosition.dy,
  );

  @override
  void onControlMove(double t, PointerMoveEvent event) => motion.pointerMove(
    t,
    trackPosition(event.localPosition),
    y: event.localPosition.dy,
  );

  @override
  void onControlUp(double t, PointerUpEvent event) => motion.pointerUp(
    t,
    trackPosition(event.localPosition),
    y: event.localPosition.dy,
  );

  @override
  void onControlCancel(double t) => motion.pointerCancel(t);
}
