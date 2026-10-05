import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);

MorphBarButton _icon(String id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: () {},
);

class _Recorder extends MorphGlassPainter {
  final List<(List<RRect>, double)> layers = [];

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
    MorphGlassOutline? outline,
  }) {
    layers.add(([for (final s in surfaces) s.shape], spacing));
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

Widget _root(void Function(BuildContext) onContext) => Builder(
  builder: (context) {
    onContext(context);
    return MorphNavigationScaffold(
      title: 'Root',
      trailing: [
        MorphBarButtonGroup([_icon('plus')]),
      ],
      slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
    );
  },
);

Widget _alpha() => MorphNavigationScaffold(
  title: 'Alpha',
  trailing: [
    MorphBarButtonGroup([_icon('share')]),
  ],
  slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
);

/// Every glass layer the bar built since the last check fuses only
/// capsules of one side of the bar, and the back button stays on its own
/// side.
void _expectSidesApart(WidgetTester tester, _Recorder glass, String when) {
  for (final (shapes, spacing) in glass.layers) {
    for (final group in morphGlassContainerGroups(shapes, spacing)) {
      final sides = {
        for (final i in group) shapes[i].center.dx < _screen.width / 2,
      };
      expect(sides, hasLength(1), reason: '$when: $shapes fused');
    }
  }
  glass.layers.clear();
  final back = find.byKey(const ValueKey<Object>('morph.back'));
  if (back.evaluate().isNotEmpty) {
    expect(
      tester.getCenter(back).dx,
      lessThan(_screen.width / 2),
      reason: '$when: the back button crossed the bar',
    );
  }
}

Future<void> _frames(
  WidgetTester tester,
  _Recorder glass,
  String when, {
  int count = 60,
}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    _expectSidesApart(tester, glass, '$when frame $i');
  }
}

void main() {
  testWidgets('a push and a pop never fuse the leading group into the '
      'trailing one', (tester) async {
    tester.view.physicalSize = _screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final glass = _Recorder();
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MorphGlass(
          painter: glass,
          child: MorphNavigationStack(home: _root((c) => root = c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final plus = tester.getCenter(find.byKey(const ValueKey<Object>('plus')));
    glass.layers.clear();

    Navigator.of(
      root,
    ).push(MorphNavigationRoute<void>(builder: (_) => _alpha()));
    await tester.pump();
    await _frames(tester, glass, 'push');
    expect(
      tester.getCenter(find.byKey(const ValueKey<Object>('share'))).dx,
      closeTo(plus.dx, 0.5),
    );
    await tester.pumpAndSettle();
    glass.layers.clear();

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    await _frames(tester, glass, 'pop');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<Object>('morph.back')), findsNothing);

    Navigator.of(
      root,
    ).push(MorphNavigationRoute<void>(builder: (_) => _alpha()));
    await tester.pumpAndSettle();
    glass.layers.clear();
    final gesture = await tester.startGesture(const Offset(4, 500));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
      _expectSidesApart(tester, glass, 'swipe $i');
    }
    await gesture.up();
    await _frames(tester, glass, 'swipe pop');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<Object>('morph.back')), findsNothing);
  });
}
