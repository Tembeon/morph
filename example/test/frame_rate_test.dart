import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

/// Opens the glass page and scrolls its frame rate control into view.
Future<void> _openGlassPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const GalleryApp());
  await _settle(tester);
  await tester.tap(find.text('Glass renderer'));
  await _settle(tester);
  await tester.scrollUntilVisible(
    find.text('Frame rate'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
  await _settle(tester);
}

/// Runs [body] with the platform overridden and restores it at the end:
/// the binding checks the override before any tear-down runs.
Future<void> _on(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUpAll(() async {
    // The host has no Impeller: the precache reports that liquid glass is
    // unavailable, as in the other gallery tests.
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    try {
      await MorphGlassRenderer.precache();
    } finally {
      FlutterError.onError = previous;
    }
  });

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(galleryDisplayChannel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(galleryDisplayChannel, null);
  });

  test('the frame rates carry their hertz, 0 for auto', () {
    expect(GalleryFrameRate.values.map((rate) => rate.hertz), [0, 60, 120]);
  });

  testWidgets('the frame rate control updates the settings and the channel', (
    tester,
  ) async {
    await _on(TargetPlatform.android, () async {
      await _openGlassPage(tester);
      final settings = GalleryGlassScope.of(
        tester.element(find.text('Frame rate')),
      );
      expect(settings.frameRate, GalleryFrameRate.auto);
      expect(find.text('60 Hz'), findsOneWidget);
      expect(find.text('120 Hz'), findsOneWidget);

      await tester.tap(find.text('60 Hz'));
      await _settle(tester);
      expect(settings.frameRate, GalleryFrameRate.hz60);
      await tester.tap(find.text('120 Hz'));
      await _settle(tester);
      expect(settings.frameRate, GalleryFrameRate.hz120);
      await tester.tap(find.text('Auto').last);
      await _settle(tester);
      expect(settings.frameRate, GalleryFrameRate.auto);

      expect(calls.map((call) => call.method), everyElement('setFrameRate'));
      expect(calls.map((call) => call.arguments), [60.0, 120.0, 0.0]);
    });
  });

  testWidgets('no channel call is made off Android', (tester) async {
    await _on(TargetPlatform.iOS, () async {
      await _openGlassPage(tester);
      final settings = GalleryGlassScope.of(
        tester.element(find.text('Frame rate')),
      );
      await tester.tap(find.text('120 Hz'));
      await _settle(tester);
      expect(settings.frameRate, GalleryFrameRate.hz120);
      expect(calls, isEmpty);
    });
  });

  testWidgets('a missing channel is swallowed on Android', (tester) async {
    await _on(TargetPlatform.android, () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(galleryDisplayChannel, null);
      final settings = GalleryGlassSettings();
      addTearDown(settings.dispose);
      settings.frameRate = GalleryFrameRate.hz60;
      await tester.pump();
      expect(settings.frameRate, GalleryFrameRate.hz60);
    });
  });
}
