import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/menu.dart' show MorphMenuLayer;

/// The tolerance of a resting frame against a UIKit layout read, in
/// points: the layout replays of navigation_title_layout_test,
/// date_picker_test and alert_test's popover placement hold resting
/// frames to it.
const double _tolerance = 0.5;

/// The tolerance of the open preview's size: the device replay of the
/// lift in morph_context_menu_test ('the hold and the lift match an
/// iPhone 16 Pro') holds it to 0.05 points.
const double _sizeTolerance = 0.05;

const Key _held = ValueKey<String>('held');

/// A recorded long press: the held view's size, the open preview and the
/// menu as UIKit rests them, each `[center x, center y, width, height]`.
({Size card, Rect preview, Rect menu}) _case(String name) {
  final data =
      (jsonDecode(
                File(
                  'test/fixtures/ios27-device/context_menu/holds.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final c = (data['cases']! as List).cast<Map<String, Object?>>().firstWhere(
    (Map<String, Object?> c) => c['name'] == name,
  );
  List<double> numbers(String key) => [
    for (final n in (c[key]! as List).cast<num>()) n.toDouble(),
  ];
  Rect rect(List<double> v) =>
      Rect.fromCenter(center: Offset(v[0], v[1]), width: v[2], height: v[3]);
  final card = numbers('card');
  return (
    card: Size(card[0], card[1]),
    preview: rect(numbers('preview')),
    menu: rect(numbers('menu')),
  );
}

void main() {
  testWidgets('a context menu held near the bottom edge opens above the '
      'lifted preview, as the device does (ctx-hold-bottom)', (tester) async {
    final recorded = _case('ctx-hold-bottom');
    // The w2ctx scene centers the held view across the 402 x 874 window
    // and the preview lifts about the held view's center, so the held
    // view rests where the recorded preview is centered.
    final held = Rect.fromCenter(
      center: recorded.preview.center,
      width: recorded.card.width,
      height: recorded.card.height,
    );
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Stack(
          children: [
            Positioned.fromRect(
              rect: held,
              child: MorphContextMenuRegion(
                onOpen: (MorphFlight f) => flight = f,
                // One free-form row that fills the recorded menu's height
                // with the menu's 10 point insets.
                menu: [
                  MorphMenuWidget(
                    height: recorded.menu.height - 20,
                    builder: (BuildContext context) =>
                        SizedBox(height: recorded.menu.height - 20),
                  ),
                ],
                child: const SizedBox.expand(
                  key: _held,
                  child: ColoredBox(color: Color(0xFF0088FF)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(held.center);
    for (var i = 0; i < 150 && flight == null; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(flight, isNotNull, reason: 'the hold opens the menu');
    await gesture.up();
    await tester.pumpAndSettle();

    final preview = tester.getRect(find.byKey(_held).last);
    expect(preview.width, closeTo(recorded.preview.width, _sizeTolerance));
    expect(preview.height, closeTo(recorded.preview.height, _sizeTolerance));
    expect(preview.center.dx, closeTo(recorded.preview.center.dx, _tolerance));
    expect(preview.center.dy, closeTo(recorded.preview.center.dy, _tolerance));
    final motion = tester
        .widget<MorphMenuLayer>(find.byType(MorphMenuLayer).first)
        .host
        .menuMotion!;
    final menu = motion.menuBlob.rect;
    expect(menu.left, closeTo(recorded.menu.left, _tolerance));
    expect(menu.top, closeTo(recorded.menu.top, _tolerance));
    expect(menu.width, closeTo(recorded.menu.width, _tolerance));
    expect(menu.height, closeTo(recorded.menu.height, _tolerance));
    expect(
      preview.top - menu.bottom,
      closeTo(recorded.preview.top - recorded.menu.bottom, _tolerance),
      reason: 'the menu stands above the preview by the recorded gap',
    );
  });
}
