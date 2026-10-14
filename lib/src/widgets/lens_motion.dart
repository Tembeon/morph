import 'dart:math' as math;
import 'dart:ui';

import 'package:morph/src/gesture.dart';
import 'package:morph/src/widgets/flex_integrator.dart';
import 'package:morph/src/widgets/flex_interaction.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// The tuning of a selection lens, as measured on a UIKit control.
///
/// [segmented] and [tabBar] are fitted to frame-by-frame recordings of
/// UISegmentedControl and UITabBar on iOS 27; the two controls share the
/// travel and lift springs and differ in when they react, how far the lens
/// lifts and how strongly it deforms.
///
/// The lens settles once every part's remaining swing is below
/// [MorphRest] (0.1 pt, 0.3 device px at 3x; an opacity half an 8-bit
/// step) and snaps onto its targets: invisible, NEAR.
class MorphLensTuning {
  /// Creates a tuning from explicit values.
  const MorphLensTuning({
    required this.selectsOnPointerDown,
    required this.liftWidth,
    required this.liftHeight,
    required this.hangTime,
    required this.hangTimePerPixel,
    required this.hangFromTouch,
    required this.presentationSpring,
    required this.followSpring,
    required this.rubberBand,
    required this.pressDelay,
    this.dragGain = 1,
    this.pressHang = 0.25,
    this.releaseDelay = 0.03,
    this.travelSpring = const MorphSpring(0.401, 0.856),
    this.liftSpring = const MorphSpring(0.25, 1),
    this.startDelay = 0.02,
    this.flagLead = 0.025,
    this.hangReferenceDistance = 70,
    this.chromeGrowth = 0,
    this.chromeSpring = const MorphSpring(0.356, 0.593),
    this.chromeLag = 0.02,
    this.reducedMotionTravelSpring,
  });

  /// Whether a touch selects on contact (tab bar) or on release
  /// (segmented control).
  final bool selectsOnPointerDown;

  /// How many pixels the lens widens while lifted.
  final double liftWidth;

  /// How many pixels the lens grows taller while lifted.
  final double liftHeight;

  /// The spring that carries the lens between slots after a tap:
  /// 0.401/0.856 fitted to test/fixtures/ios27{,-device}/lens. The
  /// device segmented replay and tab bar scrub release reject the former
  /// passport value 0.392/0.863 at their unchanged tolerances
  /// (lens_test.dart and lens_scrub_test.dart).
  final MorphSpring travelSpring;

  /// The spring that lifts and lands the lens and resizes it between
  /// slots of different widths.
  final MorphSpring liftSpring;

  /// Seconds between a tap's selection and the start of the motion.
  final double startDelay;

  /// Seconds by which the deformation switches to its lifted response
  /// before the visible lift starts and before the visible landing.
  final double flagLead;

  /// Seconds a tapped lens stays lifted, counted from the start of the
  /// lift.
  final double hangTime;

  /// Whether [hangTime] counts from the touch that selected rather than
  /// from the start of the lift; the segmented control lands a fixed time
  /// after the release whatever the input latency.
  final bool hangFromTouch;

  /// Additional hang time per pixel of travel beyond
  /// [hangReferenceDistance].
  final double hangTimePerPixel;

  /// The travel distance at which [hangTime] applies unchanged.
  final double hangReferenceDistance;

  /// The spring that carries the deformation toward its target.
  ///
  /// The targets are UIKit's flex movement law for a loupe of the lens's
  /// size ([MorphFlexSpec.loupeForSize] of the resting lens, or of the
  /// fully lifted one while it is lifted). Read from UIKit, notes private;
  /// fed UIKit's own filtered motion, the law reproduces the targets UIKit
  /// recorded on an iPhone 16 Pro (`ios27-device/lens`): scale x to
  /// 0.0053 / 0.0003 rms on the segmented control resting / lifted and
  /// 0.0028 / 0.00003 on the tab bar.
  final MorphSpring presentationSpring;

  /// The spring that makes a dragged lens follow the finger.
  final MorphSpring followSpring;

