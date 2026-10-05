import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/liquid_glass.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/widgets.dart';

/// The glass channel: a frame that keeps a layer's structure reaches the
/// render objects without a widget build below the host; a frame that
/// changes it rebuilds the tree once.
void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MultiShaderBuilder.precacheShaders([ShaderKeys.fakeGlassSurface]);
  });
  tearDownAll(() => isLocalTest = false);

  Future<(ValueNotifier<int>, List<MorphGlassSurface> Function())> pumpLayer(
    WidgetTester tester,
    MorphGlassPainter painter,
    List<MorphGlassSurface> Function(int frame) at,
  ) async {
    final frames = ValueNotifier<int>(0);
    addTearDown(frames.dispose);
    List<MorphGlassSurface> surfaces() => at(frames.value);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 60,
            child: MorphGlassLayer(
              painter: painter,
              frames: frames,
              surfaces: surfaces,
              content: const Text('A'),
            ),
          ),
        ),
      ),
    );
    return (frames, surfaces);
  }

  MorphGlassSurface track() => const MorphGlassSurface(
    kind: MorphGlassKind.track,
    shape: RRect.fromLTRBXY(0, 0, 300, 60, 30, 30),
    color: Color(0xFFE5E5EA),
    brightness: Brightness.light,
    glass: false,
  );

  MorphGlassSurface lens(double left, double lift) => MorphGlassSurface(
    kind: MorphGlassKind.lens,
    shape: RRect.fromLTRBXY(left, 4, left + 100, 56, 26, 26),
    color: const Color(0xFFFFFFFF),
    brightness: Brightness.light,
    lift: lift,
    optics: MorphGlassOptics.large,
  );

  for (final tier in MorphGlassTier.values) {
    testWidgets('a moving lens rebuilds nothing below its host ($tier)', (
      tester,
    ) async {
      final (frames, _) = await pumpLayer(
        tester,
        MorphGlassRenderer(tier: tier),
        (int f) => [track(), lens(10.0 + f * 7, 1)],
      );
      final elements = <Element>{};
      debugOnRebuildDirtyWidget = (Element element, bool _) {
        elements.add(element);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      for (var i = 1; i <= 5; i++) {
        frames.value = i;
        await tester.pump();
      }
      debugOnRebuildDirtyWidget = null;
      expect(elements.map((Element e) => e.widget.runtimeType).toSet(), {
        MorphGlassHost,
      }, reason: '${[for (final e in elements) e.widget]}');
      final layer = tester.getRect(find.byType(MorphGlassLayer));
      final placed = find
          .descendant(
            of: find.byType(MorphGlassLayer),
            matching: find.byType(MorphLivePositioned),
          )
          .last;
      expect(
        tester.getRect(placed).left - layer.left,
        moreOrLessEquals(10 + 5 * 7.0),
      );
    });
  }

  testWidgets('a lens lifting off rebuilds the layer once', (tester) async {
    final (frames, _) = await pumpLayer(
      tester,
      const MorphGlassRenderer(),
      (int f) => [track(), lens(10, f == 0 ? 0 : 1)],
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
    final hosts = <Element>[];
    debugOnRebuildDirtyWidget = (Element element, bool _) {
      if (element.widget is LiquidGlassLayer) hosts.add(element);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    frames.value = 1;
    await tester.pump();
    frames.value = 2;
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(hosts, hasLength(1));
  });

  testWidgets('a moving lens writes its shape into the glass render object', (
    tester,
  ) async {
    final (frames, _) = await pumpLayer(
      tester,
      const MorphGlassRenderer(),
      (int f) => [track(), lens(10, f == 0 ? 0.2 : 0.1)],
    );
    LiquidGlassAppearance appearance() =>
        tester.widget<LiquidGlass>(find.byType(LiquidGlass)).appearance!;
    final before = appearance();
    frames.value = 3;
    await tester.pump();
    expect(appearance(), isNot(before));
    final glass = tester.renderObject<RenderLiquidGlass>(
      find.descendant(
        of: find.byType(LiquidGlass),
        matching: find.byWidgetPredicate(
          (Widget w) => w.runtimeType.toString() == '_RawLiquidGlass',
        ),
      ),
    );
    expect(glass.appearance, appearance());
  });

  testWidgets('a painter of its own is asked for every frame', (tester) async {
    final painter = _Counting();
    final (frames, _) = await pumpLayer(
      tester,
      painter,
      (int f) => [track(), lens(10.0 + f, 1)],
    );
    for (var i = 1; i <= 4; i++) {
      frames.value = i;
      await tester.pump();
    }
    expect(painter.layers, 5);
  });

  testWidgets('a host its parent rebuilds pushes without building', (
    tester,
  ) async {
    var left = 10.0;
    late StateSetter update;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 60,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                update = setState;
                return MorphGlassHost(
                  painter: const MorphGlassRenderer(),
                  mode: MorphGlassMode.layer,
                  frame: () => MorphGlassFrame([track(), lens(left, 1)]),
                );
              },
            ),
          ),
        ),
      ),
    );
    final built = <Type>{};
    debugOnRebuildDirtyWidget = (Element element, bool _) {
      built.add(element.widget.runtimeType);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    update(() => left = 40);
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(built, {StatefulBuilder});
    expect(
      tester.getRect(find.byType(LiquidGlass).last).left -
          tester.getRect(find.byType(MorphGlassHost)).left,
      40,
    );
  });
}

class _Counting extends MorphGlassPainter {
  int layers = 0;

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
    layers++;
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
