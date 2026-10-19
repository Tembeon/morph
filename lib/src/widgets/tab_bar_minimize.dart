import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// When a [MorphTabBar] minimizes to its selected tab while the content
/// under it scrolls (UIKit `UITabBarController.MinimizeBehavior`, SwiftUI
/// `TabBarMinimizeBehavior`).
enum MorphTabBarMinimizeBehavior {
  /// The platform's default for the context. On an iPhone tab bar that
  /// does not opt in, UIKit's default does not minimize, so this resolves
  /// to [never] (an approximation: the resolution is not read from UIKit).
  automatic,

  /// The bar never minimizes.
  never,

  /// The bar minimizes when the content scrolls down. It expands at the
  /// content's top end, on a tap and when the content is pushed past its
  /// far end; a scroll back up in the middle of the content leaves it
  /// minimized, as iOS 27 does.
  onScrollDown,

  /// The bar minimizes when the content scrolls up, mirroring
  /// [onScrollDown]; for content aligned to the bottom (a chat).
  onScrollUp;

  /// Whether a bar with this behavior minimizes at all.
  bool get minimizes => this == onScrollDown || this == onScrollUp;
}

/// The measured tuning of a minimizing tab bar and its bottom accessory.
///
/// The thresholds, springs and the hint scale are read from UIKit on iOS
/// 27.0.1 (UIKit's scroll-away interaction of the floating tab bar and its
/// animation settings; notes private). The geometry is UIKit's default tab
/// bar layout record, matched to the measured search tab circle (48 pt, 28
/// from the side and the bottom). Which of the two collapse springs moves
/// the glass and which the content, the space between the minimized
/// circles and the accessory and the accessory's height are not read:
/// they wait for a recording (probe scene `w2search`, `PROBE_MINIMIZE=1`).
abstract final class MorphTabBarMinimizeTuning {
  /// The scroll in the minimizing direction, in points, before the bar
  /// starts to respond: UIKit's activation threshold, 0.
  static const double activationDistance = 0;

  /// The scroll, in points, past [activationDistance] that takes the bar
  /// from expanded to minimized: UIKit's active distance, 64.
  static const double activeDistance = 64;

  /// The scrollable range a content needs, as a multiple of
  /// [activationDistance] + [activeDistance], before the bar minimizes
  /// over it: 1.5 (96 pt), read from UIKit.
  static const double minimumRangeFactor = 1.5;

  /// The least progress of a scroll that has started to minimize the
  /// bar, so a scroll that turns back mid-way does not read as one that
  /// expanded it: UIKit clamps between 0.01 and 1.
  static const double minimumProgress = 0.01;

  /// How much smaller the bar draws at the end of a scroll's progress,
  /// before it minimizes: the bar's glass group scales by 1 - 0.05 x
  /// progress about its center, read from UIKit.
  static const double hintScale = 0.05;

  /// The spring of the hint while a finger drags the content (UIKit
  /// `scrollAwayTrackingProgressSpring`: damping 0.8, response 0.1).
  static const hintTrackingSpring = MorphSpring(0.1, 0.8);

  /// The spring of the hint while the content decelerates on its own
  /// (UIKit `scrollAwayProgressSpring`: damping 0.8, response 0.5).
  static const hintSpring = MorphSpring(0.5, 0.8);

  /// The spring the hint returns to full size on when the bar minimizes,
  /// expands or the scroll ends short of it (UIKit
  /// `scrollAwayHintResetSpring`: damping 0.8, response 0.3).
  static const hintResetSpring = MorphSpring(0.3, 0.8);

  /// The spring the glass collapses on (UIKit
  /// `collapseIntermediateSpring`: damping 0.72, response 0.36). Assigning
  /// it to the glass is an approximation.
  static const collapseShapeSpring = MorphSpring(0.36, 0.72);

  /// The spring the content collapses on, [collapseContentDelay] after
  /// the glass (UIKit `collapseFinalSpring`: damping 0.76, response 0.42).
  static const collapseContentSpring = MorphSpring(0.42, 0.76);

  /// The delay of [collapseContentSpring] (UIKit
  /// `collapseFinalSpringDelay`: 0.05 s).
  static const double collapseContentDelay = 0.05;

  /// The spring the glass expands on (UIKit `expandIntermediateSpring`:
  /// damping 0.72, response 0.3).
  static const expandShapeSpring = MorphSpring(0.3, 0.72);

  /// The spring the content expands on, [expandContentDelay] after the
  /// glass (UIKit `expandFinalSpring`: damping 0.72, response 0.36).
  static const expandContentSpring = MorphSpring(0.36, 0.72);