  /// The rubber band past the first and last slots as (limit, stiffness):
  /// a lens dragged past an end slot travels at most limit pixels beyond
  /// it, in [morphRubberband]'s form.
  final (double, double) rubberBand;

  /// How far the lens moves per pixel the finger drags it.
  ///
  /// The lens follows the finger's travel since the touch times this gain,
  /// measured in the control's own coordinates; a swelling control scales
  /// the lens around its center on top of that.
  final double dragGain;

  /// Seconds between a touch on the selected item and the start of its
  /// lift.
  final double pressDelay;

  /// The shortest time, in seconds from the touch, a pressed selected
  /// lens stays lifted.
  final double pressHang;

  /// Seconds between the release of a held lens and the start of its
  /// travel to the chosen slot and of its landing.
  final double releaseDelay;

  /// How many pixels the whole control widens while it is pressed.
  final double chromeGrowth;

  /// The spring of the control's press growth.
  final MorphSpring chromeSpring;

  /// Seconds the press growth lags behind the finger.
  final double chromeLag;

  /// The spring that carries the lens between slots, and after a dragging
  /// finger, for Reduce Motion; null when the selection does not travel
  /// then.
  ///
  /// UITabBar keeps moving its selection under Reduce Motion on dampingRatio
  /// 0.9, response 0.2 for taps and scrubs alike (its own springs are 0.85
  /// over 0.4 for a tap, which [travelSpring] fits, and 0.85 over 0.2 while
  /// scrubbing). UISegmentedControl disables its sliding selection: each
  /// segment shows its own, so the selection appears on the new segment
  /// and a press on the selected one neither lifts nor drags it. Read
  /// from UIKit, notes private; whether the segment's selection fades in
  /// is not recorded yet (it appears at once here).
  final MorphSpring? reducedMotionTravelSpring;

  /// The lens of a UISegmentedControl.
  static const segmented = MorphLensTuning(
    selectsOnPointerDown: false,
    liftWidth: 24,
    liftHeight: 16,
    hangTime: 0.25,
    hangTimePerPixel: 0,
    hangFromTouch: true,
    presentationSpring: MorphSpring(0.442, 0.582),
    followSpring: MorphSpring(0.225, 1),
    rubberBand: (12, 0.55),
    pressDelay: 0.04,
  );

  /// The lens of a floating UITabBar.
  static const tabBar = MorphLensTuning(
    selectsOnPointerDown: true,
    liftWidth: 16,
    liftHeight: 16,
    hangTime: 0.215,
    hangTimePerPixel: 0.000274,
    hangFromTouch: false,
    presentationSpring: MorphSpring(0.5, 0.73),
    followSpring: MorphSpring(0.271, 0.803),
    rubberBand: (4.55, 0.95),
    pressDelay: 0.05,
    dragGain: 1.013,
    chromeGrowth: 14.6,
    reducedMotionTravelSpring: MorphSpring(0.2, 0.9),
  );
}

/// A slot the lens can rest in: its center and width along the track.
typedef MorphLensSlot = ({double center, double width});

