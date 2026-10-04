import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

const MorphScrimMotion _scrim = MorphScrimMotion(
  motion: MorphMotion.instant,
  openDelay: Duration(milliseconds: 24),
  closeDelay: Duration(milliseconds: 32),
);

void main() {
  for (final bool direct in <bool>[false, true]) {
    testWidgets(
      'non-modal ${direct ? 'direct' : 'helper'} route keeps background tappable',
      (WidgetTester tester) async {
        late BuildContext sourceContext;
        int taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (BuildContext context, Widget? child) =>
                MorphScope(child: child!),
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  Align(
                    alignment: Alignment.topLeft,
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('background'),
                    ),
                  ),
                  Center(
                    child: MorphTag(
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
                ],
              ),
            ),
          ),
        );
        final NavigatorState navigator = Navigator.of(sourceContext);
        if (direct) {
          unawaited(
            navigator.push(
              MorphPageRoute<void>(
                from: 'source',
                modal: false,
                target: MorphTargetSpec.dialog(width: 240, height: 160),
                builder: (BuildContext context, MorphFlight flight) =>
                    const Text('content'),
              ),
            ),
          );
        } else {
          unawaited(
            showMorphRoute<void>(
              sourceContext,
              modal: false,
              target: MorphTargetSpec.dialog(width: 240, height: 160),
              builder: (BuildContext context, MorphFlight flight) =>
                  const Text('content'),
            ),
          );
        }
        await tester.pump();
        final MorphFlight flight = MorphScope.of(
          sourceContext,
        ).flightOf('source')!;
        expect(flight.modal, isFalse);
        await tester.tap(find.text('background'));
        await tester.pump();
        expect(taps, 1);
        await tester.pumpAndSettle();
        expect(flight.routeOwnsContent.value, isTrue);
        expect(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is ColoredBox &&
                widget.color.a > 0 &&
                widget.color.r == 0 &&
                widget.color.g == 0 &&
                widget.color.b == 0,
          ),
          findsNothing,
        );
        await tester.tap(find.text('background'));
        await tester.pump();
        expect(taps, 2);
        expect(flight.isOpenOrOpening, isTrue);
        navigator.pop();
        await tester.pumpAndSettle();
        expect(flight.isFinished, isTrue);
      },
    );
  }

  for (final bool direct in <bool>[false, true]) {
    testWidgets(
      '${direct ? 'direct' : 'helper'} route resolves a scope inside the source page',
      (WidgetTester tester) async {
        late BuildContext sourceContext;
        await tester.pumpWidget(
          MaterialApp(
            home: MorphScope(
              child: Scaffold(
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
          ),
        );
        final NavigatorState navigator = Navigator.of(sourceContext);
        if (direct) {
          unawaited(
            navigator.push(
              MorphPageRoute<void>(
                from: 'source',
                sourceContext: sourceContext,
                target: MorphTargetSpec.dialog(),
                builder: (BuildContext context, MorphFlight flight) =>
                    const Text('content'),
              ),
            ),
          );
        } else {
          unawaited(
            showMorphRoute<void>(
              sourceContext,
              builder: (BuildContext context, MorphFlight flight) =>
                  const Text('content'),
            ),
          );
        }
        await tester.pumpAndSettle();
        final MorphFlight flight = MorphScope.of(
          sourceContext,
        ).flightOf('source')!;
        expect(flight.routeOwnsContent.value, isTrue);
        expect(find.text('content'), findsOneWidget);
        navigator.pop();
        await tester.pumpAndSettle();
        expect(flight.isFinished, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'route scrim resolves theme and preserves the channel at handoff',
    (WidgetTester tester) async {
      late BuildContext sourceContext;
      final GlobalKey<NavigatorState> navigatorKey =
          GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData(
            extensions: const <ThemeExtension<Object?>>[
              MorphTheme(scrimMotion: _scrim),
            ],
          ),
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
      unawaited(
        showMorphRoute<void>(
          sourceContext,
          builder: (BuildContext context, MorphFlight flight) =>
              const Text('content'),
        ),
      );
      await tester.pump();
      final MorphScopeState scope = tester.state<MorphScopeState>(
        find.byType(MorphScope),
      );
      final MorphFlight themed = scope.flightOf('source')!;
      expect(themed.scrimMotion, _scrim);
      expect(themed.scrimValue, 0);
      await tester.pumpAndSettle();
      expect(themed.routeOwnsContent.value, isTrue);
      expect(themed.scrimValue, 1);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(themed.isFinished, isTrue);

      const MorphScrimMotion explicit = MorphScrimMotion(
        motion: MorphMotion.liquid,
      );
      unawaited(
        showMorphRoute<void>(
          sourceContext,
          scrimMotion: explicit,
          builder: (BuildContext context, MorphFlight flight) =>
              const Text('content'),
        ),
      );
      await tester.pumpAndSettle();
      expect(scope.flightOf('source')!.scrimMotion, explicit);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a route can fly in an overlay above its nested navigator', (
    WidgetTester tester,
  ) async {
    late BuildContext sourceContext;
    final GlobalKey<NavigatorState> rootKey = GlobalKey<NavigatorState>();
    final GlobalKey<NavigatorState> nestedKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootKey,
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 400,
              height: 300,
              child: Navigator(
                key: nestedKey,
                onGenerateRoute: (RouteSettings settings) =>
                    MaterialPageRoute<void>(
                      settings: settings,
                      builder: (BuildContext context) => Scaffold(
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
              ),
            ),
          ),
        ),
      ),
    );
    unawaited(
      showMorphRoute<void>(
        sourceContext,
        overlay: rootKey.currentState!.overlay,
        builder: (BuildContext context, MorphFlight flight) =>
            const Text('content'),
      ),
    );
    await tester.pumpAndSettle();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('source')!;
    expect(nestedKey.currentState!.canPop(), isTrue);
    expect(rootKey.currentState!.canPop(), isFalse);
    expect(
      flight.overlayBox,
      rootKey.currentState!.overlay!.context.findRenderObject(),
    );
    expect(flight.routeOwnsContent.value, isFalse);
    expect(find.text('content'), findsOneWidget);
    expect(flight.lastTargetRect.width, greaterThan(400));
    nestedKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(flight.isFinished, isTrue);
    expect(scope.flightOf('source'), isNull);
  });
}
