import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_body_shadow.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/glass_liquid_native.dart';
import 'package:morph/src/widgets/menu_content.dart';
import 'package:morph/widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('nested material replays the native dark face levels', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/ios27-device/menu_api/card-tone.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final appearance = morphLiquidAppearance(
      const MorphGlassRenderer(),
      MorphGlassSurface(
        kind: MorphGlassKind.menu,
        shape: const RRect.fromLTRBXY(0, 0, 250, 208, 32, 32),
        color: const Color(0xF2000000),
        tint: const Color(0x00000000),
        brightness: Brightness.dark,
        transmissionGamma: MorphMenuTuning.standard.cardTransmissionGamma,
      ),
    );
    final transfer = appearance.colorModel.faceTransfer(208)!;
    double face(double backdrop) {
      final y = backdrop / 255;
      return 255 *
          (transfer.emission.r +
              transfer.transmittance *
                  math.pow(
                    y + transfer.lift * y * (1 - y),
                    appearance.transmissionGamma,
                  ));
    }

    final first = face((fixture['root']! as num).toDouble());
    final secondBackdrop =
        (fixture['second_backdrop_before']! as num).toDouble() *
        first /
        (fixture['first_before']! as num).toDouble();
    expect(first, closeTo((fixture['first_native']! as num).toDouble(), 1.5));
    expect(
      face(secondBackdrop),
      closeTo((fixture['second_native']! as num).toDouble(), 1.5),
    );
  });

  test('card optics replay the native side-edge profile', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/ios27-device/menu_api/card-edge-profile.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    const tuning = MorphMenuTuning.standard;
    final settings = morphLiquidSettings(
      const MorphGlassRenderer(),
      MorphGlassSurface(
        kind: MorphGlassKind.menu,
        shape: const RRect.fromLTRBXY(0, 0, 250, 208, 32, 32),
        color: const Color(0x00000000),
        brightness: Brightness.dark,
        blurRadius: tuning.cardBlur,
        optics: MorphGlassOptics(unliftedDisplacement: tuning.cardDisplacement),
      ),
    );
    final emission = (fixture['native_emission']! as num).toDouble();
    final gain = (fixture['native_gain']! as num).toDouble();
    final rows = fixture['rows']! as List<Object?>;
    var error = 0.0;
    for (final value in rows) {
      final row = value! as List<Object?>;
      final x = (row[0]! as num).toDouble();
      final expected = (row[1]! as num).toDouble();
      final bevel = 1 - ((x - 76) / settings.refractionHeight).clamp(0, 1);
      final shift =
          settings.refractionAmount * (1 - math.sqrt(1 - bevel * bevel));
      final z = (x - 79.75 + shift) / settings.frost;
      var cdf = 0.0;
      for (var step = -6.0; step < z; step += 0.005) {
        final width = math.min(0.005, z - step);
        final midpoint = step + width / 2;
        cdf +=
            math.exp(-midpoint * midpoint / 2) * width / math.sqrt(2 * math.pi);
      }
      final backdrop = 32 * cdf;
      final actual =
          emission + gain * (backdrop + backdrop * (1 - backdrop / 255));
      error += (actual - expected) * (actual - expected);
    }
    final rms = math.sqrt(error / rows.length);
    expect(rms, lessThan((fixture['regular_60pt_rms_gray']! as num) / 2));
  });

  test('card glass ownership follows native SDF property matching', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/ios27-device/menu_api/card-material-handoff.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final content = MorphMenuContent(onChanged: ({required bool animate}) {});
    content.entries = const [
      MorphSubmenu(
        title: 'More',
        children: [MorphMenuItem(title: 'Last')],
      ),
    ];
    final motion = MorphMenuMotion(
      button: const Rect.fromLTWH(177, 126, 48, 48),
      bounds: const Size(402, 874),
      layout: content.root,
    );
    morphConnectMenu(motion, content);
    motion.open(0);
    motion.advance(1);
    motion.select(1, 0);
    motion.advance(2);
    motion.close(2);
    final frames = fixture['frames']! as List<Object?>;
    for (final value in frames) {
      final row = value! as Map<String, Object?>;
      motion.advance(2 + (row['dt']! as num).toDouble());
      expect(
        motion.cardGlassTransferred,
        row['root_glass_hidden'],
        reason: '$row',
      );
      expect(row['card_rows_alpha'], 1);
    }
    motion.open(motion.time);
    expect(motion.cardGlassTransferred, isFalse);
  });

  test('closing matched card material follows the native carrier', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/ios27-device/menu_api/card-material-copy.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final content = MorphMenuContent(onChanged: ({required bool animate}) {});
    content.entries = const [
      MorphSubmenu(
        title: 'More',
        children: [MorphMenuItem(title: 'Last')],
      ),
    ];
    final motion = MorphMenuMotion(
      button: const Rect.fromLTWH(177, 126, 48, 48),
      bounds: const Size(402, 874),
      layout: content.root,
      tuning: MorphMenuTuning(
        cardContainerDelay: (fixture['carrier_delay']! as num).toDouble(),
      ),
    );
    morphConnectMenu(motion, content);
    motion.open(0);
    motion.advance(1);
    motion.select(1, 0);
    motion.advance(2);
    motion.close(2);
    var error = 0.0;
    var rootError = 0.0;
    final frames = fixture['frames']! as List<Object?>;
    for (final value in frames) {
      final row = value! as Map<String, Object?>;
      motion.advance(2 + (row['dt']! as num).toDouble());
      final expected = ((row['width']! as num).toDouble() - 50) / 200;
      expect(
        motion.cardMaterialOpacity,
        closeTo(expected.clamp(0.0, 1.0), 0.001),
        reason: '$row',
      );
      final residual =
          motion.cardMaterialOpacity - (row['opacity']! as num).toDouble();
      error += residual * residual;
      final rows =
          motion.underCardsOpacity -
          (row['container_alpha']! as num).toDouble() *
              (row['root_list_alpha']! as num).toDouble();
      rootError += rows * rows;
    }
    expect(math.sqrt(error / frames.length), lessThan(0.015));
    expect(math.sqrt(rootError / frames.length), lessThan(0.015));
    motion.open(motion.time);
    expect(motion.cardMaterialOpacity, 1);
  });

  testWidgets('a menu in the navigator overlay draws with its button painter', (
    WidgetTester tester,
  ) async {
    isLocalTest = true;
    addTearDown(() => isLocalTest = false);
    await tester.pumpWidget(
      const MaterialApp(
        home: MorphGlass(
          painter: MorphGlassRenderer(),
          child: Scaffold(
            body: Center(
              child: MorphMenuButton(
                items: [
                  MorphSubmenu(
                    title: 'More',
                    children: [MorphMenuItem(title: 'Last')],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await tester.pumpAndSettle();
    final layer = find.byType(MorphMenuLayer);
    expect(
      MorphGlass.maybeOf(tester.element(layer)),
      isA<MorphGlassRenderer>(),
    );
    expect(
      find.descendant(of: layer, matching: find.byType(LiquidGlassLayer)),
      findsOneWidget,
    );
    await tester.tapAt(tester.getCenter(find.text('More').last));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<int>(1)),
        matching: find.byType(LiquidGlassLayer),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'submenus use the installed liquid renderer and fresh backdrops',
    (WidgetTester tester) async {
      isLocalTest = true;
      addTearDown(() => isLocalTest = false);
      await tester.pumpWidget(
        MorphGlass(
          painter: const MorphGlassRenderer(),
          child: BackdropGroup(
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: MorphMenuButton(
                    items: [
                      MorphSubmenu(
                        title: 'More',
                        children: [
                          MorphSubmenu(
                            title: 'Deeper',
                            children: [MorphMenuItem(title: 'Last')],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MorphMenuButton));
      await tester.pumpAndSettle();
      final rootLayer = find.descendant(
        of: find.byType(MorphMenuLayer),
        matching: find.byType(LiquidGlassLayer),
      );
      expect(
        tester.widget<LiquidGlassLayer>(rootLayer).settings.frost,
        MorphMenuTuning.standard.cardBlur,
      );
      for (final shape in tester.widgetList<LiquidGlass>(
        find.byType(LiquidGlass),
      )) {
        expect(shape.appearance!.tint.a, 0);
      }
      for (final (depth, title) in ['More', 'Deeper'].indexed) {
        await tester.tapAt(tester.getCenter(find.text(title).last));
        await tester.pumpAndSettle();
        final card = find.byKey(ValueKey<int>(depth + 1));
        final shapes = find.descendant(
          of: card,
          matching: find.byType(LiquidGlass),
        );
        expect(shapes, findsOneWidget);
        final shape = tester.widget<LiquidGlass>(shapes);
        expect(shape.appearance!.tint.a, 0);
        expect(
          shape.appearance!.transmissionGamma,
          MorphMenuTuning.standard.cardTransmissionGamma,
        );
        final layer = find.descendant(
          of: card,
          matching: find.byType(LiquidGlassLayer),
        );
        expect(layer, findsOneWidget);
        expect(tester.widget<LiquidGlassLayer>(layer).field, isNotNull);
        expect(
          tester.widget<LiquidGlassLayer>(layer).settings.frost,
          MorphMenuTuning.standard.cardBlur,
        );
        expect(
          tester.widget<LiquidGlassLayer>(layer).settings.refractionAmount,
          0,
        );
        final group = BackdropGroup.of(tester.element(layer));
        expect(group, isNotNull);
        final other = tester.widgetList<BackdropGroup>(
          find.byType(BackdropGroup),
        );
        expect(
          other.map((BackdropGroup value) => value.backdropKey).toSet().length,
          depth + 2,
        );
      }
      final host = tester
          .widget<MorphMenuLayer>(find.byType(MorphMenuLayer))
          .host;
      final motion = host.menuMotion!;
      motion.close(motion.time);
      host.menuWake();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      for (final index in [1, 2]) {
        final card = find.byKey(ValueKey<int>(index));
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.byType(LiquidGlass)),
          findsOneWidget,
        );
      }
      expect(find.text('Last'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('submenu blur overrides the preset without replacing lens optics', () {
    const renderer = MorphGlassRenderer();
    const shape = RRect.fromLTRBXY(0, 0, 250, 208, 32, 32);
    const surface = MorphGlassSurface(
      kind: MorphGlassKind.menu,
      shape: shape,
      color: Color(0x00000000),
      brightness: Brightness.light,
      blurRadius: 10,
    );
    final settings = morphLiquidSettings(renderer, surface);
    expect(settings.frost, 10);
    expect(
      settings.refractionAmount,
      const LiquidGlassSettings().refractionAmount,
    );
    expect(settings.dispersion, const LiquidGlassSettings().dispersion);
  });

  testWidgets('a fused menu has one exterior shadow and no button shadow', (
    WidgetTester tester,
  ) async {
    isLocalTest = true;
    addTearDown(() => isLocalTest = false);
    const menu = RRect.fromLTRBXY(30, 70, 270, 280, 80, 80);
    const button = RRect.fromLTRBXY(128, 40, 172, 84, 22, 22);
    final outline = morphMenuSilhouette(menu, button, 20);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.square(
            dimension: 320,
            child: Builder(
              builder: (BuildContext context) =>
                  const MorphGlassRenderer().buildLayer(context, [
                    const MorphGlassSurface(
                      kind: MorphGlassKind.button,
                      shape: button,
                      color: Color(0xF2FFFFFF),
                      brightness: Brightness.light,
                    ),
                    const MorphGlassSurface(
                      kind: MorphGlassKind.menu,
                      shape: menu,
                      color: Color(0xF2FFFFFF),
                      brightness: Brightness.light,
                    ),
                  ], outline: outline),
            ),
          ),
        ),
      ),
    );
    final shapes = tester.widgetList<LiquidGlass>(find.byType(LiquidGlass));
    expect(shapes.length, 2);
    for (final shape in shapes) {
      expect(shape.shadows, isEmpty);
    }
    final shadows = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    final body = shadows
        .map((CustomPaint paint) => paint.painter)
        .whereType<MorphGlassBodyShadow>()
        .single;
    expect(body.outline, same(outline.path));
    expect(body.shadows.length, 1);
    expect(tester.takeException(), isNull);
  });

  test('zero blur keeps the menu and button in one distance field', () {
    final motion = MorphMenuMotion(
      button: const Rect.fromLTWH(177, 126, 48, 48),
      itemCount: 4,
      bounds: const Size(402, 874),
      padding: EdgeInsets.zero,
    );
    motion.open(0);
    motion.advance(2);
    expect(motion.fusionRadius, 0);
    final outline = motion.silhouette!;
    expect(morphGlassOutlineField(outline), isNotNull);
    expect(outline.path.computeMetrics().length, 1);
    expect(outline.path.contains(motion.buttonBlob.rect.center), isTrue);
    motion.close(2);
    for (var frame = 0; frame < 50; frame++) {
      motion.advance(2 + frame / 120);
      if (!motion.isPresented) break;
      expect(motion.cardGlassTransferred, isFalse);
      expect(morphGlassOutlineField(motion.silhouette!), isNotNull);
    }
  });
}
