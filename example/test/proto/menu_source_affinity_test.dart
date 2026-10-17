import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _step = Duration(microseconds: 8333);

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(_step);
  }
  expect(done(), isTrue);
}

class _OtherView extends TestFlutterView {
  _OtherView(TestFlutterView original)
    : super(
        view: original,
        platformDispatcher: original.platformDispatcher,
        display: original.display,
      );

  @override
  int get viewId => 100;

  @override
  void render(ui.Scene scene, {Size? size}) {}

  @override
  void updateSemantics(ui.SemanticsUpdate update) {}
}

class _Observer extends NavigatorObserver {
  final routes = <ProbeMenuRoute>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    if (route is ProbeMenuRoute) routes.add(route);
  }
}

class _Harness {
  _Harness({this.nested = false, this.foreignView});

  final bool nested;
  final ui.FlutterView? foreignView;
  final observers = [_Observer(), _Observer()];
  final samples = <ProbeMenuSample>[];
  ValueChanged<ProbeMenuSample>? observe;
  VoidCallback? creating;
  WidgetBuilder? menuBuilder;
  final location = ValueNotifier(0);
  final navigators = [GlobalKey<NavigatorState>(), GlobalKey<NavigatorState>()];
  final source = GlobalKey<ProbeMenuSourceState>();
  final models = <MorphMenuMotion>[];
  final selected = <(int, int)>[];

  Widget slot(WidgetTester tester, int index) => ValueListenableBuilder<int>(
    valueListenable: location,
    builder: (_, current, _) => current == index
        ? ProbeMenuSource(
            key: source,
            pointerInput: true,
            now: () => Duration(
              microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
            ),
            onSample: (sample) {
              samples.add(sample);
              observe?.call(sample);
            },
            createMotion: () {
              creating?.call();
              final generation = models.length;
              final model = MorphMenuMotion(
                button: const Rect.fromLTWH(24, 80, 44, 44),
                bounds: const Size(402, 874),
                itemCount: 3,
                sourceHeight: 64,
                sourceRadius: 22,
              );
              model.onSelected = (item) => selected.add((generation, item));
              models.add(model);
              return model;
            },
            menuBuilder: (context) =>
                menuBuilder?.call(context) ?? const SizedBox.expand(),
          )
        : const SizedBox.expand(),
  );

  Widget root(WidgetTester tester, int index) => WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: navigators[index],
    navigatorObservers: [observers[index]],
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) {
        if (nested) {
          return Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (_) => PageRouteBuilder<void>(
                      transitionDuration: Duration.zero,
                      pageBuilder: (_, _, _) => slot(tester, i),
                    ),
                  ),
                ),
            ],
          );
        }
        if (foreignView case final view?) {
          return ViewAnchor(
            view: View(
              view: view,
              child: Directionality(
                textDirection: .ltr,
                child: slot(tester, index),
              ),
            ),
            child: const SizedBox.expand(),
          );
        }
        return slot(tester, index);
      },
    ),
  );

  Route<void> cover(int root) {
    final route = PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const SizedBox.expand(),
    );
    unawaited(navigators[root].currentState!.push<void>(route));
    return route;
  }

  Future<void> mount(WidgetTester tester, {_OtherView? secondView}) =>
      tester.pumpWidget(
        nested || foreignView != null
            ? root(tester, 0)
            : secondView == null
            ? Row(
                textDirection: .ltr,
                children: [
                  Expanded(child: root(tester, 0)),
                  Expanded(child: root(tester, 1)),
                ],
              )
            : ViewCollection(
                views: [
                  View(view: tester.view, child: root(tester, 0)),
                  View(view: secondView, child: root(tester, 1)),
                ],
              ),
        wrapWithView: secondView == null,
      );

  Future<ProbeMenuRoute> open(WidgetTester tester) async {
    final route = source.currentState!.open();
    await _until(tester, () => route.animation!.isCompleted);
    return route;
  }
}

class _Editor extends StatefulWidget {
  const _Editor({super.key});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final controller = TextEditingController();
  final focus = FocusNode();

  @override
  Widget build(BuildContext context) => EditableText(
    controller: controller,
    focusNode: focus,
    autofocus: true,
    style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
    cursorColor: const Color(0xFF000000),
    backgroundCursorColor: const Color(0xFFFFFFFF),
  );

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }
}

