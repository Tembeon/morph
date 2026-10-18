import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/zoom_motion.dart';
import 'package:morph_example/proto/route_probe.dart';

const _home = ValueKey<String>('home');

Widget _app(
  GlobalKey<NavigatorState> navigator, {
  Widget? home,
  List<NavigatorObserver> observers = const [],
}) => WidgetsApp(
  color: const Color(0xFFFFFFFF),
  navigatorKey: navigator,
  navigatorObservers: observers,
  restorationScopeId: 'p1',
  onGenerateRoute: (settings) => PageRouteBuilder<void>(
    settings: settings,
    transitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => home ?? const SizedBox.expand(key: _home),
  ),
);

Widget _content(BuildContext context) => const ColoredBox(
  color: Color(0xFFCCCCCC),
  child: Center(child: Text('sheet')),
);

@pragma('vm:entry-point')
Route<Object?> _restoredRoute(BuildContext context, Object? arguments) =>
    ProbeSheetRoute<Object?>(
      driver: ProbeRouteDriver.values.byName(arguments! as String),
      builder: (_) => const Center(child: Text('restored')),
    );

class _ProbePage extends Page<void> {
  const _ProbePage(this.driver, this.onRoute)
    : super(key: const ValueKey('page'));

  final ProbeRouteDriver driver;
  final ValueChanged<ProbeSheetRoute<void>> onRoute;

  @override
  Route<void> createRoute(BuildContext context) {
    final route = ProbeSheetRoute<void>(
      driver: driver,
      opaque: true,
      settings: this,
      builder: _content,
    );
    onRoute(route);
    return route;
  }
}

