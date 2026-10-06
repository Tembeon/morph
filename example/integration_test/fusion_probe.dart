// The probe measures package internals by design.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/src/widgets/menu_fusion_worker.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import 'support/fusion_baseline.dart';
import 'support/fusion_inputs.dart';

/// The menu fusion probe: `morphMenuSilhouette` over the inputs the
/// gallery's rich menu fuses (support/fusion_inputs.dart), against the
/// frozen pre-2026-10-06 fusion (support/fusion_baseline.dart).
///
/// Build it as a profile app (`flutter build apk --profile -t
/// integration_test/fusion_probe.dart`, or macos) and read the `FUSION`
/// lines from stdout (logcat's `flutter` tag on Android). Phases:
/// - `hash`: both fusions' samples and paths, hashed, and whether they
///   are equal bit for bit;
/// - `tight`: every input timed back to back (warm), per fusion;
/// - `core`: the tight pass with the UI thread pinned to each CPU in
///   turn (Linux and Android: sched_setaffinity);
/// - `paced`: one input per frame, as the menu fuses, with the CPU the
///   call ran on, its wall and thread CPU time, the CPU's clock, and a
///   variant that evicts the caches before the call;
/// - `cpu`: Dart CPU samples of the tight pass by function.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Ticker());
  await Future<void>.delayed(const Duration(seconds: 2));
  final report = <String, Object?>{'platform': Platform.operatingSystem};
  void line(String text) {
    stdout.writeln('FUSION $text');
  }

  final sets = {
    'pixel6a': _inputs(fusionInputsPixel6a),
    'iphone16pro': _inputs(fusionInputsIphone16Pro),
  };
  final spin = int.parse(Platform.environment['FUSION_SPIN'] ?? '0');
  if (spin > 0) {
    final watch = Stopwatch();
    watch.start();
    final inputs = sets[_set]!;
    final fuse = Platform.environment['FUSION_SPIN_OLD'] == null
        ? morphMenuSilhouette
        : baselineMenuSilhouette;
    while (watch.elapsedMilliseconds < spin * 1000) {
      for (final (m, s, r) in inputs) {
        fuse(m, s, r);
      }
    }
    line('spun');
  }
  final hashes = <String, Object?>{};
  for (final MapEntry(key: name, value: inputs) in sets.entries) {
    var equal = 0;
    var hashNew = 0;
    var hashOld = 0;
    for (final (menu, source, radius) in inputs) {
      final a = _digest(morphMenuSilhouette(menu, source, radius));
      final b = _digest(baselineMenuSilhouette(menu, source, radius));
      hashNew = Object.hash(hashNew, a);
      hashOld = Object.hash(hashOld, b);
      if (a == b) equal++;
    }
    hashes[name] = {
      'equal': equal,
      'of': inputs.length,
      'new': hashNew,
      'old': hashOld,
    };
    line('hash $name equal $equal/${inputs.length} new $hashNew old $hashOld');
  }
  report['hash'] = hashes;

  final inputs = sets[_set]!;
  final tight = <String, Object?>{};
  for (final (name, fuse) in _fusions) {
    final per = _tight(inputs, fuse, passes: 10);
    tight[name] = {..._stats(per), 'per': per};
    line('tight $name ${_format(per)}');
  }
  report['tight'] = tight;

  final cpus = _Native.cpuCount();
  if (_Native.available && cpus > 0) {
    final cores = <String, Object?>{};
    for (var cpu = 0; cpu < cpus; cpu++) {
      if (!_Native.pin(cpu)) continue;
      final row = <String, Object?>{};
      for (final (name, fuse) in _fusions) {
        final per = _tight(inputs, fuse, passes: 3);
        row[name] = _stats(per);
        line('core $cpu $name ${_format(per)} on ${_Native.cpu()}');
      }
      cores['$cpu'] = row;
    }
    _Native.unpin(cpus);
    report['core'] = cores;
  }

  final paced = <String, Object?>{};
  for (final evict in [false, true, null]) {
    for (final (name, fuse) in _fusions) {
      final rows = await _paced(inputs, fuse, evict: evict, rounds: 3);
      final key =
          '$name${switch (evict) {
            true => '-evicted',
            false => '',
            null => '-spun',
          }}';
      paced[key] = rows;
      final wall = [for (final r in rows) r['wall_us']! as double];
      final thread = [for (final r in rows) r['cpu_us']! as double];
      final byCpu = <int, List<double>>{};
      for (final r in rows) {
        (byCpu[r['cpu']! as int] ??= []).add(r['wall_us']! as double);
      }
      line(
        'paced $key wall ${_format(wall)} thread ${_format(thread)} '
        'by cpu ${{for (final e in byCpu.entries) e.key: '${e.value.length}x${_median(e.value).round()}'}}',
      );
    }
  }
  report['paced'] = paced;

  report['worker'] = await _workerPhase(inputs);
  report['cpu'] = await _profile(inputs);
  final out = File('${Directory.systemTemp.path}/fusion_probe.json');
  out.writeAsStringSync(jsonEncode(report));
  line('report ${out.path}');
  line('done');
  await stdout.flush();
  exit(0);
}

