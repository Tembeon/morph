import 'package:flutter/foundation.dart';

/// The isolate's cached runtime shader capability.
@internal
class LiquidCapability extends ValueNotifier<bool> {
  /// Creates an unresolved capability checked by [load].
  LiquidCapability({
    required this.load,
    void Function(String? message, {int? wrapWidth})? log,
  }) : log = log ?? debugPrint,
       super(false);

  /// Validates the GPU context, bundle and final render programs.
  final Future<void> Function() load;

  /// Receives the fallback reason once if initialization fails.
  final void Function(String? message, {int? wrapWidth}) log;

  Future<void>? _pending;

  /// Resolves once; failures remain unavailable for this isolate.
  Future<void> precache() => _pending ??= _resolve();

  Future<void> _resolve() async {
    try {
      await load();
      value = true;
    } on Object catch (error) {
      if (kDebugMode) {
        log('morph: liquid glass unavailable; using frosted glass. $error');
      }
    }
  }
}