/// The motion of a liquid selection lens: a pure function of the touches
/// it is fed and the time it is advanced to.
///
/// The lens frame rides three springs: travel for the center, and one
/// shared lift spring for the lift and for width changes between slots.
/// On top of that runs UIKit's closed deformation loop: every frame the
/// visible center is filtered three times, the rate of change of its
/// speed becomes a drift of the lens's trailing edge plus a matching
/// stretch, and both follow their targets on a presentation spring. The
/// leading edge therefore rides the travel spring exactly. The loop steps
/// on a fixed [frameRate] in motion time, so the deformation is the same
/// on any display and under any time dilation.
///
/// Feed pointer events with their timestamps, call [advance] with the
/// frame time, then read [center], [size], [scaleX] and [scaleY]. All
/// lengths are pixels along the track, all times seconds.
class MorphLensMotion {
  /// Creates a lens resting in [selected] among [slots].
  /// Empty slots have selection -1 and ignore input; other indices clamp
  /// to the available slots.
  ///
  /// [startDelay] overrides the tuning's delay between a selecting touch
  /// and the start of the motion.
  MorphLensMotion({
    required this.tuning,
    required List<MorphLensSlot> slots,
    required int selected,
    required this.height,
    this.frameRate = 120,
    this.reducedMotion = false,
    double? startDelay,
  }) : startDelay = startDelay ?? tuning.startDelay,
       _slots = List.of(slots),
       _selected = _index(selected, slots.length),
       _restWidth = slots.isEmpty
           ? 0
           : slots[_index(selected, slots.length)].width,
       _frames = MorphSubClock(frameRate) {
    final slot = _slot;
    _travel = MorphSpringState(tuning.travelSpring, slot.center);
    _width = MorphSpringState(tuning.liftSpring, slot.width);
    _lift = MorphSpringState(tuning.liftSpring, 0);
    _chrome = MorphSpringState(tuning.chromeSpring, 0);
    _drift = MorphSpringState(tuning.presentationSpring, 0);
    _scaleX = MorphSpringState(tuning.presentationSpring, 1);
    _scaleY = MorphSpringState(tuning.presentationSpring, 1);
  }

  /// The measured behavior this lens reproduces.
  final MorphLensTuning tuning;

  /// The resting height of the lens.
  final double height;

  /// The frames per second of motion time the deformation loop steps at:
  /// 120 for a ProMotion display, 60 for a 60 Hz one.
  final double frameRate;

  /// Seconds between a selecting touch and the start of the motion.
  final double startDelay;

  /// Whether the lens moves for Reduce Motion: it never lifts, as UIKit's
  /// lens does not (read from UIKit, notes private), and travels on the
  /// tuning's [MorphLensTuning.reducedMotionTravelSpring] or not at all.
  /// Its deformation and the control's press growth staying off are
  /// approximations, not recorded yet.
  bool reducedMotion;

  bool get _slides =>
      !reducedMotion || tuning.reducedMotionTravelSpring != null;

  MorphSpring get _travelSpring => reducedMotion
      ? tuning.reducedMotionTravelSpring ?? tuning.travelSpring
      : tuning.travelSpring;

  void _travelTo(double t, MorphLensSlot slot) {
    if (_slides) {
      _travel.retarget(t, slot.center, spring: _travelSpring);
      _width.retarget(t, slot.width);
    } else {
      _travel.snap(t, slot.center);
      _width.snap(t, slot.width);
    }
  }

  List<MorphLensSlot> _slots;
  int _selected;
  late final MorphSpringState _travel;
  late final MorphSpringState _width;
  late final MorphSpringState _lift;
  late final MorphSpringState _chrome;
  late final MorphSpringState _drift;
  late final MorphSpringState _scaleX;
  late final MorphSpringState _scaleY;
  double _restWidth;

  final MorphTimeline _timeline = MorphTimeline(now: 0);
  final MorphSubClock _frames;
  final MorphFlexIntegrator _flex = MorphFlexIntegrator();
  bool _started = false;
  Size? _loupeSize;
  MorphFlexSpec _loupe = MorphFlexSpec.smallLoupe;
  double? _previousVisible;
  bool _flag = false;

  _Pointer? _pointer;

  /// Called with the new index whenever the selection changes.
  void Function(int index)? onSelect;

  /// Whether the slot at an index can be selected; null makes every slot
  /// selectable.
  ///
  /// A touch landing on a slot that cannot be selected neither selects
  /// nor lifts the lens, but still swells the control (a disabled
  /// UITabBarItem on an iPhone 16 Pro, iOS 27.0.1: the bar grows under
  /// the finger, the lens stays). A drag released over such a slot
  /// returns to the selected one.
  bool Function(int index)? isSelectable;

  bool _selectable(int index) => isSelectable?.call(index) ?? true;

  double get _now => _timeline.now;

  /// The index of the selected slot, or -1 when there are no slots.
  int get selected => _selected;

  static int _index(int index, int count) =>
      count == 0 ? -1 : index.clamp(0, count - 1);

