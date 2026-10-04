import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// The glow a finger raises on a pressed glass surface, in one frame.
///
/// UIKit lights a pressed tab bar with two glows of its flex interaction,
/// both color matrices over what lies behind them rather than paint of
/// their own: a wash across the whole surface that adds [wash] to every
/// color channel, and a soft spot under the finger that multiplies the
/// channels by [factorAt] - most at [center], fading as a Gaussian of
/// standard deviation [radius]. Both stay inside the surface's shape and
/// under the control's content. A [MorphGlassPainter] draws them with
/// `buildGlow`; the default paints them with additive and color-dodge
/// blending, exact for gray backdrops.
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

/// Paints [glow] inside [shape], both in the painted box's coordinates,
/// over what the canvas already holds.
@internal
void morphPaintGlassGlow(Canvas canvas, RRect shape, MorphGlassGlow glow) {
  if (!glow.isVisible) return;
  canvas.save();
  canvas.clipRRect(shape);
  if (glow.wash > 0) {
    final wash = Paint();
    wash.blendMode = BlendMode.plus;
    wash.color = Color.fromRGBO(255, 255, 255, glow.wash.clamp(0.0, 1.0));
    canvas.drawRect(shape.outerRect, wash);
  }
  if (glow.gain > 0 && glow.radius > 0) {
    final reach = 3 * glow.radius;
    final spot = Paint();
    spot.blendMode = BlendMode.colorDodge;
    spot.shader = _spotShader(glow.radius, glow.gain);
    canvas.save();
    canvas.translate(glow.center.dx, glow.center.dy);
    canvas.drawRect(
      shape.outerRect
          .shift(-glow.center)
          .intersect(Rect.fromCircle(center: Offset.zero, radius: reach)),
      spot,
    );
    canvas.restore();
  }
  canvas.restore();
}

final Map<(double, double), Shader> _spotShaders = {};

Shader _spotShader(double radius, double gain) {
  final key = (radius, gain);
  final cached = _spotShaders[key];
  if (cached != null) return cached;
  const stops = 16;
  final colors = <Color>[];
  final positions = <double>[];
  for (var i = 0; i <= stops; i++) {
    final p = i / stops;
    final factor = 1 + gain * math.exp(-0.5 * 9 * p * p);
    final dodge = 1 - 1 / factor;
    colors.add(Color.from(alpha: 1, red: dodge, green: dodge, blue: dodge));
    positions.add(p);
  }
  final shader = RadialGradient(
    colors: colors,
    stops: positions,
  ).createShader(Rect.fromCircle(center: Offset.zero, radius: 3 * radius));
  if (_spotShaders.length == 4) _spotShaders.remove(_spotShaders.keys.first);
  _spotShaders[key] = shader;
  return shader;
}

/// Paints a surface's glow in a box placed at the surface's bounds.
@internal
class MorphGlassGlowPainter extends CustomPainter {
  /// Paints [glow] inside [shape], both relative to the painted box.
  const MorphGlassGlowPainter(this.shape, this.glow);

  /// The outline that clips the glow.
  final RRect shape;

  /// The glow to paint.
  final MorphGlassGlow glow;

  @override
  void paint(Canvas canvas, Size size) =>
      morphPaintGlassGlow(canvas, shape, glow);

  @override
  bool shouldRepaint(MorphGlassGlowPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.glow != glow;
}

/// The touch glow of a pressed glass bar as a function of time: UIKit's
/// flex interaction glows on iOS 27's tab bar, measured on an iPhone.
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
/// tall bar peaks at 0.845 and 0.2845.
class MorphTouchGlowMotion {
  /// Creates a resting glow with the peaks of a surface's flex spec.
  MorphTouchGlowMotion({required this.washPeak, required this.spotPeak});

  /// The opacity the wash rises to.
  final double washPeak;

  /// The opacity the spot rises to.
  final double spotPeak;

  /// The spring the glows rise on.
  static const riseSpring = MorphSpring(0.1, 1);

  /// The spring the glows fall, grow and turn dragging on.
  static const fallSpring = MorphSpring(0.5, 1);

  /// How long after the touch the glows start to rise, in seconds.
  static const double riseLag = 0.042;

  /// How long after the release the glows start to fall, in seconds.
  static const double releaseLag = 0.02;

  /// The diameter of the spot before it grows, in pixels.
  static const double diameter = 93;

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
  /// 3 in the dark appearance, 0.667 in the light one.
  static double spotGain(Brightness brightness) => switch (brightness) {
    Brightness.dark => 3,
    Brightness.light => 0.667,
  };

  final MorphSpringState _progress = MorphSpringState(riseSpring, 0);
  final MorphSpringState _scale = MorphSpringState(fallSpring, 1);
  final MorphSpringState _strength = MorphSpringState(fallSpring, 1);
  Offset _center = Offset.zero;
  Offset? _down;
  bool _dragging = false;
  final MorphTimeline _timeline = MorphTimeline();

  /// The center of the spot, in the pointer's coordinates.
  Offset get center => _center;

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
    final start = t + riseLag;
    _timeline.insert(
      start,
      (at) => _progress.retarget(at, 1, spring: riseSpring),
    );
  }

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
    final start = t + releaseLag;
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

  /// Whether nothing is left to animate at time [t].
  bool isSettled(double t) {
    _due(t);
    return _down == null &&
        _timeline.isEmpty &&
        _progress.isAtRest(t, 0.002) &&
        washOpacity(t) == 0 &&
        spotOpacity(t) == 0;
  }
}
