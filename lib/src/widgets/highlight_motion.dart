import 'package:flutter/animation.dart';

/// The highlight of a tappable list row (UIKit `UITableViewCell` in a
/// table), as a function of the touch and time.
///
/// Inside a scroll view the highlight waits [touchDelay] after the touch
/// went down; a tap released sooner shows it at the release. It appears
/// at full strength, without a fade. A scroll that takes the touch removes
/// it at once. A tap's release fades it out over [fadeDuration] on
/// [fadeCurve]: UIKit keeps the tapped row selected until the app
/// deselects it, and this is `deselectRow(at:animated: true)`, the fade of
/// the standard tap handler.
///
/// Measured on the iOS 27.0 simulator (UITableView inset grouped, taps
/// and holds through XCUITest, 60 Hz): the delay is the scroll view's
/// `_touchDelayForScrollDetection`, 0.15 s, read from UIKit (notes
/// private), and the highlight showed 0.155 - 0.166 s after the touch (one
/// frame later); the fade is the CABasicAnimation UIKit adds, read from
/// the layer. Times are seconds.
class MorphListRowHighlightMotion {
  /// The delay between a touch and the highlight inside a scroll view.
  static const double touchDelay = 0.15;

  /// The duration of the fade after a tap.
  static const double fadeDuration = 0.5;

  /// The curve of the fade after a tap: UIKit's ease-in-ease-out.
  static const Curve fadeCurve = Cubic(0.42, 0, 0.58, 1);

  double? _showAt;
  double? _fadeFrom;
  double? _undecidedUntil;

  /// A touch went down at [t]; until a tap claims it ([press]) or
  /// [touchDelay] passes, the motion keeps time without drawing.
  void touch(double t) => _undecidedUntil = t + touchDelay;

  /// The touch that went down at [downTime] may become a tap: the
  /// highlight shows at [downTime] plus [delay], or at [now] when that is
  /// later.
  void press(double downTime, double now, {double delay = touchDelay}) {
    _undecidedUntil = null;
    _fadeFrom = null;
    final at = downTime + delay;
    _showAt = at > now ? at : now;
  }

  /// The tap was released at [t]: the highlight shows if it still waited,
  /// then fades out.
  void release(double t) {
    if (_showAt == null) return;
    _showAt = null;
    _fadeFrom = t;
  }

  /// The touch was taken by a scroll or lost: the highlight goes at once.
  void cancel() {
    _undecidedUntil = null;
    _showAt = null;
    _fadeFrom = null;
  }

  /// The highlight's strength at [t], 0 to 1.
  double opacity(double t) {
    final show = _showAt;
    if (show != null) return t >= show ? 1 : 0;
    final from = _fadeFrom;
    if (from == null) return 0;
    final p = ((t - from) / fadeDuration).clamp(0.0, 1.0);
    return 1 - fadeCurve.transform(p);
  }

  /// Whether nothing changes after [t].
  bool isSettled(double t) {
    final undecided = _undecidedUntil;
    if (undecided != null && t < undecided) return false;
    final show = _showAt;
    if (show != null) return t >= show;
    final from = _fadeFrom;
    return from == null || t >= from + fadeDuration;
  }

  /// The time before which the highlight shows nothing new, or null while
  /// it changes every frame.
  double? wakeTime(double t) {
    final show = _showAt;
    if (show != null) return t < show ? show : null;
    final undecided = _undecidedUntil;
    if (_fadeFrom == null && undecided != null && t < undecided) {
      return undecided;
    }
    return null;
  }
}

/// The dimming of a segmented control's title under the finger
/// (UIKit `UISegmentedControl`'s `UISegmentLabel`).
///
/// A touch on a segment that is not selected dims its title to
/// [dimmedOpacity] over [dimDuration]; the release or a cancel returns
/// it to full over [restoreDuration] from where it is, both on [curve]. Read from the CABasicAnimations UIKit
/// adds to the label on the iOS 27.0 simulator (XCUITest taps and a 1 s
/// hold, 2026-10-14). A touch on the selected segment and a finger
/// sliding to another segment are not measured: the dim stays on the
/// segment the touch went down on. Times are seconds.
class MorphSegmentHighlightMotion {
  /// The opacity a pressed title dims to.
  static const double dimmedOpacity = 0.2;

  /// The duration of the dimming.
  static const double dimDuration = 0.47;

  /// The duration of the return to full opacity.
  static const double restoreDuration = 0.2;

  /// The curve of both: Core Animation's default timing function.
  static const Curve curve = Cubic(0.25, 0.1, 0.25, 1);

  int? _index;
  double _start = 0;
  double _from = 1;
  double _to = 1;
  double _duration = 0;

  /// The segment whose title is dimmed or returning, if any.
  int? get index => _index;

  /// A touch went down on segment [index] at [t].
  void press(double t, int index) {
    final from = _index == index ? _value(t) : 1.0;
    _index = index;
    _set(t, from, dimmedOpacity, dimDuration);
  }

  /// The touch ended or was cancelled at [t].
  void release(double t) {
    if (_index == null) return;
    _set(t, _value(t), 1, restoreDuration);
  }

  void _set(double t, double from, double to, double duration) {
    _start = t;
    _from = from;
    _to = to;
    _duration = duration;
  }

  double _value(double t) {
    final p = _duration <= 0 ? 1.0 : ((t - _start) / _duration).clamp(0.0, 1.0);
    return _from + (_to - _from) * curve.transform(p);
  }

  /// The opacity of segment [index]'s title at [t].
  double opacity(double t, int index) => index == _index ? _value(t) : 1;

  /// Advances to [t]: a title back at full opacity is no longer tracked.
  void advance(double t) {
    if (_index != null && _to == 1 && t >= _start + _duration) _index = null;
  }

  /// Whether nothing changes after [t].
  bool isSettled(double t) =>
      _index == null || (_to != 1 && t >= _start + _duration);
}
