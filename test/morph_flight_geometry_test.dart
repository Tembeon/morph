import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

void main() {
  testWidgets('geometry ticks exclude scrim-only motion and retain drivers', (
    WidgetTester tester,
  ) async {
    late BuildContext sourceContext;
    final ChangeNotifier repaint = ChangeNotifier();
    addTearDown(repaint.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: MorphTag(
            id: 'source',
            replica: const Text('replica'),
            child: Builder(
              builder: (BuildContext context) {
                sourceContext = context;
                return const Text('source');
              },
            ),
          ),
        ),
      ),
    );
    final MorphFlight flight = showMorph(
      sourceContext,
      motion: MorphMotion.instant,
      scrimMotion: const MorphScrimMotion(motion: MorphMotion.glacial),
      target: MorphTargetSpec.measured(
        repaint: repaint,
        constraintsFor: (Size size, EdgeInsets padding) =>
            const BoxConstraints(maxWidth: 300, maxHeight: 300),
        placeFor: (Size size, EdgeInsets padding, Size content) =>
            Rect.fromCenter(
              center: size.center(Offset.zero),
              width: content.width,
              height: content.height,
            ),
      ),
      builder: (BuildContext context, MorphFlight flight) =>
          const SizedBox(width: 200, height: 100),
    );
    int frames = 0;
    int geometry = 0;
    void onFrame() => frames++;
    void onGeometry() => geometry++;
    flight.frameTicks.addListener(onFrame);
    flight.geometryTicks.addListener(onGeometry);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(flight.controller.isAnimating, isFalse);
    expect(flight.scrimValue, lessThan(1));
    final int settledGeometry = geometry;
    final int settledFrames = frames;
    await tester.pump(const Duration(milliseconds: 50));
    expect(geometry, settledGeometry);
    expect(frames, greaterThan(settledFrames));

    repaint.notifyListeners();
    expect(geometry, settledGeometry + 1);
    flight.beginDrag();
    flight.dragBy(const Offset(10, 5));
    expect(geometry, greaterThan(settledGeometry + 1));
    flight.endDrag(Offset.zero, commit: false);
    final int beforeSize = geometry;
    flight.reportContentSize(const Size(250, 150));
    await tester.pump(const Duration(milliseconds: 16));
    expect(geometry, greaterThan(beforeSize));
    flight.close();
    await tester.pumpAndSettle();
    flight.frameTicks.removeListener(onFrame);
    flight.geometryTicks.removeListener(onGeometry);
    expect(flight.isFinished, isTrue);
  });
}
