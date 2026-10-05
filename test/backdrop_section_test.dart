import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// The backdrop keys of every filter painted on screen (null for a
/// filter that takes a copy of its own).
Set<BackdropKey?> _keys() {
  final out = <BackdropKey?>{};
  void walk(Layer layer) {
    if (layer is BackdropFilterLayer) out.add(layer.backdropKey);
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk(child);
      }
    }
  }

  for (final view in RendererBinding.instance.renderViews) {
    final root = view.debugLayer;
    if (root != null) walk(root);
  }
  return out;
}

Widget _button(String label) => MorphGlassButton(
  key: ValueKey<String>(label),
  onPressed: () {},
  child: Text(label),
);

void main() {
  testWidgets('a section in its own BackdropGroup reads a copy of its own', (
    tester,
  ) async {
    final page = BackdropKey();
    final section = BackdropKey();
    Future<Set<BackdropKey?>> keys({required bool own}) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MorphAdaptiveGlass(
            tier: MorphGlassTier.frosted,
            child: BackdropGroup(
              backdropKey: page,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _button('first'),
                    const ColoredBox(
                      color: Color(0xFFFF3B30),
                      child: SizedBox(height: 40, width: 200),
                    ),
                    if (own)
                      BackdropGroup(
                        backdropKey: section,
                        child: _button('second'),
                      )
                    else
                      _button('second'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      tester.takeException();
      await tester.pump();
      return _keys();
    }

    expect(await keys(own: false), {page});
    expect(await keys(own: true), {page, section});
  });
}
