import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// How [MorphAdaptiveGlass] steps the glass tier by the frames the device
/// achieves.
///
/// Frames are judged in windows of [window] frames against the display's
/// frame budget (1 / refresh rate). A window in which at least
/// [stepDownMissRatio] of the frames missed the budget - their build or
/// their raster took longer - steps the tier down at once, mid-gesture
/// too. A window whose 90th percentile frame took at most [stepUpHeadroom]
/// of the budget steps it up again, but never while a finger is down and
/// only [stepUpAfter] after the last change; every time a tier fails again
/// that wait doubles, up to [maxStepUpAfter], so a device that cannot hold
/// a tier stops trying it. The values are engineering defaults, not
/// measurements of UIKit, which has no such tiers.
@immutable
class MorphGlassTierPolicy {
  /// Creates a policy.
  const MorphGlassTierPolicy({
    this.window = 30,
    this.stepDownMissRatio = 0.25,
    this.stepUpHeadroom = 0.6,
    this.stepUpAfter = const Duration(seconds: 5),
    this.maxStepUpAfter = const Duration(seconds: 80),
  });

  /// The frames judged together.
  final int window;

  /// The share of a window's frames that must miss the budget to step
  /// down.
  final double stepDownMissRatio;

  /// The share of the budget a window's 90th percentile frame may take to
  /// step up.
  final double stepUpHeadroom;

  /// The quiet time after a change before the tier may step up.
  final Duration stepUpAfter;

  /// The longest [stepUpAfter] grows to after repeated failures.
  final Duration maxStepUpAfter;

  @override
  bool operator ==(Object other) =>
      other is MorphGlassTierPolicy &&
      other.window == window &&
      other.stepDownMissRatio == stepDownMissRatio &&
      other.stepUpHeadroom == stepUpHeadroom &&
      other.stepUpAfter == stepUpAfter &&
      other.maxStepUpAfter == maxStepUpAfter;

  @override
  int get hashCode => Object.hash(
    window,
    stepDownMissRatio,
    stepUpHeadroom,
    stepUpAfter,
    maxStepUpAfter,
  );
}

/// The pure decision behind [MorphAdaptiveGlass]: the tier as a function
/// of the frames it is fed, the time and whether a finger is down.
@internal
class MorphGlassTierGovernor {
  /// Starts at [ceiling], never going above it.
  MorphGlassTierGovernor({
    required this.ceiling,
    this.policy = const MorphGlassTierPolicy(),
  }) : _tier = ceiling;

  /// The best tier the governor may pick.
  final MorphGlassTier ceiling;

  /// The thresholds.
  final MorphGlassTierPolicy policy;

  MorphGlassTier _tier;
  final List<Duration> _costs = [];
  Duration? _changedAt;
  final Map<MorphGlassTier, int> _failures = {};

  /// The tier picked so far.
  MorphGlassTier get tier => _tier;

  /// The wait before stepping up to the tier above the current one.
  Duration get stepUpWait {
    if (_tier.index >= ceiling.index) return Duration.zero;
    final above = MorphGlassTier.values[_tier.index + 1];
    final failures = _failures[above] ?? 0;
    var wait = policy.stepUpAfter;
    for (var i = 1; i < failures && wait < policy.maxStepUpAfter; i++) {
      wait *= 2;
    }
    return wait < policy.maxStepUpAfter ? wait : policy.maxStepUpAfter;
  }

  /// Feeds one frame that took [build] on the UI thread and [raster] on
  /// the raster thread against [budget], reported at [now]; [gesture] is
  /// whether a finger is down. Returns whether the tier changed.
  bool addFrame({
    required Duration build,
    required Duration raster,
    required Duration budget,
    required Duration now,
    required bool gesture,
  }) {
    _changedAt ??= now;
    _costs.add(build > raster ? build : raster);
    if (_costs.length < policy.window) return false;
    final misses = _costs.where((cost) => cost > budget).length;
    final sorted = List.of(_costs);
    sorted.sort();
    final p90 = sorted[((sorted.length - 1) * 0.9).round()];
    _costs.clear();
    if (misses >= policy.stepDownMissRatio * policy.window &&
        _tier != MorphGlassTier.flat) {
      _failures[_tier] = (_failures[_tier] ?? 0) + 1;
      _tier = MorphGlassTier.values[_tier.index - 1];
      _changedAt = now;
      return true;
    }
    if (!gesture &&
        _tier.index < ceiling.index &&
        p90 <= budget * policy.stepUpHeadroom &&
        now - _changedAt! >= stepUpWait) {
      _tier = MorphGlassTier.values[_tier.index + 1];
      _changedAt = now;
      return true;
    }
    return false;
  }
}

