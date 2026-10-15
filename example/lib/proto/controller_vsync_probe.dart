import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Supplies one controller ticker with coordinated ambient and delayed pauses.
class ProbeDozingVsync implements TickerProvider {
  /// Observes the ticker mode surrounding the route's navigator.
  ProbeDozingVsync(BuildContext context)
    : _mode = TickerMode.getValuesNotifier(context) {
    _mode.addListener(_update);
  }

  ValueListenable<TickerModeData> _mode;
  Ticker? _ticker;
  Timer? _wake;
  bool _dozing = false;

  @override
  Ticker createTicker(TickerCallback onTick) {
    if (_ticker != null) throw StateError('The probe supplies one ticker');
    final ticker = Ticker(onTick);
    _ticker = ticker;
    _update();
    return ticker;
  }

  /// Refreshes inherited mode ownership when the navigator moves in the tree.
  void refresh(BuildContext context) {
    final mode = TickerMode.getValuesNotifier(context);
    if (identical(mode, _mode)) return;
    _mode.removeListener(_update);
    _mode = mode;
    _mode.addListener(_update);
    _update();
  }

  void _update() {
    final ticker = _ticker;
    if (ticker == null) return;
    final mode = _mode.value;
    ticker.forceFrames = mode.forceFrames;
    ticker.muted = !mode.enabled || _dozing;
  }

  /// Stops frame callbacks until the delay expires without cancelling the ticker.
  void doze(Duration delay) {
    _wake?.cancel();
    _dozing = true;
    _update();
    _wake = Timer(delay, wake);
  }

  /// Cancels delayed waking and resumes if the ambient ticker mode allows it.
  void wake() {
    _wake?.cancel();
    _wake = null;
    _dozing = false;
    _update();
  }

  /// Removes delayed work and mode observation; the controller owns its ticker.
  void dispose() {
    _wake?.cancel();
    _mode.removeListener(_update);
  }
}
