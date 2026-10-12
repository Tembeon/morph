import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

import '../integration_test/support/control_matrix.dart';

/// Every cell of the control matrix runs on the host: its control builds,
/// its actions find their targets and leave no presentation open, and a
/// control removed while its menu is still out lets the menu go.
void main() {
  setUpAll(() async {
    // No Impeller on the host: the renderer reports its fake fallback once.
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {};
    try {
      await MorphGlassRenderer.precache();
    } finally {
      FlutterError.onError = previous;
    }
  });

  testWidgets('every matrix cell runs and cleans up', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const GalleryApp(key: ValueKey('matrix'), home: MatrixStage()),
    );
    await tester.pump(const Duration(seconds: 1));
    final driver = _HostDriver(tester);
    final scenes = <String>[];
    await runControlMatrix(driver, (String scene) {
      scenes.add(scene);
      return true;
    });
    expect(driver.measured, scenes);
    expect(find.byType(MatrixStage), findsOneWidget);
    // Nothing presented is left over a cell: the next one sees the page.
    expect(MatrixStage.control.value, isNull);
  });
}

class _HostDriver implements MatrixDriver {
  _HostDriver(this.tester);

  @override
  final WidgetTester tester;

  final List<String> measured = [];
  int _pointer = 1;

  @override
  Future<void> settle([int ms = 900]) =>
      tester.pump(Duration(milliseconds: ms));

  @override
  Future<void> finger(
    Offset from,
    List<Offset> path, {
    Duration holdBefore = const Duration(milliseconds: 16),
  }) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    await gesture.down(from);
    await tester.pump(holdBefore);
    for (final p in path) {
      await gesture.moveTo(p);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pump();
  }

  @override
  Future<void> tap(Offset at) =>
      finger(at, const [], holdBefore: const Duration(milliseconds: 60));

  @override
  Future<void> measure(String name, Future<void> Function() body) async {
    measured.add(name);
    await body();
    final routes = find.byType(ModalBarrier);
    expect(
      routes.evaluate().length,
      lessThanOrEqualTo(1),
      reason: '$name left a presentation open',
    );
  }
}