  /// The delay of [expandContentSpring] (UIKit `expandFinalSpringDelay`:
  /// 0.05 s).
  static const double expandContentDelay = 0.05;

  /// The diameter of the minimized bar: UIKit's collapsed platter, 48,
  /// the size of the search tab's circle while searching.
  static const double collapsedSize = 48;

  /// The space between the minimized bar and the expanded bar's edges:
  /// (62 - 48) / 2 = 7, read from UIKit's layout record; with the bar 21
  /// from the screen's side and bottom, the circle sits 28 from both, as
  /// the measured search tab circle does.
  static const double collapsedInset = 7;

  /// The space between the minimized bar, the inline accessory and a
  /// minimized search circle, and between the expanded bar and the
  /// accessory above it: UIKit's layout record carries 8; which space it
  /// is was not read (an approximation).
  static const double spacing = 8;

  /// The height of the bottom accessory, expanded and inline: the
  /// collapsed platter's 48 (an approximation, not measured).
  static const double accessoryHeight = 48;

  /// The space between the screen's sides and the bar group: 21 (the
  /// measured tab bar inset).
  static const double sideInset = 21;

  /// How long a finger rests on the minimized bar before the bar expands
  /// under it: UIKit's `minimumPressDuration` of the tab bar's interactive
  /// expansion, 0.22 s, read from UIKit.
  static const double holdDuration = 0.22;

  /// How far a finger on the minimized bar moves along the bar, in points,
  /// before the bar expands at once and the touch becomes the bar's
  /// selection drag: UIKit's `expansionHysteresis`, 4, read from UIKit
  /// (the selection gesture of the floating tab bar applies the same 4
  /// points).
  static const double holdHysteresis = 4;

  /// The spring of UIKit's interactive expansion under a held finger
  /// (`expansionSpring`: damping 0.5, response 0.4), read from UIKit.
  /// Which views it moves is not read: morph expands a held bar on
  /// [expandShapeSpring] and [expandContentSpring] (an approximation).
  static const expansionSpring = MorphSpring(0.4, 0.5);

  /// The spring UIKit's interactive expansion returns on when the finger
  /// lifts without moving (`collapsedSpring`: damping 0.75, response 0.4),
  /// read from UIKit; morph collapses on [collapseShapeSpring] and
  /// [collapseContentSpring] (an approximation, as [expansionSpring]).
  static const collapsedSpring = MorphSpring(0.4, 0.75);
}

/// The scroll-away interaction of a minimizing tab bar: how far a user's
/// scroll has carried the bar toward minimizing, ported from UIKit's
/// floating tab bar (iOS 27.0.1; equations read from UIKit, notes
/// private).
///
/// Offsets are along the content's scroll axis, growing as the content
/// moves toward its end (Flutter's `pixels` on a downward list, UIKit's
/// `contentOffset.y`); [min] and [max] are the offsets of the content's
/// two ends. Only a user's scroll counts: a drag, and the deceleration
/// after it. A programmatic scroll is only recorded ([record]).
///
/// - A drag starts a fresh accumulation ([beginDrag]).
/// - Past an end, only motion further past it counts (a rubber band's
///   return does not).
/// - Motion in the minimizing direction starts the interaction once it
///   passes [MorphTabBarMinimizeTuning.activationDistance], if the
///   content's range is at least
///   [MorphTabBarMinimizeTuning.minimumRangeFactor] x (activation + active
///   distance); from then on
///   [progress] grows by the scroll over
///   [MorphTabBarMinimizeTuning.activeDistance], clamped to 0.01 - 1; at 1
///   the bar minimizes and the interaction rests until the next drag.
/// - The end of a drag that does not decelerate, and the end of a
///   deceleration, floor [progress]: a scroll that stopped short returns
///   to 0.
/// - Pushing further past the far end while the bar is minimized expands
///   it, as does reaching the near end while the interaction runs.
/// - A scroll to the top ([scrollToTop]) expands it.
/// - A drag in the expanding direction in the middle of the content does
///   not expand a minimized bar: UIKit's code has no such path, and on the
///   iOS 27 simulator a 150 point drag back left the bar minimized,
///   although the SDK header says the bar expands when the content
///   scrolls back.
class MorphScrollAway {
  /// Creates the interaction; [minimizesOnScrollUp] reverses the
  /// minimizing direction (UIKit `onScrollUp`).
  MorphScrollAway({this.minimizesOnScrollUp = false});

