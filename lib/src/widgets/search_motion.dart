import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// The measured tuning and geometry of the iOS 27 search field: a
/// UISearchController placed in the bottom toolbar, and the tab bar's
/// search tab.
abstract final class MorphSearchTuning {
  /// The spring of the focus transition: the field widens, the toolbar's
  /// other items leave, the close button arrives. SwiftUI's
  /// `GlassContainerSearchTransitionPTSettings` (duration 0.25, bounce
  /// 0.1); the frames fit 0.238 - 0.246 / 0.92 - 0.94 freely (simulator
  /// and iPhone 16 Pro) and this spring within 0.6 percent of the travel.
  static const transitionSpring = MorphSpring(0.25, 0.9);

  /// The time from a focus change to the start of the transition (0.067 s
  /// from `isActive = false` on an iPhone 16 Pro, 0.077 - 0.086 s on the
  /// simulator, 0.080 s from the lift of a tap on the close button on the
  /// device; a focus that brings up the keyboard waits for it instead, see
  /// [keyboardLag]).
  static const double transitionDelay = 0.067;

  /// The time from the keyboard's first frame to the start of a focus
  /// transition: UIKit holds the transition of a focus that brings up the
  /// keyboard until the keyboard starts to rise (an iPhone 16 Pro: 0.015 s
  /// after its first frame, 0.17 - 0.19 s after the lift of the tap that
  /// focused, 0.28 s for the first keyboard of a launch).
  static const double keyboardLag = 0.015;

  /// The longest a focus waits for the keyboard before its transition
  /// starts anyway (no keyboard rises with a hardware keyboard attached).
  /// A guard above the slowest measured wait, not a measured value.
  static const double keyboardWaitLimit = 0.3;

  /// The time from a touch to the start of the field's lift (0.051 s
  /// fitted; the lift itself is the glass button's).
  static const double pressDelay = 0.05;

  /// The height of the field, the close button and the toolbar's items.
  static const double height = 48;

  /// The height of the text inside the field.
  static const double textHeight = 28;

  /// The space between the screen's sides and the bar at rest, and
  /// between the screen's bottom and the bar.
  static const double restInset = 28;

  /// The space between the screen's sides and the focused bar.
  static const double focusedSideInset = 8;

  /// The space between the keyboard (or the screen's bottom) and the
  /// focused bar.
  static const double keyboardGap = 10;

  /// The space between the field and its neighbours.
  static const double gap = 12;

  /// The scale an item appears from and leaves at, around its center,
  /// while it fades: the close button arrives from 1.2, the toolbar's
  /// other items leave toward it.
  static const double appearScale = 1.2;

  /// The blur of an item at the start of its appearance, in logical
  /// pixels (`GlassContainerAppearanceSearchPTSettings.blurRadius`).
  static const double appearBlur = 10;

  /// The space between the field's leading edge and the magnifier.
  static const double glyphInset = 12;

  /// The size of the magnifier glyph.
  static const Size glyphSize = Size(20.67, 19.33);

  /// The space between the field's leading edge and its text.
  static const double textInset = 40.67;

  /// The size of the clear button.
  static const double clearSize = 20;

  /// The diameter of the clear button's disc, inside its [clearSize] box
  /// (16.67 on an iPhone 16 Pro's screen).
  static const double clearInk = 16.67;

  /// The space between the clear button and the field's trailing edge.
  static const double clearInset = 13.33;

  /// The size of the close button's glyph.
  static const Size closeGlyphSize = Size(22.67, 21.33);

  /// The side of the square the close button's cross fills, round caps
  /// included (16.67 on an iPhone 16 Pro's screen).
  static const double closeInk = 16.67;

  /// The thickness of the close button's strokes.
  static const double closeStroke = 2.3;

  /// The spring of a tab bar turning into a search field and back: fitted
  /// to the edges of the glass in a video of a UITabBarController selecting
  /// a UISearchTab that activates search (no tuning value was found to
  /// read; the frames are 60 Hz video, 1 - 2 points apart).
  static const tabSpring = MorphSpring(0.276, 0.8);

