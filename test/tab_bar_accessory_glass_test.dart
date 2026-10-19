import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/widgets.dart';

const _items = [
  MorphTabItem(icon: Icons.home, label: 'Home'),
  MorphTabItem(icon: Icons.search, label: 'Browse'),
  MorphTabItem(icon: Icons.radio, label: 'Radio'),
];

const _content = ValueKey<String>('player');

/// The glass hosts under [root]: where each draws its surfaces on the
/// screen (a layer draws them where they are in its box, a surface host
/// its one surface at its own origin) and the spacing it fuses them at.
List<({List<Rect> drawn, double spacing})> _glass(Element root) {
  final out = <({List<Rect> drawn, double spacing})>[];
  void visit(Element element) {
    final host = debugMorphGlassHostOf(element);
    final box = element.findRenderObject();
    if (host != null && box is RenderBox && box.attached) {
      out.add((
        drawn: [
          for (final surface in host.frame.surfaces)
            MatrixUtils.transformRect(
              box.getTransformTo(null),
              (host.mode == MorphGlassMode.layer
                      ? surface.shape.outerRect.topLeft
                      : Offset.zero) &
                  surface.shape.outerRect.size,
            ),
        ],
        spacing: host.frame.spacing,
      ));
    }
    element.visitChildren(visit);
  }

  visit(root);
  return out;
}

Widget _app(MorphGlassTier tier, Widget bar) => MaterialApp(
  builder: (BuildContext context, Widget? child) => MorphTheme(
    data: MorphThemeData(glass: .tier(tier)),
    child: child!,
  ),
  home: Scaffold(
    body: MorphContentScrollScope(
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              itemCount: 100,
              itemBuilder: (BuildContext context, int i) => SizedBox(
                height: 60,
                child: ColoredBox(color: Color(0xFF000000 | (i * 0x153F7B))),
              ),
            ),
          ),
          bar,
        ],
      ),
    ),
  ),
);

/// Checks every frame of a minimize and an expand: the accessory's glass
/// is a body of its own, never one with the bar's, and it is drawn under
/// its content.
Future<void> _follow(WidgetTester tester, Offset circle) async {
  var frames = 0;
  Future<void> check() async {
    await tester.pump(const Duration(milliseconds: 8));
    final content = tester.getRect(find.byKey(_content));
    final hosts = _glass(tester.element(find.byType(MaterialApp)));
    final accessory = [
      for (final host in hosts)
        for (final drawn in host.drawn)
          if ((drawn.center - content.center).distance < 0.5)
            (drawn: drawn, host: host),
    ];
    expect(
      accessory,
      hasLength(1),
      reason: 'frame $frames: one glass under the content $content: $hosts',
    );
    final (:drawn, :host) = accessory.single;
    for (final other in host.drawn) {
      if (identical(other, drawn)) continue;
      expect(
        other.inflate(host.spacing).overlaps(drawn),
        isFalse,
        reason: 'frame $frames: the accessory $drawn fuses with $other',
      );
    }
    frames++;
  }

  final finger = await tester.startGesture(const Offset(201, 400));
  for (var i = 0; i < 25; i++) {
    await finger.moveBy(const Offset(0, -8));
    await check();
  }
  await finger.up();
  for (var i = 0; i < 90; i++) {
    await check();
  }
  await tester.tapAt(circle);
  for (var i = 0; i < 90; i++) {
    await check();
  }
}

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MultiShaderBuilder.precacheShaders([
      ShaderKeys.fakeGlassSurface,
      ...ShaderKeys.liquidGlassRenders,
    ]);
  });
  tearDownAll(() => isLocalTest = false);

  for (final tier in MorphGlassTier.values) {
    testWidgets('tab bar accessory glass follows its content: ${tier.name}', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          tier,
          Positioned(
            left: 0,
            right: 0,
            bottom: 21,
            child: MorphTabBar(
              items: _items,
              selected: 0,
              onChanged: (_) {},
              minimizeBehavior: MorphTabBarMinimizeBehavior.onScrollDown,
              bottomAccessory: const SizedBox.expand(key: _content),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _follow(tester, const Offset(52, 874 - 21 - 31));
    });

    testWidgets('search tab bar accessory glass follows its content: '
        '${tier.name}', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          tier,
          Positioned.fill(
            child: MorphSearchTabBar(
              items: _items,
              selected: 0,
              onChanged: (_) {},
              active: false,
              onActiveChanged: (_) {},
              minimizeBehavior: MorphTabBarMinimizeBehavior.onScrollDown,
              bottomAccessory: const SizedBox.expand(key: _content),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _follow(tester, const Offset(52, 874 - 21 - 31));
    });
  }
}