  /// Whether scrolling toward the content's start minimizes the bar.
  bool minimizesOnScrollUp;

  /// How far the bar has gone toward minimizing: 0 expanded, 1 minimized.
  double get progress => _progress;
  double _progress = 0;

  /// Called with the new [progress] and whether a finger drags the
  /// content, whenever [progress] changes.
  void Function(double progress, {required bool tracking})? onProgress;

  _State _state = _State.idle;
  double _accumulated = 0;
  double _startProgress = 0;
  double? _last;
  bool _tracking = false;

  /// Starts a fresh accumulation: a finger began to drag the content.
  void beginDrag() {
    _state = _State.accumulating;
    _accumulated = 0;
    _tracking = true;
  }

  /// Records [offset] without reacting: a scroll the user did not drive.
  void record(double offset) => _last = offset;

  /// Puts [progress] at [value] without reporting it: the bar was
  /// minimized or expanded by other means (a tap, the app).
  void reset(double value) {
    _state = _State.idle;
    _progress = value;
  }

  /// Reacts to the content scrolled to [offset] by a user (dragging when
  /// [tracking], else decelerating), its ends at [min] and [max].
  void scroll(
    double offset, {
    required double min,
    required double max,
    required bool tracking,
  }) {
    _tracking = tracking;
    final last = _last;
    _last = offset;
    if (last == null || _state == _State.idle) return;
    var delta = offset - last;
    if (offset > max && delta < 0) delta = 0;
    if (offset < min && delta > 0) delta = 0;
    final signed = minimizesOnScrollUp ? -delta : delta;
    var excess = 0.0;
    if (_state == _State.accumulating) {
      final same = (signed < 0) == (_accumulated < 0);
      final acc = same ? _accumulated + signed : signed;
      _accumulated = acc;
      const threshold = MorphTabBarMinimizeTuning.activationDistance;
      if (acc.abs() < threshold) return;
      final atFarEdge = minimizesOnScrollUp ? offset <= min : offset >= max;
      if (atFarEdge && signed > 0 && _progress != 0) {
        _state = _State.idle;
        _set(0);
        return;
      }
      const range =
          MorphTabBarMinimizeTuning.minimumRangeFactor *
          (threshold + MorphTabBarMinimizeTuning.activeDistance);
      if (acc < threshold || max - min < range) return;
      _state = _State.active;
      _startProgress = _progress;
      excess = acc - threshold > 0 ? acc - threshold : 0;
    } else {
      excess = signed;
    }
    final atNearEdge = minimizesOnScrollUp ? offset >= max : offset <= min;
    if (atNearEdge && excess < 0 && _startProgress != 0) {
      _state = _State.idle;
      _set(0);
      return;
    }
    if (_progress == 1) return;
    final next = (_progress + excess / MorphTabBarMinimizeTuning.activeDistance)
        .clamp(MorphTabBarMinimizeTuning.minimumProgress, 1.0);
    if (next == _progress) return;
    if (next == 1) _state = _State.idle;
    _set(next);
  }

  /// The finger lifted; [decelerates] when the content goes on moving.
  void endDrag({required bool decelerates}) {
    _tracking = false;
    if (decelerates) return;
    _end();
  }

  /// The content stopped after a deceleration.
  void endDeceleration() => _end();

  /// The content is scrolled to its top: the bar expands.
  void scrollToTop() {
    _state = _State.idle;
    _set(0);
  }

  void _end() {
    _state = _State.idle;
    _tracking = false;
    _set(_progress.floorToDouble());
  }

  void _set(double value) {
    if (value == _progress) return;
    _progress = value;
    onProgress?.call(value, tracking: _tracking);
  }
}

enum _State { accumulating, active, idle }

/// The motion of a minimizing tab bar: the scroll-away interaction
/// ([MorphScrollAway]), the hint scale it drives and the morph between the
/// expanded bar and its minimized circle.
///
/// While a scroll carries the bar toward minimizing, the whole bar group
/// draws smaller by [MorphTabBarMinimizeTuning.hintScale] x progress on
/// the tracking spring (a finger down) or the progress spring
/// (decelerating), and returns to full size on the reset spring when it
/// minimizes, expands or the scroll stops short. Minimizing runs the
/// glass ([shape]) on the collapse spring and the content ([content]) on
/// the final collapse spring after its delay; expanding the same on the
/// expand springs. A change in the middle of another turns it around
/// with its velocity.
///
/// Times are seconds on the caller's clock.
class MorphTabBarMinimizeMotion {
  /// Creates the motion of a bar that minimizes as [behavior] says.
  MorphTabBarMinimizeMotion({
    MorphTabBarMinimizeBehavior behavior =
        MorphTabBarMinimizeBehavior.onScrollDown,
  }) : _behavior = behavior {
    scrollAway.minimizesOnScrollUp =
        behavior == MorphTabBarMinimizeBehavior.onScrollUp;
    scrollAway.onProgress = _progressChanged;
  }

