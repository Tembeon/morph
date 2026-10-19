import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

const _codec = StandardMethodCodec();

/// Sends one predictive back event as the Android embedding does.
Future<void> _back(
  WidgetTester tester,
  String method, [
  double progress = 0,
]) async {
  final arguments = switch (method) {
    'startBackGesture' || 'updateBackGestureProgress' => <String, Object?>{
      'touchOffset': <double>[4, 400],
      'progress': progress,
      'swipeEdge': 0,
    },
    _ => null,
  };
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    _codec.encodeMethodCall(MethodCall(method, arguments)),
    (ByteData? _) {},
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 16),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

final _sourceLink = MorphSourceLink();

Future<BuildContext> _pumpStack(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext inbox;
  await tester.pumpWidget(
    MaterialApp(
      home: MorphNavigationStack(
        home: Builder(
          builder: (context) {
            inbox = context;
            return MorphNavigationScaffold(
              title: 'Inbox',
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: MorphSource(
                      link: _sourceLink,
                      child: const SizedBox(width: 100, height: 80),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  return inbox;
}

Widget _detail() => const MorphNavigationScaffold(
  title: 'Message',
  slivers: [SliverToBoxAdapter(child: Center(child: Text('body')))],
);

void main() {
  testWidgets('back previews a pushed page and commits its pop', (
    tester,
  ) async {
    final inbox = await _pumpStack(tester);
    unawaited(
      Navigator.of(
        inbox,
      ).push(MorphNavigationRoute<void>(builder: (_) => _detail())),
    );
    await _settle(tester);
    final rest = tester.getCenter(find.text('body')).dx;
    await _back(tester, 'startBackGesture');
    await _back(tester, 'updateBackGestureProgress', 0.5);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getCenter(find.text('body')).dx,
      moreOrLessEquals(rest + 201, epsilon: 2),
      reason: 'the page follows half the gesture across its width',
    );
    await _back(tester, 'commitBackGesture');
    await _settle(tester);
    expect(find.text('body'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a back gesture over a pending edge touch previews', (
    tester,
  ) async {
    final inbox = await _pumpStack(tester);
    unawaited(
      Navigator.of(
        inbox,
      ).push(MorphNavigationRoute<void>(builder: (_) => _detail())),
    );
    await _settle(tester);
    final rest = tester.getCenter(find.text('body')).dx;
    final touch = await tester.startGesture(const Offset(3, 400));
    await tester.pump();
    await _back(tester, 'startBackGesture');
    await _back(tester, 'updateBackGestureProgress', 0.5);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(find.text('body')).dx, greaterThan(rest + 150));
    await touch.cancel();
    await _back(tester, 'commitBackGesture');
    await _settle(tester);
    expect(find.text('body'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled back returns the page', (tester) async {
    final inbox = await _pumpStack(tester);
    unawaited(
      Navigator.of(
        inbox,
      ).push(MorphNavigationRoute<void>(builder: (_) => _detail())),
    );
    await _settle(tester);
    final rest = tester.getCenter(find.text('body')).dx;
    await _back(tester, 'startBackGesture');
    await _back(tester, 'updateBackGestureProgress', 0.4);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(find.text('body')).dx, greaterThan(rest + 100));
    await _back(tester, 'cancelBackGesture');
    await _settle(tester);
    expect(
      tester.getCenter(find.text('body')).dx,
      moreOrLessEquals(rest, epsilon: 0.5),
    );
    expect(ModalRoute.of(tester.element(find.text('body')))!.isCurrent, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back under a sheet closes the sheet, not the page below', (
    tester,
  ) async {
    final inbox = await _pumpStack(tester);
    unawaited(
      Navigator.of(
        inbox,
      ).push(MorphNavigationRoute<void>(builder: (_) => _detail())),
    );
    await _settle(tester);
    unawaited(
      showMorphSheet<void>(
        tester.element(find.text('body')),
        detents: const [MorphSheetDetent.medium],
        builder: (_) => const Text('sheet'),
      ),
    );
    await _settle(tester);
    final rest = tester.getCenter(find.text('body')).dx;
    await _back(tester, 'startBackGesture');
    await _back(tester, 'updateBackGestureProgress', 0.5);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(find.text('body')).dx, rest);
    await _back(tester, 'commitBackGesture');
    await _settle(tester);
    expect(find.text('sheet'), findsNothing);
    expect(find.text('body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled back returns a zoomed page past the dismiss '
      'distance', (tester) async {
    final inbox = await _pumpStack(tester);
    unawaited(
      Navigator.of(inbox).push(
        MorphNavigationRoute<void>(
          from: _sourceLink,
          builder: (_) =>
              const SizedBox.expand(child: Center(child: Text('zoomed'))),
        ),
      ),
    );
    await _settle(tester);
    final open = tester.getCenter(find.text('zoomed'));
    await _back(tester, 'startBackGesture');
    await _back(tester, 'updateBackGestureProgress', 0.6);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(find.text('zoomed')), isNot(open));
    await _back(tester, 'cancelBackGesture');
    await _settle(tester);
    expect(
      tester.getCenter(find.text('zoomed')).dx,
      moreOrLessEquals(open.dx, epsilon: 0.5),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back previews a zoomed page and zooms it home', (tester) async {
    final inbox = await _pumpStack(tester);
    unawaited(
      Navigator.of(inbox).push(
        MorphNavigationRoute<void>(
          from: _sourceLink,
          builder: (_) =>
              const SizedBox.expand(child: Center(child: Text('zoomed'))),
        ),
      ),
    );
    await _settle(tester);
    final open = tester.getCenter(find.text('zoomed'));
    await _back(tester, 'startBackGesture');
    await _back(tester, 'updateBackGestureProgress', 0.5);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(find.text('zoomed')), isNot(open));
    await _back(tester, 'commitBackGesture');
    await _settle(tester);
    expect(find.text('zoomed'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
