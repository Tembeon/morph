import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/motion.dart';
import 'package:morph/src/widgets/tab_bar_chrome.dart';
import 'package:morph/src/widgets/tab_collapse.dart';
import 'package:morph/widgets.dart';

const _items = [
  MorphTabItem(icon: Icons.home, label: 'Home'),
  MorphTabItem(icon: Icons.search, label: 'Browse'),
  MorphTabItem(icon: Icons.radio, label: 'Radio'),
  MorphTabItem(icon: Icons.person, label: 'Profile'),
];

/// The iPhone 16 Pro's screen, 402 x 874 points at 3x.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Drags [away] over [steps] equal moves through [interaction], from 0.
void _drag(MorphScrollAway away, double distance, {int steps = 10}) {
  away.record(0);
  away.beginDrag();
  for (var i = 1; i <= steps; i++) {
    away.scroll(distance * i / steps, min: 0, max: 2000, tracking: true);
  }
}

void main() {
  group('MorphScrollAway (UIKit scroll-away interaction)', () {
    test('64 points of scroll minimize; the hint grows on the way', () {
      final away = MorphScrollAway();
      final reported = <double>[];
      away.onProgress = (double p, {required bool tracking}) => reported.add(p);
      _drag(away, 32, steps: 4);
      expect(away.progress, closeTo(0.5, 1e-9));
      away.scroll(64, min: 0, max: 2000, tracking: true);
      expect(away.progress, 1);
      expect(reported.last, 1);
      away.scroll(200, min: 0, max: 2000, tracking: true);
      expect(away.progress, 1);
    });

    test('a scroll that stops short returns to 0 (floor)', () {
      final away = MorphScrollAway();
      _drag(away, 40);
      expect(away.progress, closeTo(40 / 64, 1e-9));
      away.endDrag(decelerates: true);
      expect(away.progress, closeTo(40 / 64, 1e-9));
      away.endDeceleration();
      expect(away.progress, 0);
    });

    test('a content shorter than 96 points of range never minimizes', () {
      final away = MorphScrollAway();
      away.record(0);
      away.beginDrag();
      away.scroll(90, min: 0, max: 95, tracking: true);
      expect(away.progress, 0);
      away.scroll(10, min: 0, max: 96, tracking: true);
      away.scroll(90, min: 0, max: 96, tracking: true);
      expect(away.progress, greaterThan(0));
    });

    test('a programmatic scroll is only recorded', () {
      final away = MorphScrollAway();
      away.record(0);
      away.record(500);
      expect(away.progress, 0);
      away.beginDrag();
      away.scroll(510, min: 0, max: 2000, tracking: true);
      expect(away.progress, closeTo(10 / 64, 1e-9));
    });

    test('onScrollUp minimizes on the way back', () {
      final away = MorphScrollAway(minimizesOnScrollUp: true);
      away.record(1000);
      away.beginDrag();
      away.scroll(1100, min: 0, max: 2000, tracking: true);
      expect(away.progress, 0);
      away.scroll(1000, min: 0, max: 2000, tracking: true);
      expect(away.progress, 1);
    });

    test('the expanding scroll is held at 0.01 while it runs', () {
      final away = MorphScrollAway();
      _drag(away, 32);
      away.scroll(-100, min: -200, max: 2000, tracking: true);
      expect(away.progress, MorphTabBarMinimizeTuning.minimumProgress);
    });

    test('pushing past the far end expands a minimized bar', () {
      final away = MorphScrollAway();
      _drag(away, 100);
      expect(away.progress, 1);
      away.endDrag(decelerates: false);
      away.record(2000);
      away.beginDrag();
      away.scroll(2010, min: 0, max: 2000, tracking: true);
      expect(away.progress, 0);
    });

    test('a drag back by 64 points expands (approximation)', () {
      final away = MorphScrollAway();
      _drag(away, 100);
      away.endDrag(decelerates: false);
      away.record(100);
      away.beginDrag();
      away.scroll(60, min: 0, max: 2000, tracking: true);
      expect(away.progress, 1);
      away.scroll(36, min: 0, max: 2000, tracking: true);
      expect(away.progress, 0);
    });

    test('a scroll to the top expands', () {
      final away = MorphScrollAway();
      _drag(away, 100);
      away.scrollToTop();
      expect(away.progress, 0);
    });
  });

  group('MorphTabBarMinimizeMotion', () {
    test('the hint scales by 0.05 x progress, then resets', () {
      final motion = MorphTabBarMinimizeMotion();
      motion.advance(0);
      final away = motion.scrollAway;
      _drag(away, 32);
      motion.advance(1);
      expect(motion.hint(1), closeTo(1 - 0.5 * 0.05, 1e-6));
      away.endDrag(decelerates: false);
      motion.advance(3);
      expect(motion.hint(3), closeTo(1, 1e-6));
      expect(motion.minimized, isFalse);
    });

    test('minimizing runs the glass, then the content after 0.05 s', () {
      final motion = MorphTabBarMinimizeMotion();
      final changes = <bool>[];
      motion.onMinimizedChanged = ({required bool minimized}) =>
          changes.add(minimized);
      motion.advance(0);
      _drag(motion.scrollAway, 100);
      expect(motion.minimized, isTrue);
      expect(changes, [true]);
      motion.advance(0.04);
      expect(motion.shape(0.04), greaterThan(0));
      expect(motion.content(0.04), 0);
      motion.advance(0.1);
      expect(motion.content(0.1), greaterThan(0));
      motion.advance(3);
      expect(motion.isSettled(3), isTrue);
      motion.settle(3);
      expect(motion.shape(3), 1);
      expect(motion.content(3), 1);
      motion.setMinimized(3, minimized: false);
      expect(changes, [true, false]);
      motion.advance(6);
      expect(motion.restsExpanded(6), isFalse);
      motion.settle(6);
      expect(motion.restsExpanded(6), isTrue);
    });

    MorphTabBarMinimizeMotion minimized() {
      final motion = MorphTabBarMinimizeMotion();
      motion.advance(0);
      _drag(motion.scrollAway, 100);
      motion.advance(3);
      motion.settle(3);
      expect(motion.minimized, isTrue);
      return motion;
    }

    test('a finger held 0.22 s expands the bar; lifted, it collapses', () {
      final motion = minimized();
      motion.pressDown(3, 50);
      motion.advance(3.2);
      expect(motion.minimized, isTrue);
      expect(motion.wakeTime(3.2), closeTo(3.22, 1e-9));
      motion.advance(3.23);
      expect(motion.minimized, isFalse);
      expect(motion.pressMove(3.3, 53), isFalse);
      motion.pressUp(3.4);
      expect(motion.minimized, isTrue);
      expect(motion.pressed, isFalse);
    });

    test('4 points along the bar expand it at once and scrub', () {
      final motion = minimized();
      motion.pressDown(3, 50);
      expect(motion.pressMove(3.05, 53.9), isFalse);
      expect(motion.minimized, isTrue);
      expect(motion.pressMove(3.06, 46), isTrue);
      expect(motion.minimized, isFalse);
      expect(motion.scrubs, isTrue);
      expect(motion.pressMove(3.1, 200), isFalse);
      motion.advance(3.5);
      motion.pressUp(3.5);
      expect(motion.minimized, isFalse);
    });

    test('a move after the hold keeps the bar expanded', () {
      final motion = minimized();
      motion.pressDown(3, 50);
      motion.advance(3.3);
      expect(motion.minimized, isFalse);
      expect(motion.pressMove(3.35, 60), isTrue);
      motion.pressUp(3.5);
      expect(motion.minimized, isFalse);
    });

    test('a quick tap expands; the late hold does nothing', () {
      final motion = minimized();
      motion.pressDown(3, 50);
      motion.advance(3.1);
      motion.pressUp(3.1);
      expect(motion.minimized, isFalse);
      motion.advance(3.5);
      expect(motion.minimized, isFalse);
    });

    test('a cancelled hold collapses back', () {
      final motion = minimized();
      motion.pressDown(3, 50);
      motion.advance(3.3);
      motion.pressCancel(3.3);
      expect(motion.minimized, isTrue);
    });

    test('a press on an expanded bar does nothing', () {
      final motion = MorphTabBarMinimizeMotion();
      motion.pressDown(0, 50);
      expect(motion.pressed, isFalse);
      expect(motion.pressMove(0.1, 90), isFalse);
    });

    test('a behavior that stops minimizing expands the bar', () {
      final motion = MorphTabBarMinimizeMotion();
      motion.advance(0);
      _drag(motion.scrollAway, 100);
      expect(motion.minimized, isTrue);
      motion.setBehavior(0.5, MorphTabBarMinimizeBehavior.never);
      expect(motion.minimized, isFalse);
    });
  });

  group('MorphTabBarGroupGeometry', () {
    test('the minimized circle sits 28 from the side and bottom', () {
      final g = MorphTabBarGroupGeometry.of(
        width: 402,
        barWidth: 360,
        accessory: true,
      );
      expect(g.size, const Size(402, 62 + 8 + 48));
      expect(g.bar, const Rect.fromLTWH(21, 56, 360, 62));
      expect(g.collapsed, const Rect.fromLTWH(28, 63, 48, 48));
      expect(g.accessory, const Rect.fromLTWH(21, 0, 360, 48));
      expect(g.inlineAccessory, const Rect.fromLTRB(84, 63, 374, 111));
      final rtl = MorphTabBarGroupGeometry.of(
        width: 402,
        barWidth: 360,
        accessory: true,
        rtl: true,
      );
      expect(rtl.collapsed, const Rect.fromLTWH(326, 63, 48, 48));
    });
  });

  group('MorphTabBar minimizing', () {
    Widget app({
      MorphTabBarMinimizeBehavior behavior =
          MorphTabBarMinimizeBehavior.onScrollDown,
      Widget? accessory,
      ScrollController? controller,
      ValueChanged<int>? onChanged,
    }) => MaterialApp(
      home: MorphContentScrollScope(
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView.builder(
                controller: controller,
                itemCount: 100,
                itemBuilder: (BuildContext context, int i) =>
                    SizedBox(height: 60, child: Text('Row $i')),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 21,
              child: MorphTabBar(
                items: _items,
                selected: 1,
                onChanged: onChanged ?? (_) {},
                minimizeBehavior: behavior,
                bottomAccessory: accessory,
              ),
            ),
          ],
        ),
      ),
    );

    testWidgets('automatic keeps the plain bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        app(behavior: MorphTabBarMinimizeBehavior.automatic),
      );
      expect(find.byType(MorphTabBarChrome), findsNothing);
    });

    testWidgets('a drag minimizes, a tap on the circle expands', (
      WidgetTester tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(app());
      expect(find.byType(MorphTabBarChrome), findsOneWidget);
      expect(find.byType(MorphCollapsingTabs), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      final circle = find.byType(MorphCollapsingTabs);
      expect(circle, findsOneWidget);
      // Laid out at the expanded bar's box; only the circle takes touches.
      expect(tester.getRect(circle).bottom, 874 - 21);
      await tester.tapAt(const Offset(300, 874 - 21 - 31));
      await tester.pumpAndSettle();
      expect(circle, findsOneWidget);
      await tester.tapAt(const Offset(28 + 24, 874 - 21 - 31));
      await tester.pumpAndSettle();
      expect(find.byType(MorphCollapsingTabs), findsNothing);
    });

    testWidgets('a held finger expands the bar, scrubs and selects on '
        'release', (WidgetTester tester) async {
      _phone(tester);
      final changes = <int>[];
      await tester.pumpWidget(app(onChanged: changes.add));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.byType(MorphCollapsingTabs), findsOneWidget);
      final finger = await tester.startGesture(
        const Offset(28 + 24, 874 - 21 - 31),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MorphCollapsingTabs), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      // Held past 0.22 s: the bar expanded under the finger.
      expect(find.byType(MorphCollapsingTabs), findsNothing);
      for (var x = 52.0; x <= 280; x += 12) {
        await finger.moveTo(Offset(x, 874 - 21 - 31));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.up();
      await tester.pumpAndSettle();
      expect(changes.last, 2);
      expect(find.byType(MorphCollapsingTabs), findsNothing);
    });

    testWidgets('a drag from the circle expands at once and selects', (
      WidgetTester tester,
    ) async {
      _phone(tester);
      final changes = <int>[];
      await tester.pumpWidget(app(onChanged: changes.add));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      final finger = await tester.startGesture(
        const Offset(28 + 24, 874 - 21 - 31),
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (var x = 52.0; x <= 370; x += 12) {
        await finger.moveTo(Offset(x, 874 - 21 - 31));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.up();
      await tester.pumpAndSettle();
      expect(changes.last, 3);
      expect(find.byType(MorphCollapsingTabs), findsNothing);
    });

    testWidgets('a hold released without moving collapses back', (
      WidgetTester tester,
    ) async {
      _phone(tester);
      final changes = <int>[];
      await tester.pumpWidget(app(onChanged: changes.add));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      final finger = await tester.startGesture(
        const Offset(28 + 24, 874 - 21 - 31),
      );
      // The hold dozes on a timer, which pumpAndSettle does not wait for.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MorphCollapsingTabs), findsNothing);
      await finger.up();
      await tester.pumpAndSettle();
      expect(find.byType(MorphCollapsingTabs), findsOneWidget);
      expect(changes, isEmpty);
    });

    testWidgets('a programmatic scroll never minimizes; reaching the top '
        'expands', (WidgetTester tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      _phone(tester);
      await tester.pumpWidget(app(controller: controller));
      controller.jumpTo(1200);
      await tester.pumpAndSettle();
      expect(find.byType(MorphCollapsingTabs), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.byType(MorphCollapsingTabs), findsOneWidget);
      unawaited(
        controller.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MorphCollapsingTabs), findsNothing);
    });

    testWidgets('the accessory moves inline and reads its environment', (
      WidgetTester tester,
    ) async {
      final seen = <MorphTabAccessoryEnvironment>[];
      _phone(tester);
      await tester.pumpWidget(
        app(
          accessory: Builder(
            builder: (BuildContext context) {
              final environment = MorphTabAccessoryEnvironment.of(context);
              seen.add(environment);
              return Text('Player ${environment.name}');
            },
          ),
        ),
      );
      expect(find.text('Player regular'), findsOneWidget);
      final top = tester.getRect(find.text('Player regular'));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Player inline'), findsOneWidget);
      expect(
        tester.getRect(find.text('Player inline')).top,
        greaterThan(top.top),
      );
      expect(seen.toSet(), {
        MorphTabAccessoryEnvironment.regular,
        MorphTabAccessoryEnvironment.inline,
      });
    });

    testWidgets('outside an accessory the environment is none', (
      WidgetTester tester,
    ) async {
      late MorphTabAccessoryEnvironment environment;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            environment = MorphTabAccessoryEnvironment.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(environment, MorphTabAccessoryEnvironment.none);
    });

    testWidgets('the search tab bar minimizes both circles', (
      WidgetTester tester,
    ) async {
      _phone(tester);
      final active = <bool>[];
      MorphTabAccessoryEnvironment? environment;
      await tester.pumpWidget(
        MaterialApp(
          home: MorphContentScrollScope(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ListView.builder(
                    itemCount: 100,
                    itemBuilder: (BuildContext context, int i) =>
                        SizedBox(height: 60, child: Text('Row $i')),
                  ),
                ),
                Positioned.fill(
                  child: MorphSearchTabBar(
                    items: _items.take(3).toList(),
                    selected: 0,
                    onChanged: (_) {},
                    active: false,
                    onActiveChanged: active.add,
                    minimizeBehavior: MorphTabBarMinimizeBehavior.onScrollDown,
                    bottomAccessory: Builder(
                      builder: (BuildContext context) {
                        environment = MorphTabAccessoryEnvironment.of(context);
                        return const SizedBox.expand();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(environment, MorphTabAccessoryEnvironment.regular);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(environment, MorphTabAccessoryEnvironment.inline);
      final circle = find.byType(MorphCollapsingTabs);
      expect(tester.getRect(circle), const Rect.fromLTWH(28, 874 - 76, 48, 48));
      await tester.tapAt(const Offset(402 - 52, 874 - 52));
      await tester.pump();
      expect(active, [true]);
      await tester.tap(circle);
      await tester.pumpAndSettle();
      expect(environment, MorphTabAccessoryEnvironment.regular);
      expect(find.byType(MorphCollapsingTabs), findsNothing);
    });

    testWidgets('a drag that hints builds nothing', (
      WidgetTester tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      var builds = 0;
      debugOnRebuildDirtyWidget = (Element e, bool _) {
        if (e.findAncestorWidgetOfExactType<MorphTabBarChrome>() != null ||
            e.widget is MorphTabBarChrome) {
          builds++;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      final gesture = await tester.startGesture(const Offset(200, 400));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;
      expect(find.byType(MorphCollapsingTabs), findsNothing);
      expect(builds, 0);
    });
  });
}
