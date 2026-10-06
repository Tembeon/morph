import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_fusion.dart';

/// A background isolate that fuses menu silhouettes ahead of the frames
/// that show them.
///
/// The UI isolate posts the inputs it expects the next frame to fuse
/// ([request]: the menu shape, the button shape and the fusion radius as
/// eleven numbers, `MorphMenuFusion.encode`); the worker computes
/// `morphMenuSilhouetteParts` and sends the parts back, the field samples
/// without a copy. One request is in flight at a time: a request made
/// while one runs replaces any other waiting, and is sent when the
/// running one returns. [take] hands out the last parts that arrived when
/// their inputs are within a tolerance of the inputs the frame fuses.
///
/// The worker spawns on the first request and lives for the isolate's
/// lifetime; it fails closed - any error stops it, and every fusion is
/// then computed where it is needed.
@internal
abstract final class MorphFusionWorker {
  /// Whether this platform can run the worker.
  static const bool supported = true;

  static SendPort? _send;
  static ReceivePort? _port;
  static bool _failed = false;
  static bool _busy = false;
  static Float64List? _waiting;
  static Float64List? _readyInputs;
  static MorphGlassOutlineParts? _ready;

  /// Asks the worker for the fusion of [inputs].
  static void request(Float64List inputs) {
    if (_failed) return;
    if (_port == null) {
      _spawn();
    }
    if (_send == null || _busy) {
      _waiting = inputs;
      return;
    }
    _busy = true;
    _send!.send(inputs);
  }

  /// The parts the worker returned last, when every one of their inputs
  /// is within [tolerance] of [inputs] and their fusion radius samples
  /// the same grid with the same kernel (`MorphMenuFusion.sameGrid`);
  /// they are handed out once.
  static MorphGlassOutlineParts? take(Float64List inputs, double tolerance) {
    final ready = _readyInputs;
    if (ready == null) return null;
    for (var i = 0; i < inputs.length; i++) {
      if (!((ready[i] - inputs[i]).abs() <= tolerance)) return null;
    }
    if (!MorphMenuFusion.sameGrid(ready[10], inputs[10])) return null;
    final parts = _ready;
    _ready = null;
    _readyInputs = null;
    return parts;
  }

  /// The inputs of the parts that have arrived and [take] has not handed
  /// out, or null.
  @internal
  static Float64List? get debugReadyInputs => _readyInputs;

  /// Whether parts have arrived that [take] has not handed out.
  @visibleForTesting
  static bool get debugHasReady => _ready != null;

  /// Drops the parts and requests not yet handed out.
  static void reset() {
    _ready = null;
    _readyInputs = null;
    _waiting = null;
  }

  static void _spawn() {
    final port = ReceivePort('morph menu fusion');
    _port = port;
    port.listen(_receive);
    Isolate.spawn(
      _main,
      port.sendPort,
      debugName: 'morph menu fusion',
      errorsAreFatal: true,
    ).then<void>(
      (Isolate isolate) {
        isolate.addOnExitListener(port.sendPort, response: false);
      },
      onError: (Object _) {
        _fail();
      },
    );
  }

  static void _fail() {
    _failed = true;
    _send = null;
    _busy = false;
    reset();
    _port?.close();
  }

  static void _receive(Object? message) {
    switch (message) {
      case final SendPort send:
        _send = send;
        _next();
      case [
        final Float64List inputs,
        final TransferableTypedData samples,
        final Float64List points,
        final Int32List loops,
        final Float64List place,
        final Int32List size,
      ]:
        _readyInputs = inputs;
        _ready = MorphGlassOutlineParts(
          samples: samples.materialize().asFloat32List(),
          cols: size[0],
          rows: size[1],
          left: place[0],
          top: place[1],
          step: place[2],
          points: points,
          loops: loops,
        );
        _busy = false;
        _next();
      default:
        _fail();
    }
  }

  static void _next() {
    final waiting = _waiting;
    if (waiting == null || _send == null) return;
    _waiting = null;
    _busy = true;
    _send!.send(waiting);
  }

  static void _main(SendPort reply) {
    final port = ReceivePort();
    reply.send(port.sendPort);
    port.listen((Object? message) {
      final v = message! as Float64List;
      final parts = morphMenuSilhouetteParts(
        RRect.fromLTRBXY(v[0], v[1], v[2], v[3], v[4], v[4]),
        RRect.fromLTRBXY(v[5], v[6], v[7], v[8], v[9], v[9]),
        v[10],
      );
      reply.send([
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
