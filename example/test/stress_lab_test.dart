import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/playground/stress_lab.dart';

Widget host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 800, height: 600, child: child)),
  );
}

void main() {
  testWidgets('animates 24 orbiting pieces without exceptions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(const StressLab(count: 24, animate: true, blend: 24, cell: 6)),
    );
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    // Toggling animation off must stop cleanly and keep the last frame.
    await tester.pumpWidget(
      host(const StressLab(count: 24, animate: false, blend: 24, cell: 6)),
    );
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });

  testWidgets('FPS meter reports after its refresh window', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(const StressLab(count: 8, animate: true, blend: 18, cell: 6)),
    );
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.textContaining('fps'), findsOneWidget);
    expect(find.textContaining('worst'), findsOneWidget);
  });
}
