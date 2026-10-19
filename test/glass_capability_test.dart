import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/liquid_capability.dart';
import 'package:morph/src/widgets/glass_liquid_web.dart' as web;
import 'package:morph/widgets.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsupported GPU reports once and caches its reason', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    var loads = 0;
    final failure = StateError('GPU disabled');
    final capability = LiquidCapability(
      load: () async {
        loads++;
        throw failure;
      },
    );
    addTearDown(capability.dispose);
    expect(capability.value, isFalse);
    expect(capability.unavailableReason, isNull);
    await Future.wait([capability.precache(), capability.precache()]);
    await capability.precache();
    expect(capability.value, isFalse);
    expect(loads, 1);
    expect(capability.unavailableReason, failure.toString());
    final report = reports.single;
    expect(report.library, 'morph glass');
    expect(report.exception, isA<FlutterError>());
    expect(report.exception.toString(), contains('using fake glass'));
    expect(report.exception.toString(), contains(failure.toString()));
    expect(report.stack, isNotNull);
  });

  test('missing and failing shader bundles preserve the cause', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    for (final message in ['Shader bundle missing', 'Shader load failed']) {
      final capability = LiquidCapability(
        load: () async => throw StateError(message),
      );
      await capability.precache();
      await capability.precache();
      expect(capability.unavailableReason, contains(message));
      expect(capability.value, isFalse);
      capability.dispose();
    }
    expect(reports, hasLength(2));
  });

  test('flat and fake tiers do not initialize unused liquid shaders', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    expect(
      const GlassBuiltInPainter(tier: MorphGlassTier.flat).effectiveTier,
      MorphGlassTier.flat,
    );
    expect(
      const GlassBuiltInPainter(tier: MorphGlassTier.fake).effectiveTier,
      MorphGlassTier.fake,
    );
    await Future<void>.value();
    expect(GlassBuiltInPainter.liquidUnavailableReason, isNull);
    expect(reports, isEmpty);
  });

  test('public reason resolves with the runtime fallback', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    await GlassBuiltInPainter.precache();
    expect(GlassBuiltInPainter.liquidAvailable, isFalse);
    expect(const GlassBuiltInPainter().effectiveTier, MorphGlassTier.fake);
    final reason = GlassBuiltInPainter.liquidUnavailableReason;
    expect(reason, isNotEmpty);
    expect(reports.single.library, 'morph glass');
    expect(reports.single.exception.toString(), contains(reason!));
    await GlassBuiltInPainter.precache();
    expect(GlassBuiltInPainter.liquidUnavailableReason, reason);
    expect(reports, hasLength(1));
  });

  test('web fallback reports once and exposes its reason', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    expect(web.morphLiquidGlassAvailable, isFalse);
    await web.morphPrecacheLiquidGlass();
    await web.morphPrecacheLiquidGlass();
    expect(web.morphLiquidGlassUnavailableReason, contains('web'));
    expect(reports.single.library, 'morph glass');
    expect(web.morphLiquidGlassCapability.value, isFalse);
  });

  test('successful initialization has no failure or report', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    final ready = Completer<void>();
    final capability = LiquidCapability(load: () => ready.future);
    addTearDown(capability.dispose);
    final pending = capability.precache();
    expect(capability.value, isFalse);
    expect(capability.unavailableReason, isNull);
    ready.complete();
    await pending;
    expect(capability.value, isTrue);
    expect(capability.unavailableReason, isNull);
    expect(reports, isEmpty);
  });
}
