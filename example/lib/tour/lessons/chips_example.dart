import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/ui/lab_chrome.dart';

/// The living-layout scene: a search app whose filter chips are one
/// fused row. The LAYOUT (a trivial left-to-right flow over
/// content-sized widths) only computes target slots; every chip rides
/// its own spring toward its slot. Two liquid-native choices give the
/// row its feel:
///
///  - Births and deaths are mass, not position, the way Liquid Glass
///    does them: a new chip is born at a fifth of its size at its slot
///    and springs to full size (the skin absorbs the droplet as it
///    grows), and a removed chip shrinks back to a fifth in place while
///    the next chip pours over it - parked inside the survivor, like
///    a glassEffectID member that leaves a merge. The last chip of the
///    row has no survivor to park in and deflates to nothing. No mass
///    ever pops.
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
  double deathScale = 0;
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
    // The newborn spawns AT its future slot as a droplet and grows
    // there - blooming out of the row, not a slide-in.
    double x = 0;
    for (final _Chip chip in _chips) {
      if (!chip.dying) {
        x += chip.width + _gap;
      }
    }
    final _Chip chip = _Chip(_nextId++, label, x);
    if (animateIn) {
      chip
        ..scale = MorphPieceChannel.birthScale
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
    // Death is shrinking in place: the chip keeps its spot while its
    // mass shrinks; slots are computed without it, so the next chip
    // pours over it and the droplet stays parked inside that survivor
    // until it settles. With nobody after it, nothing would cover the
    // droplet, so it deflates all the way.
    final bool covered = _chips
        .skip(index + 1)
        .any((_Chip next) => !next.dying);
    chip.dying = true;
    chip.deathScale = covered ? MorphPieceChannel.birthScale : 0;
    chip.scalePending = true;
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
          ..scaleSim = MorphPieceChannel.birthSpring
              .toMotion()
              .createSimulation(
                start: chip.scale,
                end: chip.dying ? chip.deathScale : 1,
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
              ..scale = chip.dying ? chip.deathScale : 1
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
  /// birth spring briefly over-inflates a newborn about 3 percent past
  /// 1, as Liquid Glass does.
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
    return SceneScaffold(
      controls: const Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          PanelHint(
            'Tap + to add a filter, tap a filter to remove it. Births '
            'and deaths are MASS: a newborn grows from a droplet at its '
            'slot, a removed one shrinks in place while the next chip '
            'pours over it.',
          ),
          PanelHint(
            'Edits ripple as a stiffness wave - near chips absorb the '
            'change briskly, far ones lazily. The layout only computes '
            'target slots; springs and mass do everything else.',
          ),
        ],
      ),
      phone: PhoneFrame(app: (BuildContext context) => _searchApp()),
    );
  }

  Widget _searchApp() {
    final double rowWidth = _chips.isEmpty
        ? 0
        : _chips
              .map((_Chip c) => c.position + c.width)
              .reduce((double a, double b) => a > b ? a : b);
    final int alive = _chips.where((_Chip c) => !c.dying).length;
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Padding(
          padding: const .fromLTRB(16, 12, 16, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const .symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: .circular(16),
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.search_rounded,
                        size: 17,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'late night mixes',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              LabIconButton(
                icon: Icons.add_rounded,
                onPressed: alive >= 8 ? null : _add,
                tint: const Color(0xFF7C5CFF).withValues(alpha: 0.8),
                padding: 10,
              ),
            ],
          ),
        ),
        SizedBox(
          height: _height + 56,
          child: ListView(
            scrollDirection: .horizontal,
            padding: const .symmetric(horizontal: 10),
            children: <Widget>[
              SizedBox(
                width: rowWidth + 40,
                height: _height + 56,
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
                              child: GestureDetector(
                                behavior: .opaque,
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
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const .fromLTRB(16, 4, 16, 14),
            itemCount: 5,
            itemBuilder: (BuildContext context, int index) => Padding(
              padding: const .only(bottom: 10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: .circular(10),
                      color: Colors.white.withValues(
                        alpha: 0.05 + 0.03 * (index % 3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: <Widget>[
                        Container(
                          height: 10,
                          width: 120.0 + (index * 43) % 90,
                          decoration: BoxDecoration(
                            borderRadius: .circular(5),
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          height: 8,
                          width: 80.0 + (index * 67) % 120,
                          decoration: BoxDecoration(
                            borderRadius: .circular(4),
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
