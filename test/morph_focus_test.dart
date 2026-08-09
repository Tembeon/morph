import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

/// Keyboard citizenship of the overlay: Esc dismisses through the same
/// funnel as the scrim, focus moves into the overlay and traversal
/// stays there, and the pre-flight focus comes back after teardown.

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

bool inMorphScope(FocusNode? node) {
  if (node == null) {
    return false;
  }
  // The node itself, or any ancestor: focus can park on the scope node
  // when the content has no autofocus, or on a focusable inside it.
  for (final FocusNode candidate in <FocusNode>[node, ...node.ancestors]) {
    if (candidate.debugLabel == 'morph overlay') {
      return true;
    }
  }
  return false;
}

Widget host({
  required ValueChanged<MorphFlight> onFlight,
  bool barrierDismissible = true,
  Widget overlayChild = const TextField(autofocus: true),
}) {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
    home: Scaffold(
      body: Center(
        child: MorphTag(
          id: 'btn',
          child: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => onFlight(
                showMorphDialog(
                  context,
                  from: 'btn',
                  barrierDismissible: barrierDismissible,
                  builder: (BuildContext context, MorphFlight flight) =>
                      overlayChild,
                ),
              ),
              child: const Text('open-me'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Esc dismisses the open overlay', (WidgetTester tester) async {
    MorphFlight? flight;
    await tester.pumpWidget(host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);
    expect(flight!.isOpenOrOpening, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(flight!.controller.target, 0);
    await settle(tester);
    expect(flight!.isFinished, isTrue);
  });

  testWidgets('barrierDismissible: false swallows Esc', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(
      host(onFlight: (MorphFlight f) => flight = f, barrierDismissible: false),
    );
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(flight!.controller.target, 1);
    expect(flight!.isFinished, isFalse);
    flight!.abort();
    await tester.pump();
  });

  testWidgets('focus moves into the overlay and traversal stays trapped', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    // Content with two focusables and NO autofocus: the trap itself
    // must pull focus off the page into the overlay scope.
    await tester.pumpWidget(
      host(
        onFlight: (MorphFlight f) => flight = f,
        overlayChild: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextButton(onPressed: () {}, child: const Text('row-a')),
            TextButton(onPressed: () {}, child: const Text('row-b')),
          ],
        ),
      ),
    );
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    expect(
      inMorphScope(FocusManager.instance.primaryFocus),
      isTrue,
      reason: 'the overlay pulls focus off the page into its own scope',
    );
    // Tab a few times: primary focus must never leave the overlay scope.
    for (int i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        inMorphScope(FocusManager.instance.primaryFocus),
        isTrue,
        reason: 'Tab must not escape the open overlay into the page',
      );
    }
    flight!.close();
    await settle(tester);
  });

  testWidgets('focus returns to the pre-flight node after close', (
    WidgetTester tester,
  ) async {
    final FocusNode sink = FocusNode(debugLabel: 'focus-sink');
    addTearDown(sink.dispose);
    MorphFlight? flight;
    // The pre-flight focus holder sits OUTSIDE the tag, so the shuttle
    // ghost never replicates its focus node.
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Focus(
                focusNode: sink,
                child: const SizedBox(width: 20, height: 20),
              ),
              MorphTag(
                id: 'btn',
                child: Builder(
                  builder: (BuildContext context) => ElevatedButton(
                    onPressed: () => flight = showMorphDialog(
                      context,
                      from: 'btn',
                      builder: (BuildContext context, MorphFlight f) =>
                          const Text('dialog-content'),
                    ),
                    child: const Text('open-me'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    sink.requestFocus();
    await tester.pump();
    expect(sink.hasPrimaryFocus, isTrue);

    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);
    expect(sink.hasPrimaryFocus, isFalse);
    expect(inMorphScope(FocusManager.instance.primaryFocus), isTrue);

    flight!.close();
    await settle(tester);
    await tester.pump();
    expect(
      sink.hasPrimaryFocus,
      isTrue,
      reason: 'keyboard navigation continues from where the morph began',
    );
  });
}
