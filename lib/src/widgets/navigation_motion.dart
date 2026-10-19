import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:morph/src/motion/spring.dart';
import 'package:morph/src/motion/spring_state.dart';

/// The motion of a navigation bar's inline title and its scroll edge
/// effect as content scrolls under the bar.
///
/// When a large title has scrolled under the bar (or, without one, as soon
/// as content does), the inline title fades in while it rises
/// [hiddenOffset] points into place and sharpens from a [hiddenBlur]
/// blur; the edge effect fades in with it. Both run on critically damped
/// springs fitted to recorded drags on iOS 27 (`_UINavigationBarTitle
/// TransitionSpec`: fastDuration 0.45, slowDuration 0.7, blurRadius 4,
/// hiddenYOffset 15): the title appears on [showSpring] and leaves on
/// the slower [hideSpring]; the edge effect follows [edgeSpring] both
/// ways. A content offset set without a finger (a programmatic scroll)
/// switches both at once, as UIKit does.
///
/// The motion settles once every part's remaining swing is below
/// [MorphRest] (0.1 pt, 0.3 device px at 3x; an opacity half an 8-bit
/// step) and snaps onto its targets: invisible, NEAR.
///
/// Times are seconds.
class MorphNavigationTitleMotion {
  /// Creates the motion; [titleVisible] and [scrolledUnder] are the
  /// starting states.
  MorphNavigationTitleMotion({
    bool titleVisible = true,
    bool scrolledUnder = false,
  }) : _title = MorphSpringState(showSpring, titleVisible ? 1 : 0),
       _edge = MorphSpringState(edgeSpring, scrolledUnder ? 1 : 0),
       _titleVisible = titleVisible,
       _scrolledUnder = scrolledUnder;

  /// The spring the inline title appears on (fitted 0.45..0.48 s,
  /// damping 0.98..1.0).
  static const showSpring = MorphSpring(0.45, 1);

  /// The spring the inline title leaves on (fitted 0.68 s, damping 0.98).
  static const hideSpring = MorphSpring(0.7, 1);

  /// The spring the scroll edge effect fades on (fitted 0.34..0.35 s,
  /// damping 1.0; `_UIBarScrollAwaySpec.duration` is 0.35).
  static const edgeSpring = MorphSpring(0.35, 1);

  /// How far below its place the hidden inline title sits.
  static const double hiddenOffset = 15;

  /// The blur of the hidden inline title.
  static const double hiddenBlur = 4;

  final MorphSpringState _title;
  final MorphSpringState _edge;
  bool _titleVisible;
  bool _scrolledUnder;
  double _now = 0;

  /// Whether the platform asks for reduced motion: the title only fades.
  bool reducedMotion = false;

  /// Whether the inline title is shown or on its way in.
  bool get titleVisible => _titleVisible;