const String _set = String.fromEnvironment(
  'FUSION_SET',
  defaultValue: 'pixel6a',
);

typedef _Fuse = MorphGlassOutline Function(RRect, RRect, double);

final List<(String, _Fuse)> _fusions = [
  ('new', morphMenuSilhouette),
  ('old', baselineMenuSilhouette),
];

List<(RRect, RRect, double)> _inputs(List<List<double>> rows) => [
  for (final v in rows)
    (
      RRect.fromLTRBXY(v[0], v[1], v[2], v[3], v[4], v[4]),
      RRect.fromLTRBXY(v[5], v[6], v[7], v[8], v[9], v[9]),
      v[10],
    ),
];

int _digest(MorphGlassOutline outline) {
  final field = morphGlassOutlineField(outline)!;
  final bytes = field.samples.buffer.asUint32List(
    field.samples.offsetInBytes,
    field.samples.length,
  );
  var h = Object.hash(field.cols, field.rows, field.step, field.origin);
  for (var i = 0; i < bytes.length; i++) {
    h = (h * 31 + bytes[i]) & 0x3FFFFFFFFFFF;
  }
  final path = outline.path;
  final bounds = path.getBounds();
  h = Object.hash(
    h,
    (bounds.width * 100).round(),
    (bounds.height * 100).round(),
  );
  for (var y = bounds.top - 1; y < bounds.bottom + 1; y += 0.5) {
    for (var x = bounds.left - 1; x < bounds.right + 1; x += 0.5) {
      h = (h * 3 + (path.contains(Offset(x, y)) ? 1 : 0)) & 0x3FFFFFFFFFFF;
    }
  }
  return h;
}

List<double> _tight(
  List<(RRect, RRect, double)> inputs,
  _Fuse fuse, {
  required int passes,
}) {
  for (var w = 0; w < 3; w++) {
    for (final (m, s, r) in inputs) {
      fuse(m, s, r);
    }
  }
  final per = List<double>.filled(inputs.length, 0);
  final watch = Stopwatch();
  for (var p = 0; p < passes; p++) {
    for (var i = 0; i < inputs.length; i++) {
      final (m, s, r) = inputs[i];
      watch.reset();
      watch.start();
      fuse(m, s, r);
      watch.stop();
      per[i] += watch.elapsedMicroseconds / passes;
    }
  }
  return per;
}

final Uint8List _evictBuffer = Uint8List(16 << 20);

