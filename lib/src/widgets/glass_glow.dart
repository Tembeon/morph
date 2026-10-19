import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:morph/src/motion/spring.dart';
import 'package:morph/src/motion/spring_state.dart';
import 'package:morph/src/motion/timeline.dart';

/// The glow a finger raises on a pressed glass surface, in one frame.
///
/// UIKit lights a pressed tab bar with two glows of its flex interaction,
/// both color matrices over what lies behind them rather than paint of
/// their own: a wash across the whole surface that adds [wash] to every
/// color channel, and a soft spot under the finger that multiplies the
/// channels by [factorAt] - most at [center], fading as a Gaussian of
/// standard deviation [radius]. Both stay inside the surface's shape and
/// under the control's content, and clamp at white: the spot is the color
/// dodge whose white level is `1 - 1 / factorAt`. A [MorphGlassPainter]
/// renders them as part of the surface's glass or not at all; the
/// package's renderer evaluates both in its liquid tier's final glass
/// shader, and its flat and fake tiers draw no glow.
@immutable
class MorphGlassGlow {
  /// Creates a glow description.
  const MorphGlassGlow({
    required this.wash,
    required this.center,
    required this.radius,
    required this.gain,
  });

  /// How much every color channel rises across the whole surface, in
  /// `[0, 1]` units.
  final double wash;

  /// The center of the spot, in the control's local coordinates.
  final Offset center;

  /// The standard deviation of the spot's falloff, in pixels.
  final double radius;

  /// How much the spot brightens its center: there the channels are
  /// multiplied by `1 + gain`.
  final double gain;

  /// Whether the glow changes anything.
  bool get isVisible => wash > 0 || gain > 0;

  /// The factor the spot multiplies the channels by at [distance] pixels
  /// from [center].
  double factorAt(double distance) {
    if (radius <= 0) return 1;
    final r = distance / radius;
    return 1 + gain * math.exp(-0.5 * r * r);
  }

  @override
  bool operator ==(Object other) =>
      other is MorphGlassGlow &&
      other.wash == wash &&
      other.center == center &&
      other.radius == radius &&
      other.gain == gain;

  @override
  int get hashCode => Object.hash(wash, center, radius, gain);
}

/// The touch glow of a pressed glass surface as a function of time:
/// UIKit's flex interaction glows, measured on an iPhone on iOS 27's tab
/// bar and open menu, which share the law and differ in [diameter],
/// [riseLag] and their peaks.
///
/// A touch raises both glows on a critically damped [riseSpring] after
/// [riseLag]; they hold while the finger stays down. A finger that moves
/// [dragDistance] from where it landed turns the spot into its dragging
/// state: twice as wide at half the strength, on [fallSpring]. Lifting
/// the finger lets both glows fall on [fallSpring] after [releaseLag]
/// while the spot spreads to [releaseGrowth] times its size. The spot
/// follows the finger.
///
/// Peaks come from the surface's [MorphFlexSpec] - its big glow opacity
/// for the wash, its little glow opacity for the spot - so a 62 pixel
/// tall bar peaks at 0.845 and 0.2845, and an open menu
/// ([MorphFlexSpec.menu]) at 0 and 0.5.
class MorphTouchGlowMotion {
  /// Creates a resting glow with the peaks of a surface's flex spec.
  MorphTouchGlowMotion({
    required this.washPeak,
    required this.spotPeak,
    required this.diameter,
    required this.riseLag,
    this.minimumLit = 0,
  });

  /// The opacity the wash rises to.
  final double washPeak;

  /// The opacity the spot rises to.
  final double spotPeak;

  /// The spring the glows rise on.
  static const riseSpring = MorphSpring(0.1, 1);

  /// The spring the glows fall, grow and turn dragging on.
  static const fallSpring = MorphSpring(0.5, 1);

  /// How long after the touch the glows start to rise, in seconds.
  final double riseLag;

  /// The tab bar's [riseLag]: fitted to its device rows (tab-bar.md, Spec -
  /// touch glow).
  static const double tabBarRiseLag = 0.042;

  /// The least time, in seconds, the glow rises before a release lets it
  /// fall: a lift sooner than that starts the fall this long after the
  /// rise began. Zero lets the fall follow the lift after [releaseLag].
  final double minimumLit;

  double _riseAt = 0;

  /// How long after the release the glows start to fall, in seconds.
  static const double releaseLag = 0.02;

  /// The diameter of the spot before it grows, in pixels.
  final double diameter;

  /// The tab bar's [diameter]: its LittleGlow layer is a 93 pt disc
  /// (tab-bar.md, Spec - touch glow).
  static const double tabBarDiameter = 93;

  /// How many times its size the spot grows to after a release.
  static const double releaseGrowth = 4;

  /// How many times its size the spot grows to while dragged.
  static const double dragGrowth = 2;

  /// The share of its strength the spot keeps while dragged.
  static const double dragStrength = 0.5;

  /// How far the finger moves from its landing before the spot turns
  /// dragging, in pixels.
  static const double dragDistance = 50;

  /// Each glow's opacity reads zero below this.
  static const double hideBelow = 0.005;

  /// How much the wash adds to every channel at opacity 1: the offset of
  /// its color matrix.
  static const double washOffset = 0.05;

  /// The strength of the spot's center at opacity 1, as a share of its
  /// color matrix's gain.
  static const double spotCore = 0.38;

  /// The spot's Gaussian standard deviation as a share of its diameter.
  static const double spotSpread = 0.568;

  /// The gain of the spot's color matrix over a gray backdrop, less one:
  /// 3 in the dark appearance, 0.667 in the light one. They are the
  /// color-dodge gains `1 / (1 - white) - 1` of UIKit's glow white levels
  /// 0.75 (dark) and 0.4 (light) (read from UIKit, notes private).
  static double spotGain(Brightness brightness) => switch (brightness) {
    Brightness.dark => 3,
    Brightness.light => 0.667,
  };

