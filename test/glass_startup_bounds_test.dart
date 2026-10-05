import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart';
import 'package:morph/src/glass/renderer/internal/liquid_capability.dart';

void main() {
  testWidgets('a warm-up that never completes holds the launch only for '
      'its budget', (WidgetTester tester) async {
    final never = Completer<void>();
    var released = false;
    unawaited(
      morphWithinBudget(
        never.future,
        const Duration(seconds: 1),
      ).then((_) => released = true),
    );
    await tester.pump(const Duration(milliseconds: 999));
    expect(released, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(released, isTrue);
  });

  testWidgets('a warm-up inside its budget releases the launch at once', (
    WidgetTester tester,
  ) async {
    final work = Completer<void>();
    var released = false;
    unawaited(
      morphWithinBudget(
        work.future,
        const Duration(seconds: 1),
      ).then((_) => released = true),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(released, isFalse);
    work.complete();
    await tester.pump();
    expect(released, isTrue);
  });

  testWidgets('a failing warm-up is reported and releases the launch', (
    WidgetTester tester,
  ) async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    var released = false;
    unawaited(
      morphWithinBudget(
        Future<void>.error(StateError('no GPU')),
        const Duration(seconds: 1),
      ).then((_) => released = true),
    );
    await tester.pump();
    FlutterError.onError = previous;
    expect(released, isTrue);
    expect(reports.single.exception, isA<StateError>());
  });

  test('a frame never holds more than the limit of unsubmitted passes', () {
    final submitted = <int>[];
    var peak = 0;
    final pending = MorphDeferredSubmissions<int>(submitted.add);
    for (var i = 0; i < 100; i++) {
      pending.add(i);
      if (pending.length > peak) peak = pending.length;
    }
    pending.flush();
    expect(peak, lessThan(MorphDeferredSubmissions.defaultLimit));
    expect(submitted, [for (var i = 0; i < 100; i++) i]);
    expect(pending.isEmpty, isTrue);
  });

  test('a failing submission neither strands the rest nor repeats', () {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    final attempts = <int>[];
    final pending = MorphDeferredSubmissions<int>((entry) {
      attempts.add(entry);
      if (entry == 1) throw StateError('Failed to submit CommandBuffer');
    }, limit: 8);
    for (var i = 0; i < 4; i++) {
      pending.add(i);
    }
    pending.flush();
    pending.flush();
    expect(attempts, [0, 1, 2, 3]);
    expect(pending.isEmpty, isTrue);
    expect(reports, hasLength(1));
  });
}