  MorphLensSlot _slotFor(int index) => _slots.isEmpty
      ? (center: 0, width: 0)
      : _slots[_index(index, _slots.length)];

  MorphLensSlot get _slot => _slotFor(_selected);

  /// The slots the lens can rest in.
  List<MorphLensSlot> get slots => _slots;

  /// Replaces the slots, snapping the lens to the selected one.
  set slots(List<MorphLensSlot> value) {
    _slots = List.of(value);
    _selected = _index(_selected, _slots.length);
    final slot = _slot;
    _travel.snap(_now, slot.center);
    _width.snap(_now, slot.width);
    _restWidth = slot.width;
    if (_slots.isEmpty) {
      _timeline.clear();
      _pointer = null;
      _flag = false;
      _lift.retarget(_now, 0);
      _chrome.retarget(_now, 0);
    }
    _drift.snap(_now, 0);
    _scaleX.snap(_now, 1);
    _scaleY.snap(_now, 1);
    _previousVisible = slot.center;
    _flex.reset(slot.center);
  }

  /// The time the lens was last advanced to.
  double get time => _now;

  /// The center the travel spring carries, before the deformation drift.
  double get travelCenter => _travel.value(_now);

  /// The visible center along the track, drift included.
  double get center => _travel.value(_now) + _drift.value(_now);

  /// The lens bounds before the deformation scale: rest size plus lift.
  ({double width, double height}) get size {
    final lift = _lift.value(_now);
    return (
      width: _width.value(_now) + tuning.liftWidth * lift,
      height: height + tuning.liftHeight * lift,
    );
  }

  /// The deformation scale along the track.
  double get scaleX => _scaleX.value(_now);

  /// The deformation scale across the track.
  double get scaleY => _scaleY.value(_now);

  /// The lift progress, 0 resting and 1 fully lifted.
  double get lift => _lift.value(_now);

  /// How many pixels the whole control is widened by the press.
  double get chromeGrowth => tuning.chromeGrowth * _chrome.value(_now);

  /// Whether the finger currently drags the lens.
  bool get isDragging => _pointer?.dragging ?? false;

  /// Whether what remains of the motion is invisible: no touch, nothing
  /// pending, and every spring's remaining swing below [MorphRest]
  /// (NEAR, invisible; [settle] snaps the rest).
  bool get isSettled {
    if (_pointer != null || !_timeline.isEmpty) return false;
    const length = MorphRest.length;
    final lifted = math.max(tuning.liftWidth, tuning.liftHeight);
    final scale = MorphRest.scale(_restWidth + tuning.liftWidth);
    return _travel.isWithin(_now, length) &&
        _width.isWithin(_now, length) &&
        _lift.isWithin(_now, length / math.max(lifted, 1)) &&
        _chrome.isWithin(_now, length / math.max(tuning.chromeGrowth, 1)) &&
        _drift.isWithin(_now, length) &&
        _drift.target.abs() < length &&
        _scaleX.isWithin(_now, scale) &&
        (_scaleX.target - 1).abs() < scale &&
        _scaleY.isWithin(_now, scale) &&
        (_scaleY.target - 1).abs() < scale;
  }

  /// Puts a settled lens exactly onto its slot, flat and undeformed.
  void settle() {
    _travel.settle(_now);
    _width.settle(_now);
    _lift.settle(_now);
    _chrome.settle(_now);
    _drift.snap(_now, 0);
    _scaleX.snap(_now, 1);
    _scaleY.snap(_now, 1);
    _previousVisible = _travel.target;
    _flex.reset(_travel.target);
  }