  /// Whether content is under the bar.
  bool get scrolledUnder => _scrolledUnder;

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
  }

  /// Shows the inline title from time [t] when [visible], hides it
  /// otherwise; [animated] false
  /// switches at once.
  void setTitleVisible(
    double t, {
    required bool visible,
    bool animated = true,
  }) {
    advance(t);
    if (visible == _titleVisible) return;
    _titleVisible = visible;
    final target = visible ? 1.0 : 0.0;
    if (!animated) {
      _title.snap(t, target);
      return;
    }
    _title.retarget(t, target, spring: visible ? showSpring : hideSpring);
  }

  /// Content went under the bar ([scrolledUnder] true) or left it at
  /// time [t]; [animated] false switches at once.
  void setScrolledUnder(
    double t, {
    required bool scrolledUnder,
    bool animated = true,
  }) {
    advance(t);
    if (scrolledUnder == _scrolledUnder) return;
    _scrolledUnder = scrolledUnder;
    final target = scrolledUnder ? 1.0 : 0.0;
    if (!animated) {
      _edge.snap(t, target);
      return;
    }
    _edge.retarget(t, target, spring: edgeSpring);
  }

  /// The inline title's progress, 0 hidden and 1 shown.
  double get titleProgress => _title.value(_now).clamp(0.0, 1.0);

  /// The inline title's opacity.
  double get titleOpacity => titleProgress;

  /// How far below its place the inline title is drawn.
  double get titleOffset =>
      reducedMotion ? 0 : hiddenOffset * (1 - titleProgress);

  /// The blur the inline title is drawn with.
  double get titleBlur => reducedMotion ? 0 : hiddenBlur * (1 - titleProgress);

  /// The opacity of the scroll edge effect.
  double get edgeOpacity => _edge.value(_now).clamp(0.0, 1.0);

  /// Whether what remains of the motion is invisible: the title's and the
  /// edge effect's remaining change is below [MorphRest.opacity] (the
  /// title's rise then stays under [MorphRest.length]; NEAR, invisible).
  /// [settle] snaps the rest.
  bool get isSettled =>
      _title.isWithin(_now, MorphRest.opacity) &&
      _edge.isWithin(_now, MorphRest.opacity);

  /// Puts a settled motion exactly onto its targets.
  void settle() {
    _title.settle(_now);
    _edge.settle(_now);
  }
}

/// The springs and geometry of a navigation stack's page transitions on
/// iOS 27, read from `_UIFluidNavigationTransitionsSpec` and the
/// recordings.
abstract final class MorphNavigationTuning {
  /// The spring a page settles on after an interactive edge swipe, and a
  /// cancelled swipe returns on: the spec's `interactiveSpring`
  /// (response 0.3, damping 0.85; the recorded completion overshoots by
  /// the 0.6 percent this spring predicts).
  static const interactiveSpring = MorphSpring(0.3, 0.85);

  /// The spring a page slides in and out on when pushed or popped
  /// without a finger: the spec's `noninteractiveSpring` (response 0.3,
  /// critically damped).
  static const pushSpring = MorphSpring(0.3, 1);

  /// The speed a push or pop starts at, in page widths per second: the
  /// page leaves its start at full speed rather than from rest (fitted to
  /// the device recordings of the page underneath on [pushSpring]: 8.0 on
  /// a push, 8.6 on a pop, 0.6 pt rms).
  static const double pushVelocity = 8.3;

  /// The share of the width the page underneath moves by: it parallaxes
  /// by 30 percent of the screen.
  static const double parallax = 0.3;

  /// The width of the screen edge an interactive pop starts from.
  static const double edgeWidth = 20;

  /// The touch travel before a content back swipe begins, in points.
  /// iPhone 16 Pro content gestures at 0 / 20 / 25 / 26 degrees and a
  /// slow horizontal drag start after 29.67–30 points of radial travel.
  /// Deeper horizontal controls reach Flutter's touch slop first.
  static const double contentPopTouchSlop = 30;

  /// The limiting angle from horizontal of a content back swipe, in
  /// degrees. Device captures accept 29 degrees and reject 30; the
  /// boundary is fitted to that one-degree bracket (NEAR).
  static const double contentPopMaxAngle = 30;

  /// The corner radius of a page while it slides, in points, when the
  /// platform reports no display corner radius: the moving page is a card
  /// with the display's continuous corners (fitted to a simulator film of
  /// an iPhone 17 Pro edge swipe: about 62 pt, the display's radius; the
  /// card is square again once it rests). Where the platform reports one
  /// (`MediaQueryData.displayCornerRadii`) the card takes it.
  static const double fallbackCardRadius = 62;

  /// The opacity of the black over the page underneath when the page on
  /// top covers it fully; it follows the top page's progress linearly.
  /// iPhone 16 Pro, iOS 27.0.1: black alpha 0.1, with layer opacity
  /// equal to the covering page's progress on a push and an edge or
  /// content pop. Held edge samples at x 65.33 / 145.67 / 229 / 327.33
  /// on a 402 point page give 0.8375 / 0.6376 / 0.4303 / 0.1857 opacity.
  static const double underDimOpacity = 0.1;

