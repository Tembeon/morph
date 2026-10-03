import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import 'package:morph/src/liquid_field.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/scrim.dart';

/// Ambient engine defaults as a [ThemeExtension]: "how this app
/// morphs", declared once instead of being threaded through every
/// call site.
///
/// Resolution order everywhere is: explicit parameter > MorphTheme >
/// built-in default. Every field is nullable so partial themes compose
/// (a subtree can override just the motion, inheriting the rest).
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(
///     extensions: const <ThemeExtension<Object?>>[
///       MorphTheme(motion: MorphMotion.glacial, skinStyle: MorphSkinStyle.subtle),
///     ],
///   ),
/// )
/// ```
///
/// Note the scope of this class: it holds ENGINE defaults (motion,
/// scrim, shadow, liquid knobs). An app's surface vocabulary
/// (pill/card/fab specs) belongs in the app's own ThemeExtension as
/// [MorphSurfaceSpec] values - the engine cannot know those names.
@immutable
class MorphTheme extends ThemeExtension<MorphTheme> {
  /// Creates the extension; null fields fall through to built-ins.
  const MorphTheme({
    this.motion,
    this.maxScrimOpacity,
    this.scrimColor,
    this.shadowColor,
    this.skinStyle,
    this.scrimMotion,
  });

  /// The built-in scrim ceiling, used when neither the call nor the
  /// theme sets [maxScrimOpacity].
  static const double defaultMaxScrimOpacity = 0.45;

  /// The built-in scrim hue, used when neither the call nor the theme
  /// sets [scrimColor].
  static const Color defaultScrimColor = Color(0xFF000000);

  /// The built-in shadow color (60 percent black), used by flights and
  /// [MorphSkin] when neither the call nor the theme sets
  /// [shadowColor].
  static const Color defaultShadowColor = Color(0x99000000);

  /// The built-in elevation of a flight's destination surface.
  static const double defaultTargetElevation = 24;

  /// The default motion profile for flights launched without an
  /// explicit `motion`; [MorphMotion.liquid] when unset.
  final MorphMotion? motion;

  /// Default scrim ceiling for flights.
  final double? maxScrimOpacity;

  /// Default scrim color for flights (black when unset).
  ///
  /// The color's own opacity composes with the animated scrim opacity:
  /// the frame drives the dimming (up to [maxScrimOpacity]) and this
  /// color supplies the hue.
  final Color? scrimColor;

  /// Default shadow color, applied verbatim - its opacity is part of
  /// the value.
  ///
  /// Both flights and [MorphSkin] resolve this slot (one builtin, 60%
  /// black, when unset), so the shadow tint holds when a piece launches
  /// a flight.
  final Color? shadowColor;

  /// Default knob bundle for [MorphSkin]s without a style or explicit
  /// knobs.
  final MorphSkinStyle? skinStyle;

  /// Default scrim springs for flights launched without an explicit
  /// `scrimMotion`; null keeps the scrim on the flight value.
  final MorphScrimMotion? scrimMotion;

  /// The extension from the ambient [ThemeData], if installed.
  static MorphTheme? maybeOf(BuildContext context) =>
      Theme.of(context).extension<MorphTheme>();

  @override
  MorphTheme copyWith({
    MorphMotion? motion,
    double? maxScrimOpacity,
    Color? scrimColor,
    Color? shadowColor,
    MorphSkinStyle? skinStyle,
    MorphScrimMotion? scrimMotion,
  }) {
    return MorphTheme(
      motion: motion ?? this.motion,
      maxScrimOpacity: maxScrimOpacity ?? this.maxScrimOpacity,
      scrimColor: scrimColor ?? this.scrimColor,
      shadowColor: shadowColor ?? this.shadowColor,
      skinStyle: skinStyle ?? this.skinStyle,
      scrimMotion: scrimMotion ?? this.scrimMotion,
    );
  }

  @override
  MorphTheme lerp(MorphTheme? other, double t) {
    if (other == null) {
      return this;
    }
    // Discrete values (a motion profile, a named style) switch at the
    // midpoint; the numeric knobs interpolate.
    return MorphTheme(
      motion: t < 0.5 ? motion : other.motion,
      maxScrimOpacity: lerpDouble(maxScrimOpacity, other.maxScrimOpacity, t),
      scrimColor: Color.lerp(scrimColor, other.scrimColor, t),
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t),
      skinStyle: t < 0.5 ? skinStyle : other.skinStyle,
      scrimMotion: t < 0.5 ? scrimMotion : other.scrimMotion,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MorphTheme &&
        other.motion == motion &&
        other.maxScrimOpacity == maxScrimOpacity &&
        other.scrimColor == scrimColor &&
        other.shadowColor == shadowColor &&
        other.skinStyle == skinStyle &&
        other.scrimMotion == scrimMotion;
  }

  @override
  int get hashCode => Object.hash(
    motion,
    maxScrimOpacity,
    scrimColor,
    shadowColor,
    skinStyle,
    scrimMotion,
  );
}
