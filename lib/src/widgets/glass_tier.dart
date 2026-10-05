import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
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
/// a tier stops trying it. A step goes to the next of [tiers], skipping
/// the tiers left out of it. The values are engineering defaults, not
/// measurements of UIKit, which has no such tiers.
@immutable
class MorphGlassTierPolicy {
  /// Creates a policy.
  const MorphGlassTierPolicy({
    this.tiers = const {MorphGlassTier.flat, MorphGlassTier.liquid},
    this.window = 30,
    this.warmUp = const Duration(seconds: 1),
    this.stepDownMissRatio = 0.25,
    this.stepUpHeadroom = 0.6,
    this.stepUpAfter = const Duration(seconds: 5),
    this.maxStepUpAfter = const Duration(seconds: 80),
  });

  /// The tiers the automatic choice steps between, besides the ceiling,
  /// which it always may use.
  ///
  /// The default leaves out [MorphGlassTier.frosted]: on the iPhone 16
  /// Pro (profile, 2026-10-05, p95 raster ms over the glass audit's
  /// scenes) frosted costs more than liquid on segmented 2.29 vs 2.00,
  /// controls 3.65 vs 2.88, home scroll 2.51 vs 2.14 and sheet 3.92 vs
  /// 3.21, about the same on the tab bar 2.71 vs 2.74, and less only on
  /// the menu 2.25 vs 2.92, where its build p95 is higher, 3.77 vs 2.16:
  /// it blurs every glass surface where liquid frosts only bars, menus
  /// and lifted lenses, so a device that cannot hold liquid steps to
  /// flat. Without liquid (no Flutter GPU) the ceiling is frosted and
  /// stays in use.
  final Set<MorphGlassTier> tiers;

  /// The startup interval ignored after mounting or changing tiers.
  ///
  /// Engineering default, not measured: shader and route warm-up costs
  /// do not count as sustained rendering failures.
  final Duration warmUp;

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
      setEquals(other.tiers, tiers) &&
      other.window == window &&
      other.warmUp == warmUp &&
      other.stepDownMissRatio == stepDownMissRatio &&
      other.stepUpHeadroom == stepUpHeadroom &&
      other.stepUpAfter == stepUpAfter &&
      other.maxStepUpAfter == maxStepUpAfter;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(tiers),
    window,
    warmUp,
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
  }) : _tier = ceiling,
       _ladder = [
         for (final tier in MorphGlassTier.values)
           if (tier == ceiling ||
               (tier.index < ceiling.index && policy.tiers.contains(tier)))
             tier,
       ];

  /// The best tier the governor may pick.
  final MorphGlassTier ceiling;

  /// The thresholds.
  final MorphGlassTierPolicy policy;

  MorphGlassTier _tier;
  final List<MorphGlassTier> _ladder;
  final List<Duration> _costs = [];
  Duration? _changedAt;
  final Map<MorphGlassTier, int> _failures = {};

  /// The tier picked so far.
  MorphGlassTier get tier => _tier;

  /// The wait before stepping up to the tier above the current one.
  Duration get stepUpWait {
    final step = _ladder.indexOf(_tier);
    if (step < 0 || step + 1 >= _ladder.length) return Duration.zero;
    final above = _ladder[step + 1];
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
    if (now - _changedAt! < policy.warmUp) return false;
    _costs.add(build > raster ? build : raster);
    if (_costs.length < policy.window) return false;
    final misses = _costs.where((cost) => cost > budget).length;
    final sorted = List.of(_costs);
    sorted.sort();
    final p90 = sorted[((sorted.length - 1) * 0.9).round()];
    _costs.clear();
    final step = _ladder.indexOf(_tier);
    if (misses >= policy.stepDownMissRatio * policy.window && step > 0) {
      _failures[_tier] = (_failures[_tier] ?? 0) + 1;
      _tier = _ladder[step - 1];
      _changedAt = now;
      return true;
    }
    if (!gesture &&
        step + 1 < _ladder.length &&
        p90 <= budget * policy.stepUpHeadroom &&
        now - _changedAt! >= stepUpWait) {
      _tier = _ladder[step + 1];
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
/// with [onTierChanged]. An ancestor [BackdropGroup] is reused, otherwise
/// this widget installs one for its controls.
///
/// Resting glass in one [BackdropGroup] shares one copy of the screen,
/// taken where the group's first glass paints, so glass painted after
/// other content misses that content - a button on a card drawn over a
/// list whose own glass painted first shows the list as it stood before
/// the card. Give such a section a group of its own:
///
/// ```dart
/// BackdropGroup(child: card)
/// ```
///
/// Its glass then reads a copy taken where the section paints, at the
/// price of one more full-screen copy per frame while anything in it
/// moves. Bars, menus, sheets and lifted glass already take their own.
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
    morphLiquidGlassCapability.addListener(_capabilityChanged);
    _listen();
  }

  void _capabilityChanged() {
    if (!mounted) return;
    setState(() => _governor = _newGovernor());
    widget.onTierChanged?.call(
      widget.renderer
          .copyWith(tier: widget.tier ?? _governor.tier)
          .effectiveTier,
    );
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
        oldWidget.policy != widget.policy ||
        oldWidget.tier != widget.tier) {
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
    morphLiquidGlassCapability.removeListener(_capabilityChanged);
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = MorphGlass(
      painter: widget.renderer.copyWith(tier: widget.tier ?? _governor.tier),
      child: widget.child,
    );
    return BackdropGroup.of(context) == null
        ? BackdropGroup(child: glass)
        : glass;
  }
}
