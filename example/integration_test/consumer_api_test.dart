import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/consumer_api.dart';

/// Native smoke and screenshots of the public Sonatide consumer example.
///
/// Build as a profile app, run on the locked physical device and retrieve
/// tmp/sonatide-public-api from its data container. The report records actual
/// shader availability; a host fallback is not evidence of liquid rendering.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'public consumer API on the native renderer',
    semanticsEnabled: false,
    (tester) async {
      final out = Directory('${Directory.systemTemp.path}/sonatide-public-api');
      out.createSync(recursive: true);
      await MorphTheme.precacheGlass();
      expect(MorphTheme.liquidGlassAvailable, isTrue);
      final report = <String, Object?>{
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'liquid_available': MorphTheme.liquidGlassAvailable,
        'fallback': MorphTheme.liquidGlassUnavailableReason,
      };
      Future<void> shot(String name) async {
        final data = await binding.callbackManager.takeScreenshot(name);
        File(
          '${out.path}/$name.png',
        ).writeAsBytesSync((data['bytes']! as List<Object?>).cast<int>());
      }

      for (final tier in MorphGlassTier.values) {
        await tester.pumpWidget(
          WidgetsApp(
            key: ValueKey(tier),
            color: const Color(0xFF007AFF),
            builder: (context, child) => MorphTheme(
              data: MorphThemeData(
                brightness: Brightness.light,
                glass: MorphGlassRenderer.tier(tier),
              ),
              child: child!,
            ),
            pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, animation, secondaryAnimation) =>
                  builder(context),
            ),
            home: const ConsumerApiExamples(),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await shot('${tier.name}-rest');
        final reaction = find.byType(MorphSegmentedControl).first;
        final gesture = await tester.startGesture(tester.getCenter(reaction));
        await tester.pump(const Duration(milliseconds: 400));
        await shot('${tier.name}-preview');
        await gesture.up();
        await tester.pump(const Duration(seconds: 1));
        final vibe = await tester.startGesture(
          tester.getCenter(find.byType(MorphSegmentedControl).last),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await vibe.moveBy(const Offset(50, 0));
        await tester.pump(const Duration(milliseconds: 200));
        await shot('${tier.name}-vibe');
        await vibe.cancel();
        await tester.pump(const Duration(seconds: 1));
        final touch = await tester.startGesture(
          tester.getCenter(find.byType(MorphTouchTarget).first),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await shot('${tier.name}-touch');
        await touch.up();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.textContaining('Sort:'));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Alphabetically'), findsOneWidget);
        await shot('${tier.name}-menu');
        await tester.tap(find.text('Name'));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Sort: Name'), findsOneWidget);
        expect(tester.takeException(), isNull);
        report[tier.name] = 'passed';
      }
      File(
        '${out.path}/report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    },
  );
}