  /// The distance fraction of the legacy distance/flick approximation.
  /// [MorphNavigationPopMotion] predicts the release from recent movement
  /// instead; the recorded 0.27-return / 0.32-pop bracket alone does not
  /// establish a distance threshold when the finger has been held.
  static const double popDistance = 0.3;

  /// The speed of the legacy distance/flick approximation, in widths/s.
  /// [MorphNavigationPopMotion] uses recent velocity and acceleration;
  /// a single release-speed threshold does not decide its outcome.
  static const double popVelocity = 1.06;

  /// The legacy scale fitted against a 50 ms touch-window speed estimate.
  /// [MorphNavigationPopMotion] reconstructs the pan speed directly;
  /// the interactive spring carries that speed without this multiplier.
  static const double cancelVelocityScale = 2.9;

  /// The share of an interactive pop's progress the navigation bar's
  /// capsules travel toward their places on the screen below while the
  /// finger drags the page: half the way when the page is fully out.
  static const double barDrift = 0.5;

  /// The seconds a push or pop without a finger cross-fades for under
  /// Reduce Motion: the leaving page fades out while the arriving one
  /// fades in, on [crossFadeCurve], instead of sliding. An edge swipe
  /// still slides. Read from UIKit, notes private: UINavigationController
  /// hands a transition without a finger to its cross-fade animator when
  /// the platform prefers cross-fade transitions (on with Reduce Motion;
  /// Flutter reports only Reduce Motion, so morph follows that).
  static const double crossFadeDuration = 0.5;

  /// The easing of the cross-fade: UIView's default animation curve.
  static const Curve crossFadeCurve = Curves.easeInOut;
}

/// Predicts whether an interactive back swipe completes.
///
/// Read from UIKit (notes private), then replayed from iPhone 16 Pro,
/// iOS 27.0.1 touches: pan speed mixes the last two movement speeds with
/// weights 0.2 / 0.8. The last three normalized speeds and accelerations
/// predict progress after 0.35 s. The page pops past the smaller of
/// 187.5 points and half its width. Holding a finger keeps its last pan
/// speed; a lift updates the statistics without adding a stationary move.
/// An uninterrupted fast flick also boosts the spring's starting speed
/// by [flickBoost] until its mean speed falls below [flickThreshold].
///
/// Supply positions before recognition with [addPosition], call [begin]
/// when the drag wins, then [update] after each page movement and at lift.
/// Times are monotonic seconds; positions increase toward the popping side.
/// The equations reproduce the recorded inputs; platform event timing and
/// gesture admission can differ (NEAR).
class MorphNavigationPopMotion {
  /// Creates a predictor for a page [width] points wide.
  MorphNavigationPopMotion(this.width) : assert(width > 0);

  /// The page width captured when the pointer starts.
  final double width;

  /// The native prediction interval, in seconds (read from UIKit).
  static const double predictionTime = 0.35;

  /// The maximum projected distance needed to pop, in points.
  static const double predictionDistance = 187.5;

  /// The projected fraction needed on narrower pages.
  static const double predictionFraction = 0.5;

  /// The mean speed below which the initial flick phase ends, in widths/s.
  /// Read from UIKit on iOS 27.0.1, notes private.
  static const double flickThreshold = 1.5;

  /// The settle-speed boost while the initial flick phase persists.
  /// Read from UIKit on iOS 27.0.1, notes private.
  static const double flickBoost = 4.25;

  final _velocities = List<double>.filled(3, 0);
  final _accelerations = List<double>.filled(3, 0);
  double? _positionTime;
  double _position = 0;
  double? _rawVelocity;
  double _panVelocity = 0;
  double _previousVelocity = 0;
  double _previousAcceleration = 0;
  double _previousDisplacement = 0;
  double _previousTime = 0;
  double _attemptTime = 0;
  bool _changed = false;
  bool _flick = true;
  int _sampleCount = 0;
  double _averageVelocity = 0;
  double _averageAcceleration = 0;