void main() {
  testWidgets(
    'new root gets an independent session while old popup stays alive',
    (tester) async {
      final h = _Harness();
      addTearDown(h.location.dispose);
      await h.mount(tester);
      final originalState = h.source.currentState!;
      final first = await h.open(tester);
      h.location.value = 1;
      await tester.pump();
      expect(h.source.currentState, same(originalState));
      expect(originalState.activeRoute, isNull);
      final next = await h.open(tester);
      expect(next, isNot(same(first)));
      expect(first.navigator, same(h.navigators[0].currentState));
      expect(next.navigator, same(h.navigators[1].currentState));
      expect(h.models, hasLength(2));
      h.navigators[0].currentState!.pop();
      await _until(tester, () => first.disposed);
      expect(first.handBack, isNull);
      expect(originalState.activeRoute, same(next));
      h.navigators[1].currentState!.pop();
      await _until(tester, () => next.disposed);
      await _until(tester, () => originalState.motionSettled);
      expect(next.handBack, isNotNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('old root does not hand its model to a source moved elsewhere', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.location.dispose);
    await h.mount(tester);
    final first = await h.open(tester);
    h.location.value = 1;
    await tester.pump();
    h.navigators[0].currentState!.pop();
    await _until(tester, () => first.disposed);
    expect(first.handBack, isNull);
    expect(h.models.first.isSettled, isTrue);
    expect(h.source.currentState!.activeRoute, isNull);
    expect(h.source.currentState!.motionSettled, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'old popup keeps its view when its source moves to another view',
    (tester) async {
      final h = _Harness();
      addTearDown(h.location.dispose);
      final second = _OtherView(tester.view);
      await h.mount(tester, secondView: second);
      final originalState = h.source.currentState!;
      final first = await h.open(tester);
      h.location.value = 1;
      await tester.pump();
      expect(h.source.currentState, same(originalState));
      final target = first.frame.menu.outerRect.center;
      final wrongView = await tester.startGesture(target, view: second);
      await wrongView.up(view: second);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.selected, isEmpty);
      expect(first.closing, isFalse);
      final correctView = await tester.startGesture(target, view: tester.view);
      await correctView.up(view: tester.view);
      await _until(tester, () => first.disposed);
      expect(h.selected.single.$1, 0);
      expect(first.handBack, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('returning to the old root never resurrects its session', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.location.dispose);
    await h.mount(tester);
    final first = await h.open(tester);
    final state = h.source.currentState!;
    h.location.value = 1;
    await tester.pump();
    final second = await h.open(tester);
    h.location.value = 0;
    await tester.pump();
    expect(h.source.currentState, same(state));
    expect(state.activeRoute, isNull);
    final third = await h.open(tester);
    expect(h.models, hasLength(3));
    expect(h.observers[0].routes, [first, third]);
    h.navigators[1].currentState!.pop();
    await _until(tester, () => second.disposed);
    expect(second.handBack, isNull);
    h.navigators[0].currentState!.pop();
    await _until(tester, () => third.disposed);
    await _until(tester, () => state.motionSettled);
    h.navigators[0].currentState!.pop();
    await _until(tester, () => first.disposed);
    expect(first.handBack, isNull);
    expect(state.activeRoute, isNull);
    expect(h.models, hasLength(3));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('nested relocation in the same root keeps its model and popup', (
    tester,
  ) async {
    final h = _Harness(nested: true);
    addTearDown(h.location.dispose);
    await h.mount(tester);
    final first = await h.open(tester);
    final state = h.source.currentState!;
    h.location.value = 1;
    await tester.pump();
    expect(h.source.currentState, same(state));
    expect(state.activeRoute, same(first));
    expect(state.open(), same(first));
    expect(h.models, hasLength(1));
    h.navigators[0].currentState!.pop();
    await _until(tester, () => first.disposed);
    expect(first.handBack, isNotNull);
    await _until(tester, () => state.motionSettled);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('route-owned closing completes without landing after a move', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.location.dispose);
    await h.mount(tester);
    final first = await h.open(tester);
    h.navigators[0].currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(first.handBack, isNull);
    final before = first.frame.time;
    h.location.value = 1;
    await tester.pump();
    await _until(tester, () => first.disposed);
    expect(first.handBack, isNull);
    expect(first.frame.time, greaterThanOrEqualTo(before));
    expect(h.models.first.isSettled, isTrue);
    expect(h.source.currentState!.motionFrames, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'source-owned landing tail is abandoned without a hidden ticker',
    (tester) async {
      final h = _Harness();
      addTearDown(h.location.dispose);
      await h.mount(tester);
      final first = await h.open(tester);
      h.navigators[0].currentState!.pop();
      await _until(tester, () => first.handBack != null);
      expect(h.source.currentState!.ownsMotion, isTrue);
      expect(h.models.first.isSettled, isFalse);
      h.location.value = 1;
      await tester.pump();
      final abandonedTime = h.models.first.time;
      await tester.pump(const Duration(seconds: 2));
      expect(h.models.first.time, abandonedTime);
      expect(h.models.first.isSettled, isFalse);
      expect(h.source.currentState!.motionFrames, 0);
      expect(h.source.currentState!.motionSettled, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      final next = await h.open(tester);
      h.navigators[1].currentState!.pop();
      await _until(tester, () => next.disposed);
      await _until(tester, () => h.source.currentState!.motionSettled);
      expect(next.handBack, isNotNull);
      expect(h.models.first.time, abandonedTime);
    },
  );

  for (final covered in [false, true]) {
    testWidgets(
      'hidden held preparation retires on old root, covered: $covered',
      (tester) async {
        final h = _Harness();
        addTearDown(h.location.dispose);
        var builds = 0;
        h.menuBuilder = (_) {
          builds++;
          return const SizedBox.expand();
        };
        await h.mount(tester);
        final hold = await tester.startGesture(const Offset(46, 102));
        final first = h.source.currentState!.activeRoute!;
        await tester.pump();
        final cover = covered ? h.cover(0) : null;
        await tester.pump();
        h.location.value = 1;
        await tester.pump();
        await hold.up();
        await _until(tester, () => first.disposed);
        expect(builds, 0);
        expect(first.handBack, isNull);
        expect(h.models.first.isSettled, isTrue);
        expect(h.source.currentState!.activeRoute, isNull);
        expect(cover?.isCurrent, covered ? isTrue : isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  for (final delay in [40, 300]) {
    testWidgets('held reopening detaches finitely at ${delay}ms closing', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.location.dispose);
      await h.mount(tester);
      final first = await h.open(tester);
      h.navigators[0].currentState!.pop();
      await tester.pump();
      for (var elapsed = 0; elapsed < delay; elapsed += 8) {
        await tester.pump(_step);
      }
      final hold = await tester.startGesture(const Offset(46, 102));
      await tester.pump();
      expect(h.observers[0].routes, hasLength(2));
      final reserved = h.observers[0].routes.last;
      final sourceOwned = h.source.currentState!.ownsMotion;
      h.location.value = 1;
      await tester.pump();
      await hold.up();
      await _until(tester, () => reserved.disposed && first.disposed);
      final oldTime = h.models.first.time;
      await tester.pump(const Duration(seconds: 2));
      expect(h.models.first.time, oldTime);
      if (!sourceOwned) expect(h.models.first.isSettled, isTrue);
      expect(h.observers[1].routes, isEmpty);
      expect(h.source.currentState!.activeRoute, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets(
    'stale source semantic and raw callbacks cannot open the new session',
    (tester) async {
      final h = _Harness();
      addTearDown(h.location.dispose);
      await h.mount(tester);
      final semantics = tester.widget<Semantics>(
        find.descendant(
          of: find.byKey(h.source),
          matching: find.byType(Semantics),
        ),
      );
      final listener = tester.widget<Listener>(
        find.descendant(
          of: find.byKey(h.source),
          matching: find.byType(Listener),
        ),
      );
      h.location.value = 1;
      await tester.pump();
      semantics.properties.onTap!();
      listener.onPointerDown!(
        const PointerDownEvent(position: Offset(46, 102), pointer: 91),
      );
      await tester.pump();
      expect(h.observers.expand((o) => o.routes), isEmpty);
      expect(h.models, hasLength(2));
      expect(h.source.currentState!.motionFrames, 0);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'a source in a foreign overlay view declines every acquisition path',
    (tester) async {
      final second = _OtherView(tester.view);
      final h = _Harness(foreignView: second);
      addTearDown(h.location.dispose);
      await h.mount(tester);
      expect(h.source.currentState!.open, throwsStateError);
      final semantic = tester.widget<Semantics>(
        find.descendant(
          of: find.byKey(h.source),
          matching: find.byType(Semantics),
        ),
      );
      semantic.properties.onTap!();
      final gesture = await tester.startGesture(
        const Offset(46, 102),
        view: second,
      );
      await gesture.up(view: second);
      await tester.pump(const Duration(seconds: 1));
      expect(h.observers[0].routes, isEmpty);
      expect(h.models, hasLength(1));
      expect(h.source.currentState!.motionFrames, 0);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'factory reentry during attachment replacement fails explicitly',
    (tester) async {
      final h = _Harness();
      addTearDown(h.location.dispose);
      await h.mount(tester);
      final state = h.source.currentState!;
      var attempts = 0;
      h.creating = () {
        attempts++;
        expect(state.open, throwsStateError);
      };
      h.location.value = 1;
      await tester.pump();
      expect(attempts, 1);
      expect(h.models, hasLength(2));
      expect(state.activeRoute, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'old popup keeps editor, focus and dismissal policy after source move',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = _Harness();
        addTearDown(h.location.dispose);
        final editor = GlobalKey<_EditorState>();
        final allowed = ValueNotifier(false);
        addTearDown(allowed.dispose);
        var builds = 0;
        h.menuBuilder = (_) {
          builds++;
          return ValueListenableBuilder<bool>(
            valueListenable: allowed,
            builder: (_, canPop, child) =>
                PopScope<void>(canPop: canPop, child: child!),
            child: _Editor(key: editor),
          );
        };
        await h.mount(tester);
        final first = await h.open(tester);
        final original = editor.currentState!;
        original.controller.text = 'retained in root A';
        expect(original.focus.hasFocus, isTrue);
        h.location.value = 1;
        await tester.pump();
        expect(editor.currentState, same(original));
        expect(original.controller.text, 'retained in root A');
        expect(original.focus.hasFocus, isTrue);
        expect(builds, 1);
        expect(await h.navigators[0].currentState!.maybePop(), isTrue);
        await tester.pump();
        expect(first.closing, isFalse);
        expect(first.isCurrent, isTrue);
        allowed.value = true;
        await tester.pump();
        final routeSemantics = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .singleWhere((s) => s.properties.label == 'Prototype menu');
        routeSemantics.properties.onDismiss!();
        await tester.pump();
        await _until(tester, () => first.disposed);
        expect(original.mounted, isFalse);
        expect(first.handBack, isNull);
        expect(h.source.currentState!.activeRoute, isNull);
        expect(tester.binding.transientCallbackCount, 0);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'deferred cancellation may open the new root without locked-tree publication',
    (tester) async {
      final h = _Harness();
      addTearDown(h.location.dispose);
      await h.mount(tester);
      final hold = await tester.startGesture(const Offset(46, 102));
      final first = h.source.currentState!.activeRoute!;
      var cancellations = 0;
      ProbeMenuRoute? next;
      h.observe = (sample) {
        if (sample.kind != .cancelInput) return;
        cancellations++;
        expect(h.source.currentState!.activeRoute, isNull);
        next = h.source.currentState!.open();
      };
      h.location.value = 1;
      await tester.pump();
      await hold.up();
      await _until(tester, () => first.disposed);
      expect(cancellations, 1);
      expect(next!.navigator, same(h.navigators[1].currentState));
      expect(h.source.currentState!.activeRoute, same(next));
      await _until(tester, () => next!.animation!.isCompleted);
      h.navigators[1].currentState!.pop();
      await _until(tester, () => next!.disposed);
      await _until(tester, () => h.source.currentState!.motionSettled);
      expect(h.models, hasLength(2));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'committed hidden release is canceled on old root after attachment loss',
    (tester) async {
      final h = _Harness();
      addTearDown(h.location.dispose);
      var builds = 0;
      h.menuBuilder = (_) {
        builds++;
        return const SizedBox.expand();
      };
      await h.mount(tester);
      await tester.tapAt(const Offset(46, 102));
      final first = h.source.currentState!.activeRoute!;
      expect(h.models.first.isOpenPending, isTrue);
      h.location.value = 1;
      await tester.pump();
      await _until(tester, () => first.disposed);
      expect(h.models.first.isSettled, isTrue);
      expect(h.models.first.isOpenPending, isFalse);
      expect(builds, 0);
      expect(first.handBack, isNull);
      expect(h.observers[1].routes, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