  /// The spring a tab bar's search field rises above the keyboard on when
  /// it takes the focus, and sinks back on when it loses it: critically
  /// damped, response 0.30 (an iPhone 16 Pro: 0.19 and 0.93 pt rms over
  /// 308 points; [transitionSpring] leaves 12).
  static const tabFocusSpring = MorphSpring(0.3, 1);

  /// The time from the lift of the tap on the search tab to the field
  /// taking the focus when the tab activates search (an iPhone 16 Pro:
  /// `willPresentSearchController` 0.085 s and the first responder 0.159
  /// s after the lift, the keyboard's first frame 0.25 s after it, while
  /// the tab's morph still runs).
  static const double tabActivationDelay = 0.16;

  /// The time from the keyboard's first frame to the start of a tab bar
  /// search's rise (an iPhone 16 Pro, 0.07 s).
  static const double tabKeyboardLag = 0.07;

  /// The time from the end of a tab bar search's focus to the start of its
  /// fall (an iPhone 16 Pro: 0.038 and 0.064 s after the lift of the
  /// close tap in two captures; the fall itself runs on [tabFocusSpring],
  /// 0.08 percent rms of 308 points).
  static const double tabUnfocusDelay = 0.05;

  /// The space between the screen's sides and bottom and a tab bar that
  /// carries a search tab.
  static const double tabBarInset = 21;

  /// The diameter of the search tab's circle next to the tab bar.
  static const double searchTabSize = 62;

  /// The space between the field and the close button of a tab bar's
  /// focused search.
  static const double tabCloseGap = 8;

  /// The space between the keyboard and a tab bar's focused search (8,
  /// where the toolbar's search keeps [keyboardGap]).
  static const double tabKeyboardGap = 8;
}

/// The geometry of a tab bar with a search tab, at rest and searching.
@internal
@immutable
class MorphSearchTabGeometry {
  /// Creates a geometry.
  const MorphSearchTabGeometry({
    required this.bar,
    required this.search,
    required this.tab,
    required this.field,
    required this.focusedField,
    required this.close,
  });

  /// The tab bar at rest.
  final Rect bar;

  /// The search tab's circle at rest.
  final Rect search;

  /// The circle the tab bar becomes while searching: the selected tab's
  /// glyph.
  final Rect tab;

  /// The search field while searching.
  final Rect field;

  /// The search field focused above the keyboard.
  final Rect focusedField;

  /// The close button next to the focused field.
  final Rect close;
}

/// Lays out a tab bar [barWidth] wide with a search tab in a screen of
/// [size], above a keyboard [keyboard] tall, as iOS 27 does (iPhone 18 Pro
/// Max: bar and circle 21 from the sides and bottom; searching, the tab
/// circle 28 from the side and bottom and the field 12 after it to 28
/// from the side; focused, the field 8 from the side, the close button 8
/// after it, 8 above the keyboard). [rtl] mirrors it.
@internal
MorphSearchTabGeometry morphSearchTabLayout({
  required Size size,
  required double barWidth,
  double keyboard = 0,
  bool rtl = false,
}) {
  const inset = MorphSearchTuning.tabBarInset;
  const circle = MorphSearchTuning.searchTabSize;
  const h = MorphSearchTuning.height;
  const rest = MorphSearchTuning.restInset;
  final w = size.width;
  final barTop = size.height - inset - circle;
  final top = size.height - rest - h;
  final focusedTop =
      size.height - keyboard - MorphSearchTuning.tabKeyboardGap - h;
  final close = Rect.fromLTWH(
    w - MorphSearchTuning.focusedSideInset - h,
    focusedTop,
    h,
    h,
  );
  final geometry = MorphSearchTabGeometry(
    bar: Rect.fromLTWH(inset, barTop, barWidth, circle),
    search: Rect.fromLTWH(w - inset - circle, barTop, circle, circle),
    tab: Rect.fromLTWH(rest, top, h, h),
    field: Rect.fromLTRB(
      rest + h + MorphSearchTuning.gap,
      top,
      w - rest,
      top + h,
    ),
    focusedField: Rect.fromLTRB(
      MorphSearchTuning.focusedSideInset,
      focusedTop,
      close.left - MorphSearchTuning.tabCloseGap,
      focusedTop + h,
    ),
    close: close,
  );
  if (!rtl) return geometry;
  Rect mirror(Rect r) =>
      Rect.fromLTRB(w - r.right, r.top, w - r.left, r.bottom);
  return MorphSearchTabGeometry(
    bar: mirror(geometry.bar),
    search: mirror(geometry.search),
    tab: mirror(geometry.tab),
    field: mirror(geometry.field),
    focusedField: mirror(geometry.focusedField),
    close: mirror(geometry.close),
  );
}

