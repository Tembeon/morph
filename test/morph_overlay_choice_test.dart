import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

const double _barHeight = 80;
const double _tabTop = 100;

/// A shell in the shape that forces the choice: a nested navigator (a
/// tab) offset from the window origin, and a floating bar layered over
/// it. Flights in the tab's own overlay live under the bar; flights in
/// the shell's overlay fly above it.
class _Shell extends StatelessWidget {
  const _Shell({required this.useShellOverlay, required this.onFlight});

  final bool useShellOverlay;
  final ValueChanged<MorphFlight> onFlight;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              top: _tabTop,
              child: Navigator(
                onGenerateRoute: (RouteSettings settings) =>
                    MaterialPageRoute<void>(
                      settings: settings,
                      builder: (BuildContext context) => Center(
                        child: MorphTag(
                          id: 'btn',
                          child: Builder(
                            builder: (BuildContext context) => ElevatedButton(
                              onPressed: () => onFlight(
                                showMorphDialog(
                                  context,
                                  from: 'btn',
                                  width: 200,
                                  height: 120,
                                  overlay: useShellOverlay
                                      ? Overlay.of(context, rootOverlay: true)
                                      : null,
                                  builder:
                                      (
                                        BuildContext context,
                                        MorphFlight flight,
                                      ) => const Text('content'),
                                ),
                              ),
                              child: const Text('open'),
                            ),
                          ),
                        ),
                      ),
                    ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _barHeight,
              child: ColoredBox(
                color: Color(0xFFFF0000),
                child: Center(child: Text('bar')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

void main() {
  testWidgets('by default the flight lives in the nearest overlay, under the '
      'bar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MorphFlight? flight;
    await tester.pumpWidget(
      _Shell(useShellOverlay: false, onFlight: (MorphFlight f) => flight = f),
    );
    // Measured BEFORE the launch: mid-flight the shuttle carries a
    // replica of the button too.
    final Rect button = tester.getRect(find.byType(ElevatedButton));
    await tester.tap(find.text('open'));
    await settle(tester);
    // Two overlays above the content: the tab's (where it renders) and
    // the app's.
    expect(
      find.ancestor(of: find.text('content'), matching: find.byType(Overlay)),
      findsNWidgets(2),
    );
    // The dialog centers in the TAB's overlay, which starts 100 px down.
    final Offset center = tester.getCenter(find.text('content'));
    expect(center.dy, moreOrLessEquals((_tabTop + 800) / 2, epsilon: 2));
    // The source rect is measured in the tab's space too.
    expect(flight!.sourceRect.top, moreOrLessEquals(button.top - _tabTop));
    // The bar sits above the flight: a tap on it never reaches the scrim.
    await tester.tap(find.text('bar'));
    await settle(tester);
    expect(find.text('content'), findsOneWidget);
    flight!.abort();
    await tester.pump();
  });

  testWidgets('a chosen overlay hosts the flight, above the bar, with honest '
      'coordinates', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MorphFlight? flight;
    await tester.pumpWidget(
      _Shell(useShellOverlay: true, onFlight: (MorphFlight f) => flight = f),
    );
    final Rect button = tester.getRect(find.byType(ElevatedButton));
    await tester.tap(find.text('open'));
    await settle(tester);
    // Only the app's overlay is above the content now.
    expect(
      find.ancestor(of: find.text('content'), matching: find.byType(Overlay)),
      findsOneWidget,
    );
    // The dialog centers in the WHOLE window.
    final Offset center = tester.getCenter(find.text('content'));
    expect(center.dy, moreOrLessEquals(400, epsilon: 2));
    // The source rect is measured in the shell overlay's space - the
    // button's screen rect, not the nested navigator's local one.
    expect(flight!.sourceRect.top, moreOrLessEquals(button.top));
    expect(flight!.sourceRect.left, moreOrLessEquals(button.left));
    // The scrim covers the bar: a tap there dismisses the flight.
    await tester.tap(find.text('bar'), warnIfMissed: false);
    await settle(tester);
    expect(find.text('content'), findsNothing);
  });

  testWidgets('morphAnchorRect measures in the chosen overlay', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _Shell(useShellOverlay: true, onFlight: (MorphFlight _) {}),
    );
    final BuildContext context = tester.element(find.text('open'));
    final Rect nearest = morphAnchorRect(context);
    final Rect shell = morphAnchorRect(
      context,
      overlay: Overlay.of(context, rootOverlay: true),
    );
    expect(shell.top - nearest.top, moreOrLessEquals(_tabTop));
    expect(shell.size, nearest.size);
    expect(maybeMorphAnchorRect(context, overlay: null), nearest);
  });
}