  /// The scroll-away interaction; feed it the content's scrolls.
  final MorphScrollAway scrollAway = MorphScrollAway();

  final MorphSpringState _hint = MorphSpringState(
    MorphTabBarMinimizeTuning.hintResetSpring,
    1,
  );
  final MorphSpringState _shape = MorphSpringState(
    MorphTabBarMinimizeTuning.collapseShapeSpring,
    0,
  );
  final MorphSpringState _content = MorphSpringState(
    MorphTabBarMinimizeTuning.collapseContentSpring,
    0,
  );
  final MorphTimeline _timeline = MorphTimeline(now: 0);
  double _now = 0;
  int _generation = 0;

  /// The behavior; a bar that no longer minimizes expands.
  MorphTabBarMinimizeBehavior get behavior => _behavior;
  MorphTabBarMinimizeBehavior _behavior;

  /// Changes the behavior at time [t].
  void setBehavior(double t, MorphTabBarMinimizeBehavior value) {
    if (value == _behavior) return;
    _behavior = value;
    scrollAway.minimizesOnScrollUp =
        value == MorphTabBarMinimizeBehavior.onScrollUp;
    scrollAway.reset(0);
    _hint.retarget(t, 1, spring: MorphTabBarMinimizeTuning.hintResetSpring);
    if (!value.minimizes) setMinimized(t, minimized: false);
  }

  /// Whether the bar is minimized or heading there.
  bool get minimized => _minimized;
  bool _minimized = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Minimizes or expands the bar at time [t].
  void setMinimized(double t, {required bool minimized}) {
    scrollAway.reset(minimized ? 1 : 0);
    if (_hint.target != 1) {
      _hint.retarget(t, 1, spring: MorphTabBarMinimizeTuning.hintResetSpring);
    }
    _morph(t, minimized: minimized);
  }

  void _progressChanged(double progress, {required bool tracking}) {
    final t = _now;
    if (progress > 0 && progress < 1) {
      _hint.retarget(
        t,
        1 - progress * MorphTabBarMinimizeTuning.hintScale,
        spring: tracking
            ? MorphTabBarMinimizeTuning.hintTrackingSpring
            : MorphTabBarMinimizeTuning.hintSpring,
      );
    } else {
      _hint.retarget(t, 1, spring: MorphTabBarMinimizeTuning.hintResetSpring);
    }
    if (progress == 0 && _minimized) _morph(t, minimized: false);
    if (progress == 1 && !_minimized && _behavior.minimizes) {
      _morph(t, minimized: true);
    }
  }

  void _morph(double t, {required bool minimized}) {
    final value = minimized;
    if (value == _minimized) return;
    _minimized = value;
    final generation = ++_generation;
    final target = value ? 1.0 : 0.0;
    _shape.retarget(
      t,
      target,
      spring: value
          ? MorphTabBarMinimizeTuning.collapseShapeSpring
          : MorphTabBarMinimizeTuning.expandShapeSpring,
    );
    _timeline.at(
      t +
          (value
              ? MorphTabBarMinimizeTuning.collapseContentDelay
              : MorphTabBarMinimizeTuning.expandContentDelay),
      (double at) {
        if (generation != _generation) return;
        _content.retarget(
          at,
          target,
          spring: value
              ? MorphTabBarMinimizeTuning.collapseContentSpring
              : MorphTabBarMinimizeTuning.expandContentSpring,
        );
      },
    );
  }

  double? _pressX;
  bool _held = false;
  bool _scrubs = false;
  int _press = 0;

  /// Whether a finger that went down on the minimized bar is still on it.
  bool get pressed => _pressX != null;

  /// Whether the finger on the bar has rested long enough to expand it
  /// under itself ([MorphTabBarMinimizeTuning.holdDuration]).
  bool get held => _held;

  /// Whether the finger on the bar has become the bar's selection drag
  /// ([pressMove] returned true): it scrubs the tabs and its release
  /// selects, as the expanded bar's own drag does.
  bool get scrubs => _scrubs;

