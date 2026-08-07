import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:morph/morph.dart';

class _Sample {
  const _Sample(this.t, this.value, this.velocity, this.phase);

  final double t;
  final double value;
  final double velocity;
  final MorphPhase phase;
}

/// Debug HUD: a live graph of the spring rawValue colored by phase,
/// handoff markers, current velocity/phase/latch.
class SpringHud extends StatefulWidget {
  /// Creates the HUD bound to the scope's last flight.
  const SpringHud({super.key, required this.lastFlight});

  /// The flight source, usually MorphScopeState.lastFlight.
  final ValueListenable<MorphFlight?> lastFlight;

  @override
  State<SpringHud> createState() => _SpringHudState();
}

class _SpringHudState extends State<SpringHud> {
  static const double _window = 6;

  final Stopwatch _clock = Stopwatch()..start();
  final List<_Sample> _samples = <_Sample>[];
  final List<double> _handoffs = <double>[];
  MorphFlight? _flight;
  bool _lastHandedOff = true;

  @override
  void initState() {
    super.initState();
    widget.lastFlight.addListener(_onFlightChanged);
    _onFlightChanged();
  }

  @override
  void dispose() {
    widget.lastFlight.removeListener(_onFlightChanged);
    _detach();
    super.dispose();
  }

  void _detach() {
    _flight?.controller.removeListener(_onTick);
    _flight = null;
  }

  void _onFlightChanged() {
    _detach();
    final MorphFlight? next = widget.lastFlight.value;
    if (next != null) {
      _flight = next;
      _lastHandedOff = next.controller.hasHandedOff;
      next.controller.addListener(_onTick);
    }
  }

  void _onTick() {
    final MorphController c = _flight!.controller;
    final double t = _clock.elapsedMicroseconds / 1e6;
    _samples.add(_Sample(t, c.value, c.velocity, c.phase));
    if (!_lastHandedOff && c.hasHandedOff) {
      _handoffs.add(t);
    }
    _lastHandedOff = c.hasHandedOff;
    final double cutoff = t - _window;
    _samples.removeWhere((_Sample s) => s.t < cutoff);
    _handoffs.removeWhere((double h) => h < cutoff);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final MorphController? c = _flight?.controller;
    final MorphPhase phase = c?.phase ?? .idle;
    return Container(
      height: 150,
      margin: const .all(12),
      padding: const .fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.92),
        borderRadius: .circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          FittedBox(
            fit: .scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: <Widget>[
                Text(
                  'SPRING',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                for (final MorphPhase p in MorphPhase.values)
                  Padding(
                    padding: const .only(right: 6),
                    child: _PhaseChip(phase: p, active: p == phase),
                  ),
                const SizedBox(width: 18),
                _Stat(
                  label: 'value',
                  value: (c?.value ?? 0).toStringAsFixed(3),
                ),
                _Stat(
                  label: 'velocity',
                  value: (c?.velocity ?? 0).toStringAsFixed(2),
                ),
                _Stat(
                  label: 'latch',
                  value: (c?.hasHandedOff ?? true) ? 'armed' : 'flying',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              painter: _SpringPainter(
                samples: .of(_samples),
                handoffs: .of(_handoffs),
                now: _clock.elapsedMicroseconds / 1e6,
                scheme: scheme,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase, required this.active});

  final MorphPhase phase;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = phaseColor(phase, Theme.of(context).colorScheme);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const .symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.25) : Colors.transparent,
        borderRadius: .circular(20),
        border: Border.all(
          color: active ? color : color.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        phase.name,
        style: TextStyle(
          fontSize: 10,
          color: active ? color : color.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const .only(left: 14),
      child: Row(
        children: <Widget>[
          Text(
            '$label ',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          SizedBox(
            width: 52,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: <FontFeature>[.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The HUD accent for a flight phase.
Color phaseColor(MorphPhase phase, ColorScheme scheme) {
  return switch (phase) {
    .idle => scheme.onSurfaceVariant,
    .detaching => const Color(0xFFFFB74D),
    .travelling => const Color(0xFF4FC3F7),
    .arriving => const Color(0xFFBA68C8),
    .settled => const Color(0xFF81C784),
  };
}

class _SpringPainter extends CustomPainter {
  _SpringPainter({
    required this.samples,
    required this.handoffs,
    required this.now,
    required this.scheme,
  });

  static const double _window = 6;
  static const double _minY = -0.35;
  static const double _maxY = 1.35;

  final List<_Sample> samples;
  final List<double> handoffs;
  final double now;
  final ColorScheme scheme;

  double _x(double t, Size size) =>
      size.width - (now - t) / _window * size.width;

  double _y(double v, Size size) =>
      size.height - (v - _minY) / (_maxY - _minY) * size.height;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint guide = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final double level in <double>[0, 1]) {
      final double y = _y(level, size);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }

    if (samples.length > 1) {
      final Paint line = Paint()
        ..style = .stroke
        ..strokeWidth = 2
        ..strokeCap = .round;
      for (int i = 1; i < samples.length; i++) {
        final _Sample a = samples[i - 1];
        final _Sample b = samples[i];
        if (b.t - a.t > 0.25) {
          continue;
        }
        line.color = phaseColor(b.phase, scheme);
        canvas.drawLine(
          Offset(_x(a.t, size), _y(a.value, size)),
          Offset(_x(b.t, size), _y(b.value, size)),
          line,
        );
      }
    }

    final Paint latch = Paint()..color = const Color(0xFFE57373);
    for (final double h in handoffs) {
      final double x = _x(h, size);
      canvas
        ..drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          latch
            ..strokeWidth = 1
            ..style = .stroke,
        )
        ..drawCircle(Offset(x, _y(0, size)), 3.5, latch..style = .fill);
    }
  }

  @override
  bool shouldRepaint(_SpringPainter oldDelegate) => true;
}