Future<List<Map<String, Object?>>> _paced(
  List<(RRect, RRect, double)> inputs,
  _Fuse fuse, {
  required bool? evict,
  required int rounds,
}) async {
  final rows = <Map<String, Object?>>[];
  for (var round = 0; round < rounds; round++) {
    for (var i = 0; i < inputs.length; i++) {
      await SchedulerBinding.instance.endOfFrame;
      final done = Completer<void>();
      SchedulerBinding.instance.scheduleFrameCallback((Duration _) {
        if (evict == null) {
          final spin = Stopwatch();
          spin.start();
          while (spin.elapsedMicroseconds < 4000) {}
        } else if (evict) {
          var x = 0;
          for (var k = 0; k < _evictBuffer.length; k += 64) {
            x += _evictBuffer[k]++;
          }
          if (x == -1) stdout.writeln(x);
        }
        final (m, s, r) = inputs[i];
        final cpu = _Native.cpu();
        final freq = _Native.freq(cpu);
        final thread0 = _Native.threadMicros();
        final watch = Stopwatch();
        watch.start();
        fuse(m, s, r);
        watch.stop();
        final thread1 = _Native.threadMicros();
        rows.add({
          'i': i,
          'cpu': cpu,
          'cpu_after': _Native.cpu(),
          'khz': freq,
          'wall_us': watch.elapsedMicroseconds.toDouble(),
          'cpu_us': thread1 - thread0,
        });
        done.complete();
      });
      SchedulerBinding.instance.scheduleFrame();
      await done.future;
    }
  }
  return rows;
}

Future<Object?> _profile(List<(RRect, RRect, double)> inputs) async {
  try {
    final info = await developer.Service.getInfo();
    final uri = info.serverWebSocketUri;
    if (uri == null) return 'no vm service';
    final service = await vmServiceConnectUri(uri.toString());
    final isolate = developer.Service.getIsolateId(Isolate.current)!;
    await service.setFlag('profile_period', '100');
    await service.setFlag('profiler', 'true');
    final result = <String, Object?>{};
    for (final (name, fuse) in _fusions) {
      await service.clearCpuSamples(isolate);
      final from = developer.Timeline.now;
      _tight(inputs, fuse, passes: 10);
      final samples = await service.getCpuSamples(
        isolate,
        from,
        developer.Timeline.now - from,
      );
      final functions = samples.functions ?? const <vm.ProfileFunction>[];
      final self = <String, int>{};
      var total = 0;
      for (final sample in samples.samples ?? const <vm.CpuSample>[]) {
        final stack = sample.stack ?? const <int>[];
        if (stack.isEmpty) continue;
        total++;
        final Object? f = functions[stack.first].function;
        final key = switch (f) {
          vm.FuncRef(:final name, :final owner) => switch (owner) {
            vm.ClassRef(name: final c) => '$c.$name',
            vm.FuncRef(name: final o) => '$o.$name',
            _ => name ?? '?',
          },
          vm.NativeFunction(:final name) => 'native $name',
          _ => '$f',
        };
        self[key] = (self[key] ?? 0) + 1;
      }
      final top = self.entries.toList();
      top.sort((a, b) => b.value.compareTo(a.value));
      result[name] = {
        'samples': total,
        'self': [
          for (final e in top.take(25)) [e.key, e.value],
        ],
      };
      stdout.writeln(
        'FUSION cpu $name $total samples: ${[for (final e in top.take(12)) '${e.key} ${(100 * e.value / total).toStringAsFixed(1)}%'].join(', ')}',
      );
    }
    await service.dispose();
    return result;
  } on Object catch (error) {
    return '$error';
  }
}

Future<Map<String, Object?>> _workerPhase(
  List<(RRect, RRect, double)> inputs,
) async {
  MorphMenuFusion.debugPrefetch = true;
  final result = <String, Object?>{};
  for (var round = 0; round < 3; round++) {
    var hits = 0;
    final ui = <double>[];
    final uiHit = <double>[];
    final uiMiss = <double>[];
    final scratch = Float64List(11);
    for (var i = 0; i < inputs.length; i++) {
      await SchedulerBinding.instance.endOfFrame;
      final done = Completer<void>();
      SchedulerBinding.instance.scheduleFrameCallback((Duration _) {
        final (m, s, r) = inputs[i];
        final watch = Stopwatch();
        watch.start();
        final ahead = MorphFusionWorker.take(
          MorphMenuFusion.encode(m, s, r, scratch),
          0,
        );
        morphGlassOutlineFromParts(ahead ?? morphMenuSilhouetteParts(m, s, r));
        watch.stop();
        final us = watch.elapsedMicroseconds.toDouble();
        ui.add(us);
        if (ahead != null) {
          hits++;
          uiHit.add(us);
        } else {
          uiMiss.add(us);
        }
        if (i + 1 < inputs.length) {
          final (m2, s2, r2) = inputs[i + 1];
          MorphMenuFusion().prefetch(m2, s2, r2);
        }
        done.complete();
      });
      SchedulerBinding.instance.scheduleFrame();
      await done.future;
    }
    stdout.writeln(
      'FUSION worker round $round hits $hits/${inputs.length} ui ${_format(ui)} '
      'hit ${uiHit.isEmpty ? '-' : _format(uiHit)} miss ${uiMiss.isEmpty ? '-' : _format(uiMiss)}',
    );
    result['$round'] = {'hits': hits, 'ui': _stats(ui)};
    await Future<void>.delayed(const Duration(milliseconds: 200));
    MorphFusionWorker.reset();
  }
  MorphMenuFusion.debugPrefetch = null;
  return result;
}

