import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/morph.dart';

/// The layout-as-targets probe: a row of filter chips fused by one
/// skin. The LAYOUT (a trivial left-to-right flow over content-sized
/// widths) only computes target slots; every chip rides its own spring
/// toward its slot. Two liquid-native choices give the row its feel:
///
///  - Births and deaths are mass, not position: a new chip inflates
///    from nothing at its slot (the skin absorbs the droplet as it
///    grows) and a removed chip deflates in place while the neighbors
///    pour into the vacated space. No mass ever pops.
///  - The change propagates as a wave: each chip's spring stiffness
///    falls with its slot distance from the edit point, so near chips
///    absorb the change briskly and far ones lazily. Evaluating the
///    same spring at t*rate IS a softer spring (same damping ratio,
///    scaled frequency) - no timeline, retarget-safe.
class ChipsExample extends StatefulWidget {
  /// Creates the chapter demo.
  const ChipsExample({super.key, required this.motion});

  /// Motion profile of the demo springs and flights.
  final MorphMotion motion;

  @override
  State<ChipsExample> createState() => _ChipsExampleState();
}

class _Chip {
  _Chip(this.id, this.label, double x) : position = x, velocity = 0;

  final int id;
  final String label;
  double position;
  double velocity;
  Simulation? sim;
  Duration simStart = .zero;
  double target = 0;
  double rate = 1;

  double scale = 1;
  double scaleVelocity = 0;
  Simulation? scaleSim;
  Duration scaleStart = .zero;
  bool dying = false;
  bool scalePending = false;

  double get width => 56 + label.length * 8.0;
}

