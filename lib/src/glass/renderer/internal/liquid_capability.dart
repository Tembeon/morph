import 'dart:async';

import 'package:flutter/foundation.dart';

/// The isolate's cached runtime shader capability.
@internal
class LiquidCapability extends ValueNotifier<bool> {
  /// Creates an unresolved capability checked by [load].
  LiquidCapability({required this.load}) : super(false);

  /// Validates the GPU context, bundle and final render programs.
  final Future<void> Function() load;

  /// The cached initialization failure, or null before failure.
  String? get unavailableReason => _unavailableReason;

  Future<void>? _pending;
  String? _unavailableReason;

  /// Resolves once; failures remain unavailable for this isolate.
  Future<void> precache() => _pending ??= _resolve();

  Future<void> _resolve() async {
    try {
      await load();
      value = true;
    } on Object catch (error, stack) {
      _unavailableReason = error.toString();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError(
            'Liquid glass is unavailable; morph is using fake glass. '
            'Reason: $_unavailableReason',
          ),
          stack: stack,
          library: 'morph glass',
          context: ErrorDescription('while initializing the liquid glass tier'),
        ),
      );
    }
  }
}

/// Completes when [work] does or once [budget] has passed, whichever comes
/// first; [work] keeps running after the budget is spent.
///
/// A launch that awaits the glass warm-up waits at most [budget] for it: a
/// GPU context that is slow to start, or a warm-up scene the raster thread
/// never returns, then costs the first glass frames their warm pipelines
/// instead of the app its first frame.
@internal
Future<void> morphWithinBudget(Future<void> work, Duration budget) {
  final done = Completer<void>();
  final timer = Timer(budget, () {
    if (!done.isCompleted) done.complete();
  });
  void finish() {
    timer.cancel();
    if (!done.isCompleted) done.complete();
  }

  unawaited(
    work.then<void>(
      (_) => finish(),
      onError: (Object error, StackTrace stack) {
        finish();
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'morph glass',
            context: ErrorDescription('while warming the glass pipelines'),
          ),
        );
      },
    ),
  );
  return done.future;
}
