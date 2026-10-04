import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Renderer approximations with no UIKit measurement behind them.
@internal
abstract final class MorphGlassDefaults {
  /// Engineering default, not measured: lift span of materialization.
  static const glassLiftSpan = 0.25;

  /// Engineering default, not measured: extra glint at full lift.
  static const liftedHighlight = 0.5;

  /// Engineering default, not measured: frosted chrome blur sigma.
  static const chromeFrost = 14.0;

  /// Engineering default, not measured: frosted button blur sigma.
  static const buttonFrost = 10.0;

  /// Engineering default, not measured: frosted track blur sigma.
  static const trackFrost = 8.0;

  /// Engineering default, not measured: floating-surface base blur sigma.
  static const floatingFrost = 2.0;

  /// Engineering default, not measured: resting frosted highlight alpha.
  static const frostHighlight = 0.18;

  /// Engineering default, not measured: lift's extra frosted highlight alpha.
  static const frostLiftHighlight = 0.22;

  /// Engineering default, not measured: frosted rim stroke width.
  static const frostRimWidth = 0.5;

  /// Engineering default, not measured: dark frosted rim alpha.
  static const darkFrostRim = 0.22;

  /// Engineering default, not measured: light frosted rim alpha.
  static const lightFrostRim = 0.55;

  /// Engineering default, not measured: fused frosted rim width.
  static const bodyRimWidth = 1.0;

  /// Engineering default, not measured: dark fused frosted rim color.
  static const darkBodyRim = Color(0x38FFFFFF);

  /// Engineering default, not measured: light fused frosted rim color.
  static const lightBodyRim = Color(0x8CFFFFFF);

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