class _ChipsExampleState extends State<ChipsExample>
    with SingleTickerProviderStateMixin {
  static const List<String> _pool = <String>[
    'Ambient',
    'Lo-fi',
    'Synth',
    'Jazz',
    'Vapor',
    'Drone',
    'Chill',
    'Noise',
  ];
  static const double _gap = 12;
  static const double _height = 52;

  // Deliberately hand-rolled (not SingleMotionController): the wave
  // evaluates each sim at t*rate to soften springs by slot distance,
  // and a controller owns its own clock - it cannot time-scale.
  late final Ticker _ticker;
  final List<_Chip> _chips = <_Chip>[];
  int _nextId = 0;
  int _nextLabel = 0;
  Duration _now = .zero;

  @override
  void initState() {
    super.initState();
    // The ticker must exist before _add: re-slotting starts it.
    _ticker = createTicker(_tick);
    for (int i = 0; i < 4; i++) {
      _add(animateIn: false);
    }
  }

  void _add({bool animateIn = true}) {
    final String label = _pool[_nextLabel++ % _pool.length];
    // The newborn spawns AT its future slot with zero mass and inflates
    // there - a droplet blooming out of the row, not a slide-in.
    double x = 0;
    for (final _Chip chip in _chips) {
      if (!chip.dying) {
        x += chip.width + _gap;
      }
    }
    final _Chip chip = _Chip(_nextId++, label, x);
    if (animateIn) {
      chip
        ..scale = 0
        ..scalePending = true;
    }
    _chips.add(chip);
    _reslot(disturbance: _chips.length - 1);
  }

  void _remove(_Chip chip) {
    if (chip.dying) {
      return;
    }
    final int index = _chips.indexOf(chip);
    // Death is deflation in place: the chip keeps its spot while its
    // mass shrinks to nothing; slots are computed without it, so the
    // neighbors pour in and the skin swallows what remains.
    chip
      ..dying = true
      ..scalePending = true;
    _reslot(disturbance: index);
  }

  /// The "layout": target x positions from a trivial content-sized
  /// flow. Springs do the rest - each chip retargets from its CURRENT
  /// position and velocity.
  void _reslot({required int disturbance}) {
    // Ticker.elapsed restarts from zero on every start(): when the
    // ticker is idle, the stale _now from the previous run would put
    // simulation starts in the future, and springs evaluated at
    // negative time thrash. Reset the clock together with the ticker.
    if (!_ticker.isActive) {
      _now = .zero;
    }
    double x = 0;
    for (int i = 0; i < _chips.length; i++) {
      // The wave: stiffness falls with slot distance from the edit
      // point. The sim is evaluated at t*rate, so the stored velocity
      // (observed px/s) divides by the NEW rate on the way in and
      // multiplies by it on the way out - continuity holds across
      // retargets even when the rate changes.
      final _Chip chip = _chips[i]
        ..rate = 1 / (1 + 0.25 * (i - disturbance).abs());
      if (chip.dying) {
        chip.target = chip.position;
      } else {
        chip.target = x;
        x += chip.width + _gap;
      }
      chip
        ..sim = widget.motion.closeMotion.createSimulation(
          start: chip.position,
          end: chip.target,
          velocity: chip.velocity / chip.rate,
        )
        ..simStart = _now;
      if (chip.scalePending) {
        chip
          ..scalePending = false
          ..scaleSim = widget.motion.closeMotion.createSimulation(
            start: chip.scale,
            end: chip.dying ? 0 : 1,
            velocity: chip.scaleVelocity,
          )
          ..scaleStart = _now;
      }
    }
    if (!_ticker.isActive) {
      _ticker.start();
    }
    setState(() {});
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    bool anyActive = false;
    setState(() {
      for (final _Chip chip in _chips) {
        final Simulation? sim = chip.sim;
        if (sim != null) {
          final double t =
              (elapsed - chip.simStart).inMicroseconds /
              Duration.microsecondsPerSecond *
              chip.rate;
          chip
            ..position = sim.x(t)
            ..velocity = sim.dx(t) * chip.rate;
          if (sim.isDone(t)) {
            chip
              ..position = chip.target
              ..velocity = 0
              ..sim = null;
          } else {
            anyActive = true;
          }
        }
        final Simulation? scaleSim = chip.scaleSim;
        if (scaleSim != null) {
          final double t =
              (elapsed - chip.scaleStart).inMicroseconds /
              Duration.microsecondsPerSecond;
          chip
            ..scale = scaleSim.x(t)
            ..scaleVelocity = scaleSim.dx(t);
          if (scaleSim.isDone(t)) {
            chip
              ..scale = chip.dying ? 0 : 1
              ..scaleVelocity = 0
              ..scaleSim = null;
          } else {
            anyActive = true;
          }
        }
      }
      _chips.removeWhere((_Chip chip) => chip.dying && chip.scaleSim == null);
    });
    if (!anyActive) {
      _ticker.stop();
    }
  }

  /// The rendered mass: the slot rect scaled around its own center. The
  /// closeMotion overshoot briefly over-inflates a newborn past 1 - the
  /// droplet pops in with character.
  Rect _rectOf(_Chip chip) {
    final double s = chip.scale < 0 ? 0 : chip.scale;
    return Rect.fromCenter(
      center: Offset(chip.position + chip.width / 2, 30 + _height / 2),
      width: chip.width * s,
      height: _height * s,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double rowWidth = _chips.isEmpty
        ? 0
        : _chips
              .map((_Chip c) => c.position + c.width)
              .reduce((double a, double b) => a > b ? a : b);
    final int alive = _chips.where((_Chip c) => !c.dying).length;
    return Column(
      mainAxisAlignment: .center,
      children: <Widget>[
        SizedBox(
          height: _height + 60,
          width: .infinity,
          child: Center(
            child: SizedBox(
              width: rowWidth + 40,
              height: _height + 60,
              child: MorphSkin(
                blend: 18,
                color: const Color(0xFF241F35),
                elevation: 3,
                pieces: <MorphPiece>[
                  for (final _Chip chip in _chips)
                    MorphPiece(
                      id: chip.id,
                      rect: _rectOf(chip),
                      radius: _rectOf(chip).shortestSide / 2,
                      child: Opacity(
                        opacity: chip.scale.clamp(0.0, 1.0),
                        child: OverflowBox(
                          minWidth: chip.width,
                          maxWidth: chip.width,
                          minHeight: _height,
                          maxHeight: _height,
                          child: Transform.scale(
                            scale: chip.scale.clamp(0.0, 1.2),
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: chip.dying ? null : () => _remove(chip),
                              child: Center(
                                child: Text(
                                  chip.label,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: .w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.tonalIcon(
          onPressed: alive >= 8 ? null : _add,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add chip'),
        ),
        const SizedBox(height: 6),
        Text(
          'tap a chip to remove it - it deflates, neighbors pour in',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}
