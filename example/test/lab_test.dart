import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/lab/lab_app.dart';

import 'support/lab_replay.dart';

Map<String, Object?> scenario() =>
    jsonDecode(
          File(
            '../tool/ios_reference/lab/scenarios/button-press-drag.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  testWidgets('lab observes short menu cards at every nested level', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final menu =
        jsonDecode(
              File(
                '../tool/ios_reference/lab/scenarios/menu-stack.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final rows = <Map<String, Object?>>[];
    await tester.pumpWidget(
      LabApp(
        scenario: menu,
        tier: MorphGlassTier.flat,
        writeTrace: false,
        onRow: rows.add,
      ),
    );
    final rootButton = find.byType(MorphMenuButton);
    for (final target in [
      rootButton,
      find.text('More').last,
      find.text('Deeper').last,
    ]) {
      await tester.tap(target);
      await tester.pump();
      for (var frame = 0; frame < 100; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      if (identical(target, rootButton)) {
        final root = rows.lastWhere(
          (row) => row['k'] == 'lab_sample' && row['id'] == 'rows/0',
        );
        final values = root['values']! as Map<String, Object?>;
        expect(values['height'], closeTo(208, 0.01));
      }
    }
    final cards = rows
        .where((row) => row['k'] == 'lab_sample')
        .map((row) => row['id'])
        .toSet();
    expect(cards, containsAll(['rows/0', 'rows/1', 'rows/2']));
    expect(find.text('Ask Siri'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lab records cancellation without activating the button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = <Map<String, Object?>>[];
    await tester.pumpWidget(
      LabApp(
        scenario: scenario(),
        tier: MorphGlassTier.flat,
        writeTrace: false,
        onRow: rows.add,
      ),
    );
    await replayLabTouches(tester, [
      {'k': 'touch', 't': 50, 'pointer': 'one', 'phase': 0, 'x': 201, 'y': 402},
      {
        'k': 'touch',
        't': 50.2,
        'pointer': 'one',
        'phase': 4,
        'x': 201,
        'y': 402,
      },
    ]);
    await tester.pump(const Duration(milliseconds: 600));
    expect(rows.where((row) => row['k'] == 'touch').last['phase'], 4);
    expect(rows.where((row) => row['k'] == 'lab_event'), isEmpty);
    expect(rows.where((row) => row['k'] == 'lab_sample'), isNotEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lab captures semantic activation from a measured tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = <Map<String, Object?>>[];
    await tester.pumpWidget(
      LabApp(
        scenario: scenario(),
        tier: MorphGlassTier.flat,
        writeTrace: false,
        onRow: rows.add,
      ),
    );
    await replayLabTouches(tester, [
      {'k': 'touch', 't': 90, 'pointer': 'one', 'phase': 0, 'x': 201, 'y': 402},
      {
        'k': 'touch',
        't': 90.12,
        'pointer': 'one',
        'phase': 3,
        'x': 201,
        'y': 402,
      },
    ]);
    await tester.pump(const Duration(milliseconds: 600));
    expect(rows.where((row) => row['e'] == 'activate').length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