  /// A finger went down at [x] along the minimized bar at time [t].
  ///
  /// Held for [MorphTabBarMinimizeTuning.holdDuration] without moving,
  /// the bar expands under it (UIKit's interactive expansion of the
  /// minimized tab bar). Nothing happens on a bar that is not minimized.
  void pressDown(double t, double x) {
    if (!_minimized) return;
    _pressX = x;
    _held = false;
    _scrubs = false;
    final press = ++_press;
    _timeline.at(t + MorphTabBarMinimizeTuning.holdDuration, (double at) {
      if (press != _press || _pressX == null || _scrubs) return;
      _held = true;
      setMinimized(at, minimized: false);
    });
  }

  /// The finger moved to [x] along the bar at time [t]; true on the move
  /// that makes it the bar's selection drag.
  ///
  /// A move of [MorphTabBarMinimizeTuning.holdHysteresis] from where the
  /// finger went down, before or after the hold expanded the bar, expands
  /// it for good: from then on the touch is the expanded bar's drag.
  bool pressMove(double t, double x) {
    final from = _pressX;
    if (from == null || _scrubs) return false;
    if ((x - from).abs() < MorphTabBarMinimizeTuning.holdHysteresis) {
      return false;
    }
    _scrubs = true;
    if (_minimized) setMinimized(t, minimized: false);
    return true;
  }

  /// The finger lifted at time [t].
  ///
  /// After a hold that did not move, the bar collapses back, as UIKit's
  /// interactive expansion ends; a drag leaves it expanded. A release
  /// before the hold expands the bar: UIKit's tab bar does not
  /// (`expandsOnTap` is NO), but a tap on the minimized bar has no other
  /// path back to the tabs in the code read; this waits for a recording.
  void pressUp(double t) {
    if (_pressX == null) return;
    final held = _held;
    final scrubs = _scrubs;
    _endPress();
    if (scrubs) return;
    setMinimized(t, minimized: held);
  }

  /// The touch was taken away at time [t]: a held bar collapses back.
  void pressCancel(double t) {
    if (_pressX == null) return;
    final back = _held && !_scrubs;
    _endPress();
    if (back) setMinimized(t, minimized: true);
  }

  void _endPress() {
    _press++;
    _pressX = null;
    _held = false;
    _scrubs = false;
  }

  /// The time the motion next changes on its own (a held finger's
  /// expansion) while every spring rests within [MorphRest] for a bar
  /// group [extent] points wide, or null.
  double? wakeTime({double extent = 400}) {
    final due = _timeline.nextDue;
    if (due == null) return null;
    return _hint.isWithin(_now, MorphRest.scale(extent)) &&
            _shape.isWithin(_now, MorphRest.scale(extent)) &&
            _content.isWithin(_now, MorphRest.scale(extent))
        ? due
        : null;
  }

  /// Advances the motion to time [t]; feed scrolls stamped at [t] after.
  void advance(double t) {
    _timeline.runDue(t);
    if (t > _now) _now = t;
  }

  /// The scale of the bar group: 1, or less while a scroll
  /// hints at minimizing.
  double get hint => _hintAt(_now);

  double _hintAt(double t) => _hint.value(t);

  /// The glass's way from the expanded bar (0) to the minimized circle
  /// (1).
  double get shape => _shapeAt(_now);

  double _shapeAt(double t) => _shape.value(t);

  /// The content's way from the expanded bar (0) to the minimized circle
  /// (1).
  double get content => _contentAt(_now);

  double _contentAt(double t) => _content.value(t);

  /// Whether the bar rests expanded: nothing of the morph
  /// moves and nothing is pending.
  bool get restsExpanded => _restsExpandedAt(_now);

  bool _restsExpandedAt(double t) =>
      !_minimized &&
      _timeline.isEmpty &&
      _shape.target == 0 &&
      _content.target == 0 &&
      _shape.value(t) == 0 &&
      _content.value(t) == 0;

  /// Whether nothing moves: every spring is within its visible rest
  /// ([MorphRest]) for a bar group [extent] points wide, and nothing is
  /// pending.
  bool isSettled({double extent = 400}) =>
      _timeline.isEmpty &&
      _hint.isWithin(_now, MorphRest.scale(extent)) &&
      _shape.isWithin(_now, MorphRest.scale(extent)) &&
      _content.isWithin(_now, MorphRest.scale(extent));

  /// Puts every spring onto its target at time [t] (NEAR, invisible: the
  /// motion has settled within [MorphRest]).
  void settle(double t) {
    _hint.settle(t);
    _shape.settle(t);
    _content.settle(t);
  }
}
