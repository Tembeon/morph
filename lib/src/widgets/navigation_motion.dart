import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';

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

  /// Whether nothing is moving.
  bool get isSettled =>
      _title.isAtRest(_now, 0.001) && _edge.isAtRest(_now, 0.001);
}

/// The springs and geometry of a navigation stack's page transitions on
/// iOS 27, read from `_UIFluidNavigationTransitionsSpec` and the
/// recordings.
abstract final class MorphNavigationTransition {
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

  /// How far out, as a share of the width, a page released without a
  /// flick has to be for the swipe to pop it: device recordings stay at
  /// 0.27 and pop from 0.32.
  static const double popDistance = 0.3;

  /// The release speed, in page widths per second, past which a flick
  /// decides the swipe on its own: outward it pops (device recordings
  /// stay at 1.02 and pop from 1.10), back toward the edge it returns
  /// (pops at -1.02, returns from -1.28).
  static const double popVelocity = 1.06;

  /// The factor a returning page's starting speed carries the release
  /// speed by: a page flicked short of the threshold keeps travelling
  /// outward about three times as fast as the finger left it before it
  /// springs back (device fits 2.7..3.1). A popping page starts from
  /// rest.
  static const double cancelVelocityScale = 2.9;
}
