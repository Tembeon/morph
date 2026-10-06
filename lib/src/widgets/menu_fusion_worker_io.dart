import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_fusion.dart';

/// Background isolates that fuse menu silhouettes ahead of the frames
/// that show them.
///
/// The UI isolate posts, once a frame, the inputs it expects a coming
/// frame to fuse ([request]: the menu shape, the button shape and the
/// fusion radius as eleven numbers, `MorphMenuFusion.encode`); a worker
/// computes `morphMenuSilhouetteParts` and sends the parts back, the
/// field samples without a copy. Up to [poolSize] workers run, one
/// request each; requests made while every worker runs wait, the
/// [waitingLimit] newest of them, for the first worker that returns. [take] hands
/// out an arrived fusion whose inputs are within a tolerance of the
/// inputs the frame fuses.
///
/// The workers spawn on demand and live for the isolate's lifetime; they
/// fail closed - any error stops them, and every fusion is then computed
/// where it is needed.
@internal
abstract final class MorphFusionWorker {
  /// Whether this platform can run the worker.
  static const bool supported = true;

  /// The most workers that run at once.
  static const int poolSize = 4;

  /// The most requests that wait for a worker.
  static const int waitingLimit = 3;

  /// The most arrived fusions kept for [take].
  static const int keep = 9;

  static final List<_Worker> _workers = [];
  static ReceivePort? _port;
  static bool _failed = false;
  static final List<Float64List> _waiting = [];
  static final List<(Float64List, MorphGlassOutlineParts)> _ready = [];

  /// Asks a worker for the fusion of [inputs].
  static void request(Float64List inputs) {
    if (_failed) return;
    final port = _port ??= _listen();
    for (final worker in _workers) {
      if (!worker.busy && worker.send != null) {
        worker.dispatch(inputs);
        return;
      }
    }
    _waiting.add(inputs);
    if (_waiting.length > waitingLimit) _waiting.removeAt(0);
    if (_workers.length < poolSize &&
        _workers.every((_Worker worker) => worker.send != null)) {
      _spawn(port);
    }
  }

  /// An arrived fusion whose every input is within [tolerance] of
  /// [inputs] and whose fusion radius samples the same grid with the same
  /// kernel (`MorphMenuFusion.sameGrid`), the newest such; it is handed
  /// out once, and the fusions that arrived before it are dropped.
  static MorphGlassOutlineParts? take(Float64List inputs, double tolerance) {
    for (var k = _ready.length - 1; k >= 0; k--) {
      final (ready, parts) = _ready[k];
      if (_matches(ready, inputs, tolerance)) {
        _ready.removeRange(0, k + 1);
        debugTakenInputs = ready;
        return parts;
      }
    }
    return null;
  }

  static bool _matches(Float64List a, Float64List b, double tolerance) {
    for (var i = 0; i < b.length; i++) {
      if (!((a[i] - b[i]).abs() <= tolerance)) return false;
    }
    return MorphMenuFusion.sameGrid(a[10], b[10]);
  }

  /// The inputs of the fusion [take] handed out last.
  @internal
  static Float64List? debugTakenInputs;

  /// The inputs of the newest arrived fusion not handed out, or null.
  @internal
  static Float64List? get debugReadyInputs =>
      _ready.isEmpty ? null : _ready.last.$1;

  /// Whether fusions have arrived that [take] has not handed out.
  @visibleForTesting
  static bool get debugHasReady => _ready.isNotEmpty;

  /// Drops the fusions and the request not yet handed out.
  static void reset() {
    _ready.clear();
    _waiting.clear();
  }

  static ReceivePort _listen() {
    final port = ReceivePort('morph menu fusion');
    port.listen(_receive);
    return port;
  }

  static void _spawn(ReceivePort port) {
    final worker = _Worker(_workers.length);
    _workers.add(worker);
    Isolate.spawn(
      _main,
      (port.sendPort, worker.index),
      debugName: 'morph menu fusion ${worker.index}',
      errorsAreFatal: true,
    ).then<void>((Isolate isolate) {
      isolate.addOnExitListener(port.sendPort, response: false);
    }, onError: (Object _) => _fail());
  }

  static void _fail() {
    _failed = true;
    for (final worker in _workers) {
      worker.send = null;
    }
    reset();
    _port?.close();
  }

  static void _receive(Object? message) {
    switch (message) {
      case (final int index, final SendPort send):
        final worker = _workers[index];
        worker.send = send;
        _next(worker);
      case [
        final int index,
        final Float64List inputs,
        final TransferableTypedData samples,
        final Float64List points,
        final Int32List loops,
        final Float64List place,
        final Int32List size,
      ]:
        _ready.add((
          inputs,
          MorphGlassOutlineParts(
            samples: samples.materialize().asFloat32List(),
            cols: size[0],
            rows: size[1],
            left: place[0],
            top: place[1],
            step: place[2],
            points: points,
            loops: loops,
          ),
        ));
        if (_ready.length > keep) _ready.removeAt(0);
        final worker = _workers[index];
        worker.busy = false;
        _next(worker);
      default:
        _fail();
    }
  }

  static void _next(_Worker worker) {
    if (_waiting.isEmpty) return;
    worker.dispatch(_waiting.removeAt(0));
  }

  static void _main((SendPort, int) start) {
    final (reply, index) = start;
    final port = ReceivePort();
    reply.send((index, port.sendPort));
    port.listen((Object? message) {
      final v = message! as Float64List;
      final parts = morphMenuSilhouetteParts(
        RRect.fromLTRBXY(v[0], v[1], v[2], v[3], v[4], v[4]),
        RRect.fromLTRBXY(v[5], v[6], v[7], v[8], v[9], v[9]),
        v[10],
      );
      reply.send([
        index,
        v,
        TransferableTypedData.fromList([parts.samples]),
        Float64List.fromList(parts.points),
        parts.loops,
        Float64List.fromList([parts.left, parts.top, parts.step]),
        Int32List.fromList([parts.cols, parts.rows]),
      ]);
    });
  }
}

/// One fusion isolate as the UI isolate sees it.
class _Worker {
  _Worker(this.index);

  final int index;
  SendPort? send;
  bool busy = false;

  void dispatch(Float64List inputs) {
    busy = true;
    send!.send(inputs);
  }
}
