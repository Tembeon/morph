import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:morph/morph.dart';

/// Stress rig for the liquid skin: N pieces orbiting deterministic
/// paths on one canvas, so necks form and rip continuously while the
/// tracing pipeline recomputes every frame. Complements the isolated
/// microbenchmarks in benchmark/ by measuring the FULL frame (tracing +
/// shadow + raster + everything around it) via the on-screen FPS meter.
///
/// Motion is a pure function of elapsed time with per-piece phases from
/// the golden angle - runs are reproducible, no randomness.
///
/// Debug-mode numbers are pessimistic; judge real performance in
/// --profile or --release.
class StressLab extends StatefulWidget {
  /// Creates the stress rig.
  const StressLab({
    super.key,
    required this.count,
    required this.animate,
    required this.blend,
    required this.cell,
  });

  /// Number of orbiting pieces.
  final int count;

  /// Whether the orbits tick.
  final bool animate;

  /// Skin fusion width, forwarded from the LIQUID knobs.
  final double blend;

  /// Outline grid step, forwarded from the LIQUID knobs.
  final double cell;

  @override
  State<StressLab> createState() => _StressLabState();
}

class _StressLabState extends State<StressLab>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(
      (Duration elapsed) => setState(() {
        _time = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      }),
    );
    if (widget.animate) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(StressLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _ticker.start();
      } else {
        _ticker.stop();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<MorphPiece> _pieces(Size size) {
    final int count = widget.count;
    final int cols = math.max(
      1,
      math.sqrt(count * size.width / math.max(1, size.height)).round(),
    );
    final int rows = (count / cols).ceil();
    final double stepX = size.width / (cols + 1);
    final double stepY = size.height / (rows + 1);
    // The orbit amplitude deliberately exceeds half the lattice spacing
    // so neighbors keep crossing each other's blend reach: necks must
    // form and rip, not just wobble in place.
    final double ampX = stepX * 0.42;
    final double ampY = stepY * 0.42;
    const double goldenAngle = 2.399963229728653;

    return <MorphPiece>[
      for (int i = 0; i < count; i++)
        () {
          final double phase = i * goldenAngle;
          final double w1 = 0.5 + (i % 5) * 0.11;
          final double w2 = 0.4 + (i % 3) * 0.17;
          final Offset base = Offset(
            stepX * (1 + i % cols),
            stepY * (1 + i ~/ cols),
          );
          final Offset orbit = Offset(
            math.sin(_time * w1 + phase) * ampX,
            math.cos(_time * w2 + phase * 1.7) * ampY,
          );
          return MorphPiece(
            id: i,
            rect: .fromCenter(
              center: base + orbit,
              width: 46 + (i % 4) * 18,
              height: 34 + (i % 3) * 14,
            ),
            radius: 12 + (i % 3) * 6.0,
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: MorphSkin(
                blend: widget.blend,
                cell: widget.cell,
                color: const Color(0xFF2A2440),
                elevation: 5,
                pieces: _pieces(constraints.biggest),
              ),
            ),
            const Positioned(top: 8, right: 8, child: FpsMeter()),
          ],
        );
      },
    );
  }
}

/// A minimal frame meter: average FPS and the worst frame over the last
/// refresh window. Its own ticker keeps frames coming even on a static
/// scene, so the idle ceiling is visible too. The label refreshes twice
/// a second so the meter's own text relayout stays out of the numbers
/// it reports.
class FpsMeter extends StatefulWidget {
  /// Creates the meter.
  const FpsMeter({super.key});

  @override
  State<FpsMeter> createState() => _FpsMeterState();
}

class _FpsMeterState extends State<FpsMeter>
    with SingleTickerProviderStateMixin {
  static const double _windowMs = 500;

  late final Ticker _ticker;
  Duration? _last;
  double _accumulatedMs = 0;
  int _frames = 0;
  double _worstMs = 0;
  String _label = '... fps';

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final Duration? last = _last;
    _last = elapsed;
    if (last == null) {
      return;
    }
    final double ms = (elapsed - last).inMicroseconds / 1000;
    _accumulatedMs += ms;
    _frames++;
    if (ms > _worstMs) {
      _worstMs = ms;
    }
    if (_accumulatedMs >= _windowMs) {
      final double avgMs = _accumulatedMs / _frames;
      setState(() {
        _label =
            '${(1000 / avgMs).toStringAsFixed(0)} fps  '
            'avg ${avgMs.toStringAsFixed(1)}ms  '
            'worst ${_worstMs.toStringAsFixed(1)}ms';
      });
      _accumulatedMs = 0;
      _frames = 0;
      _worstMs = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const .symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: .circular(10),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white,
          fontFeatures: <FontFeature>[.tabularFigures()],
        ),
      ),
    );
  }
}