/// Installs a [MorphGlassRenderer] whose tier follows the frame timings
/// the device achieves, unless [tier] fixes it.
///
/// The [renderer]'s own tier is the best one used. Frame timings come from
/// [SchedulerBinding.addTimingsCallback]; [policy] says when to step down
/// and back up. The tier never steps up while a finger is down, so a
/// control never changes its look under the finger it is following;
/// stepping down is immediate. The shapes, motion and fusion of every
/// control are the same on every tier.
///
/// Read the tier in use with [MorphAdaptiveGlass.tierOf] or follow it
/// with [onTierChanged].
class MorphAdaptiveGlass extends StatefulWidget {
  /// Installs [renderer] for [child] at [tier], or at the tier the frame
  /// timings allow when [tier] is null.
  const MorphAdaptiveGlass({
    required this.child,
    this.renderer = const MorphGlassRenderer(),
    this.tier,
    this.policy = const MorphGlassTierPolicy(),
    this.onTierChanged,
    super.key,
  });

  /// The renderer; its tier is the best one the automatic choice uses.
  final MorphGlassRenderer renderer;

  /// The tier to draw, or null to choose it from the frame timings.
  final MorphGlassTier? tier;

  /// When the automatic choice steps the tier.
  final MorphGlassTierPolicy policy;

  /// Called when the tier in use changes.
  final ValueChanged<MorphGlassTier>? onTierChanged;

  /// The subtree that draws its glass with the renderer.
  final Widget child;

  /// The effective tier of the [MorphGlassRenderer] installed above
  /// [context], or null when the painter above is not one.
  static MorphGlassTier? tierOf(BuildContext context) =>
      switch (MorphGlass.maybeOf(context)) {
        final MorphGlassRenderer renderer => renderer.effectiveTier,
        _ => null,
      };

  @override
  State<MorphAdaptiveGlass> createState() => _MorphAdaptiveGlassState();
}

class _MorphAdaptiveGlassState extends State<MorphAdaptiveGlass> {
  late MorphGlassTierGovernor _governor = _newGovernor();
  final Set<int> _pointers = {};
  bool _listening = false;
  Duration _budget = const Duration(microseconds: 16667);

  MorphGlassTierGovernor _newGovernor() => MorphGlassTierGovernor(
    ceiling: widget.renderer.effectiveTier,
    policy: widget.policy,
  );

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rate = View.maybeOf(context)?.display.refreshRate ?? 60;
    _budget = Duration(microseconds: (1e6 / (rate > 0 ? rate : 60)).round());
  }

  @override
  void didUpdateWidget(MorphAdaptiveGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderer.effectiveTier != widget.renderer.effectiveTier ||
        oldWidget.policy != widget.policy) {
      _governor = _newGovernor();
    }
    _listen();
  }

  void _listen() {
    final automatic = widget.tier == null;
    if (automatic == _listening) return;
    _listening = automatic;
    if (automatic) {
      SchedulerBinding.instance.addTimingsCallback(_timings);
      GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    } else {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
      _pointers.clear();
    }
  }

  void _pointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointers.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
  }

  void _timings(List<FrameTiming> timings) {
    if (!mounted) return;
    final before = _governor.tier;
    for (final timing in timings) {
      _governor.addFrame(
        build: timing.buildDuration,
        raster: timing.rasterDuration,
        budget: _budget,
        now: Duration(
          microseconds: timing.timestampInMicroseconds(FramePhase.rasterFinish),
        ),
        gesture: _pointers.isNotEmpty,
      );
    }
    if (_governor.tier != before) {
      setState(() {});
      widget.onTierChanged?.call(_governor.tier);
    }
  }

  @override
  void dispose() {
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MorphGlass(
      painter: widget.renderer.copyWith(tier: widget.tier ?? _governor.tier),
      child: widget.child,
    );
  }
}
