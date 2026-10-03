import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);
const _back = Offset(40, 84);

Widget _page(String title) => MorphNavigationScaffold(
  title: title,
  slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
);

Future<void> _stack(WidgetTester tester) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late BuildContext home;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: _screen,
          padding: EdgeInsets.only(top: 62, bottom: 34),
        ),
        child: MorphNavigationStack(
          home: Builder(
            builder: (BuildContext context) {
              home = context;
              return _page('Mailboxes');
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final navigator = Navigator.of(home);
  for (final title in ['Inbox', 'Thread', 'Message']) {
    navigator.push(MorphNavigationRoute<void>(builder: (_) => _page(title)));
    await tester.pumpAndSettle();
  }
}

Future<void> _hold(WidgetTester tester, TestGesture gesture, double s) async {
  final frames = (s / 0.016).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('a tap on the back button pops one screen', (
    WidgetTester tester,
  ) async {
    await _stack(tester);
    expect(find.text('Message'), findsWidgets);
    final gesture = await tester.startGesture(_back);
    await _hold(tester, gesture, 0.25);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsNothing);
    expect(find.text('Thread'), findsWidgets);
  });

  testWidgets('a long press opens the back stack, nearest screen first', (
    WidgetTester tester,
  ) async {
    await _stack(tester);
    final gesture = await tester.startGesture(_back);
    await _hold(tester, gesture, 0.5);
    expect(find.text('Mailboxes'), findsNothing);
    await _hold(tester, gesture, 0.15);
    await _hold(tester, gesture, 0.6);
    final thread = tester.getCenter(find.text('Thread').last);
    final inbox = tester.getCenter(find.text('Inbox').last);
    final mailboxes = tester.getCenter(find.text('Mailboxes').last);
    expect(thread.dy, lessThan(inbox.dy));
    expect(inbox.dy, lessThan(mailboxes.dy));
    await gesture.moveTo(const Offset(300, 700));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsWidgets);
    await tester.tapAt(mailboxes);
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsNothing);
    expect(find.text('Mailboxes'), findsWidgets);
    expect(find.bySemanticsLabel('Back'), findsNothing);
  });

  testWidgets('a hold released past recognition does not pop, the menu opens', (
    WidgetTester tester,
  ) async {
    await _stack(tester);
    final gesture = await tester.startGesture(_back);
    await _hold(tester, gesture, 0.45);
    await gesture.up();
    await _hold(tester, gesture, 0.4);
    expect(find.text('Mailboxes'), findsOneWidget);
    expect(find.text('Message'), findsWidgets);
    await tester.tapAt(const Offset(300, 700));
    await tester.pumpAndSettle();
    expect(find.text('Mailboxes'), findsNothing);
    expect(find.text('Message'), findsWidgets);
  });

  testWidgets('lifting on the back button after the menu opened pops once', (
    WidgetTester tester,
  ) async {
    await _stack(tester);
    final gesture = await tester.startGesture(_back);
    await _hold(tester, gesture, 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsNothing);
    expect(find.text('Thread'), findsWidgets);
  });

  testWidgets('the capsule rings out after the menu closes into it', (
    WidgetTester tester,
  ) async {
    await _stack(tester);
    final back = find.bySemanticsLabel('Back');
    final rest = tester.getRect(back);
    final gesture = await tester.startGesture(_back);
    await _hold(tester, gesture, 1.0);
    await gesture.moveTo(const Offset(300, 700));
    await gesture.up();
    await _hold(tester, gesture, 0.6);
    await tester.tapAt(const Offset(300, 700));
    var landed = false;
    var swing = 0.0;
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.text('Mailboxes').evaluate().isNotEmpty) continue;
      landed = true;
      final r = tester.getRect(back);
      final d = (r.center - rest.center).distance;
      if (d > swing) swing = d;
    }
    expect(landed, isTrue);
    expect(swing, greaterThan(0.3));
    await tester.pumpAndSettle();
    expect(tester.getRect(back).center.dx, closeTo(rest.center.dx, 0.01));
    expect(tester.getRect(back).center.dy, closeTo(rest.center.dy, 0.01));
    expect(find.text('Message'), findsWidgets);
  });

  test('the measured timing', () {
    expect(MorphBarMenuTuning.recognition, 0.4);
    expect(MorphBarMenuTuning.open, 0.595);
  });
}
