import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

import 'support/shuttle.dart';

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

    expect(
      shuttleMaterial,
      findsOneWidget,
      reason:
          'The shuttle Material must pin animationDuration to zero: '
          'the spring is the only clock.',
    );
    final MorphFlight flight = tester
        .state<MorphScopeState>(find.byType(MorphScope))
        .flightOf('pill')!;
    final MorphFrame frame = computeMorphFrame(
      value: flight.controller.value,
      sourceRect: flight.sourceRect,
      targetRect: flight.lastTargetRect,
      sourceShape: flight.tag.shape,
      targetShape: flight.target.shape,
      sourceColor: const Color(0xFF000000),
      targetColor: const Color(0xFF000000),
      maxScrimOpacity: 0,
    );
    final RoundedRectangleBorder frameShape =
        frame.shape as RoundedRectangleBorder;
    final double frameRadius = frameShape.borderRadius.resolve(.ltr).topLeft.x;
    // Mid-flight: strictly between the endpoints (140 and 28), so a
    // lagging tween could not coincide by accident.
    expect(frameRadius, lessThan(139));
    expect(frameRadius, greaterThan(29));

    // The surface the shuttle draws (the replica inside carries its own
    // PhysicalShape further down) clips to exactly this frame's shape.
    expect(shuttleShape(tester), frame.shape);
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
              child: _SpecSurface(
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
    // shadowless; only the container may carry elevation.
    expect(shuttleSurface(tester).elevation, greaterThan(0));
    final Iterable<PhysicalShape> inner = tester.widgetList<PhysicalShape>(
      find.descendant(
        of: shuttleMaterial,
        matching: find.byType(PhysicalShape),
      ),
    );
    expect(inner, isNotEmpty);
    for (final PhysicalShape shape in inner) {
      expect(shape.elevation, 0);
    }
  });
}

/// A surface rendered from the enclosing tag's declared spec, the way an
/// app's own button would: the replica in the shuttle reads the spec the
/// shuttle republishes, so its elevation must arrive zeroed.
class _SpecSurface extends StatelessWidget {
  const _SpecSurface({required this.onTap, required this.child});

  final void Function(BuildContext context) onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MorphSurfaceSpec spec = MorphTag.specOf(context);
    return Material(
      shape: spec.shape,
      color: spec.color,
      elevation: spec.elevation,
      child: GestureDetector(onTap: () => onTap(context), child: child),
    );
  }
}
