import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:morph/src/liquid_field.dart';
import 'package:morph/src/motion.dart';

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
///       MorphTheme(motion: MorphMotion.fast, skinStyle: MorphSkinStyle.goo),
///     ],
///   ),
/// )
/// ```
///
/// Note the scope of this class: it holds ENGINE defaults (motion,
/// landing bump, scrim, liquid knobs). An app's surface vocabulary
/// (pill/card/fab specs) belongs in the app's own ThemeExtension as
/// [MorphSurfaceSpec] values - the engine cannot know those names.
@immutable
class MorphTheme extends ThemeExtension<MorphTheme> {
  /// Creates the extension; null fields fall through to built-ins.
  const MorphTheme({
    this.motion,
    this.bumpScale,
    this.bumpRecoil,
    this.maxScrimOpacity,
    this.skinStyle,
  });

  /// The default motion profile for flights launched without an
  /// explicit `motion`.
  final MorphMotion? motion;

  /// Default landing-bump knobs for [MorphTag]s that do not declare
  /// their own.
  final double? bumpScale;

  /// Default landing kick-off distance in px.
  final double? bumpRecoil;

  /// Default scrim ceiling for flights.
  final double? maxScrimOpacity;

  /// Default knob bundle for [MorphSkin]s without a style or explicit
  /// knobs.
  final MorphSkinStyle? skinStyle;

  /// The extension from the ambient [ThemeData], if installed.
  static MorphTheme? maybeOf(BuildContext context) =>
      Theme.of(context).extension<MorphTheme>();

  @override
  MorphTheme copyWith({
    MorphMotion? motion,
    double? bumpScale,
    double? bumpRecoil,
    double? maxScrimOpacity,
    MorphSkinStyle? skinStyle,
  }) {
    return MorphTheme(
      motion: motion ?? this.motion,
      bumpScale: bumpScale ?? this.bumpScale,
      bumpRecoil: bumpRecoil ?? this.bumpRecoil,
      maxScrimOpacity: maxScrimOpacity ?? this.maxScrimOpacity,
      skinStyle: skinStyle ?? this.skinStyle,
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
      bumpScale: lerpDouble(bumpScale, other.bumpScale, t),
      bumpRecoil: lerpDouble(bumpRecoil, other.bumpRecoil, t),
      maxScrimOpacity: lerpDouble(maxScrimOpacity, other.maxScrimOpacity, t),
      skinStyle: t < 0.5 ? skinStyle : other.skinStyle,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MorphTheme &&
        other.motion == motion &&
        other.bumpScale == bumpScale &&
        other.bumpRecoil == bumpRecoil &&
        other.maxScrimOpacity == maxScrimOpacity &&
        other.skinStyle == skinStyle;
  }

  @override
  int get hashCode =>
      Object.hash(motion, bumpScale, bumpRecoil, maxScrimOpacity, skinStyle);
}
