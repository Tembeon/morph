import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/tour/lessons/hold_lesson.dart';

Widget host(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: .dark),
    builder: (BuildContext context, Widget? c) => MorphScope(child: c!),
    home: Scaffold(body: child),
  );
}

Future<void> settle(WidgetTester tester, {int limit = 300}) async {
  for (int i = 0; i < limit; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  testWidgets('hold: a bubble becomes its menu; a reaction lands at once and '
      'unfolds the note; delete dissolves it', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const HoldLesson(motion: .liquid)));
    expect(find.text('no flight yet'), findsOneWidget);

    await tester.longPress(find.text('Hold this bubble'));
    await settle(tester);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    // The lesson follows the flight's moments.
    expect(find.textContaining('settled'), findsOneWidget);
    expect(find.textContaining('held "Hold this bubble"'), findsOneWidget);
    expect(find.text('Add a note'), findsNothing);
    final double replyBefore = tester.getTopLeft(find.text('Reply')).dy;

    // A reaction lands on the bubble while the menu is open - the
    // hidden source, the shuttle's ghost replica and the hero copy all
    // carry the badge - and the capsule unfolds the note field; the
    // actions slide down for the badge's height.
    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await settle(tester);
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(4));
    expect(find.text('Add a note'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Reply')).dy, greaterThan(replyBefore));

    // Sending the note flies everything home; the badge stays.
    await tester.enterText(find.byType(TextField).last, 'nice');
    await tester.tap(find.byIcon(Icons.send_rounded).last);
    await settle(tester);
    expect(find.text('Reply'), findsNothing);
    expect(find.textContaining('landed'), findsOneWidget);
    expect(find.textContaining('noted "nice"'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // Delete from the bubble's own menu: the source unmounts while the
    // menu is still flying home - the flight dissolves, nothing throws.
    await tester.longPress(find.text('Hold this bubble'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Hold this bubble'), findsNothing);
    expect(find.textContaining('delete "Hold this bubble"'), findsOneWidget);
  });

  testWidgets('hold: the visible door opens the same menu, and the overlay '
      'toggle keeps it working under and above the bar', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const HoldLesson(motion: .liquid)));
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await settle(tester);
    expect(find.text('Pin'), findsOneWidget);
    await tester.tap(find.text('Pin'));
    await settle(tester);
    expect(find.text('Pin'), findsNothing);
    expect(find.textContaining('pin "'), findsOneWidget);

    // The tab's own overlay: the menu still opens and closes cleanly.
    await tester.tap(find.text('Chat tab'));
    await settle(tester);
    await tester.longPress(find.text('Long-press me too'));
    await settle(tester);
    expect(find.text('Reply'), findsOneWidget);
    // Dismiss through the scrim: the chat header sits under it.
    await tester.tap(find.text('Sam'), warnIfMissed: false);
    await settle(tester);
    expect(find.text('Reply'), findsNothing);
  });

  testWidgets('hold: the keyboard pushes the open menu out from under it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const HoldLesson(motion: .liquid)));
    await tester.longPress(find.text('Hold this bubble'));
    await settle(tester);
    final Rect before = tester.getRect(find.text('Reply'));

    await tester.tap(find.text('Shown'));
    await settle(tester);
    final Rect keyboard = tester.getRect(find.byKey(PhoneFrame.keyboardKey));
    expect(keyboard.height, moreOrLessEquals(240, epsilon: 0.01));
    // The whole column moved up: the actions clear the keyboard, and
    // the compose bar rose with it.
    final Rect reply = tester.getRect(find.text('Reply'));
    expect(reply.top, lessThan(before.top));
    expect(reply.bottom, lessThanOrEqualTo(keyboard.top));
    expect(
      tester.getRect(find.text('Message')).bottom,
      lessThanOrEqualTo(keyboard.top),
    );

    await tester.tap(find.text('Hidden'));
    await settle(tester);
    expect(
      tester.getRect(find.text('Reply')).top,
      moreOrLessEquals(before.top, epsilon: 0.01),
    );
    await tester.tap(find.text('Sam'), warnIfMissed: false);
    await settle(tester);
    expect(find.text('Reply'), findsNothing);
  });
}
