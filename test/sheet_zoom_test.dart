import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

Rect _rect(List<Object?> v) => Rect.fromLTRB(
  (v[0]! as num).toDouble(),
  (v[1]! as num).toDouble(),
  (v[2]! as num).toDouble(),
  (v[3]! as num).toDouble(),
);

List<Map<String, Object?>> _segments() {
  final json =
      jsonDecode(
            File(
              'test/fixtures/ios27-device/zoom/zoom.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  return (json['segments']! as List<Object?>).cast<Map<String, Object?>>();
}

MorphZoomMotion _motionFor(String way) {
  final motion = MorphZoomMotion();
  if (way == 'open') {
    motion.open(0);
  } else {
    motion.open(-10);
    motion.advance(0);
    motion.close(0);
  }
  return motion;
}

const _source = ValueKey<String>('source');
const _content = ValueKey<String>('content');

Widget _app(void Function(BuildContext context) onPresent) => MaterialApp(
  home: MorphScope(
    child: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 131,
              top: 276,
              width: 140,
              height: 48,
              child: MorphTag(
                id: 'source',
                shape: const StadiumBorder(),
                child: GestureDetector(
                  onTap: () => onPresent(context),
                  child: const ColoredBox(
                    key: _source,
                    color: Color(0xFFFF00FF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget _sheet(BuildContext context) =>
    const ColoredBox(key: _content, color: Color(0xFF00C800));

Future<void> _pumpFor(WidgetTester tester, double seconds) async {
  final frames = (seconds / 0.016).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

void main() {
  group('device replay', () {
    for (final segment in _segments()) {
      final name = segment['name']! as String;
      final way = segment['way']! as String;
      test('$name: container, crossfade and dimming', () {
        final source = _rect(segment['source']! as List<Object?>);
        final sheet = _rect(segment['sheet']! as List<Object?>);
        final frames = (segment['frames']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .where((f) => (f['t']! as num) > -0.01);
        final motion = _motionFor(way);
        var edges = 0.0;
        var fades = 0.0;
        var dims = 0.0;
        var n = 0;
        for (final f in frames) {
          final t = (f['t']! as num).toDouble();
          motion.advance(t);
          final r = motion.rect(t, source, sheet);
          final m = _rect(f['rect']! as List<Object?>);
          edges +=
              (math.pow(r.left - m.left, 2) +
                      math.pow(r.top - m.top, 2) +
                      math.pow(r.right - m.right, 2) +
                      math.pow(r.bottom - m.bottom, 2))
                  .toDouble() /
              4;
          fades += math.pow(motion.fade(t) - (f['fade']! as num), 2);
          dims += math.pow(motion.dimming(t) - (f['dim']! as num), 2);
          n++;
        }
        expect(n, greaterThan(20));
        final edgeRms = math.sqrt(edges / n);
        expect(edgeRms, lessThan(way == 'open' ? 4.0 : 6.0), reason: name);
        expect(math.sqrt(fades / n), lessThan(0.05), reason: name);
        expect(math.sqrt(dims / n), lessThan(0.08), reason: name);
      });
    }
  });

  test('a reversal turns around without a jump', () {
    const source = Rect.fromLTWH(131, 276, 140, 48);
    const sheet = Rect.fromLTRB(8, 414.67, 394, 866);
    final motion = MorphZoomMotion();
    motion.open(0);
    motion.advance(0.12);
    final before = motion.rect(0.12, source, sheet);
    motion.close(0.12);
    final after = motion.rect(0.12, source, sheet);
    expect(after, before);
    motion.advance(0.121);
    expect(
      (motion.rect(0.121, source, sheet).center - before.center).distance,
      lessThan(2),
    );
    motion.advance(3);
    expect(motion.isClosed, isTrue);
  });

  testWidgets('a sheet zooms out of its source and back into it', (
    WidgetTester tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        (BuildContext context) => presentMorphSheet<void>(
          context,
          from: 'source',
          detents: const [MorphSheetDetent.medium],
          builder: _sheet,
        ),
      ),
    );
    await tester.tap(find.byKey(_source));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final early = tester.getRect(find.byKey(_content));
    expect(early.width, lessThan(386));
    expect(early.top, greaterThan(276));
    await _pumpFor(tester, 1.2);
    final open = tester.getRect(find.byKey(_content));
    expect(open.left, moreOrLessEquals(8, epsilon: 0.5));
    expect(open.width, moreOrLessEquals(386, epsilon: 0.5));
    expect(open.bottom, moreOrLessEquals(866, epsilon: 0.5));
    final hidden = tester.widget<Opacity>(
      find
          .ancestor(of: find.byKey(_source), matching: find.byType(Opacity))
          .first,
    );
    expect(hidden.opacity, 0);

    Navigator.of(tester.element(find.byKey(_content))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    final closing = tester.getRect(find.byKey(_content));
    expect(closing.width, lessThan(open.width));
    await _pumpFor(tester, 1.5);
    expect(find.byKey(_content), findsNothing);
    final shown = tester.widget<Opacity>(
      find
          .ancestor(of: find.byKey(_source), matching: find.byType(Opacity))
          .first,
    );
    expect(shown.opacity, 1);
  });

  testWidgets('a drag down from the smallest detent zooms the sheet away', (
    WidgetTester tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        (BuildContext context) => presentMorphSheet<void>(
          context,
          from: 'source',
          detents: const [MorphSheetDetent.medium],
          builder: _sheet,
        ),
      ),
    );
    await tester.tap(find.byKey(_source));
    await tester.pump();
    await _pumpFor(tester, 1.2);
    final gesture = await tester.startGesture(const Offset(201, 600));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _pumpFor(tester, 0.2);
    final closing = tester.getRect(find.byKey(_content));
    expect(closing.width, lessThan(380));
    await gesture.up();
    await _pumpFor(tester, 1.5);
    expect(find.byKey(_content), findsNothing);
  });
}
