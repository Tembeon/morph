import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FramePhase;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// Builds a custom scenario control and emits its observable events.
typedef LabWidgetBuilder =
    Widget Function(
      Map<String, Object?> specification,
      void Function(String event, Object? value) emit,
    );

double _number(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;

Rect _rect(Object? value) {
  final parts = (value! as List<Object?>).cast<num>();
  return Rect.fromLTWH(
    parts[0].toDouble(),
    parts[1].toDouble(),
    parts[2].toDouble(),
    parts[3].toDouble(),
  );
}

/// Captures geometry and real input for a shared native/Flutter scenario.
class LabApp extends StatefulWidget {
  /// Creates a capture host with optional custom controls or a complete scene.
  const LabApp({
    required this.scenario,
    this.builders = const {},
    this.child,
    this.writeTrace = true,
    this.tier = MorphGlassTier.liquid,
    this.onRow,
    this.observables = const {},
    super.key,
  });

  /// The versioned scene and gesture specification.
  final Map<String, Object?> scenario;

  /// Additional control kinds keyed by scenario kind.
  final Map<String, LabWidgetBuilder> builders;

  /// A complete custom scene, tracked with the same selectors.
  final Widget? child;

  /// Whether to persist JSONL in the application temporary directory.
  final bool writeTrace;

  /// The renderer tier used for this capture.
  final MorphGlassTier tier;

  /// Receives telemetry before it is written to disk.
  final void Function(Map<String, Object?> row)? onRow;

  /// Extra numeric channels from custom motion or state adapters.
  final Map<String, Map<String, double> Function()> observables;

  @override
  State<LabApp> createState() => _LabAppState();
}

class _LabAppState extends State<LabApp> with SingleTickerProviderStateMixin {
  final Stopwatch _clock = Stopwatch();
  final Map<String, double> _values = {};
  Ticker? _ticker;
  IOSink? _sink;
  int _sequence = 0;
  final ValueNotifier<int> _marker = ValueNotifier<int>(0);
  double? _pointerOrigin;
  double _flushed = 0;
  bool _started = false;
  void Function(FlutterErrorDetails)? _previousErrorHandler;

  double get _now => _clock.elapsedMicroseconds / 1e6;

  @override
  void initState() {
    super.initState();
    _clock.start();
    _previousErrorHandler = FlutterError.onError;
    FlutterError.onError = _error;
    if (widget.writeTrace) {
      _sink = File('${Directory.systemTemp.path}/morph-lab.jsonl').openWrite();
    }
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _ticker = createTicker(_tick);
    _ticker!.start();
  }

  void _log(Map<String, Object?> row) {
    widget.onRow?.call(row);
    _sink?.writeln(jsonEncode(row));
    if (_now - _flushed > 0.5) {
      _flushed = _now;
      _sink?.flush();
    }
  }

  void _error(FlutterErrorDetails details) {
    _log({'k': 'lab_error', 't': _now, 'e': details.exceptionAsString()});
    _previousErrorHandler?.call(details);
  }

  void _pointer(PointerEvent event) {
    final phase = switch (event) {
      PointerDownEvent() => 0,
      PointerMoveEvent() => 1,
      PointerUpEvent() => 3,
      PointerCancelEvent() => 4,
      _ => null,
    };
    if (phase == null) return;
    _pointerOrigin ??= _now - event.timeStamp.inMicroseconds / 1e6;
    _log({
      'k': 'touch',
      't': event.timeStamp.inMicroseconds / 1e6 + _pointerOrigin!,
      'delivered_t': _now,
      'raw_timestamp_us': event.timeStamp.inMicroseconds,
      'clock_origin': _pointerOrigin,
      'phase': phase,
      'pointer': event.pointer.toString(),
      'x': event.position.dx,
      'y': event.position.dy,
      'pressure': event.pressure,
      'radius': event.radiusMajor,
      'kind': event.kind.name,
    });
  }

  void _timings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _log({
        'k': 'lab_timing',
        't': _now,
        'build_ms': timing.buildDuration.inMicroseconds / 1000,
        'raster_ms': timing.rasterDuration.inMicroseconds / 1000,
        'vsync_us': timing.timestampInMicroseconds(FramePhase.vsyncStart),
      });
    }
  }

  void _tick(Duration elapsed) {
    _sequence = (_sequence + 1) & 65535;
    _marker.value = _sequence;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sample());
  }

  void _sample() {
    if (!mounted) return;
    final began = _now;
    if (!_started) {
      _started = true;
      final view = View.of(context);
      final size = view.physicalSize / view.devicePixelRatio;
      final canvas = (widget.scenario['canvas']! as Map<String, Object?>)
          .cast<String, Object?>();
      _log({
        'k': 'lab_start',
        't': began,
        'side': 'flutter',
        'id': widget.scenario['id'],
        'w': size.width,
        'h': size.height,
        'scale': view.devicePixelRatio,
        'maxfps': view.display.refreshRate,
        'rm': view.platformDispatcher.accessibilityFeatures.reduceMotion,
        'rt': null,
        'os': Platform.operatingSystemVersion,
        'tier': widget.tier.name,
        'sha256': const String.fromEnvironment('MORPH_LAB_SHA256'),
      });
      if ((size.width - _number(canvas['width'])).abs() > 0.1 ||
          (size.height - _number(canvas['height'])).abs() > 0.1) {
        _log({'k': 'lab_error', 't': began, 'e': 'canvas mismatch'});
      }
    }
    _log({
      'k': 'lab_marker',
      't': began,
      'sequence': _sequence,
      'phase': 'postFrame',
      'frame_source_us':
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
    });
    final elements = <Element>[];
    void walk(Element element) {
      elements.add(element);
      element.visitChildren(walk);
    }

    context.visitChildElements(walk);
    final tracks = (widget.scenario['tracks']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final raw in tracks) {
      final track = raw.cast<String, Object?>();
      final selector = (track['flutter']! as Map<String, Object?>)
          .cast<String, Object?>();
      final found = elements.where((element) => _matches(element, selector));
      final list = found.toList();
      final indices = selector['all'] == true
          ? List<int>.generate(list.length, (index) => index)
          : [selector['index'] as int? ?? 0];
      if (list.isEmpty || indices.any((index) => index >= list.length)) {
        _log({'k': 'lab_missing', 'id': track['id'], 't': began});
      }
      for (final index in indices.where((index) => index < list.length)) {
        final element = list[index];
        var object = element.findRenderObject();
        if (selector['paintChild'] == true && object is RenderProxyBox) {
          object = object.child;
        }
        if (object is! RenderBox || !object.hasSize || !object.attached) {
          continue;
        }
        final matrix = object.getTransformTo(null);
        final rect = MatrixUtils.transformRect(
          matrix,
          Offset.zero & object.size,
        );
        final clips = <List<double>>[];
        var opacity = 1.0;
        RenderObject? child = object;
        RenderObject? ancestor = object.parent;
        while (ancestor != null) {
          if (ancestor is RenderOpacity) opacity *= ancestor.opacity;
          if (ancestor is RenderAnimatedOpacity) {
            opacity *= ancestor.opacity.value;
          }
          if (ancestor is RenderBox && ancestor.hasSize) {
            final clip = ancestor.describeApproximatePaintClip(child!);
            if (clip != null) {
              final box = MatrixUtils.transformRect(
                ancestor.getTransformTo(null),
                clip,
              );
              clips.add([box.left, box.top, box.width, box.height]);
            }
          }
          if (ancestor is RenderOffstage && ancestor.offstage) opacity = 0;
          child = ancestor;
          ancestor = ancestor.parent;
        }
        final values = <String, Object?>{
          'left': rect.left,
          'top': rect.top,
          'width': rect.width,
          'height': rect.height,
          'opacity': opacity,
          'scaleX': math.sqrt(
            matrix.entry(0, 0) * matrix.entry(0, 0) +
                matrix.entry(1, 0) * matrix.entry(1, 0),
          ),
          'scaleY': math.sqrt(
            matrix.entry(0, 1) * matrix.entry(0, 1) +
                matrix.entry(1, 1) * matrix.entry(1, 1),
          ),
        };
        if (object is RenderViewport) {
          values['scrollY'] = object.offset.pixels;
        }
        final properties = (track['properties'] as List<Object?>?)
            ?.cast<String>();
        if (properties != null) {
          values.removeWhere((key, value) => !properties.contains(key));
        }
        _log({
          'k': 'lab_sample',
          't': began,
          'id': selector['all'] == true ? '${track['id']}/$index' : track['id'],
          'identity': identityHashCode(object).toString(),
          'values': values,
          'clips': clips,
        });
      }
    }
    for (final entry in widget.observables.entries) {
      _log({
        'k': 'lab_sample',
        't': began,
        'id': entry.key,
        'identity': entry.key,
        'values': entry.value(),
        'clips': <Object?>[],
      });
    }
    _log({'k': 'lab_tick', 't': began, 'cost_ms': (_now - began) * 1000});
  }

  bool _matches(Element element, Map<String, Object?> selector) {
    final widget = element.widget;
    if (selector['type'] case final String type) {
      if (widget.runtimeType.toString() != type) return false;
    }
    if (selector['key'] case final String key) {
      if (widget.key != ValueKey<String>(key)) return false;
    }
    if (selector['text'] case final String text) {
      if (widget is! Text || widget.data != text) return false;
    }
    if (selector['within'] case final String key) {
      var matched = widget.key == ValueKey<String>(key);
      element.visitAncestorElements((ancestor) {
        matched = matched || ancestor.widget.key == ValueKey<String>(key);
        return !matched;
      });
      if (!matched) return false;
    }
    return true;
  }

  void _emit(String id, String event, Object? value) {
    _log({'k': 'lab_event', 't': _now, 'id': id, 'e': event, 'value': value});
  }

  Widget _control(Map<String, Object?> spec) {
    final id = spec['id']! as String;
    void emit(String event, Object? value) => _emit(id, event, value);
    if (widget.builders[spec['kind']] case final LabWidgetBuilder builder) {
      return builder(spec, emit);
    }
    final enabled = spec['enabled'] != false;
    final value = _values[id] ?? _number(spec['value'], 0.3);
    void changed(double next) {
      setState(() => _values[id] = next);
      emit('changed', next);
    }

    return switch (spec['kind']) {
      'button' => MorphGlassButton(
        padding: EdgeInsets.zero,
        onPressed: enabled ? () => emit('activate', null) : null,
        child: Text(spec['title'] as String? ?? 'Glass'),
      ),
      'slider' => MorphSlider(
        value: value,
        onChanged: enabled ? changed : null,
        semanticLabel: id,
      ),
      'switch' => MorphSwitch(
        value: (_values[id] ?? _number(spec['value'])) > 0,
        onChanged: enabled ? (next) => changed(next ? 1 : 0) : null,
        semanticLabel: id,
      ),
      'segmented' => MorphSegmentedControl(
        segments: (spec['labels']! as List<Object?>).cast<String>(),
        selected: (_values[id] ?? _number(spec['value'])).toInt(),
        onChanged: enabled ? (next) => changed(next.toDouble()) : null,
      ),
      'menu' => MorphMenuButton(
        items: [
          ..._items(spec['items']! as List<Object?>, emit),
          if (spec['systemFooter'] == 'askSiri') ...[
            MorphMenuWidget(
              height: 20,
              builder: (context) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(
                      color: MorphMenuStyle.resolve(
                        context,
                        null,
                      ).separatorColor,
                    ),
                  ),
                ),
              ),
            ),
            MorphMenuItem(
              title: 'Ask Siri',
              icon: Icons.circle_outlined,
              onSelected: () => emit('selected', 'Ask Siri'),
            ),
          ],
        ],
        semanticLabel: id,
      ),
      _ => throw StateError('No lab builder for ${spec['kind']}'),
    };
  }

  List<MorphMenuEntry> _items(
    List<Object?> items,
    void Function(String, Object?) emit,
  ) => items.map((raw) {
    final item = raw! as Map<String, Object?>;
    final children = item['children'];
    if (children is List<Object?>) {
      return MorphSubmenu(
        title: item['title']! as String,
        children: _items(children, emit),
      );
    }
    return MorphMenuItem(
      title: item['title']! as String,
      destructive: item['destructive'] == true,
      onSelected: () => emit('selected', item['title']),
    );
  }).toList();

  @override
  Widget build(BuildContext context) {
    final dark = widget.scenario['appearance'] == 'dark';
    final background = (widget.scenario['background']! as Map<String, Object?>)
        .cast<String, Object?>();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: DefaultTextStyle(
        style: TextStyle(
          fontSize: 17,
          color: dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
        ),
        child: MorphScope(
          child: MorphGlass(
            painter: MorphGlassRenderer(tier: widget.tier),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _LabBackgroundPainter(background)),
                if (widget.child != null) widget.child!,
                for (final raw
                    in (widget.scenario['widgets']! as List<Object?>)
                        .cast<Map<String, Object?>>())
                  Positioned.fromRect(
                    rect: _rect(raw['rect']),
                    child: SizedBox.expand(
                      key: ValueKey<String>(raw['id']! as String),
                      child: Semantics(
                        identifier: raw['id']! as String,
                        child: _control(raw.cast<String, Object?>()),
                      ),
                    ),
                  ),
                Positioned.fromRect(
                  rect: _rect(widget.scenario['marker'] ?? [8, 56, 100, 10]),
                  child: IgnorePointer(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _marker,
                      builder: (context, sequence, child) =>
                          CustomPaint(painter: _LabMarkerPainter(sequence)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _ticker?.dispose();
    _marker.dispose();
    _sink?.close();
    if (FlutterError.onError == _error) {
      FlutterError.onError = _previousErrorHandler;
    }
    super.dispose();
  }
}

class _LabMarkerPainter extends CustomPainter {
  const _LabMarkerPainter(this.sequence);
  final int sequence;

  @override
  void paint(Canvas canvas, Size size) {
    final bits = List<int>.generate(16, (index) => (sequence >> index) & 1);
    final parity = bits.fold<int>(0, (a, b) => a ^ b);
    final values = [0, 1, ...bits, parity, 1 - parity];
    final paint = Paint();
    for (var index = 0; index < 20; index++) {
      paint.color = values[index] == 1
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF000000);
      canvas.drawRect(
        Rect.fromLTWH(index * size.width / 20, 0, size.width / 20, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LabMarkerPainter oldDelegate) =>
      sequence != oldDelegate.sequence;
}

class _LabBackgroundPainter extends CustomPainter {
  const _LabBackgroundPainter(this.spec);
  final Map<String, Object?> spec;

  @override
  void paint(Canvas canvas, Size size) {
    final hex = spec['color'] as String? ?? '#F2F2F7';
    final paint = Paint();
    paint.color = Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
    canvas.drawRect(Offset.zero & size, paint);
    if (spec['kind'] == 'grid') {
      final cell = _number(spec['cell'], 12);
      const colors = [
        Color(0xFFFF0000),
        Color(0xFF00FF00),
        Color(0xFF0000FF),
        Color(0xFFFFFFFF),
      ];
      for (var row = 0; row < (size.height / cell).ceil(); row++) {
        for (var column = 0; column < (size.width / cell).ceil(); column++) {
          paint.color = colors[(row * 3 + column) % 4];
          canvas.drawRect(
            Rect.fromLTWH(column * cell, row * cell, cell, cell),
            paint,
          );
        }
      }
    }
    if (spec['kind'] == 'ramp') {
      final period = _number(spec['period'], 120);
      for (var column = 0; column < size.width.ceil(); column++) {
        final level = ((column % period) / period * 255).round();
        paint.color = Color.fromARGB(255, level, level, level);
        canvas.drawRect(
          Rect.fromLTWH(column.toDouble(), 0, 1, size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LabBackgroundPainter oldDelegate) =>
      spec != oldDelegate.spec;
}
