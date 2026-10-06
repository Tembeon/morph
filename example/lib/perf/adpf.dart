import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

typedef _GetManagerC = Pointer<Void> Function();
typedef _CreateSessionC =
    Pointer<Void> Function(Pointer<Void>, Pointer<Int32>, Size, Int64);
typedef _CreateSessionDart =
    Pointer<Void> Function(Pointer<Void>, Pointer<Int32>, int, int);
typedef _SessionInt64C = Int32 Function(Pointer<Void>, Int64);
typedef _SessionInt64Dart = int Function(Pointer<Void>, int);
typedef _SessionBoolC = Int32 Function(Pointer<Void>, Uint8);
typedef _ManagerInt64C = Int64 Function(Pointer<Void>);
typedef _ManagerInt64Dart = int Function(Pointer<Void>);
typedef _GetTidC = Int32 Function();
typedef _GetTidDart = int Function();
typedef _MallocC = Pointer<Void> Function(Size);
typedef _MallocDart = Pointer<Void> Function(int);

/// An experimental Android Performance Hint (ADPF) client for the device
/// energy audit, not a package feature.
///
/// It opens one hint session for the UI thread (the platform thread the
/// root isolate runs on, merged with the UI thread since Flutter 3.29) and
/// one for the engine's raster thread (`1.raster`), each with the measured
/// frame cadence as its target, and reports every frame's build and raster
/// durations from [ui.FrameTiming] as they arrive. The engine batches
/// timings (every 100 ms in a profile build, every second in a release
/// build), so the reports reach the system up to one batch late.
class GalleryPerformanceHints {
  GalleryPerformanceHints._(
    this._ui,
    this._raster,
    this._update,
    this._report,
    this.threads,
    this.preferredRateNs,
    this._targetNs,
  );

  /// Opens the sessions and starts reporting, or returns null where the
  /// platform has no hint manager or refuses a session; `powerEfficient`
  /// also asks both sessions to prefer power efficiency (API 35).
  static GalleryPerformanceHints? start({bool powerEfficient = false}) {
    if (!Platform.isAndroid) return null;
    final android = DynamicLibrary.open('libandroid.so');
    final libc = DynamicLibrary.open('libc.so');
    final getManager = android.lookupFunction<_GetManagerC, _GetManagerC>(
      'APerformanceHint_getManager',
    );
    final createSession = android
        .lookupFunction<_CreateSessionC, _CreateSessionDart>(
          'APerformanceHint_createSession',
        );
    final update = android.lookupFunction<_SessionInt64C, _SessionInt64Dart>(
      'APerformanceHint_updateTargetWorkDuration',
    );
    final report = android.lookupFunction<_SessionInt64C, _SessionInt64Dart>(
      'APerformanceHint_reportActualWorkDuration',
    );
    final rate = android.lookupFunction<_ManagerInt64C, _ManagerInt64Dart>(
      'APerformanceHint_getPreferredUpdateRateNanos',
    );
    final gettid = libc.lookupFunction<_GetTidC, _GetTidDart>('gettid');
    final malloc = libc.lookupFunction<_MallocC, _MallocDart>('malloc');
    final manager = getManager();
    if (manager == nullptr) return null;
    final uiTid = gettid();
    final rasterTid = _threadNamed('1.raster');
    if (rasterTid == null) return null;
    final refresh =
        ui.PlatformDispatcher.instance.displays.firstOrNull?.refreshRate ?? 60;
    final targetNs = (1e9 / refresh).round();
    final tids = malloc(4).cast<Int32>();
    Pointer<Void> open(int tid) {
      tids.value = tid;
      return createSession(manager, tids, 1, targetNs);
    }

    final uiSession = open(uiTid);
    final rasterSession = open(rasterTid);
    if (uiSession == nullptr || rasterSession == nullptr) return null;
    if (powerEfficient) {
      final prefer = android.lookupFunction<_SessionBoolC, _SessionInt64Dart>(
        'APerformanceHint_setPreferPowerEfficiency',
      );
      prefer(uiSession, 1);
      prefer(rasterSession, 1);
    }
    final hints = GalleryPerformanceHints._(
      uiSession,
      rasterSession,
      update,
      report,
      {'ui': uiTid, 'raster': rasterTid},
      rate(manager),
      targetNs,
    );
    SchedulerBinding.instance.addTimingsCallback(hints._onTimings);
    return hints;
  }

  static int? _threadNamed(String name) {
    for (final task in Directory('/proc/self/task').listSync()) {
      try {
        final comm = File('${task.path}/comm').readAsStringSync().trim();
        if (comm == name) return int.parse(task.path.split('/').last);
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  final Pointer<Void> _ui;
  final Pointer<Void> _raster;
  final _SessionInt64Dart _update;
  final _SessionInt64Dart _report;

  /// The thread ids the sessions hold, by role.
  final Map<String, int> threads;

  /// The rate at which the system wants reports, in nanoseconds.
  final int preferredRateNs;

  int _targetNs;
  int _lastVsyncUs = 0;
  final List<int> _intervalsUs = [];

  /// The frames reported so far.
  int reports = 0;

  /// The reports the system refused.
  int errors = 0;

  /// The targets set so far, in nanoseconds, the initial one first.
  late final List<int> targetsNs = [_targetNs];

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      final vsync = t.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      final interval = vsync - _lastVsyncUs;
      _lastVsyncUs = vsync;
      if (interval > 4000 && interval < 50000) _intervalsUs.add(interval);
      final build = t.buildDuration.inMicroseconds * 1000;
      final raster = t.rasterDuration.inMicroseconds * 1000;
      if (_report(_ui, build < 1000 ? 1000 : build) != 0) errors++;
      if (_report(_raster, raster < 1000 ? 1000 : raster) != 0) errors++;
      reports++;
    }
    if (_intervalsUs.length >= 60) {
      final sorted = [..._intervalsUs];
      sorted.sort();
      _intervalsUs.clear();
      final cadenceNs = sorted[sorted.length ~/ 10] * 1000;
      if ((cadenceNs - _targetNs).abs() * 10 > _targetNs) {
        _targetNs = cadenceNs;
        targetsNs.add(cadenceNs);
        _update(_ui, cadenceNs);
        _update(_raster, cadenceNs);
      }
    }
  }

  /// What the sessions did, for a report.
  Map<String, Object?> stats() => {
    'threads': threads,
    'preferred_rate_ns': preferredRateNs,
    'targets_ns': targetsNs,
    'reports': reports,
    'errors': errors,
  };
}
