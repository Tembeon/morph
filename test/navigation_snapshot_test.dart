import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/navigation_snapshot.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => value++),
    child: SizedBox(
      key: const ValueKey('counter'),
      width: 200,
      height: 80,
      child: Text('count $value'),
    ),
  );
}

Widget _page(String title, {Widget? body}) => MorphNavigationScaffold(
  title: title,
  slivers: [SliverToBoxAdapter(child: body ?? const SizedBox(height: 2000))],
);

Future<NavigatorState> _pumpStack(
  WidgetTester tester, {
  MorphGlassTier tier = .flat,
}) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: MorphGlass(
        painter: MorphGlassRenderer(tier: tier),
        child: MorphNavigationStack(
          home: Builder(
            builder: (BuildContext c) {
              context = c;
              return _page('Inbox', body: const _Counter());
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Navigator.of(context);
}

Finder get _snapshots => find.descendant(
  of: find.byType(MorphNavigationStack),
  matching: find.byType(SnapshotWidget, skipOffstage: false),
  skipOffstage: false,
);

List<bool> _allowed(WidgetTester tester) => [
  for (final SnapshotWidget w in tester.widgetList<SnapshotWidget>(_snapshots))
    w.controller.allowSnapshotting,
];

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MultiShaderBuilder.precacheShaders([
      ShaderKeys.fakeGlassSurface,
      ...ShaderKeys.liquidGlassRenders,
    ]);
  });
  tearDownAll(() => isLocalTest = false);
  tearDown(() => MorphNavigationSnapshot.debugEnabled = null);

  group('with the option on', () {
    setUp(() => MorphNavigationSnapshot.debugEnabled = true);

    testWidgets('both pages draw from snapshots while the slide moves only', (
      tester,
    ) async {
      final navigator = await _pumpStack(tester);
      expect(_snapshots, findsOneWidget);
      expect(_allowed(tester), [false]);

      navigator.push(MorphNavigationRoute<void>(builder: (_) => _page('Next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(_snapshots, findsNWidgets(2));
      expect(_allowed(tester), [true, true]);
      expect(
        find.ancestor(
          of: find.byType(SnapshotWidget),
          matching: find.byType(Transform),
        ),
        findsWidgets,
      );

      await tester.pumpAndSettle();
      expect(_snapshots, findsNWidgets(2));
      expect(_allowed(tester), [false, false]);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(_allowed(tester), [true, true]);
      await tester.pumpAndSettle();
      expect(_snapshots, findsOneWidget);
      expect(_allowed(tester), [false]);
    });

    testWidgets('an edge swipe snapshots until the page rests', (tester) async {
      final navigator = await _pumpStack(tester);
      navigator.push(MorphNavigationRoute<void>(builder: (_) => _page('Next')));
      await tester.pumpAndSettle();
      expect(_allowed(tester), [false, false]);
      final gesture = await tester.startGesture(const Offset(4, 500));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_allowed(tester), [true, true]);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_allowed(tester).every((bool allowed) => !allowed), isTrue);
    });

    testWidgets('a resting page is live and its hit testing is intact', (
      tester,
    ) async {
      final navigator = await _pumpStack(tester);
      navigator.push(
        MorphNavigationRoute<void>(
          builder: (_) => _page('Next', body: const _Counter()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('counter')).last);
      await tester.pump();
      expect(find.text('count 1'), findsOneWidget);
    });

    testWidgets('page state survives a push and its settle', (tester) async {
      final navigator = await _pumpStack(tester);
      await tester.tap(find.byKey(const ValueKey('counter')));
      await tester.tap(find.byKey(const ValueKey('counter')));
      await tester.pump();
      expect(find.text('count 2'), findsOneWidget);

      navigator.push(MorphNavigationRoute<void>(builder: (_) => _page('Next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('count 2'), findsOneWidget);
    });

    for (final tier in [MorphGlassTier.fake, MorphGlassTier.liquid]) {
      testWidgets('the $tier tier keeps every page live', (tester) async {
        final navigator = await _pumpStack(tester, tier: tier);
        expect(_snapshots, findsOneWidget);
        expect(_allowed(tester), [false]);

        navigator.push(
          MorphNavigationRoute<void>(builder: (_) => _page('Next')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 48));
        expect(_snapshots, findsNWidgets(2));
        expect(_allowed(tester), [false, false]);

        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 48));
        expect(_allowed(tester), [false, false]);
        await tester.pumpAndSettle();
      });
    }

    testWidgets('no renderer above the stack keeps every page live', (
      tester,
    ) async {
      tester.view.physicalSize = _screen * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: MorphNavigationStack(
            home: Builder(
              builder: (BuildContext c) {
                context = c;
                return _page('Inbox');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(
        context,
      ).push(MorphNavigationRoute<void>(builder: (_) => _page('Next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(_snapshots, findsNWidgets(2));
      expect(_allowed(tester), [false, false]);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('with the option off no page is wrapped', (tester) async {
    MorphNavigationSnapshot.debugEnabled = false;
    final navigator = await _pumpStack(tester);
    navigator.push(MorphNavigationRoute<void>(builder: (_) => _page('Next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    expect(_snapshots, findsNothing);
    await tester.pumpAndSettle();
    expect(_snapshots, findsNothing);
  });
}
