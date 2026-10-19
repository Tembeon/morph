import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

const _step = Duration(milliseconds: 8);

final _nav = GlobalKey<NavigatorState>();

Widget _app() => WidgetsApp(
  color: const Color(0xFFFFFFFF),
  navigatorKey: _nav,
  pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
      PageRouteBuilder<T>(
        settings: settings,
        transitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => builder(context),
      ),
  home: const SizedBox.expand(),
);

MorphSheetRoute<void> _sheet() => MorphSheetRoute<void>(
  builder: (context) => const SizedBox.expand(child: Text('sheet')),
  detents: const [MorphSheetDetent.large],
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await tester.pump(_step);
  }
  expect(done(), isTrue, reason: 'the motion must finish within 400 frames');
}

void _screen(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the route animation follows the sheet and completes at rest', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final route = _sheet();
    _nav.currentState!.push<void>(route);
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.forward);
    var opening = 0;
    while (route.animation!.status == AnimationStatus.forward) {
      expect(route.animation!.value, 1);
      await tester.pump(_step);
      opening++;
      expect(opening, lessThan(400));
    }
    expect(route.animation!.status, AnimationStatus.completed);
    expect(route.animation!.value, 1);
    expect(opening, greaterThan(5), reason: 'completed waits for the rest');

    _nav.currentState!.pop();
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.reverse);
    expect(route.isActive, isFalse);
    await _pumpUntil(
      tester,
      () => route.animation!.status == AnimationStatus.dismissed,
    );
    await tester.pump();
    expect(find.text('sheet'), findsNothing);
  });

  testWidgets('pushReplacement keeps the replaced route until the new sheet '
      'rests', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final first = _sheet();
    _nav.currentState!.push<void>(first);
    await _pumpUntil(
      tester,
      () => first.animation!.status == AnimationStatus.completed,
    );
    final second = _sheet();
    _nav.currentState!.pushReplacement<void, void>(second);
    await tester.pump();
    await tester.pump(_step);
    expect(second.animation!.status, AnimationStatus.forward);
    expect(first.isActive, isFalse);
    expect(
      find.text('sheet', skipOffstage: false),
      findsNWidgets(2),
      reason: 'the replaced sheet stays mounted while the new one opens',
    );
    await _pumpUntil(
      tester,
      () => second.animation!.status == AnimationStatus.completed,
    );
    await tester.pump();
    expect(find.text('sheet', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a replace and an initial route start in place', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final first = _sheet();
    _nav.currentState!.push<void>(first);
    await _pumpUntil(
      tester,
      () => first.animation!.status == AnimationStatus.completed,
    );
    final second = _sheet();
    _nav.currentState!.replace<void>(oldRoute: first, newRoute: second);
    await tester.pump();
    expect(second.animation!.status, AnimationStatus.completed);
    expect(second.animation!.value, 1);
  });

  testWidgets('a page zoomed out of a source completes at the zoom\'s rest', (
    tester,
  ) async {
    _screen(tester);
    final link = MorphSourceLink();
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        navigatorKey: _nav,
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<T>(
              settings: settings,
              transitionDuration: Duration.zero,
              pageBuilder: (context, _, _) => builder(context),
            ),
        home: Center(
          child: MorphSource(
            link: link,
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      ),
    );
    final route = MorphNavigationRoute<void>(
      from: link,
      builder: (context) => const SizedBox.expand(child: Text('page')),
    );
    _nav.currentState!.push<void>(route);
    await tester.pump();
    var opening = 0;
    while (route.animation!.status == AnimationStatus.forward) {
      await tester.pump(_step);
      opening++;
      expect(opening, lessThan(400));
    }
    expect(route.animation!.status, AnimationStatus.completed);
    expect(opening, greaterThan(5), reason: 'completed waits for the rest');
    _nav.currentState!.pop();
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.reverse);
    await _pumpUntil(
      tester,
      () => route.animation!.status == AnimationStatus.dismissed,
    );
  });
}
