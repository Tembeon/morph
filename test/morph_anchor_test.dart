import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

class _AnchorHost extends StatefulWidget {
  const _AnchorHost();

  @override
  State<_AnchorHost> createState() => _AnchorHostState();
}

class _AnchorHostState extends State<_AnchorHost> {
  bool _open = false;
  int dismissRequests = 0;

  bool get open => _open;

  set open(bool value) => setState(() => _open = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: Center(
          child: MorphAnchor(
            isOpen: _open,
            onDismiss: () {
              dismissRequests++;
              open = false;
            },
            target: MorphTargetSpec.sheet(),
            shape: const StadiumBorder(),
            closedBuilder: (BuildContext context) => TextButton(
              onPressed: () => open = true,
              child: const Text('anchor-button'),
            ),
            openBuilder: (BuildContext context, MorphFlight flight) =>
                const Text('anchor-sheet'),
          ),
        ),
      ),
    );
  }
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

_AnchorHostState _hostState(WidgetTester tester) =>
    tester.state<_AnchorHostState>(find.byType(_AnchorHost));

void main() {
  testWidgets('the morph is a function of state: the bool opens and closes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const _AnchorHost());
    expect(find.text('anchor-sheet'), findsNothing);

    await tester.tap(find.text('anchor-button'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('anchor-sheet'), findsOneWidget);

    await settle(tester);

    _hostState(tester).open = false;
    await tester.pump();
    await settle(tester);
    expect(find.text('anchor-sheet'), findsNothing);
    expect(find.text('anchor-button'), findsOneWidget);
  });

  testWidgets('toggling the bool mid-flight retargets and carries velocity', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const _AnchorHost());
    final _AnchorHostState host = _hostState(tester);
    host.open = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));

    final MorphScopeState scope = MorphScope.of(
      tester.element(find.text('anchor-sheet')),
    );
    final MorphFlight flight = scope.lastFlight.value!;
    final double vBefore = flight.controller.velocity;
    expect(flight.controller.target, 1);
    expect(vBefore, greaterThan(0));

    host.open = false;
    await tester.pump();
    expect(flight.controller.target, 0);
    expect(flight.controller.velocity, moreOrLessEquals(vBefore));

    host.open = true;
    await tester.pump();
    expect(flight.controller.target, 1);

    host.open = false;
    await tester.pump();
    await settle(tester);
    expect(flight.isFinished, isTrue);
  });

  testWidgets('unmounting an open anchor: external listeners stay safe', (
    WidgetTester tester,
  ) async {
    bool showAnchor = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              if (!showAnchor) {
                return const SizedBox();
              }
              return Center(
                child: MorphAnchor(
                  isOpen: true,
                  onDismiss: () {},
                  target: MorphTargetSpec.sheet(),
                  closedBuilder: (BuildContext context) =>
                      const Text('anchor-btn'),
                  openBuilder: (BuildContext context, MorphFlight flight) =>
                      const Text('anchor-sheet'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('anchor-sheet'), findsOneWidget);

    final MorphScopeState scope = MorphScope.of(
      tester.element(find.text('anchor-sheet')),
    );
    final MorphFlight flight = scope.lastFlight.value!;
    void listener() {}
    flight.controller.addListener(listener);

    rebuild(() => showAnchor = false);
    await tester.pump();
    await tester.pump();

    expect(flight.isFinished, isTrue);
    expect(find.text('anchor-sheet'), findsNothing);
    flight.controller.removeListener(listener);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an anchor rebuild refreshes the open overlay content', (
    WidgetTester tester,
  ) async {
    int counter = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return Center(
                child: MorphAnchor(
                  isOpen: true,
                  onDismiss: () {},
                  target: MorphTargetSpec.sheet(),
                  closedBuilder: (BuildContext context) =>
                      const Text('anchor-btn'),
                  openBuilder: (BuildContext context, MorphFlight flight) =>
                      Text('count-$counter'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await settle(tester);
    expect(find.text('count-0'), findsOneWidget);

    rebuild(() => counter = 7);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('count-7'),
      findsOneWidget,
      reason:
          'overlay content derives from the owner state like the '
          'inline widget does - it must rebuild with the anchor',
    );
  });

  testWidgets('the anchor declares the full source surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphAnchor(
              isOpen: true,
              onDismiss: () {},
              target: MorphTargetSpec.sheet(),
              spec: const MorphSurfaceSpec(
                shape: StadiumBorder(),
                elevation: 6,
              ),
              semanticLabel: 'Share sheet',
              closedBuilder: (BuildContext context) => const Text('anchor-btn'),
              openBuilder: (BuildContext context, MorphFlight flight) =>
                  const Text('anchor-sheet'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    final MorphScopeState scope = MorphScope.of(
      tester.element(find.text('anchor-sheet')),
    );
    final MorphFlight flight = scope.lastFlight.value!;
    expect(flight.tag.elevation, 6);
    expect(flight.tag.shape, isA<StadiumBorder>());
    expect(flight.semanticLabel, 'Share sheet');
    await settle(tester);
  });

  testWidgets('tapping the scrim calls onDismiss, not closing by itself', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const _AnchorHost());
    final _AnchorHostState host = _hostState(tester);
    host.open = true;
    await tester.pump();
    await settle(tester);
    expect(find.text('anchor-sheet'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(host.dismissRequests, 1);
    expect(host.open, isFalse);

    await settle(tester);
    expect(find.text('anchor-sheet'), findsNothing);
  });
}
