import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Walks every gallery page with a few synthetic gestures through the
/// gallery's navigation stack, prints
/// `AUTODEMO` progress lines and exits.
///
/// Each page is pushed, tapped at its center, dragged across and scrolled,
/// then popped back to the home page, so a run exercises every page's
/// build, its springs and its route transitions. Framework errors land in
/// the log as usual; the run itself never stops on them. The web build
/// stays on the home page at the end instead of exiting.
///
/// With `--dart-define=AUTODEMO_TIMES=true` (a profile build) each page
/// also reports its frames: `AUTODEMO times PAGE n build_p95 raster_p95
/// over`, over counting frames whose build or raster exceeds the display's
/// frame budget.
Future<void> runAutodemo(GlobalKey<NavigatorState> navigatorKey) async {
  await _pause(800);
  var pointer = 1;
  final frames = <FrameTiming>[];
  if (_times) SchedulerBinding.instance.addTimingsCallback(frames.addAll);
  for (final entry in galleryEntries) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      break;
    }
    _report('page ${entry.title}');
    frames.clear();
    navigator.push(MorphNavigationRoute<void>(builder: entry.builder));
    await _pause(900);
    final size = _viewSize();
    await _drag(pointer++, size.center(Offset.zero), Offset.zero);
    await _pause(700);
    await _drag(
      pointer++,
      Offset(size.width * 0.3, size.height * 0.45),
      Offset(size.width * 0.4, 0),
    );
    await _pause(700);
    await _drag(
      pointer++,
      Offset(size.width * 0.5, size.height * 0.7),
      Offset(0, -size.height * 0.3),
    );
    await _pause(900);
    navigator.popUntil((Route<Object?> route) => route.isFirst);
    await _pause(700);
    if (_times) _reportTimes(entry.title, frames);
  }
  _report('done');
  if (!kIsWeb) {
    exit(0);
  }
}

const bool _times = bool.fromEnvironment('AUTODEMO_TIMES');

void _reportTimes(String page, List<FrameTiming> frames) {
  double p95(Iterable<Duration> values) {
    final sorted = values.map((d) => d.inMicroseconds / 1000).toList()..sort();
    return sorted.isEmpty ? 0 : sorted[(sorted.length * 0.95).floor()];
  }

  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final budget = 1000 / view.display.refreshRate;
  final over = frames
      .where(
        (f) =>
            f.buildDuration.inMicroseconds / 1000 > budget ||
            f.rasterDuration.inMicroseconds / 1000 > budget,
      )
      .length;
  _report(
    'times ${page.replaceAll(' ', '_')} ${frames.length} '
    '${p95(frames.map((f) => f.buildDuration)).toStringAsFixed(2)} '
    '${p95(frames.map((f) => f.rasterDuration)).toStringAsFixed(2)} $over',
  );
}

void _report(String line) {
  debugPrint('AUTODEMO $line');
}

Future<void> _pause(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

Size _viewSize() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  return view.physicalSize / view.devicePixelRatio;
}

Future<void> _drag(int pointer, Offset from, Offset by) async {
  const steps = 12;
  const frame = Duration(milliseconds: 16);
  final binding = GestureBinding.instance;
  var time = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);
  binding.handlePointerEvent(
    PointerDownEvent(pointer: pointer, position: from, timeStamp: time),
  );
  for (var i = 1; i <= steps; i++) {
    await Future<void>.delayed(frame);
    time += frame;
    binding.handlePointerEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: from + by * (i / steps),
        delta: by / steps.toDouble(),
        timeStamp: time,
      ),
    );
  }
  await Future<void>.delayed(frame);
  binding.handlePointerEvent(
    PointerUpEvent(pointer: pointer, position: from + by, timeStamp: time),
  );
}
