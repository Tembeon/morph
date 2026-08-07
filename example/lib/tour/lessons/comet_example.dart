import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/morph.dart';

/// The goo comet: a chain of pieces chases the pointer, each link a
/// critically-damped spring tracking the previous one with softer
/// constants down the tail. The whole trail fuses into one mass whose
/// necks stretch and rip from pure velocity - and since EVERY pointer
/// move is a retarget, this toy is the interruption philosophy made
/// visceral: there is no timeline anywhere, only springs chasing
/// targets.
class CometExample extends StatefulWidget {
  /// Creates the chapter demo.
  const CometExample({super.key});

  @override
  State<CometExample> createState() => _CometExampleState();
}

class _CometExampleState extends State<CometExample>
    with SingleTickerProviderStateMixin {
  static const int _links = 9;

  late final Ticker _ticker;
  Duration _last = .zero;
  Offset _target = const Offset(300, 200);
  final List<Offset> _positions = <Offset>[];
  final List<Offset> _velocities = <Offset>[];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _links; i++) {
      _positions.add(_target);
      _velocities.add(Offset.zero);
    }
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final double dt = math.min(
      (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond,
      1 / 30,
    );
    _last = elapsed;
    if (dt <= 0) {
      return;
    }
    setState(() {
      Offset lead = _target;
      for (int i = 0; i < _links; i++) {
        // A critically damped spring per link (damping = 2*sqrt(k)),
        // stiffness falling down the tail so the comet stretches under
        // motion and regroups at rest.
        final double stiffness = 340.0 / (1 + i * 0.55);
        final double damping = 2 * math.sqrt(stiffness);
        final Offset delta = lead - _positions[i];
        _velocities[i] += (delta * stiffness - _velocities[i] * damping) * dt;
        _positions[i] += _velocities[i] * dt;
        lead = _positions[i];
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (PointerHoverEvent event) => _target = event.localPosition,
      child: GestureDetector(
        behavior: .opaque,
        onPanUpdate: (DragUpdateDetails details) =>
            _target = details.localPosition,
        onTapDown: (TapDownDetails details) => _target = details.localPosition,
        child: MorphSkin(
          blend: 30,
          color: const Color(0xFF6FD0BE),
          elevation: 3,
          pieces: <MorphPiece>[
            for (int i = 0; i < _links; i++)
              MorphPiece(
                id: i,
                rect: .fromCenter(
                  center: _positions[i],
                  width: 54.0 - i * 4.6,
                  height: 54.0 - i * 4.6,
                ),
                radius: 27,
              ),
          ],
        ),
      ),
    );
  }
}