  /// The number of accepted statistics samples, including recognition.
  int get sampleCount => _sampleCount;

  double get _currentVelocity => _panVelocity / width;

  /// The last accepted pan speed in page widths per second.
  double get velocity => _previousVelocity;

  /// The initial settle speed, including an uninterrupted fast flick.
  double get settleVelocity => velocity * (_flick ? flickBoost : 1);

  /// The mean of the last three accepted speeds, in widths per second.
  double get averageVelocity => _averageVelocity;

  /// The mean of the last three limited accelerations, in widths/s².
  double get averageAcceleration => _averageAcceleration;

  /// Records a pointer position, including movement before recognition.
  /// A lift does not add a position: UIKit preserves the last move speed.
  void addPosition(double t, double x) {
    final previous = _positionTime;
    if (previous != null) {
      final dt = t - previous;
      if (dt > 0) {
        final raw = dt >= 0.001 ? (x - _position) / dt : 0.0;
        final old = _rawVelocity;
        _panVelocity = old == null ? raw : 0.2 * raw + 0.8 * old;
        _rawVelocity = raw;
      }
    }
    _positionTime = t;
    _position = x;
  }

  /// Starts statistics at recognition, with the current drag [progress].
  void begin(double t, {double progress = 0}) {
    _previousTime = t;
    _attemptTime = t;
    _previousDisplacement = progress;
    _previousVelocity = _currentVelocity;
    _previousAcceleration = 0;
    _averageVelocity = _currentVelocity;
    _averageAcceleration = 0;
    _velocities.fillRange(0, 3, 0);
    _accelerations.fillRange(0, 3, 0);
    _velocities[0] = _currentVelocity;
    _sampleCount = 1;
    _changed = false;
    _flick = true;
  }

  /// Samples movement or a lift at [t], with the actual page [progress].
  /// Set [ending] for a lift so a never-updated drag cannot complete.
  void update(double t, double progress, {bool ending = false}) {
    if (_sampleCount == 0) return;
    if (!ending && t > _attemptTime) _changed = true;
    final attempt = t - _attemptTime;
    _attemptTime = t;
    final displacement = math.max(0.0, progress);
    if (attempt < 0.01 &&
        (attempt <= 0.001 || displacement == _previousDisplacement)) {
      return;
    }
    final dt = t - _previousTime;
    if (dt <= 0) return;
    final v = _currentVelocity;
    final acceleration = (v - _previousVelocity) / dt;
    final limited =
        _previousAcceleration +
        (acceleration - _previousAcceleration).clamp(-5.0, 5.0);
    final slot = _sampleCount % 3;
    final count = math.min(3, _sampleCount);
    final divisor = math.min(3, _sampleCount + 1);
    _averageVelocity =
        (v +
            _averageVelocity * count -
            (_sampleCount >= 3 ? _velocities[slot] : 0)) /
        divisor;
    _averageAcceleration =
        (limited +
            _averageAcceleration * count -
            (_sampleCount >= 3 ? _accelerations[slot] : 0)) /
        divisor;
    if (_averageVelocity.abs() < flickThreshold) _flick = false;
    _velocities[slot] = v;
    _accelerations[slot] = limited;
    _previousVelocity = v;
    _previousAcceleration = limited;
    _previousDisplacement = displacement;
    _previousTime = t;
    _sampleCount++;
  }

  /// Whether the page released at [progress] completes its pop.
  bool shouldPop(double progress) {
    if (!_changed) return false;
    if (_sampleCount < 3) return _averageVelocity > 0;
    final projected =
        progress +
        predictionTime * _averageVelocity +
        0.5 * predictionTime * predictionTime * _averageAcceleration;
    return projected > math.min(predictionDistance / width, predictionFraction);
  }
}
