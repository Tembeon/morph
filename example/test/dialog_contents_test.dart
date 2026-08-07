import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';
import 'package:morph_example/main.dart';
import 'package:morph/morph.dart';

typedef Launcher = MorphFlight Function(BuildContext context);

Widget host(Launcher launch) {
  return MaterialApp(
    theme: ThemeData(
      brightness: .dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C5CFF),
        brightness: .dark,
      ),
    ),
    builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
    home: Scaffold(
      body: Center(
        child: MorphTag(
          id: 'probe',
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => launch(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> openAndSettle(WidgetTester tester, Launcher launch) async {
  tester.view.physicalSize = const Size(1100, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host(launch));
  await tester.tap(find.text('go'));
  for (int i = 0; i < 400; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  testWidgets('ShareSheetContent opens in a sheet without overflow', (
    WidgetTester tester,
  ) async {
    await openAndSettle(
      tester,
      (BuildContext context) => showMorphSheet(
        context,
        from: 'probe',
        heightFactor: 0.52,
        builder: (BuildContext context, MorphFlight flight) =>
            ShareSheetContent(onClose: flight.close),
      ),
    );
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('PlayerDialogContent opens in a dialog without overflow', (
    WidgetTester tester,
  ) async {
    await openAndSettle(
      tester,
      (BuildContext context) => showMorphDialog(
        context,
        from: 'probe',
        width: 440,
        height: 520,
        builder: (BuildContext context, MorphFlight flight) =>
            PlayerDialogContent(flight: flight),
      ),
    );
    expect(find.text('Ambient Drift'), findsOneWidget);
  });

  testWidgets('ComposeDialogContent opens in a dialog without overflow', (
    WidgetTester tester,
  ) async {
    await openAndSettle(
      tester,
      (BuildContext context) => showMorphDialog(
        context,
        from: 'probe',
        width: 480,
        height: 460,
        builder: (BuildContext context, MorphFlight flight) =>
            ComposeDialogContent(flight: flight),
      ),
    );
    expect(find.text('New playlist'), findsOneWidget);
  });

  testWidgets('the tour app builds at the minimum window size 900x640', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MorphTourApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
