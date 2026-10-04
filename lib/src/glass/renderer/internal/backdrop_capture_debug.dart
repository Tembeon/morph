import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Records that [owner] submitted a backdrop filter during this frame.
///
/// No-op in release builds.
@internal
void debugRegisterBackdropCapture(Object owner, BackdropKey? key) {
  if (!kDebugMode || !BackdropCaptureDebug.enabled) return;
  BackdropCaptureDebug._register(owner, key);
}

/// Debug-only registry of glass render objects that submit a backdrop filter.
///
/// After painting, distinct captures (a `null` [BackdropKey] is its own
/// capture) are counted. More than one in the same frame prints a rate-limited
/// warning: the same count is not printed again until it changes.
@internal
abstract final class BackdropCaptureDebug {
  /// Whether independent capture counts are logged in debug builds.
  ///
  /// Off by default: lifted lenses and overlapping chrome intentionally
  /// capture different content planes and cannot share one backdrop key.
  static bool enabled = false;

  static final Map<Object, BackdropKey?> _captures = {};
  static int? _lastReportedCount;
  static bool _callbackScheduled = false;
  static int _generation = 0;

  static void _register(Object owner, BackdropKey? key) {
    _captures[owner] = key;
    if (_callbackScheduled) return;
    _callbackScheduled = true;
    final generation = _generation;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (generation != _generation) return;
      _callbackScheduled = false;
      _evaluate();
      _captures.clear();
    });
  }

  static void _evaluate() {
    if (_captures.isEmpty) return;
    var independent = 0;
    final sharedKeys = <BackdropKey>{};
    for (final key in _captures.values) {
      if (key == null) {
        independent++;
      } else {
        sharedKeys.add(key);
      }
    }
    final count = independent + sharedKeys.length;
    // Only report when the number of captures grows; a scene that toggles
    // between one and two captures every frame must not spam the log.
    if (count <= 1 || (_lastReportedCount ?? 0) >= count) return;
    _lastReportedCount = count;
    debugPrint(
      'morph: $count independent backdrop captures in this frame. '
      'Non-overlapping surfaces on the same content plane can share a '
      'BackdropGroup; lifted lenses and overlapping glass need independent '
      'captures.',
    );
  }

  /// Clears in-flight registrations and rate-limit state.
  @visibleForTesting
  static void reset() {
    _generation++;
    _captures.clear();
    _lastReportedCount = null;
    _callbackScheduled = false;
  }
}