double _median(List<double> values) {
  final sorted = [...values];
  sorted.sort();
  return sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2];
}

Map<String, double> _stats(List<double> values) {
  final sorted = [...values];
  sorted.sort();
  double at(double q) => sorted[((sorted.length - 1) * q).round()];
  return {
    'mean': values.fold(0.0, (a, b) => a + b) / values.length,
    'p50': at(0.5),
    'p95': at(0.95),
    'max': sorted.last,
  };
}

String _format(List<double> values) {
  final s = _stats(values);
  return 'mean ${s['mean']!.round()} p50 ${s['p50']!.round()} '
      'p95 ${s['p95']!.round()} max ${s['max']!.round()} us';
}

/// Keeps frames coming while the probe runs.
class _Ticker extends StatefulWidget {
  const _Ticker();

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _frame++;
    return ColoredBox(color: Color(0xFF000000 | (_frame & 0xFF)));
  }
}

final class _Timespec extends Struct {
  @Int64()
  external int seconds;

  @Int64()
  external int nanos;
}

/// libc through FFI: the CPU a thread runs on, pinning, thread CPU time
/// and the CPU's clock; Linux and Android only, inert elsewhere.
abstract final class _Native {
  static final bool available = Platform.isAndroid || Platform.isLinux;

  static final DynamicLibrary _libc = DynamicLibrary.process();

  static final int Function() _getcpu = _libc
      .lookupFunction<Int32 Function(), int Function()>('sched_getcpu');

  static final int Function(int, int, Pointer<Uint64>) _setaffinity = _libc
      .lookupFunction<
        Int32 Function(Int32, IntPtr, Pointer<Uint64>),
        int Function(int, int, Pointer<Uint64>)
      >('sched_setaffinity');

  static final int Function(int, Pointer<_Timespec>) _clock = _libc
      .lookupFunction<
        Int32 Function(Int32, Pointer<_Timespec>),
        int Function(int, Pointer<_Timespec>)
      >('clock_gettime');

  static final Pointer<Void> Function(int) _malloc = _libc
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');

  static final Pointer<_Timespec> _time = _malloc(16).cast<_Timespec>();
  static final Pointer<Uint64> _mask = _malloc(128).cast<Uint64>();

  static int cpu() => available ? _getcpu() : -1;

  static int cpuCount() => available ? Platform.numberOfProcessors : 0;

  static bool pin(int cpu) {
    for (var i = 0; i < 16; i++) {
      _mask[i] = 0;
    }
    _mask[cpu ~/ 64] = 1 << (cpu % 64);
    return _setaffinity(0, 128, _mask) == 0;
  }

  static void unpin(int cpus) {
    for (var i = 0; i < 16; i++) {
      _mask[i] = 0;
    }
    for (var c = 0; c < cpus; c++) {
      _mask[c ~/ 64] |= 1 << (c % 64);
    }
    _setaffinity(0, 128, _mask);
  }

  static double threadMicros() {
    final id = Platform.isMacOS || Platform.isIOS ? 16 : 3;
    if (_clock(id, _time) != 0) return 0;
    return _time.ref.seconds * 1e6 + _time.ref.nanos / 1e3;
  }

  static int freq(int cpu) {
    if (cpu < 0) return 0;
    try {
      return int.parse(
        File(
          '/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq',
        ).readAsStringSync().trim(),
      );
    } on Object {
      return 0;
    }
  }
}
