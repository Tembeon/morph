import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:morph/widgets.dart';

/// Stress rig for the liquid skin: N pieces orbiting deterministic
/// paths on one canvas, so necks form and rip continuously while the
/// tracing pipeline recomputes every frame. The orbits ride the piece
/// geometry channels - the ticker writes offsets, the skin re-traces,
/// and not a single widget rebuilds or relayouts per frame.
/// Complements the isolated microbenchmarks in benchmark/ by measuring
/// the FULL frame (tracing + shadow + raster + everything around it)
/// via the on-screen FPS meter.
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

typedef _Grid = ({
  int cols,
  double stepX,
  double stepY,
  double ampX,
  double ampY,
});

class _StressLabState extends State<StressLab>
    with SingleTickerProviderStateMixin {
  static const double _goldenAngle = 2.399963229728653;

  late final Ticker _ticker;
  List<MorphPieceChannel> _channels = <MorphPieceChannel>[];
  Size _stage = Size.zero;

  @override
  void initState() {
    super.initState();
    _channels = _createChannels(widget.count);
    _ticker = createTicker(_tick);
    if (widget.animate) {
      _ticker.start();
    }
  }

  static List<MorphPieceChannel> _createChannels(int count) {
    return <MorphPieceChannel>[
      for (int i = 0; i < count; i++) MorphPieceChannel(),
    ];
  }

  @override
  void didUpdateWidget(StressLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count) {
      for (final MorphPieceChannel channel in _channels) {
        channel.dispose();
      }
      _channels = _createChannels(widget.count);
    }
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
    for (final MorphPieceChannel channel in _channels) {
      channel.dispose();
    }
    super.dispose();
  }

  // The whole per-frame path: N channel writes, zero rebuilds. The
  // skin subscribes to the channels and re-traces on paint.
  void _tick(Duration elapsed) {
    if (_stage.isEmpty) {
      return;
    }
    final double t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final _Grid grid = _gridFor(_stage, widget.count);
    for (int i = 0; i < _channels.length; i++) {
      _channels[i].update(offset: _orbit(grid, i, t));
    }
  }

  static _Grid _gridFor(Size size, int count) {
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
    return (
      cols: cols,
      stepX: stepX,
      stepY: stepY,
      ampX: stepX * 0.42,
      ampY: stepY * 0.42,
    );
  }

  static Offset _orbit(_Grid grid, int i, double t) {
    final double phase = i * _goldenAngle;
    final double w1 = 0.5 + (i % 5) * 0.11;
    final double w2 = 0.4 + (i % 3) * 0.17;
    return Offset(
      math.sin(t * w1 + phase) * grid.ampX,
      math.cos(t * w2 + phase * 1.7) * grid.ampY,
    );
  }

  List<MorphPiece> _pieces(Size size) {
    final _Grid grid = _gridFor(size, widget.count);
    return <MorphPiece>[
      for (int i = 0; i < widget.count; i++)
        MorphPiece(
          id: i,
          rect: .fromCenter(
            center: Offset(
              grid.stepX * (1 + i % grid.cols),
              grid.stepY * (1 + i ~/ grid.cols),
            ),
            width: 46 + (i % 4) * 18,
            height: 34 + (i % 3) * 14,
          ),
          radius: 12 + (i % 3) * 6.0,
          channel: _channels[i],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _stage = constraints.biggest;
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