void main() {
  for (final driver in ProbeRouteDriver.values) {
    group(driver.name, () {
      testWidgets('publishes progress and completes pop before visual rest', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(nav));
        final route = ProbeSheetRoute<int>(driver: driver, builder: _content);
        var resultReceived = false;
        final result = nav.currentState!.push<int>(route);
        final observed = result.then((value) {
          resultReceived = true;
          return value;
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(route.animation!.status, AnimationStatus.forward);
        expect(route.animation!.value, inExclusiveRange(0, 1));
        await tester.pumpAndSettle();
        expect(route.animation!.status, AnimationStatus.completed);
        expect(route.motionSettled, isTrue);
        nav.currentState!.pop(42);
        await tester.pump();
        expect(resultReceived, isTrue);
        expect(await observed, 42);
        expect(route.animation!.status, AnimationStatus.reverse);
        expect(route.disposed, isFalse);
        await tester.pumpAndSettle();
        expect(route.disposed, isTrue);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('releases input and focus on the first closing frame', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        final homeFocus = FocusNode();
        final sheetFocus = FocusNode();
        addTearDown(homeFocus.dispose);
        addTearDown(sheetFocus.dispose);
        var taps = 0;
        await tester.pumpWidget(
          _app(
            nav,
            home: Focus(
              focusNode: homeFocus,
              autofocus: true,
              child: GestureDetector(
                behavior: .opaque,
                onTap: () => taps++,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pump();
        final route = ProbeSheetRoute<void>(
          driver: driver,
          builder: (_) => Focus(
            focusNode: sheetFocus,
            autofocus: true,
            child: const SizedBox.expand(),
          ),
        );
        nav.currentState!.push<void>(route);
        await tester.pumpAndSettle();
        expect(sheetFocus.hasFocus, isTrue);
        nav.currentState!.pop();
        await tester.pump();
        expect(route.disposed, isFalse);
        expect(sheetFocus.hasFocus, isFalse);
        await tester.tapAt(const Offset(10, 10));
        expect(taps, 1);
        await tester.pumpAndSettle();
        expect(homeFocus.hasFocus, isTrue);
      });

      testWidgets(
        'pushReplacement retains the old route until all motion rests',
        (tester) async {
          final nav = GlobalKey<NavigatorState>();
          await tester.pumpWidget(_app(nav));
          final old = ProbeSheetRoute<void>(
            driver: driver,
            opaque: true,
            builder: (_) => const Text('old'),
          );
          nav.currentState!.push<void>(old);
          await tester.pumpAndSettle();
          final route = ProbeSheetRoute<void>(
            driver: driver,
            opaque: true,
            builder: _content,
          );
          nav.currentState!.pushReplacement<void, void>(route);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(route.motionSettled, isFalse);
          expect(route.overlayEntries.first.opaque, isFalse);
          expect(old.disposed, isFalse);
          expect(find.text('old'), findsOneWidget);
          await tester.pumpAndSettle();
          expect(route.motionSettled, isTrue);
          expect(route.overlayEntries.first.opaque, isTrue);
          expect(old.disposed, isTrue);
        },
      );

      testWidgets('initial Pages are completed without running an entrance', (
        tester,
      ) async {
        late ProbeSheetRoute<void> route;
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFFFFFFFF),
            builder: (_, _) => Navigator(
              pages: [_ProbePage(driver, (created) => route = created)],
              onDidRemovePage: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(route.animation!.value, 1);
        expect(route.animation!.status, AnimationStatus.completed);
        expect(route.motionSettled, isTrue);
        expect(route.overlayEntries.first.opaque, isTrue);
        final frames = route.motionFrames;
        await tester.pump(const Duration(seconds: 1));
        expect(route.motionFrames, frames);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('replace transfers an in-flight motion without a jump', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(nav));
        final old = ProbeSheetRoute<void>(driver: driver, builder: _content);
        nav.currentState!.push<void>(old);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final before = old.rawProgress;
        final beforeTime = old.motionTime;
        final route = ProbeSheetRoute<void>(driver: driver, builder: _content);
        nav.currentState!.replace<void>(oldRoute: old, newRoute: route);
        expect(route.rawProgress, closeTo(before, 1e-9));
        expect(route.motionTime, beforeTime);
        await tester.pumpAndSettle();
        expect(route.animation!.value, 1);
        expect(route.animation!.status, AnimationStatus.completed);
        expect(route.motionSettled, isTrue);
        expect(route.overlayEntries.first.opaque, route.opaque);
        expect(old.disposed, isTrue);
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        expect(route.disposed, isTrue);
      });

      testWidgets('replace of a settled page keeps motion and SDK in sync', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(nav));
        final old = ProbeSheetRoute<void>(driver: driver, builder: _content);
        nav.currentState!.push<void>(old);
        await tester.pumpAndSettle();
        final route = ProbeSheetRoute<void>(
          driver: driver,
          opaque: true,
          builder: _content,
        );
        nav.currentState!.replace<void>(oldRoute: old, newRoute: route);
        await tester.pumpAndSettle();
        expect(route.animation!.value, 1);
        expect(route.animation!.status, AnimationStatus.completed);
        expect(route.motionSettled, isTrue);
        expect(route.overlayEntries.first.opaque, isTrue);
        final frames = route.motionFrames;
        await tester.pump(const Duration(seconds: 1));
        expect(route.motionFrames, frames);
        expect(tester.binding.transientCallbackCount, 0);
      });

      testWidgets('restoration adds a completed route that still dismisses', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(nav));
        nav.currentState!.restorablePush<Object?>(
          _restoredRoute,
          arguments: driver.name,
        );
        await tester.pumpAndSettle();
        await tester.restartAndRestore();
        await tester.pumpAndSettle();
        final route =
            ModalRoute.of(tester.element(find.text('restored')))!
                as ProbeSheetRoute<Object?>;
        expect(route.animation!.value, 1);
        expect(route.animation!.status, AnimationStatus.completed);
        expect(route.motionSettled, isTrue);
        expect(route.overlayEntries.first.opaque, route.opaque);
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        expect(route.disposed, isTrue);
      });

      testWidgets('PopScope veto keeps the open motion and result pending', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(nav));
        var attempts = 0;
        var returned = false;
        final route = ProbeSheetRoute<void>(
          driver: driver,
          builder: (_) => PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              expect(didPop, isFalse);
              attempts++;
            },
            child: const Text('protected'),
          ),
        );
        unawaited(
          nav.currentState!.push<void>(route).then((_) => returned = true),
        );
        await tester.pumpAndSettle();
        await nav.currentState!.maybePop();
        await tester.pump();
        expect(attempts, 1);
        expect(returned, isFalse);
        expect(route.isActive, isTrue);
        expect(route.animation!.status, AnimationStatus.completed);
        expect(route.motionSettled, isTrue);
      });

      testWidgets(
        'uses the input timestamp rather than restarting at delivery',
        (tester) async {
          final nav = GlobalKey<NavigatorState>();
          await tester.pumpWidget(_app(nav));
          final route = ProbeSheetRoute<void>(
            driver: driver,
            eventAge: const Duration(milliseconds: 32),
            builder: _content,
          );
          nav.currentState!.push<void>(route);
          await tester.pump();
          final reference = MorphZoomMotion();
          reference.open(0);
          reference.advance(0.032);
          expect(route.motionTime, closeTo(0.032, 1e-9));
          expect(
            route.rawProgress,
            closeTo(reference.centerProgress(0.032), 1e-9),
          );
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'keeps content stable during frames, insets and a covering route',
        (tester) async {
          final nav = GlobalKey<NavigatorState>();
          final editorKey = GlobalKey<_EditorState>();
          await tester.pumpWidget(_app(nav));
          final route = ProbeSheetRoute<void>(
            driver: driver,
            builder: (_) => Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => _Editor(key: editorKey),
              ),
            ),
          );
          nav.currentState!.push<void>(route);
          await tester.pumpAndSettle();
          final state = editorKey.currentState!;
          await tester.enterText(find.byType(EditableText), 'still here');
          final builds = route.pageBuilds;
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          addTearDown(tester.view.resetViewInsets);
          await tester.pump();
          expect(editorKey.currentState, same(state));
          expect(state.controller.text, 'still here');
          final cover = RawDialogRoute<void>(
            pageBuilder: (_, _, _) => const Center(child: Text('cover')),
            transitionDuration: Duration.zero,
          );
          nav.currentState!.push<void>(cover);
          await tester.pumpAndSettle();
          nav.currentState!.pop();
          await tester.pumpAndSettle();
          expect(editorKey.currentState, same(state));
          expect(state.controller.text, 'still here');
          expect(state.focus.hasFocus, isTrue);
          final frames = route.motionFrames;
          await tester.pump(const Duration(seconds: 1));
          expect(route.motionFrames, frames);
          expect(route.pageBuilds, builds);
          nav.currentState!.pop();
          await tester.pump();
          expect(editorKey.currentState, same(state));
          await tester.pumpAndSettle();
          expect(editorKey.currentState, isNull);
        },
      );

      testWidgets('paints motion without rebuilding the content each frame', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(nav));
        var contentBuilds = 0;
        final route = ProbeSheetRoute<void>(
          driver: driver,
          builder: (context) {
            contentBuilds++;
            return _content(context);
          },
        );
        nav.currentState!.push<void>(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final before = tester.getRect(find.text('sheet'));
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(tester.getRect(find.text('sheet')), isNot(before));
        expect(contentBuilds, 1);
        expect(route.pageBuilds, 1);
        await tester.pumpAndSettle();
        final frames = route.motionFrames;
        await tester.pump(const Duration(seconds: 5));
        expect(route.motionFrames, frames);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
      testWidgets('records SDK rebuilds during steady motion', (tester) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(nav));
        final route = ProbeSheetRoute<void>(driver: driver, builder: _content);
        nav.currentState!.push<void>(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final owners = <String, int>{};
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          final type = element.widget.runtimeType.toString();
          owners[type] = (owners[type] ?? 0) + 1;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);
        var frames = 0;
        while (!route.motionSettled && frames < 200) {
          await tester.pump(const Duration(milliseconds: 16));
          frames++;
        }
        debugOnRebuildDirtyWidget = previous;
        expect(route.motionSettled, isTrue);
        expect(route.pageBuilds, 1);
        final builds = owners.values.fold(0, (sum, count) => sum + count);
        debugPrint(
          'P1_BUILDS ${jsonEncode({'driver': driver.name, 'frames': frames, 'builds': builds, 'buildsPerFrame': builds / frames, 'owners': owners})}',
        );
        await tester.pumpAndSettle();
      });

      testWidgets(
        'keeps raw overshoot while the SDK progress remains bounded',
        (tester) async {
          final nav = GlobalKey<NavigatorState>();
          await tester.pumpWidget(_app(nav));
          final route = ProbeSheetRoute<void>(
            driver: driver,
            builder: _content,
          );
          nav.currentState!.push<void>(route);
          await tester.pump();
          var peak = 0.0;
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (route.rawProgress > peak) peak = route.rawProgress;
            expect(route.animation!.value, inInclusiveRange(0, 1));
            if (!route.motionSettled) {
              expect(route.animation!.status, AnimationStatus.forward);
            }
          }
          expect(peak, greaterThan(1));
          expect(route.motionSettled, isTrue);
          expect(route.animation!.value, 1);
          expect(route.animation!.status, AnimationStatus.completed);
        },
      );

      testWidgets(
        'pop during entrance preserves geometry and disposes at rest',
        (tester) async {
          final nav = GlobalKey<NavigatorState>();
          await tester.pumpWidget(_app(nav));
          final route = ProbeSheetRoute<void>(
            driver: driver,
            builder: _content,
          );
          nav.currentState!.push<void>(route);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          const destination = Rect.fromLTWH(8, 240, 784, 352);
          final before = route.rectangle(destination);
          nav.currentState!.pop();
          expect(route.rectangle(destination), before);
          await tester.pump();
          expect(route.animation!.status, AnimationStatus.reverse);
          expect(route.disposed, isFalse);
          await tester.pumpAndSettle();
          expect(route.disposed, isTrue);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );

      testWidgets('forced removal cancels the active clock and push signal', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(nav));
        final route = ProbeSheetRoute<int>(driver: driver, builder: _content);
        final result = nav.currentState!.push<int>(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        nav.currentState!.removeRoute(route, 7);
        await tester.pumpAndSettle();
        expect(await result, 7);
        expect(route.disposed, isTrue);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('runs Hero flights with an explicitly installed controller', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        var flights = 0;
        Widget hero(double size) => Hero(
          tag: 'p1-hero',
          flightShuttleBuilder: (_, _, _, _, _) {
            flights++;
            return const ColoredBox(color: Color(0xFF00AA00));
          },
          child: SizedBox.square(
            dimension: size,
            child: const ColoredBox(color: Color(0xFF00AA00)),
          ),
        );
        await tester.pumpWidget(
          _app(
            nav,
            observers: [HeroController()],
            home: Center(child: hero(80)),
          ),
        );
        final route = ProbeSheetRoute<void>(
          driver: driver,
          opaque: true,
          builder: (_) => Center(child: hero(160)),
        );
        nav.currentState!.push<void>(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(flights, 1);
        await tester.pumpAndSettle();
        nav.currentState!.pop();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(flights, 2);
        expect(route.disposed, isTrue);
        expect(tester.takeException(), isNull);
      });
    });
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
    style: const TextStyle(fontSize: 18),
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
