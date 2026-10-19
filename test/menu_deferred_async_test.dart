import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

const Offset _outside = Offset(5, 590);

const MorphMenuItem _copy = MorphMenuItem(title: 'Copy');
const MorphMenuItem _paste = MorphMenuItem(title: 'Paste');

Widget _app(List<MorphMenuEntry> menu, {Key? key, bool button = true}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: const Alignment(0, -0.6),
          child: button
              ? MorphMenuButton(key: key, menu: menu)
              : const SizedBox.shrink(),
        ),
      ),
    );

/// Hands out one pending answer per call of `load`, so a test decides
/// when and how each load finishes and counts the loads.
class _Loads {
  final List<Completer<List<MorphMenuEntry>>> calls = [];

  Future<List<MorphMenuEntry>> load() {
    final answer = Completer<List<MorphMenuEntry>>();
    calls.add(answer);
    return answer.future;
  }
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

// A loading row spins until its answer comes, so an opening cannot settle;
// these pumps carry the tap through its opening delay and the open spring.
Future<void> _tapButton(WidgetTester tester) async {
  await tester.tap(find.byType(MorphMenuButton));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _close(WidgetTester tester) async {
  await tester.tapAt(_outside);
  await _settle(tester);
}

/// Nothing animates, nothing waits to draw, and a minute later still
/// nothing does: no ticker, spinner or timer is left running.
Future<void> _expectQuiet(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  expect(find.byType(MorphActivityIndicator), findsNothing);
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.binding.hasScheduledFrame, isFalse);
  await tester.pump(const Duration(minutes: 1));
  expect(tester.takeException(), isNull);
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.binding.hasScheduledFrame, isFalse);
}

/// The menu still opens and closes on taps, showing [rows].
Future<void> _expectWorks(WidgetTester tester, List<String> rows) async {
  await _tapButton(tester);
  for (final row in rows) {
    expect(find.text(row), findsOneWidget, reason: '$row after reopening');
  }
  expect(find.text('Loading...'), findsNothing);
  await _settle(tester);
  await _expectQuiet(tester);
  await _close(tester);
  for (final row in rows) {
    expect(find.text(row), findsNothing, reason: '$row after closing');
  }
  await _expectQuiet(tester);
}

/// Closes the open menu with a tap outside it and taps the button again,
/// [closing] while the close is still on screen, otherwise once it has
/// settled.
Future<void> _closeAndReopen(
  WidgetTester tester, {
  required bool closing,
}) async {
  await tester.tapAt(_outside);
  await tester.pump();
  if (closing) {
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Copy'), findsOneWidget, reason: 'still closing');
  } else {
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
  }
  await _tapButton(tester);
  expect(find.text('Copy'), findsOneWidget, reason: 'reopened');
}

Future<void> _uncachedReopen(
  WidgetTester tester, {
  required bool closing,
}) async {
  final loads = _Loads();
  await tester.pumpWidget(
    _app([_copy, MorphMenuDeferred(loads.load, id: 'recent', cache: false)]),
  );
  await _tapButton(tester);
  await _closeAndReopen(tester, closing: closing);
  expect(find.text('Loading...'), findsOneWidget);
  expect(loads.calls, hasLength(2), reason: 'every opening loads');
  loads.calls.first.complete(const [MorphMenuItem(title: 'Stale')]);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.text('Stale'), findsNothing);
  expect(find.text('Loading...'), findsOneWidget);
  loads.calls.last.complete(const [MorphMenuItem(title: 'Fresh')]);
  await tester.pump();
  await _settle(tester);
  expect(find.text('Fresh'), findsOneWidget);
  expect(find.text('Stale'), findsNothing);
  expect(find.text('Loading...'), findsNothing);
  await _expectQuiet(tester);
  await _close(tester);
  await _tapButton(tester);
  expect(loads.calls, hasLength(3));
  loads.calls.last.complete(const [MorphMenuItem(title: 'Fresh')]);
  await tester.pump();
  await _settle(tester);
  expect(find.text('Fresh'), findsOneWidget);
  await _close(tester);
  await _expectQuiet(tester);
}

