import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Renderer approximations with no UIKit measurement behind them.
@internal
abstract final class MorphGlassDefaults {
  /// Engineering default, not measured: lift span of materialization.
  static const glassLiftSpan = 0.25;

  /// Engineering default, not measured: extra glint at full lift.
  static const liftedHighlight = 0.5;

  /// Engineering default, not measured: button and menu shadow.
  static const bodyShadow = BoxShadow(
    color: Color(0x14000000),
    offset: Offset(0, 4),
    blurRadius: 16,
  );

  /// Engineering default, not measured: floating platter shadow color.
  static const floatingShadowColor = Color(0x1A000000);

  /// Engineering default, not measured: resting platter shadow offset.
  static const floatingShadowOffset = 1.5;

  /// Engineering default, not measured: lift's extra platter shadow offset.
  static const floatingLiftOffset = 2.0;

  /// Engineering default, not measured: resting platter shadow blur.
  static const floatingShadowBlur = 3.0;

  /// Engineering default, not measured: lift's extra platter shadow blur.
  static const floatingLiftBlur = 6.0;
}
