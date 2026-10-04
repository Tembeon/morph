import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);
const _fixture = 'test/fixtures/ios27-device/menu/navbar-tap.json';

Future<List<String>> _stack(
  WidgetTester tester, {
  VoidCallback? onPressed,
  bool enabled = true,
}) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final log = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: _screen,
          padding: EdgeInsets.only(top: 62, bottom: 34),
        ),
        child: MorphNavigationStack(
          home: MorphNavigationScaffold(
            title: 'Inbox',
            trailing: [
              MorphBarButtonGroup([
                MorphBarButton(
                  id: 'more',
                  icon: const SizedBox.square(dimension: 24),
                  semanticLabel: 'More',
                  onPressed: onPressed,
                  enabled: enabled,
                  menu: [
                    for (final title in ['Copy', 'Share', 'Delete'])
                      MorphMenuItem(
                        title: title,
                        onSelected: () => log.add(title),
                      ),
                  ],
                ),
              ]),
            ],
            slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return log;
}

Offset _button(WidgetTester tester) =>
    tester.getCenter(find.bySemanticsLabel('More'));

Future<void> _frames(WidgetTester tester, double seconds) async {
  final frames = (seconds / 0.008).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(microseconds: 8000));
  }
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

Map<String, Object?> _capture(String name) {
  final json =
      jsonDecode(File(_fixture).readAsStringSync()) as Map<String, Object?>;
  final captures = json['captures']! as Map<String, Object?>;
  return captures[name]! as Map<String, Object?>;
}

List<double> _tapLags(String name) {
  final capture = _capture(name);
  final touches = [
    for (final t in capture['touches']! as List<Object?>)
      t! as Map<String, Object?>,
  ];
  final morphs = [
    for (final m in capture['morph']! as List<Object?>)
      ((m! as List<Object?>).first! as num).toDouble(),
  ];
  final lags = <double>[];
  for (var i = 0; i + 1 < touches.length; i++) {
    final down = touches[i];
    final up = touches[i + 1];
    if (down['phase'] != 0 || up['phase'] != 3) continue;
    final x = (down['x']! as num).toDouble();
    if (x < 150) continue;
    final release = (up['t']! as num).toDouble();
    final open = morphs.firstWhere((double t) => t > release);
    lags.add(open - release);
  }
  return lags;
}

double _holdLag(String name) => (_capture(name)['morph']! as List<Object?>)
    .map((Object? m) => ((m! as List<Object?>).first! as num).toDouble())
    .first;

double _mean(Iterable<double> values) =>
    values.reduce((double a, double b) => a + b) / values.length;

void main() {
  testWidgets('a tap on a bar button with only a menu opens it on release', (
    WidgetTester tester,
  ) async {
    await _stack(tester);
    final gesture = await tester.startGesture(_button(tester));
    await _frames(tester, 0.1);
    await gesture.up();
    await _frames(tester, MorphBarMenuTuning.measuredMenu.tapOpenDelay - 0.02);
    expect(find.text('Copy'), findsNothing);
    await _frames(tester, 0.04);
    expect(find.text('Copy'), findsOneWidget);
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tapAt(const Offset(200, 700));
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a hold opens the menu under the finger; a slide chooses a row', (
    WidgetTester tester,
  ) async {
    final log = await _stack(tester);
    final gesture = await tester.startGesture(_button(tester));
    await _frames(tester, MorphMenuTuning.standard.holdDuration - 0.03);
    expect(find.text('Share'), findsNothing);
    await _frames(tester, 0.06);
    expect(find.text('Share'), findsOneWidget);
    await _frames(tester, 0.6);
    await gesture.moveTo(tester.getCenter(find.text('Share')));
    await _frames(tester, 0.1);
    await gesture.up();
    await _settle(tester);
    expect(log, ['Share']);
    expect(find.text('Share'), findsNothing);
  });

  testWidgets('a release on the button after a hold leaves the menu open', (
    WidgetTester tester,
  ) async {
    final log = await _stack(tester);
    final gesture = await tester.startGesture(_button(tester));
    await _frames(tester, 0.75);
    await gesture.up();
    await _settle(tester);
    expect(log, isEmpty);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(log, ['Delete']);
  });

  testWidgets('a disabled menu button does not open', (
    WidgetTester tester,
  ) async {
    await _stack(tester, enabled: false);
    final gesture = await tester.startGesture(_button(tester));
    await _frames(tester, 0.8);
    await gesture.up();
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a bar button with an action keeps its menu on a long press', (
    WidgetTester tester,
  ) async {
    var presses = 0;
    await _stack(tester, onPressed: () => presses++);
    await tester.tapAt(_button(tester));
    await _settle(tester);
    expect(presses, 1);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets(
    'screen readers find an enabled button whose tap opens the menu',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      await _stack(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('More'));
      expect(
        node,
        matchesSemantics(
          label: 'More',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasExpandedState: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('More'));
      await _settle(tester);
      expect(find.text('Copy'), findsOneWidget);
      semantics.dispose();
    },
  );

  test('a held finger that never leaves the button chooses nothing on '
      'release (center3-hold700, navbar3-hold300/700)', () {
    for (final center in [const Offset(201, 437), const Offset(364, 84)]) {
      final motion = MorphMenuMotion(
        button: Rect.fromCenter(center: center, width: 48, height: 48),
        itemCount: 3,
        bounds: _screen,
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      final selected = <int>[];
      motion.onSelected = selected.add;
      motion.advance(0);
      motion.pointerDown(0, center);
      motion.advance(0.5);
      expect(motion.isOpen, isTrue);
      motion.pointerMove(0.6, center + const Offset(2, 2));
      motion.pointerUp(0.742, center + const Offset(2, 2));
      motion.advance(2);
      expect(selected, isEmpty);
      expect(motion.isOpen, isTrue);
    }
  });

  test('the bar item opens later than the inline button by the recorded '
      'difference; holds within a display frame', () {
    final bar = _tapLags('navbar3-repeat');
    final inline = _tapLags('center3-repeat');
    expect(bar, hasLength(5));
    expect(inline, hasLength(4));
    final difference = _mean(bar.skip(1)) - _mean(inline.skip(1));
    expect(difference, closeTo(0.013, 0.001));
    expect(
      MorphBarMenuTuning.measuredMenu.tapOpenDelay -
          MorphMenuTuning.standard.tapOpenDelay,
      moreOrLessEquals(0.013, epsilon: 1e-9),
    );
    final inlineHold = _holdLag('center3-hold700');
    for (final name in [
      'navbar3-hold300',
      'navbar3-hold700',
      'navbar3-dragselect',
    ]) {
      expect(_holdLag(name), closeTo(inlineHold, 1 / 120), reason: name);
    }
    final hold = _capture('navbar3-hold700');
    expect(hold['morph'], hasLength(1), reason: 'no close after the release');
    final select = _capture('navbar3-dragselect');
    expect((select['actions']! as List<Object?>), hasLength(1));
  });
}