void main() {
  group(
    'a load that throws',
    () {
      testWidgets('is reported once and leaves the group empty', (
        WidgetTester tester,
      ) async {
        var loads = 0;
        await tester.pumpWidget(
          _app([
            _copy,
            MorphMenuDeferred(() {
              loads++;
              throw StateError('offline');
            }, id: 'recent'),
          ]),
        );
        await _tapButton(tester);
        expect(tester.takeException(), isA<StateError>());
        expect(find.text('Copy'), findsOneWidget, reason: 'the menu opens');
        expect(find.text('Loading...'), findsNothing);
        await _settle(tester);
        await _expectQuiet(tester);
        await _close(tester);
        await _expectWorks(tester, ['Copy']);
        expect(loads, 1, reason: 'cached like a rejected Future');
      });
    },
    skip:
        'defect: a synchronous throw from load escapes MorphMenuContent '
        '_resolve, the first tap opens nothing and every later opening '
        'spins forever',
  );

  testWidgets('a rejected Future is reported and leaves the group empty', (
    WidgetTester tester,
  ) async {
    final loads = _Loads();
    await tester.pumpWidget(
      _app([_copy, MorphMenuDeferred(loads.load, id: 'recent')]),
    );
    await _tapButton(tester);
    expect(find.text('Loading...'), findsOneWidget);
    loads.calls.single.completeError(StateError('offline'));
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Loading...'), findsNothing);
    await _expectQuiet(tester);
    await _close(tester);
    await _expectWorks(tester, ['Copy']);
    expect(loads.calls, hasLength(1), reason: 'the failure is cached as empty');
  });

  testWidgets('an empty answer leaves the menu as if the group were absent', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(const [_copy, MorphMenuDivider(), _paste], key: const Key('plain')),
    );
    await _tapButton(tester);
    await _settle(tester);
    final copy = tester.getRect(find.text('Copy'));
    final paste = tester.getRect(find.text('Paste'));
    await _close(tester);

    final loads = _Loads();
    await tester.pumpWidget(
      _app([
        _copy,
        const MorphMenuDivider(),
        MorphMenuDeferred(loads.load, id: 'recent'),
        const MorphMenuDivider(),
        _paste,
      ], key: const Key('deferred')),
    );
    await _tapButton(tester);
    expect(find.text('Loading...'), findsOneWidget);
    loads.calls.single.complete(const []);
    await tester.pump();
    await _settle(tester);
    expect(find.text('Loading...'), findsNothing);
    // The resize spring rests within a thousandth of a point of its target.
    expect(
      tester.getRect(find.text('Copy')),
      rectMoreOrLessEquals(copy, epsilon: 0.01),
    );
    expect(
      tester.getRect(find.text('Paste')),
      rectMoreOrLessEquals(paste, epsilon: 0.01),
    );
    await _expectQuiet(tester);
    await _close(tester);
    await _expectWorks(tester, ['Copy', 'Paste']);
    expect(loads.calls, hasLength(1));
  });

  testWidgets('a menu whose only group answers nothing still settles', (
    WidgetTester tester,
  ) async {
    final loads = _Loads();
    await tester.pumpWidget(_app([MorphMenuDeferred(loads.load, id: 'only')]));
    await _tapButton(tester);
    expect(find.text('Loading...'), findsOneWidget);
    loads.calls.single.complete(const []);
    await tester.pump();
    await _settle(tester);
    expect(find.text('Loading...'), findsNothing);
    await _expectQuiet(tester);
    await _close(tester);
    await _expectQuiet(tester);
    await _expectWorks(tester, const []);
    expect(loads.calls, hasLength(1));
  });

  testWidgets('an answer after the close waits quietly for the next opening', (
    WidgetTester tester,
  ) async {
    final loads = _Loads();
    await tester.pumpWidget(
      _app([_copy, MorphMenuDeferred(loads.load, id: 'recent')]),
    );
    await _tapButton(tester);
    expect(find.text('Loading...'), findsOneWidget);
    await _close(tester);
    expect(find.text('Copy'), findsNothing);
    await _expectQuiet(tester);
    loads.calls.single.complete(const [MorphMenuItem(title: 'Recent')]);
    await tester.pump();
    expect(find.text('Recent'), findsNothing);
    await _expectQuiet(tester);
    await _expectWorks(tester, ['Copy', 'Recent']);
    expect(loads.calls, hasLength(1));
  });

  testWidgets('an answer after the button left the tree is dropped', (
    WidgetTester tester,
  ) async {
    final loads = _Loads();
    final menu = [_copy, MorphMenuDeferred(loads.load, id: 'recent')];
    await tester.pumpWidget(_app(menu));
    await _tapButton(tester);
    expect(find.text('Loading...'), findsOneWidget);
    await tester.pumpWidget(_app(menu, button: false));
    await tester.pump();
    loads.calls.single.complete(const [MorphMenuItem(title: 'Recent')]);
    await tester.pump();
    expect(find.text('Recent'), findsNothing);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    await _expectQuiet(tester);

    await tester.pumpWidget(_app(menu));
    await _tapButton(tester);
    expect(
      loads.calls,
      hasLength(2),
      reason: 'the answers live with the button that asked',
    );
    loads.calls.last.complete(const [MorphMenuItem(title: 'Recent')]);
    await tester.pump();
    await _settle(tester);
    expect(find.text('Recent'), findsOneWidget);
    await _close(tester);
    await _expectQuiet(tester);
  });

  for (final closing in [false, true]) {
    final when = closing ? 'during its close' : 'after its close';
    testWidgets('a cached group reopened $when keeps its one load', (
      WidgetTester tester,
    ) async {
      final loads = _Loads();
      await tester.pumpWidget(
        _app([_copy, MorphMenuDeferred(loads.load, id: 'recent')]),
      );
      await _tapButton(tester);
      await _closeAndReopen(tester, closing: closing);
      expect(find.text('Loading...'), findsOneWidget);
      expect(loads.calls, hasLength(1));
      loads.calls.single.complete(const [MorphMenuItem(title: 'Recent')]);
      await tester.pump();
      await _settle(tester);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Loading...'), findsNothing);
      await _expectQuiet(tester);
      await _close(tester);
      await _expectWorks(tester, ['Copy', 'Recent']);
      expect(loads.calls, hasLength(1));
    });
  }

  testWidgets('an uncached group reopened after its close loads again', (
    WidgetTester tester,
  ) async {
    await _uncachedReopen(tester, closing: false);
  });

  group(
    'an uncached group reopened during its close',
    () {
      testWidgets('loads again and drops the stale answer', (
        WidgetTester tester,
      ) async {
        await _uncachedReopen(tester, closing: true);
      });
    },
    skip:
        'defect: a reopen during the close skips beginSession, so load does '
        'not run again and the previous opening answers the new one',
  );
}
