import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);

/// The backdrop filters painted inside an opacity layer that is not fully
/// opaque: such a filter reads the layer's own empty backdrop instead of
/// the screen under it.
List<BackdropFilterLayer> _blursUnderOpacity() {
  final out = <BackdropFilterLayer>[];
  void walk(Layer layer, {required bool faded}) {
    final fading =
        faded || (layer is OpacityLayer && (layer.alpha ?? 255) < 255);
    if (layer is BackdropFilterLayer && fading) out.add(layer);
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk(child, faded: fading);
      }
    }
  }

  for (final view in RendererBinding.instance.renderViews) {
    final root = view.debugLayer;
    if (root != null) walk(root, faded: false);
  }
  return out;
}

Widget _page(String title, void Function(BuildContext)? onContext) => Builder(
  builder: (BuildContext context) {
    onContext?.call(context);
    return MorphNavigationScaffold(
      title: title,
      slivers: [
        SliverList.builder(
          itemCount: 60,
          itemBuilder: (BuildContext context, int i) => Container(
            height: 44,
            color: i.isEven ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
          ),
        ),
      ],
    );
  },
);

void main() {
  testWidgets('the scroll edge effect fades without an opacity layer over '
      'its blur', (tester) async {
    tester.view.physicalSize = _screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MorphNavigationStack(home: _page('Root', (c) => root = c)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();

    var fading = 0;
    Future<void> frames(String when) async {
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        for (final effect in tester.widgetList<MorphScrollEdgeEffect>(
          find.byType(MorphScrollEdgeEffect),
        )) {
          if (effect.opacity > 0.01 && effect.opacity < 0.99) fading++;
        }
        expect(_blursUnderOpacity(), isEmpty, reason: '$when frame $i');
      }
    }

    Navigator.of(
      root,
    ).push(MorphNavigationRoute<void>(builder: (_) => _page('Alpha', null)));
    await tester.pump();
    await frames('push');
    await tester.pumpAndSettle();
    Navigator.of(root).pop();
    await tester.pump();
    await frames('pop');
    expect(fading, greaterThan(10), reason: 'the effect never faded');
  });
}
