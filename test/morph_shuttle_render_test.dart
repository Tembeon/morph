import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

/// Material double-animates shape and elevation changes on its own
/// hidden 200 ms clock (kThemeChangeDuration): fed a fresh shape every
/// spring tick, its internal tween chases the frame with visible lag on
/// open and a radius pop at the handoff swap on close. The shuttle must
/// pin animationDuration to zero so the spring stays the only clock -
/// this test reads the actual render-layer clipper mid-flight and
/// requires it to match the frame's shape exactly.
void main() {
  testWidgets('the rendered shuttle shape tracks the frame with no lag', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphTag(
              id: 'pill',
              shape: const RoundedRectangleBorder(
                borderRadius: .all(.circular(140)),
              ),
              child: SizedBox(
                width: 360,
                height: 280,
                child: Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () => showMorphSheet(
                      context,
                      from: 'pill',
                      motion: .glacial,
                      builder: (BuildContext context, MorphFlight flight) =>
                          const Text('sheet'),
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final Finder shuttleMaterial = find.byWidgetPredicate(
      (Widget w) => w is Material && w.animationDuration == .zero,
    );
    expect(
      shuttleMaterial,
      findsOneWidget,
      reason:
          'The shuttle Material must pin animationDuration to zero: '
          'the spring is the only clock.',
    );
    final Material material = tester.widget<Material>(shuttleMaterial);
    final RoundedRectangleBorder frameShape =
        material.shape! as RoundedRectangleBorder;
    final double frameRadius = frameShape.borderRadius.resolve(.ltr).topLeft.x;
    // Mid-flight: strictly between the endpoints (140 and 28), so a
    // lagging tween could not coincide by accident.
    expect(frameRadius, lessThan(139));
    expect(frameRadius, greaterThan(29));

    // The replica inside the shuttle carries its own PhysicalShape:
    // the OUTERMOST one is the shuttle surface.
    final PhysicalShape physical = tester.widget<PhysicalShape>(
      find
          .descendant(of: shuttleMaterial, matching: find.byType(PhysicalShape))
          .first,
    );
    final ShapeBorderClipper clipper = physical.clipper as ShapeBorderClipper;
    expect(clipper.shape, material.shape);
  });

  testWidgets('the replica rides the container geometry and casts no '
      'second shadow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Align(
            alignment: const Alignment(-0.6, 0.6),
            child: MorphTag(
              id: 'fab',
              spec: const MorphSurfaceSpec(
                shape: StadiumBorder(),
                color: Color(0xFF7C5CFF),
                elevation: 4,
              ),
              child: MorphSurface(
                onTap: (BuildContext context) => showMorphDialog(
                  context,
                  from: 'fab',
                  width: 420,
                  height: 360,
                  motion: .glacial,
                  builder: (BuildContext context, MorphFlight flight) =>
                      const Text('dialog'),
                ),
                child: const Padding(
                  padding: .symmetric(horizontal: 24, vertical: 14),
                  child: Text('compose'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final double homeWidth = tester.getSize(find.text('compose')).width;
    await tester.tap(find.text('compose'));
    await tester.pump();
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final Finder shuttleMaterial = find.byWidgetPredicate(
      (Widget w) => w is Material && w.animationDuration == .zero,
    );
    final Size shuttle = tester.getSize(shuttleMaterial);
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final Rect source = scope.flightOf('fab')!.sourceRect;
    expect(shuttle.width, greaterThan(source.width * 1.3));

    // Two 'compose' texts exist: the hidden home original and the
    // flying replica. The replica's painted width must track the
    // container's growth (width ratio), not sit at natural size.
    final Finder flyingText = find.descendant(
      of: shuttleMaterial,
      matching: find.text('compose'),
    );
    expect(flyingText, findsOneWidget);
    final double flownWidth = tester.getRect(flyingText).width;
    expect(
      flownWidth / homeWidth,
      moreOrLessEquals(shuttle.width / source.width, epsilon: 0.05),
    );

    // One mass - one shadow: every surface INSIDE the shuttle is
    // shadowless; only the container (the first PhysicalShape) may
    // carry elevation.
    final Iterable<PhysicalShape> inner = tester
        .widgetList<PhysicalShape>(
          find.descendant(
            of: shuttleMaterial,
            matching: find.byType(PhysicalShape),
          ),
        )
        .skip(1);
    expect(inner, isNotEmpty);
    for (final PhysicalShape shape in inner) {
      expect(shape.elevation, 0);
    }
  });
}
