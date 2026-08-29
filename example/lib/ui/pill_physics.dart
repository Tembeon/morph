import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:morph/widgets.dart';

/// The reference glide of a selection pill travelling between slots:
/// near-critically damped (~0.38 s, a whisper of bounce), so the
/// landing is precise and the squash-and-stretch - not the overshoot -
/// carries the life. Calibrated against the liquid-glass reference
/// pill; its companion springs there are a lift of ~0.40 s / bounce
/// 0.40 and a landing of ~0.39 s / bounce 0.45 that stops on its first
/// rebound through rest - adopt those numbers when a pill grows a
/// lifted state.
const Motion pillGlide = CupertinoMotion(
  duration: Duration(milliseconds: 376),
  bounce: 0.06,
);

/// Drives a [MorphSquash] from a spring the scene already owns: the
/// scene says where the body is each frame, this samples it and writes
/// the deformation out.
///
/// The clock comes from the ticker's own [Ticker.elapsed] deltas with a
/// null reset on wake - never a wall [Stopwatch], which advances in real
/// seconds while a test (or a time-dilated app) advances the springs in
/// its own, so the sampled acceleration would be off by that ratio and
/// the deformation would pin at its cap or never develop.
class SquashDriver {
  /// Creates a driver ticking on [vsync]; [position] is sampled every
  /// frame and [onFrame] receives the deformation to write out.
  SquashDriver({
    required TickerProvider vsync,
    required this.position,
    required this.onFrame,
    required this.isBusy,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  /// Where the body is now, in px.
  final Offset Function() position;

  /// Called after every sample with the live squash.
  final void Function(MorphSquash squash) onFrame;

  /// Whether the scene's own driver is still moving: the driver keeps
  /// ticking until this is false AND the deformation has drained.
  final bool Function() isBusy;

  final MorphSquash _squash = MorphSquash();
  late final Ticker _ticker;
  Duration? _last;
  double _now = 0;

  /// The live deformation, for a consumer that has to re-aim outside a
  /// frame (a layout change) without disturbing it.
  MorphSquash get squash => _squash;

  /// Starts sampling from a clean history - a fresh journey must not
  /// deform from the previous one's motion.
  void start() {
    if (_ticker.isActive) {
      return;
    }
    _squash.reset();
    _last = null;
    _ticker.start();
  }

  /// Releases the ticker.
  void dispose() => _ticker.dispose();

  void _tick(Duration elapsed) {
    final Duration last = _last ?? elapsed;
    _last = elapsed;
    final double dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0) {
      return;
    }
    _now += dt;
    _squash.track(position(), now: _now, dt: dt);
    onFrame(_squash);
    if (!isBusy() && _squash.isSettled) {
      _ticker.stop();
    }
  }
}
