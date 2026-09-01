import 'package:material_ui/material_ui.dart';
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

  testWidgets('keyboard cannot activate the ghost replica of the source', (
    WidgetTester tester,
  ) async {
    int sourcePresses = 0;
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphTag(
              id: 'btn',
              child: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  onPressed: () {
                    sourcePresses++;
                    flight ??= showMorphDialog(
                      context,
                      from: 'btn',
                      builder: (BuildContext context, MorphFlight f) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TextButton(
                            onPressed: () {},
                            child: const Text('row-a'),
                          ),
                          TextButton(
                            onPressed: () {},
                            child: const Text('row-b'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('open-me'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);
    expect(sourcePresses, 1);
    // The ghost keeps the live replica MOUNTED for the whole flight
    // (shared-element markers must keep measuring), so a copy of the
    // source button exists inside the shuttle - inside the overlay's
    // own Tab trap.
    expect(find.text('open-me'), findsNWidgets(2));

    // Cycle the trapped traversal and activate whatever gets focus:
    // only the overlay CONTENT may respond; the replica is pixels-only
    // (IgnorePointer already blocks the mouse - the keyboard must be
    // blocked symmetrically).
    for (int i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }
    expect(
      sourcePresses,
      1,
      reason:
          'Tab+Enter inside the open overlay reached the hidden source '
          'replica and fired its onPressed',
    );
    flight!.close();
    await settle(tester);
  });

  testWidgets('an explicit source FocusNode cannot pull focus into the ghost', (
    WidgetTester tester,
  ) async {
    final FocusNode node = FocusNode(debugLabel: 'source-button');
    addTearDown(node.dispose);
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphTag(
              id: 'btn',
              child: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  focusNode: node,
                  onPressed: () => flight ??= showMorphDialog(
                    context,
                    from: 'btn',
                    builder: (BuildContext context, MorphFlight f) =>
                        const TextField(autofocus: true),
                  ),
                  child: const Text('open-me'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);
    expect(inMorphScope(FocusManager.instance.primaryFocus), isTrue);

    // The replica shares the source widget config - the node included,
    // so during the flight the node is attached to the ghost copy. A
    // requestFocus while the overlay is up must land nowhere: the real
    // button is hidden and the replica is pixels-only.
    node.requestFocus();
    await tester.pump();
    expect(
      node.hasPrimaryFocus,
      isFalse,
      reason:
          'requestFocus on the source node focused the ghost replica '
          'inside the shuttle',
    );
    expect(
      inMorphScope(FocusManager.instance.primaryFocus),
      isTrue,
      reason: 'focus must stay with the overlay content',
    );
    flight!.close();
    await settle(tester);
  });
}
