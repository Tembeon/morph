import 'dart:math' as math;

import 'package:morph/src/gesture.dart';
import 'package:morph/src/widgets/flex_integrator.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// The tuning of a selection lens, as measured on a UIKit control.
///
/// [segmented] and [tabBar] are fitted to frame-by-frame recordings of
/// UISegmentedControl and UITabBar on iOS 27; the two controls share the
/// travel and lift springs and differ in when they react, how far the lens
/// lifts and how strongly it deforms.
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
    required this.restingGain,
    required this.restingThreshold,
    required this.restingWidthCap,
    required this.restingStretchCoefficient,
    required this.liftedGain,
    required this.liftedThreshold,
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
    this.restingSoftness = (0.55, 1.26),
    this.liftedSoftness = (0.54, 1.34),
    this.liftedStretchRatio = 1.191,
    this.liftedStretchKnee = 0.158,
    this.liftedStretchSoftness = (0.961, 0.0847),
    this.chromeGrowth = 0,
    this.chromeSpring = const MorphSpring(0.356, 0.593),
    this.chromeLag = 0.02,
  });

  /// Whether a touch selects on contact (tab bar) or on release
  /// (segmented control).
  final bool selectsOnPointerDown;

  /// How many pixels the lens widens while lifted.
  final double liftWidth;

  /// How many pixels the lens grows taller while lifted.
  final double liftHeight;

  /// The spring that carries the lens between slots after a tap.
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
  final MorphSpring presentationSpring;

  /// The spring that makes a dragged lens follow the finger.
  final MorphSpring followSpring;

  /// Drift per unit of filtered acceleration per pixel of resting width.
  final double restingGain;

  /// Where the resting drift turns soft, as a fraction of the width.
  final double restingThreshold;

  /// The width beyond which the resting deformation stops growing.
  final double restingWidthCap;

  /// How strongly resting drift squashes the lens across its motion.
  final double restingStretchCoefficient;

  /// The soft knee of the resting drift as (strength, width).
  final (double, double) restingSoftness;

  /// Drift per unit of filtered acceleration per pixel of lifted width.
  final double liftedGain;

  /// Where the lifted drift turns soft, as a fraction of the width.
  final double liftedThreshold;

  /// The soft knee of the lifted drift as (strength, width).
  final (double, double) liftedSoftness;

  /// How strongly lifted stretch squashes the lens across its motion.
  final double liftedStretchRatio;

  /// The cross-axis squash at which the lifted response turns soft.
  final double liftedStretchKnee;

  /// The soft knee of the lifted squash as (strength, width).
  final (double, double) liftedStretchSoftness;

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
    restingGain: 2.5e-5,
    restingThreshold: 0.05,
    restingWidthCap: 100,
    restingStretchCoefficient: 2,
    liftedGain: 2.626e-5,
    liftedThreshold: 0.0555,
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
    restingGain: 2.785e-5,
    restingThreshold: 0.069,
    restingWidthCap: double.infinity,
    restingStretchCoefficient: 2.82,
    liftedGain: 3.0e-5,
    liftedThreshold: 0.0555,
    rubberBand: (4.55, 0.95),
    pressDelay: 0.05,
    dragGain: 1.013,
    chromeGrowth: 14.6,
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
       _selected = selected,
       _restWidth = slots[selected].width,
       _frames = MorphSubClock(frameRate) {
    final slot = _slots[selected];
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

  /// Whether the lens moves for Reduce Motion: it travels between slots
  /// but never lifts, deforms or grows the control. This approximates
  /// the platform's behavior; it is not measured.
  bool reducedMotion;

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
  double? _previousVisible;
  bool _flag = false;

  _Pointer? _pointer;

  /// Called with the new index whenever the selection changes.
  void Function(int index)? onSelect;

  double get _now => _timeline.now;

  /// The index of the selected slot.
  int get selected => _selected;

  /// The slots the lens can rest in.
  List<MorphLensSlot> get slots => _slots;

  /// Replaces the slots, snapping the lens to the selected one.
  set slots(List<MorphLensSlot> value) {
    _slots = List.of(value);
    _selected = _selected.clamp(0, _slots.length - 1);
    final slot = _slots[_selected];
    _travel.snap(_now, slot.center);
    _width.snap(_now, slot.width);
    _restWidth = slot.width;
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

  /// Whether every spring is at rest.
  bool get isSettled =>
      _pointer == null &&
      _timeline.isEmpty &&
      _travel.isAtRest(_now) &&
      _width.isAtRest(_now) &&
      _lift.isAtRest(_now) &&
      _chrome.isAtRest(_now) &&
      _drift.isAtRest(_now, 0.01) &&
      _scaleX.isAtRest(_now, 1e-4) &&
      _scaleY.isAtRest(_now, 1e-4);

  /// The index of the slot nearest to [x].
  int slotAt(double x) {
    var best = 0;
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
    final index = slotAt(x);
    final onSelected = index == _selected;
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
    final index = slotAt(x);
    if (pointer.pressedSelected) {
      if (index != _selected) _setSelected(index);
      final slot = _slots[_selected];
      _restWidth = slot.width;
      _timeline.at(t + tuning.releaseDelay, (double s) {
        _travel.retarget(s, slot.center, spring: tuning.travelSpring);
        _width.retarget(s, slot.width);
      });
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
    _travel.retarget(t, _slots[_selected].center, spring: tuning.travelSpring);
    _flag = false;
    _lift.retarget(t, 0);
  }

  /// Selects [index] without a touch: the lens travels without lifting.
  void select(double t, int index) {
    advance(t);
    if (index == _selected) return;
    _setSelected(index);
    final slot = _slots[index];
    _resetFlex();
    _travel.retarget(t, slot.center, spring: tuning.travelSpring);
    _width.retarget(t, slot.width);
    _restWidth = slot.width;
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
    final af = _flex.af;
    double drift;
    double sx;
    double sy;
    if (_flag) {
      final lifted = width + tuning.liftWidth;
      final threshold = tuning.liftedThreshold * lifted;
      drift =
          -threshold *
          _soft(
            tuning.liftedGain * lifted * af / threshold,
            tuning.liftedSoftness,
          );
      final e = -2 * drift / lifted;
      sx = 1 + e;
      final q = tuning.liftedStretchRatio * e;
      final knee = tuning.liftedStretchKnee;
      final (strength, softWidth) = tuning.liftedStretchSoftness;
      sy =
          1 -
          (q <= knee
              ? q
              : knee + strength * softWidth * _tanh((q - knee) / softWidth));
    } else {
      final capped = math.min(width, tuning.restingWidthCap);
      final threshold = tuning.restingThreshold * capped;
      drift =
          -threshold *
          _soft(
            tuning.restingGain * capped * af / threshold,
            tuning.restingSoftness,
          );
      sx = 1 - 2 * drift / width;
      sy = 1 + tuning.restingStretchCoefficient * drift / capped;
    }
    _drift.retarget(t, drift * _flex.vf.sign);
    _scaleX.retarget(t, sx);
    _scaleY.retarget(t, sy);
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
    _travel.retarget(t, target, spring: tuning.followSpring);
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
      _travel.retarget(s, slot.center, spring: tuning.travelSpring);
      _width.retarget(s, slot.width);
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

  static double _soft(double x, (double, double) softness) {
    final ax = x.abs();
    if (ax <= 1) return x;
    final (strength, width) = softness;
    return x.sign * (1 + strength * width * _tanh((ax - 1) / width));
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
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
  double x;
  double unliftNotBefore = 0;
}