  /// The glow white level of clear glass in both appearances (read from
  /// UIKit, notes private).
  static const double clearGlassWhite = 0.7;

  /// The glow white level of tinted glass over the tint's luminance:
  /// UIKit lerps from [tintWhiteFrom] to [tintWhiteTo] by luminance to the
  /// power [tintLuminanceExponent] (read from UIKit, notes private).
  static const double tintWhiteFrom = 0.7;

  /// See [tintWhiteFrom].
  static const double tintWhiteTo = 0.25;

  /// See [tintWhiteFrom].
  static const double tintLuminanceExponent = 1.25;

  /// The gain less one of a spot with color-dodge white level [white].
  static double spotGainOfWhite(double white) => 1 / (1 - white) - 1;

  /// The spot's gain less one for a glass surface: tinted glass by its
  /// [tint]'s luminance (UIKit's Rec. 709 weights of the gamma-encoded
  /// channels, times alpha), clear glass by [clearGlassWhite], regular
  /// glass by [spotGain]. Tinted and clear values are read from UIKit, not
  /// measured on a device.
  static double spotGainFor(
    Brightness brightness, {
    Color? tint,
    bool clear = false,
  }) {
    if (tint != null) {
      final luminance =
          (0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b) * tint.a;
      final t = math.pow(luminance.clamp(0.0, 1.0), tintLuminanceExponent);
      return spotGainOfWhite(tintWhiteFrom + (tintWhiteTo - tintWhiteFrom) * t);
    }
    if (clear) return spotGainOfWhite(clearGlassWhite);
    return spotGain(brightness);
  }

  final MorphSpringState _progress = MorphSpringState(riseSpring, 0);
  final MorphSpringState _scale = MorphSpringState(fallSpring, 1);
  final MorphSpringState _strength = MorphSpringState(fallSpring, 1);
  Offset _center = Offset.zero;
  Offset? _down;
  bool _dragging = false;
  final MorphTimeline _timeline = MorphTimeline();

  /// The center of the spot, in the pointer's coordinates.
  Offset get center => _center;

  /// Whether a finger is down.
  bool get isDown => _down != null;

  void _due(double t) => _timeline.runDue(t);

  /// A finger touched at [position] at time [t].
  void pointerDown(double t, Offset position) {
    _due(t);
    _timeline.clear();
    _center = position;
    _down = position;
    _dragging = false;
    _scale.snap(t, 1);
    _strength.snap(t, 1);
    _riseAt = t + riseLag;
    _timeline.insert(_riseAt, _rise);
  }

  void _rise(double at) => _progress.retarget(at, 1, spring: riseSpring);

  /// The finger moved to [position] at time [t].
  void pointerMove(double t, Offset position) {
    _due(t);
    final down = _down;
    if (down == null) return;
    _center = position;
    if (_dragging || (position - down).distance < dragDistance) return;
    _dragging = true;
    final start = t + riseLag;
    _timeline.insert(start, (at) {
      _scale.retarget(at, dragGrowth, spring: fallSpring);
      _strength.retarget(at, dragStrength, spring: fallSpring);
    });
  }

  /// The finger lifted, or its touch was cancelled, at time [t].
  void pointerUp(double t) {
    _due(t);
    if (_down == null) return;
    _down = null;
    _timeline.clear();
    if (minimumLit > 0 && _riseAt > t) _timeline.insert(_riseAt, _rise);
    final start = math.max(t + releaseLag, _riseAt + minimumLit);
    _timeline.insert(start, (at) {
      _progress.retarget(at, 0, spring: fallSpring);
      _scale.retarget(at, releaseGrowth, spring: fallSpring);
    });
  }

  /// Applies the reactions due by time [t].
  void advance(double t) => _due(t);

  /// The wash's opacity at time [t].
  double washOpacity(double t) {
    _due(t);
    final value = washPeak * _progress.value(t).clamp(0.0, 1.0);
    return value < hideBelow ? 0 : value;
  }

  /// The spot's opacity at time [t].
  double spotOpacity(double t) {
    _due(t);
    final value =
        spotPeak * _progress.value(t).clamp(0.0, 1.0) * _strength.value(t);
    return value < hideBelow ? 0 : value;
  }

  /// The spot's scale over [diameter] at time [t].
  double spotScale(double t) {
    _due(t);
    return _scale.value(t);
  }

  /// The glow to paint at time [t] for the [brightness] the control
  /// resolved, with the spot's center moved by [transform].
  MorphGlassGlow? glowAt(
    double t,
    Brightness brightness, {
    Offset Function(Offset)? transform,
  }) {
    final wash = washOpacity(t);
    final spot = spotOpacity(t);
    if (wash == 0 && spot == 0) return null;
    return MorphGlassGlow(
      wash: washOffset * wash,
      center: transform == null ? _center : transform(_center),
      radius: spotSpread * diameter * spotScale(t),
      gain: spotGain(brightness) * spotCore * spot,
    );
  }

  /// Whether nothing is left to animate at time [t]. Under a finger held
  /// still the glow rests lit until the finger moves or lifts.
  bool isSettled(double t) {
    _due(t);
    if (!_timeline.isEmpty || !_progress.isWithin(t, MorphRest.opacity)) {
      return false;
    }
    if (_down != null) {
      return _scale.isWithin(t, MorphRest.scale(diameter)) &&
          _strength.isWithin(t, MorphRest.opacity);
    }
    return washOpacity(t) == 0 && spotOpacity(t) == 0;
  }
}