/// The motion of an iOS 27 search field: the focus transition and the
/// touch lift.
///
/// One progress, 0 at rest and 1 focused, drives the whole transition on
/// [MorphSearchTuning.transitionSpring], starting
/// [MorphSearchTuning.transitionDelay] after the change: the field's
/// frame, the close button arriving (its opacity is the progress, its
/// scale 1.2 at nothing) and the toolbar's other items leaving the same
/// way in reverse. A change in the middle of another reverses from where
/// it stands, velocity included.
///
/// A touch lifts the field like a glass button of its size
/// ([MorphFlexSpec.forSize]: the tracking spring up, the scale spring
/// back), [MorphSearchTuning.pressDelay] after the contact.
///
/// Times are seconds on the caller's clock.
class MorphSearchMotion {
  /// Creates the motion of a field of [size], resting; the focus
  /// transition rides [spring].
  MorphSearchMotion({
    Size size = const Size(346, 48),
    MorphSpring spring = MorphSearchTuning.transitionSpring,
  }) : _size = size,
       _spec = MorphFlexSpec.forSize(size),
       _progress = MorphSpringState(spring, 0);

  final MorphTimeline _timeline = MorphTimeline(now: 0);
  final MorphSpringState _progress;
  final MorphSpringState _press = MorphSpringState(
    MorphFlexSpec.large.trackingSpring,
    1,
  );
  Size _size;
  MorphFlexSpec _spec;
  double _now = 0;
  bool _focused = false;
  bool _pressed = false;
  int _focusGeneration = 0;
  int _pressGeneration = 0;

  /// Whether the field moves for Reduce Motion: the transition still runs,
  /// but nothing lifts. An approximation; it is not measured.
  bool reducedMotion = false;

  /// The size of the field at rest, which sets its lift.
  Size get size => _size;

  set size(Size value) {
    if (value == _size) return;
    _size = value;
    _spec = MorphFlexSpec.forSize(value);
  }

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the field is focused or heading there.
  bool get isFocused => _focused;

  /// Whether a finger is down on the field.
  bool get isPressed => _pressed;

  /// Whether nothing moves and nothing is pending.
  bool get isSettled =>
      _timeline.isEmpty &&
      !_pressed &&
      _progress.isAtRest(_now, 0.001) &&
      _press.isAtRest(_now, 1e-4);

  /// The scale of the fully lifted field.
  double get liftedScale =>
      _size.width > 0 ? 1 + _spec.liftScalePoints / _size.width : 1;

  /// Advances the motion to time [t].
  void advance(double t) {
    _timeline.runDue(t);
    if (t > _now) _now = t;
  }

  /// Focuses the field at time [t]; the transition starts [delay] seconds
  /// later.
  void focus(double t, {double delay = MorphSearchTuning.transitionDelay}) =>
      _transition(t, focused: true, delay: delay);

  /// Ends the search at time [t]; the transition starts [delay] seconds
  /// later.
  void unfocus(double t, {double delay = MorphSearchTuning.transitionDelay}) =>
      _transition(t, focused: false, delay: delay);

  void _transition(
    double t, {
    required bool focused,
    double delay = MorphSearchTuning.transitionDelay,
  }) {
    advance(t);
    if (_focused == focused) return;
    _focused = focused;
    final generation = ++_focusGeneration;
    _timeline.at(t + delay, (double at) {
      if (generation != _focusGeneration) return;
      _progress.retarget(at, focused ? 1 : 0);
    });
  }

  /// Puts the transition at rest, focused or not, at time [t].
  void snap(double t, {required bool focused}) {
    advance(t);
    _focused = focused;
    _focusGeneration++;
    _progress.snap(t, focused ? 1 : 0);
  }

