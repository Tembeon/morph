import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

/// The morph route: pushed immediately, the flight plays as the
/// transition, the SECOND latch hands the live content subtree to the
/// route page at settle and back to the shuttle on pop - state must
/// survive both reparents.

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => n++),
      child: Text('count-$n'),
    );
  }
}

final Finder shuttleFinder = find.byWidgetPredicate(
  (Widget w) =>
      w is Material && w.animationDuration == .zero && w.child is Stack,
);

Widget host() {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MorphTag(
          id: 'card',
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showMorphRoute<void>(
                context,
                from: 'card',
                semanticLabel: 'Card',
                builder: (BuildContext context, MorphFlight flight) =>
                    const Center(child: Counter()),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> settle(WidgetTester tester, {int frames = 600}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  testWidgets('the second latch hands live state to the route and back', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;

    // Mid-open: the shuttle owns the content.
    expect(flight.routeOwnsContent.value, isFalse);
    expect(shuttleFinder, findsOneWidget);
    expect(find.text('count-0'), findsOneWidget);

    await settle(tester);

    // Settled: the route page owns the content, the shuttle stepped
    // aside, the flight stays alive for the close.
    expect(flight.routeOwnsContent.value, isTrue);
    expect(shuttleFinder, findsNothing);
    expect(find.text('count-0'), findsOneWidget);
    expect(flight.isFinished, isFalse);
    final Material pageSurface = tester.widget<Material>(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Material && widget.elevation == flight.target.elevation,
      ),
    );
    expect(pageSurface.animationDuration, Duration.zero);

    // Mutate state while the ROUTE owns the subtree.
    await tester.tap(find.text('count-0'));
    await tester.pump();
    expect(find.text('count-1'), findsOneWidget);

    // Pop: the content returns to the shuttle IN THE SAME FRAME with
    // its state, and the ordinary close flight plays.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    expect(flight.routeOwnsContent.value, isFalse);
    expect(shuttleFinder, findsOneWidget);
    expect(find.text('count-1'), findsOneWidget);
    expect(flight.controller.isClosing, isTrue);

    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(scope.flightOf('card'), isNull);
    expect(find.text('count-1'), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('removing a settled route reveals and retires its flight', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('go'));
    await settle(tester);
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    final ModalRoute<Object?> route = ModalRoute.of(
      tester.element(find.text('count-0')),
    )!;
    expect(flight.routeOwnsContent.value, isTrue);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(MorphTag),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      0,
    );

    tester.state<NavigatorState>(find.byType(Navigator)).removeRoute(route);
    await settle(tester);

    expect(flight.isFinished, isTrue);
    expect(scope.flightOf('card'), isNull);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(MorphTag),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
    );
    expect(find.text('count-0'), findsNothing);
    expect(find.text('go'), findsOneWidget);
    expect(await flight.closed, isNull);
  });

  testWidgets('showMorphRoute works without Material localizations', (
    WidgetTester tester,
  ) async {
    late BuildContext sourceContext;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
          settings: settings,
          pageBuilder:
              (
                BuildContext context,
                Animation<double> animation,
                Animation<double> secondaryAnimation,
              ) => MorphTag(
                id: 'card',
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
    final NavigatorState navigator = Navigator.of(sourceContext);
    final Future<void> closed = showMorphRoute<void>(
      sourceContext,
      builder: (BuildContext context, MorphFlight flight) =>
          const Text('destination'),
    );
    await settle(tester);
    expect(find.text('destination'), findsOneWidget);
    final ModalRoute<Object?> route = ModalRoute.of(
      tester.element(find.text('destination')),
    )!;
    expect(route.barrierLabel, isNull);
    navigator.pop();
    await settle(tester);
    await closed;
  });

  testWidgets('flight.close() from content retires the route', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    await settle(tester);
    expect(flight.routeOwnsContent.value, isTrue);

    flight.close();
    await tester.pump();
    // The route follows the flight: content handed back, route removed.
    expect(flight.routeOwnsContent.value, isFalse);
    expect(shuttleFinder, findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );

    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(find.text('count-0'), findsNothing);
  });

  testWidgets('a pop before the second latch closes mid-flight', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(flight.routeOwnsContent.value, isFalse);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    expect(flight.controller.isClosing, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('a barrier tap pre-latch pops the route', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    // The shuttle scrim owns the tap pre-latch; it must route through
    // the Navigator, not close the flight behind the route's back.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(flight.controller.isClosing, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
  });

  testWidgets('predictive back scrubs the flight; cancel and commit', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    final NavigatorState nav = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    final MorphPageRoute<void> route = MorphPageRoute<void>(
      from: 'card',
      target: MorphTargetSpec.dialog(),
      builder: (BuildContext context, MorphFlight flight) =>
          const Center(child: Counter()),
    );
    unawaited(nav.push(route));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    await settle(tester);
    expect(flight.routeOwnsContent.value, isTrue);

    // The gesture starts: the content returns to the shuttle and the
    // finger owns a shallow scrub of the value.
    route.handleStartBackGesture();
    await tester.pump();
    expect(flight.routeOwnsContent.value, isFalse);
    expect(shuttleFinder, findsOneWidget);
    expect(flight.controller.isScrubbing, isTrue);
    route.handleUpdateBackGestureProgress(progress: 1);
    await tester.pump();
    expect(flight.controller.value, lessThan(0.9));
    expect(flight.controller.value, greaterThan(0.7));
    expect(find.text('count-0'), findsOneWidget);

    // Cancel: springs back to settled, the page re-adopts the content.
    route.handleCancelBackGesture();
    await settle(tester);
    expect(flight.controller.value, closeTo(1, 0.01));
    expect(flight.routeOwnsContent.value, isTrue);
    expect(shuttleFinder, findsNothing);

    // A second gesture, committed this time: pop plus the ordinary
    // close from the scrubbed value.
    route.handleStartBackGesture();
    route.handleUpdateBackGestureProgress(progress: 0.6);
    await tester.pump();
    route.handleCommitBackGesture();
    await tester.pump();
    expect(flight.controller.isClosing, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(nav.canPop(), isFalse);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('a covered or finished route ignores the back gesture', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    final NavigatorState nav = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    final MorphPageRoute<void> route = MorphPageRoute<void>(
      from: 'card',
      target: MorphTargetSpec.dialog(),
      builder: (BuildContext context, MorphFlight flight) =>
          const Center(child: Counter()),
    );
    unawaited(nav.push(route));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    await settle(tester);

    // Covered by another route: not current - the gesture must not
    // start a scrub or steal the content.
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const Scaffold(body: Text('top')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    route.handleStartBackGesture();
    expect(flight.controller.isScrubbing, isFalse);
    expect(flight.routeOwnsContent.value, isTrue);
    nav.pop();
    await tester.pumpAndSettle();

    nav.pop();
    await settle(tester);
    expect(flight.isFinished, isTrue);
    route.handleStartBackGesture();
    expect(flight.controller.isScrubbing, isFalse);
  });

  testWidgets('predictive back arrives through the real binding bridge', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The system events enter through the platform channel, exactly as
    // Android sends them: the _RouteBackGestureObserver must claim the
    // gesture (a PopupRoute is never wrapped by the material detector,
    // so nobody else would deliver it).
    Future<void> backEvent(String method, [Map<String, Object?>? args]) {
      return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.backGesture.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (ByteData? _) {},
      );
    }

    Map<String, Object?> touch(double progress) => <String, Object?>{
      'touchOffset': <double>[12, 400],
      'progress': progress,
      'swipeEdge': 0,
    };

    await tester.pumpWidget(host());
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    await settle(tester);
    expect(flight.routeOwnsContent.value, isTrue);

    // Start + drag: the observer claims the gesture and the flight
    // scrubs shallowly under the finger.
    await backEvent('startBackGesture', touch(0));
    await tester.pump();
    expect(flight.controller.isScrubbing, isTrue);
    expect(flight.routeOwnsContent.value, isFalse);
    await backEvent('updateBackGestureProgress', touch(1));
    await tester.pump();
    expect(flight.controller.value, lessThan(0.9));

    // Cancel: springs back, the page re-adopts the content.
    await backEvent('cancelBackGesture');
    await settle(tester);
    expect(flight.controller.value, closeTo(1, 0.01));
    expect(flight.routeOwnsContent.value, isTrue);

    // A second gesture, committed: the route pops and the ordinary
    // close plays from the scrubbed value.
    await backEvent('startBackGesture', touch(0));
    await backEvent('updateBackGestureProgress', touch(0.6));
    await tester.pump();
    await backEvent('commitBackGesture');
    await tester.pump();
    expect(flight.controller.isClosing, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('a cover pushed over a still-opening route gets the latch', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    final NavigatorState nav = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    await tester.pump(const Duration(milliseconds: 30));
    expect(flight.routeOwnsContent.value, isFalse);

    // Cover the still-opening morph route with a plain page.
    int taps = 0;
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('top-button'),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // The spring settled under the cover: the latch must still fire -
    // otherwise the shuttle (scrim included) parks above the cover and
    // swallows its input forever.
    expect(flight.routeOwnsContent.value, isTrue);
    expect(shuttleFinder, findsNothing);
    await tester.tap(find.text('top-button'));
    expect(taps, 1);

    // Popping back lands on a live, latched morph page.
    nav.pop();
    await settle(tester);
    expect(flight.routeOwnsContent.value, isTrue);
    await tester.tap(find.text('count-0'));
    await tester.pump();
    expect(find.text('count-1'), findsOneWidget);

    nav.pop();
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('an overlay flight above the route pops FIRST', (
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
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MorphTag(
              id: 'card',
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphRoute<void>(
                    context,
                    from: 'card',
                    builder: (BuildContext context, MorphFlight flight) =>
                        Center(
                          child: MorphTag(
                            id: 'pill',
                            child: Builder(
                              builder: (BuildContext context) => TextButton(
                                onPressed: () => showMorphDialog(
                                  context,
                                  from: 'pill',
                                  width: 200,
                                  height: 200,
                                  builder:
                                      (
                                        BuildContext context,
                                        MorphFlight flight,
                                      ) => const Text('menu'),
                                ),
                                child: const Text('open menu'),
                              ),
                            ),
                          ),
                        ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final NavigatorState nav = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.tap(find.text('open menu'));
    await tester.pump();
    final MorphFlight menu = scope.flightOf('pill')!;
    await settle(tester);

    // The pop (Esc routes here via DismissIntent -> maybePop) must
    // close the MENU, not the route beneath it.
    unawaited(nav.maybePop());
    await tester.pump();
    expect(menu.controller.isClosing, isTrue);
    await settle(tester);
    expect(menu.isFinished, isTrue);
    final MorphFlight lesson = scope.flightOf('card')!;
    expect(lesson.isFinished, isFalse);
    expect(lesson.routeOwnsContent.value, isTrue);
    expect(find.text('open menu'), findsOneWidget);

    // The next pop closes the route itself.
    unawaited(nav.maybePop());
    await settle(tester);
    expect(lesson.isFinished, isTrue);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('an overlay flight over a plain page joins local history', (
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
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MorphTag(
              id: 'card',
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'card',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('content'),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    await settle(tester);

    final NavigatorState nav = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    // The flight's entry makes the home route poppable; popping closes
    // the flight, not the page.
    expect(nav.canPop(), isTrue);
    unawaited(nav.maybePop());
    await tester.pump();
    expect(flight.controller.isClosing, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(nav.canPop(), isFalse);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('scrim and shadow colors survive the second latch', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const Color scrim = Color(0x80102030);
    const Color shadow = Color(0xCC445566);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MorphTag(
              id: 'card',
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphRoute<void>(
                    context,
                    from: 'card',
                    scrimColor: scrim,
                    shadowColor: shadow,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('content'),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;
    expect(flight.scrimColor, scrim);
    expect(flight.shadowColor, shadow);
    await settle(tester);

    // The route page owns the settled state and paints the same colors
    // the shuttle flew with: the same hue on the scrim, the same shadow
    // on the surface.
    expect(flight.routeOwnsContent.value, isTrue);
    expect(shuttleFinder, findsNothing);
    final bool scrimPainted = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .any(
          (ColoredBox b) =>
              b.color.a > 0 &&
              b.color.withValues(alpha: 1) == scrim.withValues(alpha: 1),
        );
    expect(scrimPainted, isTrue);
    final bool shadowPainted = tester
        .widgetList<Material>(find.byType(Material))
        .any((Material m) => m.shadowColor == shadow);
    expect(shadowPainted, isTrue);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(flight.isFinished, isTrue);
  });
}
