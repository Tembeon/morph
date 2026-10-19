import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/morph.dart';

class _Recording extends MorphGlassPainter {
  List<MorphGlassSurface> last = const [];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) =>
      buildFill(context, surface);

  @override
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
    List<Rect> contentSlots = const [],
    double spacing = 0,
    MorphGlassOutline? outline,
  }) {
    last = surfaces;
    return super.buildLayer(
      context,
      surfaces,
      content: content,
      contentSlots: contentSlots,
      spacing: spacing,
      outline: outline,
    );
  }
}

Widget _scene(Widget child, {MorphGlassPainter? painter}) {
  final Widget scene = MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 300, child: child)),
    ),
  );
  return painter == null
      ? scene
      : MorphGlassScope(painter: painter, child: scene);
}

void main() {
  testWidgets('no selection hides the lens until a tap selects', (
    tester,
  ) async {
    final painter = _Recording();
    int? selected;
    await tester.pumpWidget(
      _scene(
        StatefulBuilder(
          builder: (context, setState) => MorphSegmentedControl(
            segments: const [
              MorphSegment('One'),
              MorphSegment('Two'),
              MorphSegment('Three'),
            ],
            selectedIndex: selected,
            onChanged: (int i) => setState(() => selected = i),
          ),
        ),
        painter: painter,
      ),
    );
    expect(painter.last.where((s) => s.kind == MorphGlassKind.lens), isEmpty);
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    final lens = painter.last.singleWhere((s) => s.kind == MorphGlassKind.lens);
    expect(lens.shape.center.dx, closeTo(150, 1));
  });

  testWidgets('a disabled segment does not select, the keys skip it', (
    tester,
  ) async {
    final changes = <int>[];
    await tester.pumpWidget(
      _scene(
        MorphSegmentedControl(
          segments: const [
            MorphSegment('One'),
            MorphSegment('Two', enabled: false),
            MorphSegment('Three'),
          ],
          selectedIndex: 0,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.tap(find.text('Three'));
    await tester.pumpAndSettle();
    expect(changes, [2]);
  });

  testWidgets('a fixed width segment keeps its width', (tester) async {
    final painter = _Recording();
    await tester.pumpWidget(
      _scene(
        MorphSegmentedControl(
          segments: const [MorphSegment('A', width: 60), MorphSegment('B')],
          selectedIndex: 1,
          onChanged: (_) {},
        ),
        painter: painter,
      ),
    );
    await tester.pumpAndSettle();
    final lens = painter.last.singleWhere((s) => s.kind == MorphGlassKind.lens);
    expect(lens.shape.center.dx, closeTo(60 + 240 / 2, 1));
  });
}
