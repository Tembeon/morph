import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/spring_state.dart';

const _titles = [
  'Copy',
  'Share',
  'Rename',
  'Duplicate',
  'Move',
  'Tag',
  'Pin',
  'Archive',
  'Print',
  'Delete',
];

Widget _app(Widget body) => WidgetsApp(
  color: const Color(0xFF007AFF),
  pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
      PageRouteBuilder<T>(
        settings: settings,
        pageBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
            ) => builder(context),
      ),
  home: Align(alignment: const Alignment(0, -0.6), child: body),
);

T _ancestor<T extends RenderObject>(RenderObject from) {
  RenderObject? node = from.parent;
  while (node != null && node is! T) {
    node = node.parent;
  }
  return node! as T;
}

/// One frame of the open: where the far row is painted, the glyph
/// drawing's own snap included, and where its layout puts it.
typedef _Frame = ({double painted, double laidOut});

Future<List<_Frame>> _open(
  WidgetTester tester, {
  required int hz,
  required bool hold,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      MorphMenuButton(
        menu: [for (final title in _titles) MorphMenuItem(title: title)],
      ),
    ),
  );
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(MorphMenuButton)),
  );
  if (!hold) {
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
  }
  final step = Duration(microseconds: (1e6 / hz).round());
  final frames = <_Frame>[];
  for (var i = 0; i < hz * 2; i++) {
    await tester.pump(step);
    final far = find.text(_titles.last);
    if (far.evaluate().isEmpty) continue;
    final row = tester.renderObject<RenderBox>(far);
    final glyphs = _ancestor<RenderMorphGlyphs>(row);
    final local = MatrixUtils.transformPoint(
      row.getTransformTo(glyphs),
      Offset.zero,
    );
    final painted = MatrixUtils.transformPoint(
      glyphs.getTransformTo(null),
      MatrixUtils.transformPoint(glyphs.debugPaintTransform, local),
    );
    frames.add((
      painted: painted.dy,
      laidOut: row.localToGlobal(Offset.zero).dy,
    ));
  }
  if (hold) await gesture.up();
  return frames;
}

int _reversals(List<double> values) {
  var count = 0;
  double? direction;
  for (var i = 1; i < values.length; i++) {
    final d = values[i] - values[i - 1];
    if (d.abs() < 1e-3) continue;
    if (direction != null && d.sign != direction) count++;
    direction = d.sign;
  }
  return count;
}

void main() {
  for (final hz in [120, 60]) {
    for (final hold in [false, true]) {
      testWidgets('the far row rides the card to rest without a jump '
          '($hz Hz, ${hold ? 'hold' : 'tap'})', (WidgetTester tester) async {
        final frames = await _open(tester, hz: hz, hold: hold);
        expect(frames.length, greaterThan(hz ~/ 2));
        for (final (i, f) in frames.indexed) {
          expect(
            (f.painted - f.laidOut).abs(),
            lessThan(MorphRest.length),
            reason: 'frame $i: the row is drawn where the card holds it',
          );
        }
        final rest = frames.last;
        var last = frames.length - 1;
        while (last > 0 && frames[last - 1].painted == rest.painted) {
          last--;
        }
        expect(
          (frames[last].painted - frames[last - 1].painted).abs(),
          lessThan(MorphRest.length),
          reason: 'the last step onto rest is invisible',
        );
        expect(
          _reversals([for (final f in frames) f.painted]),
          lessThanOrEqualTo(_reversals([for (final f in frames) f.laidOut])),
          reason: 'no reversal beyond the spring\'s own overshoot',
        );
      });
    }
  }
}
