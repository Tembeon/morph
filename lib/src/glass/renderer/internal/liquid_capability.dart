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
            'Liquid glass is unavailable; morph is using frosted glass. '
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
