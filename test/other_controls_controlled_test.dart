import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/date_picker.dart';
import 'package:morph/src/widgets/page_control.dart';
import 'package:morph/src/widgets/stepper.dart';

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('image')),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  testWidgets(
    'C4 page control restores a rejected page without parent rebuild',
    (tester) async {
      final changes = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: const ValueKey('image'),
              child: MorphPageControl(
                count: 3,
                page: 0,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      );
      final initial = await _pixels(tester);
      final rect = tester.getRect(find.byType(MorphPageControl));
      await tester.tapAt(rect.centerRight - const Offset(4, 0));
      await tester.pumpAndSettle();
      expect(changes, [1]);
      expect(await _pixels(tester), orderedEquals(initial));
      await tester.tapAt(rect.centerRight - const Offset(4, 0));
      await tester.pumpAndSettle();
      expect(changes, [1, 1]);
    },
  );

  testWidgets('C4 rejected stepper repeats always start from parent value', (
    tester,
  ) async {
    final changes = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: MorphStepper(value: 5, onChanged: changes.add)),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphStepper)) + const Offset(20, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 510));
    await tester.pump(const Duration(milliseconds: 510));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, [6, 6]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(changes.last, 6);
  });

  testWidgets('C4 calendar restores a rejected day without parent rebuild', (
    tester,
  ) async {
    final changes = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MorphDatePicker(
            value: DateTime(2026, 10, 3),
            onChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphDatePicker));
    await tester.pumpAndSettle();
    final day = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == '4 October 2026',
    );
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(changes, [DateTime(2026, 10, 4)]);
    expect(tester.widget<Semantics>(day).properties.selected, isFalse);
    final accepted = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == '3 October 2026',
    );
    expect(tester.widget<Semantics>(accepted).properties.selected, isTrue);
  });
}