  /// A finger touched the field at time [t].
  void pointerDown(double t) {
    advance(t);
    _pressed = true;
    final generation = ++_pressGeneration;
    _timeline.at(t + MorphSearchTuning.pressDelay, (double at) {
      if (!_pressed || generation != _pressGeneration) return;
      _press.retarget(
        at,
        reducedMotion ? 1 : liftedScale,
        spring: _spec.trackingSpring,
      );
    });
  }

  /// The finger left the field at time [t].
  void pointerUp(double t) {
    advance(t);
    if (!_pressed) return;
    _pressed = false;
    _press.retarget(t, 1, spring: _spec.scaleSpring);
  }

  /// The touch was cancelled at time [t].
  void pointerCancel(double t) => pointerUp(t);

  /// The focus progress at time [t]: 0 at rest, 1 focused.
  double progress(double t) => _progress.value(t);

  /// The lift scale of the field at time [t].
  double pressScale(double t) => _press.value(t);

  /// The scale of an item that is [presence] there (0 gone, 1 fully
  /// there): [MorphSearchTuning.appearScale] at nothing.
  static double appearScaleFor(double presence) =>
      1 + (MorphSearchTuning.appearScale - 1) * (1 - presence.clamp(0.0, 1.0));

  /// The blur of an item that is [presence] there.
  static double appearBlurFor(double presence) =>
      MorphSearchTuning.appearBlur * (1 - presence.clamp(0.0, 1.0));
}

/// The geometry of a bottom search bar in one configuration: the field,
/// the close button and the toolbar items around the field.
@internal
@immutable
class MorphSearchBarGeometry {
  /// Creates a geometry.
  const MorphSearchBarGeometry({
    required this.field,
    required this.close,
    required this.leading,
    required this.trailing,
  });

  /// The field's capsule.
  final Rect field;

  /// Where the close button sits in this configuration.
  final Rect close;

  /// The items before the field, in order.
  final List<Rect> leading;

  /// The items after the field, in order.
  final List<Rect> trailing;
}

/// Lays out a bottom search bar [width] wide whose capsules' bottom edge
/// is at [bottom]: at rest ([focused] false) the [leading] and [trailing]
/// item widths around a flexible field, [MorphSearchTuning.restInset]
/// from the sides; focused, the field and the close button,
/// [MorphSearchTuning.focusedSideInset] from the sides. Items absent from
/// a configuration still get the slot they would take there, so they can
/// arrive from it. [rtl] mirrors everything.
@internal
MorphSearchBarGeometry morphSearchBarLayout({
  required double width,
  required double bottom,
  required bool focused,
  List<double> leading = const [],
  List<double> trailing = const [],
  bool rtl = false,
}) {
  const h = MorphSearchTuning.height;
  const gap = MorphSearchTuning.gap;
  final inset = focused
      ? MorphSearchTuning.focusedSideInset
      : MorphSearchTuning.restInset;
  final top = bottom - h;
  final lead = <Rect>[];
  var x = inset;
  for (final w in leading) {
    lead.add(Rect.fromLTWH(x, top, w, h));
    x += w + gap;
  }
  final trail = <Rect>[];
  var right = width - inset;
  for (final w in trailing.reversed) {
    trail.insert(0, Rect.fromLTWH(right - w, top, w, h));
    right -= w + gap;
  }
  final close = Rect.fromLTWH(width - inset - h, top, h, h);
  final Rect field;
  if (focused) {
    field = Rect.fromLTRB(inset, top, close.left - gap, bottom);
  } else {
    final left = leading.isEmpty ? inset : lead.last.right + gap;
    final end = trailing.isEmpty ? width - inset : trail.first.left - gap;
    field = Rect.fromLTRB(left, top, end, bottom);
  }
  if (!rtl) {
    return MorphSearchBarGeometry(
      field: field,
      close: close,
      leading: lead,
      trailing: trail,
    );
  }
  Rect mirror(Rect r) =>
      Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom);
  return MorphSearchBarGeometry(
    field: mirror(field),
    close: mirror(close),
    leading: [for (final r in lead) mirror(r)],
    trailing: [for (final r in trail) mirror(r)],
  );
}
