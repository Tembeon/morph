import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/widgets/menu.dart' show MorphMenuLayer;

const _hero = Key('fitted-preview');
const _screen = Size(402, 874);
const _safe = EdgeInsets.fromLTRB(0, 62, 0, 34);
// Resting-frame tolerance used by the existing native edge replay; UIKit
// aligns the fitted platter to screen pixels while preserving its content scale.
const _tolerance = .5;

Rect _rect(List<Object?> values) => Rect.fromCenter(
  center: Offset(
    (values[0]! as num).toDouble(),
    (values[1]! as num).toDouble(),
  ),
  width: (values[2]! as num).toDouble(),
  height: (values[3]! as num).toDouble(),
);

Future<MorphFlight> _open(
  WidgetTester tester,
  Rect home, {
  VoidCallback? onPreviewTap,
  VoidCallback? onSelect,
  WidgetBuilder? preview,
  Size? previewSize,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
  MorphFlight? flight;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          MorphTheme(data: const MorphThemeData(), child: child!),
      home: Stack(
        children: [
          Positioned.fromRect(
            rect: home,
            child: MorphContextMenuRegion(
              onOpen: (value) => flight = value,
              onPreviewTap: onPreviewTap,
              preview: preview,
              previewSize: previewSize,
              menu: [
                MorphMenuItem(title: 'Copy', onSelected: onSelect ?? () {}),
                MorphMenuItem(title: 'Share', onSelected: () {}),
              ],
              child: const ColoredBox(key: _hero, color: Color(0xFF334455)),
            ),
          ),
        ],
      ),
    ),
  );
  final finger = await tester.startGesture(home.center);
  for (var i = 0; i < 150; i++) {
    await tester.pump(const Duration(milliseconds: 8));
  }
  await finger.up();
  await tester.pumpAndSettle();
  expect(flight, isNotNull);
  return flight!;
}

Rect _menu(WidgetTester tester) => tester
    .widget<MorphMenuLayer>(find.byType(MorphMenuLayer).first)
    .host
    .menuMotion!
    .menuRect;

void main() {
  final fixture =
      (jsonDecode(
                File(
                  'test/fixtures/ios27-simulator/context_menu/preview_fit.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();
  for (final sample in cases) {
    testWidgets(
      '${sample['name']}: context preview and menu replay native viewport fitting',
      (tester) async {
        final home = _rect((sample['source']! as List).cast<Object?>());
        final target = _rect((sample['preview']! as List).cast<Object?>());
        final menuTarget = _rect((sample['menu']! as List).cast<Object?>());
        final flight = await _open(tester, home);
        final shown = tester.getRect(find.byKey(_hero).last);
        final menu = _menu(tester);
        for (final pair in [(shown, target), (menu, menuTarget)]) {
          expect(pair.$1.center.dx, closeTo(pair.$2.center.dx, _tolerance));
          expect(pair.$1.center.dy, closeTo(pair.$2.center.dy, _tolerance));
          expect(pair.$1.width, closeTo(pair.$2.width, _tolerance));
          expect(pair.$1.height, closeTo(pair.$2.height, _tolerance));
        }
        expect(
          shown.width / shown.height,
          closeTo(home.width / home.height, 1e-6),
        );
        expect(shown.left, greaterThanOrEqualTo(_safe.left));
        expect(shown.right, lessThanOrEqualTo(_screen.width - _safe.right));
        expect(shown.top, greaterThanOrEqualTo(_safe.top));
        expect(shown.bottom, lessThanOrEqualTo(_screen.height - _safe.bottom));
        flight.close();
        await tester.pumpAndSettle();
        final back = tester.getRect(find.byKey(_hero));
        expect((back.center - home.center).distance, lessThan(.1));
        expect(back.width, closeTo(home.width, .1));
        expect(back.height, closeTo(home.height, .1));
      },
    );
  }

  testWidgets(
    'a menu over a tall preview takes its action instead of the preview tap',
    (tester) async {
      var selected = 0;
      var previewed = 0;
      await _open(
        tester,
        const Rect.fromLTWH(6, -380, 390, 1600),
        onSelect: () => selected++,
        onPreviewTap: () => previewed++,
      );
      final preview = tester.getRect(find.byKey(_hero).last);
      final menu = _menu(tester);
      expect(preview.overlaps(menu), isTrue);
      final action = tester.getCenter(find.text('Copy'));
      expect(
        preview.contains(action),
        isTrue,
        reason: 'exercise the overlapping portion',
      );
      await tester.tapAt(action);
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(previewed, 0);
    },
  );

  testWidgets(
    'the unobstructed portion of a fitted preview still runs its primary action',
    (tester) async {
      var selected = 0;
      var previewed = 0;
      await _open(
        tester,
        const Rect.fromLTWH(6, -380, 390, 1600),
        onSelect: () => selected++,
        onPreviewTap: () => previewed++,
      );
      await tester.tapAt(tester.getRect(find.byKey(_hero).last).center);
      await tester.pumpAndSettle();
      expect(selected, 0);
      expect(previewed, 1);
    },
  );

  testWidgets(
    'a custom preferred preview also fits uniformly and returns to its thumbnail',
    (tester) async {
      const home = Rect.fromLTWH(170, 280, 40, 40);
      const custom = Key('custom-fitted-preview');
      final flight = await _open(
        tester,
        home,
        previewSize: const Size(600, 400),
        preview: (_) => const ColoredBox(key: custom, color: Color(0xFF334455)),
      );
      final shown = tester.getRect(find.byKey(custom));
      expect(shown.width, closeTo(370, .1));
      expect(shown.width / shown.height, closeTo(1.5, 1e-6));
      expect(shown.left, greaterThanOrEqualTo(16 - .1));
      expect(shown.right, lessThanOrEqualTo(_screen.width - 16 + .1));
      flight.close();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_hero)), home);
    },
  );
}
