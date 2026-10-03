import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/foundation.dart';

Widget _app(Widget child) {
  return MaterialApp(
    builder: (BuildContext context, Widget? routed) =>
        MorphScope(child: routed!),
    home: Scaffold(body: child),
  );
}

void main() {
  group('release-mode errors', () {
    testWidgets('MorphScope.of without a scope is a FlutterError', (
      WidgetTester tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox();
          },
        ),
      );
      expect(() => MorphScope.of(captured), throwsA(isA<FlutterError>()));
      expect(MorphScope.maybeOf(captured), isNull);
    });

    testWidgets('an unknown tag id is a FlutterError; tryTagOf is null', (
      WidgetTester tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final MorphScopeState scope = MorphScope.of(captured);
      expect(() => scope.tagOf('missing'), throwsA(isA<FlutterError>()));
      expect(scope.tryTagOf('missing'), isNull);
      expect(
        () => showMorph(
          captured,
          from: 'missing',
          target: MorphTargetSpec.dialog(),
          builder: (BuildContext context, MorphFlight flight) =>
              const SizedBox(),
        ),
        throwsA(isA<FlutterError>()),
      );
    });

    testWidgets('specOf and idOf outside a tag are FlutterErrors', (
      WidgetTester tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(() => MorphTag.specOf(captured), throwsA(isA<FlutterError>()));
      expect(() => MorphTag.idOf(captured), throwsA(isA<FlutterError>()));
      expect(
        () => showMorph(
          captured,
          target: MorphTargetSpec.dialog(),
          builder: (BuildContext context, MorphFlight flight) =>
              const SizedBox(),
        ),
        throwsA(isA<FlutterError>()),
      );
    });

    testWidgets('morphAnchorRect off the tree is a FlutterError', (
      WidgetTester tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox(width: 10, height: 10);
            },
          ),
        ),
      );
      expect(morphAnchorRect(captured), isNotNull);
      await tester.pumpWidget(_app(const SizedBox()));
      expect(() => morphAnchorRect(captured), throwsA(isA<FlutterError>()));
    });
  });

  group('registry', () {
    testWidgets('a duplicate id is reported and the first tag keeps it', (
      WidgetTester tester,
    ) async {
      late BuildContext captured;
      Widget tags({required bool first}) {
        return _app(
          Builder(
            builder: (BuildContext context) {
              captured = context;
              return Column(
                children: <Widget>[
                  if (first)
                    const MorphTag(
                      id: 'x',
                      child: SizedBox(key: Key('first'), height: 10),
                    ),
                  const MorphTag(
                    id: 'x',
                    child: SizedBox(key: Key('second'), height: 20),
                  ),
                ],
              );
            },
          ),
        );
      }

      await tester.pumpWidget(tags(first: true));
      final Object? error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains('Duplicate MorphTag(id: x)'));
      final MorphScopeState scope = MorphScope.of(captured);
      expect(
        scope.tagOf('x').widget.child.key,
        const Key('first'),
        reason: 'the tag registered first keeps the id',
      );

      await tester.pumpWidget(tags(first: false));
      expect(tester.takeException(), isNull);
      expect(
        scope.tagOf('x').widget.child.key,
        const Key('second'),
        reason: 'the waiting tag takes over when the first one leaves',
      );
    });

    testWidgets('a morphable piece outside a scope degrades to fusion', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: MorphSkin(
                color: Color(0xFF2196F3),
                pieces: <MorphPiece>[
                  MorphPiece.morphable(
                    id: 'p',
                    rect: Rect.fromLTWH(0, 0, 80, 40),
                    radius: 20,
                    child: SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tag reparented under another scope re-registers', (
      WidgetTester tester,
    ) async {
      final GlobalKey tagKey = GlobalKey();
      final GlobalKey<MorphScopeState> a = GlobalKey<MorphScopeState>();
      final GlobalKey<MorphScopeState> b = GlobalKey<MorphScopeState>();
      Widget tree({required bool inA}) {
        final Widget tag = MorphTag(
          key: tagKey,
          id: 't',
          child: const SizedBox(height: 10),
        );
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              MorphScope(key: a, child: inA ? tag : const SizedBox()),
              MorphScope(key: b, child: inA ? const SizedBox() : tag),
            ],
          ),
        );
      }

      await tester.pumpWidget(tree(inA: true));
      expect(a.currentState!.tryTagOf('t'), isNotNull);
      expect(b.currentState!.tryTagOf('t'), isNull);
      await tester.pumpWidget(tree(inA: false));
      expect(a.currentState!.tryTagOf('t'), isNull);
      expect(b.currentState!.tryTagOf('t'), isNotNull);
    });
  });
}