  /// The index of the slot nearest to [x].
  int slotAt(double x) {
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < _slots.length; i++) {
      final distance = (_slots[i].center - x).abs();
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// A finger touched the track at [x].
  void pointerDown(double t, double x) {
    advance(t);
    if (_slots.isEmpty || _pointer != null) return;
    final index = slotAt(x);
    if (!_selectable(index)) {
      final inert = _Pointer(offset: 0, pressedSelected: false, downX: x);
      inert.inert = true;
      _pointer = inert;
      _chromeTo(t + tuning.chromeLag, 1);
      return;
    }
    final onSelected = index == _selected && _slides;
    final pointer = _Pointer(
      offset: center - x,
      pressedSelected: onSelected,
      downX: x,
    );
    _pointer = pointer;
    _chromeTo(t + tuning.chromeLag, 1);
    if (onSelected) {
      _flagOn(t);
      final liftAt = t + tuning.pressDelay;
      pointer.unliftNotBefore = t + tuning.pressHang;
      _timeline.at(liftAt, (double s) {
        if (!pointer.cancelled) _liftTo(s, 1);
      });
    } else if (tuning.selectsOnPointerDown) {
      pointer.pressedSelected = true;
      pointer.offset = 0;
      _selectWithLift(t, index, hold: true);
    }
  }

  /// The finger moved to [x].
  void pointerMove(double t, double x) {
    advance(t);
    final pointer = _pointer;
    if (pointer == null || !pointer.pressedSelected) return;
    pointer.dragging = true;
    pointer.x = x;
  }

  /// The finger left the track at [x]; the slot nearest the finger wins.
  void pointerUp(double t, double x) {
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    _chromeTo(t + tuning.chromeLag, 0);
    if (pointer.inert) return;
    final under = slotAt(x);
    final index = _selectable(under) ? under : _selected;
    if (pointer.pressedSelected) {
      if (index != _selected) _setSelected(index);
      final slot = _slots[_selected];
      _restWidth = slot.width;
      _timeline.at(
        t + tuning.releaseDelay,
        (double s) => _travelTo(s, _slotFor(index)),
      );
      final unliftAt = math.max(
        t + tuning.releaseDelay,
        pointer.unliftNotBefore,
      );
      _timeline.at(unliftAt - tuning.flagLead, (s) => _flag = false);
      _timeline.at(unliftAt, (s) => _lift.retarget(s, 0));
    } else {
      _selectWithLift(t, index, hold: false);
    }
  }

  /// The touch was cancelled; the lens returns to the selected slot.
  void pointerCancel(double t) {
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    pointer.cancelled = true;
    _chromeTo(t + tuning.chromeLag, 0);
    if (!pointer.pressedSelected) return;
    final slot = _slots[_selected];
    _travelTo(t, slot);
    _restWidth = slot.width;
    _flag = false;
    _lift.retarget(t, 0);
  }

  /// Selects the clamped [index] without a touch: the lens travels without
  /// lifting. With [notify] false, reconciles the parent's selection and
  /// cancels pending touch reactions without calling [onSelect].
  void select(double t, int index, {bool notify = true}) {
    advance(t);
    if (_slots.isEmpty) return;
    final selected = _index(index, _slots.length);
    if (selected == _selected) return;
    if (!notify) {
      _timeline.clear();
      _flag = false;
      _lift.retarget(t, 0);
    }
    _selected = selected;
    if (notify) onSelect?.call(selected);
    final slot = _slots[selected];
    _resetFlex();
    _travelTo(t, slot);
    _restWidth = slot.width;
  }

  /// Puts the lens at rest on the clamped [index] at once, without
  /// travel, lift or [onSelect]: where a control that showed no selection
  /// shows one appear. Cancels a touch and pending reactions.
  void place(double t, int index) {
    advance(t);
    if (_slots.isEmpty) return;
    _timeline.clear();
    _pointer = null;
    _flag = false;
    _selected = _index(index, _slots.length);
    _lift.snap(t, 0);
    slots = _slots;
  }

  /// Advances the lens to time [t], stepping the deformation loop once
  /// for every frame of [frameRate] on the way.
  void advance(double t) {
    if (!_started) {
      _started = true;
      _timeline.runDue(t);
      _frames.start(t);
      _previousVisible = center;
      return;
    }
    if (t < _now) return;
    _frames.run(t, _frame);
    _timeline.runDue(t);
  }

  void _frame(double t) {
    _timeline.runDue(t);
    final pointer = _pointer;
    if (pointer != null && pointer.dragging) _follow(t, pointer);
    final visible = _travel.value(t) + _drift.value(t);
    final previous = _previousVisible ?? visible;
    if (_flex.pf != null) {
      _flex.step(previous, _frames.frame);
      _retargetFlex(t);
    }
    _previousVisible = visible;
  }

  void _retargetFlex(double t) {
    if (reducedMotion) {
      _drift.retarget(t, 0);
      _scaleX.retarget(t, 1);
      _scaleY.retarget(t, 1);
      return;
    }
    final width = _restWidth;
    if (width <= 0) return;
    final size = _flag
        ? Size(width + tuning.liftWidth, height + tuning.liftHeight)
        : Size(width, height);
    if (size != _loupeSize) {
      _loupeSize = size;
      _loupe = MorphFlexSpec.loupeForSize(size);
    }
    final v = MorphFlexInteraction.withMovement(
      MorphFlexInteraction.rest,
      spec: _loupe,
      size: size,
      acceleration: Offset(_flex.af, 0),
      velocity: Offset(_flex.vf, 0),
    );
    _drift.retarget(t, v.driftX);
    _scaleX.retarget(t, v.scaleX);
    _scaleY.retarget(t, v.scaleY);
  }

  void _follow(double t, _Pointer pointer) {
    final first = _slots.first.center;
    final last = _slots.last.center;
    final anchor = pointer.downX + pointer.offset;
    final u = pointer.x + pointer.offset;
    final inside = u.clamp(first, last);
    final (limit, stiffness) = tuning.rubberBand;
    final excess = u - inside;
    final band =
        excess.sign *
        morphRubberband(excess.abs(), dimension: limit, coefficient: stiffness);
    final target = anchor + tuning.dragGain * (inside - anchor) + band;
    _travel.retarget(
      t,
      target,
      spring: reducedMotion
          ? tuning.reducedMotionTravelSpring ?? tuning.followSpring
          : tuning.followSpring,
    );
    final under = slotAt(_travel.value(t));
    if (_slots[under].width != _width.target) {
      _width.retarget(t, _slots[under].width);
      _restWidth = _slots[under].width;
    }
  }

  void _selectWithLift(double t, int index, {required bool hold}) {
    final from = _slots[_selected].center;
    if (index != _selected) _setSelected(index);
    final slot = _slots[index];
    _flagOn(t);
    final start = t + startDelay;
    final distance = (slot.center - from).abs();
    final hang =
        tuning.hangTime +
        tuning.hangTimePerPixel *
            math.max(0, distance - tuning.hangReferenceDistance);
    _restWidth = slot.width;
    _timeline.at(start, (s) {
      _travelTo(s, _slotFor(index));
      _liftTo(s, 1);
    });
    final landing = (tuning.hangFromTouch ? t : start) + hang;
    if (hold) {
      _pointer?.unliftNotBefore = landing;
    } else {
      _timeline.at(landing - tuning.flagLead, (s) => _flag = false);
      _timeline.at(landing, (s) => _lift.retarget(s, 0));
    }
  }

  void _flagOn(double t) {
    _flag = true;
    _resetFlex();
  }

  void _resetFlex() {
    _flex.reset(_previousVisible ?? center);
  }

  void _chromeTo(double t, double target) {
    if (tuning.chromeGrowth == 0) return;
    _timeline.at(t, (s) => _chrome.retarget(s, reducedMotion ? 0 : target));
  }

  void _liftTo(double t, double target) {
    _lift.retarget(t, reducedMotion ? 0 : target);
  }

  void _setSelected(int index) {
    _selected = index;
    onSelect?.call(index);
  }
}

class _Pointer {
  _Pointer({
    required this.offset,
    required this.pressedSelected,
    required this.downX,
  }) : x = downX;

  double offset;
  bool pressedSelected;
  final double downX;
  bool dragging = false;
  bool cancelled = false;
  bool inert = false;
  double x;
  double unliftNotBefore = 0;
}
