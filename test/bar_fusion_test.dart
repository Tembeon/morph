import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/liquid_field.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);

MorphBarButton _icon(String id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: () {},
);

class _Recorder extends MorphGlassPainter {
  final List<double> spacings = [];
  final List<int> counts = [];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) =>
      const SizedBox.expand();

  @override
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
    List<Rect> contentSlots = const [],
    double spacing = 0,
  }) {
    spacings.add(spacing);
    counts.add(surfaces.length);
    return super.buildLayer(
      context,
      surfaces,
      content: content,
      contentSlots: contentSlots,
      spacing: spacing,
    );
  }
}

Widget _toolbar(List<MorphBarButtonGroup> leading, {MorphGlassPainter? glass}) {
  final bar = MorphToolbar(
    leading: leading,
    trailing: [
      MorphBarButtonGroup([_icon('compose')]),
    ],
  );
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: _screen,
        padding: EdgeInsets.only(top: 62, bottom: 34),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: glass == null ? bar : MorphGlass(painter: glass, child: bar),
          ),
        ],
      ),
    ),
  );
}

double _midpoint(double gap, double k) {
  const h = 48.0;
  const a = Rect.fromLTWH(0, 0, 48, h);
  final b = Rect.fromLTWH(48 + gap, 0, 48, h);
  final field = LiquidField([
    const MorphMass.box(a, radius: h / 2),
    MorphMass.box(b, radius: h / 2),
  ], k: k);
  return field.eval(Offset(48 + gap / 2, h / 2));
}

void main() {
  test('the measured container spacing of both bars is 12', () {
    expect(MorphBarMetrics.navigation.containerSpacing, 12);
    expect(MorphBarMetrics.toolbar.containerSpacing, 12);
    expect(MorphBarMetrics.toolbar.groupGap, 12);
  });

  test('at 12, resting groups stay apart and closer ones fuse', () {
    expect(_midpoint(12, 12), greaterThan(2.9));
    expect(_midpoint(8, 12), greaterThan(0));
    expect(_midpoint(5, 12), lessThan(0));
    expect(_midpoint(12, 18), lessThan(_midpoint(12, 12)));
  });

  testWidgets('a bar hands all its capsules to the painter as one container', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = _screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final recorder = _Recorder();
    await tester.pumpWidget(
      _toolbar([
        MorphBarButtonGroup([_icon('trash')]),
        MorphBarButtonGroup([_icon('folder')]),
      ], glass: recorder),
    );
    await tester.pumpAndSettle();
    expect(recorder.spacings.last, 12);
    expect(recorder.counts.last, 3);
  });

  testWidgets('flat capsules fuse while a group splits and part at rest', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = _screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _toolbar([
        MorphBarButtonGroup([_icon('trash'), _icon('folder')]),
      ]),
    );
    await tester.pumpAndSettle();
    final rest = find.byType(MorphToolbar);
    expect(rest, isNot(paints..path()));
    await tester.pumpWidget(
      _toolbar([
        MorphBarButtonGroup([_icon('trash')]),
        MorphBarButtonGroup([_icon('folder')]),
      ]),
    );
    var fused = false;
    for (var i = 0; i < 30 && !fused; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final painted = tester.renderObject<RenderBox>(rest);
      fused = _drawsPath(painted);
    }
    expect(fused, isTrue);
    await tester.pumpAndSettle();
    expect(_drawsPath(tester.renderObject<RenderBox>(rest)), isFalse);
  });
}

bool _drawsPath(RenderObject object) {
  try {
    expect(object, paints..path());
    return true;
  } on TestFailure {
    return false;
  }
}
