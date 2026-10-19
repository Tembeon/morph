import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/liquid_glass_render_scope.dart';
import 'package:morph/src/glass/renderer/renderer.dart';

/// The first shape of every liquid glass layer on screen that holds one,
/// in tree order: each stands for a layer that reads a backdrop on a
/// device.
///
/// flutter_test has no Impeller, so a layer paints no backdrop filter
/// there; a layer without shapes would paint none on a device either.
List<Element> _layerShapes() {
  final seen = <State<LiquidGlassLayer>>{};
  return [
    for (final shape in find.byType(LiquidGlass).evaluate())
      if (shape.findAncestorStateOfType<State<LiquidGlassLayer>>()
          case final layer? when seen.add(layer))
        shape,
  ];
}

/// How many liquid glass layers on screen hold a shape: the backdrop
/// filters a device paints for them.
int glassLayersWithShapes() => _layerShapes().length;

/// The backdrop key every liquid glass layer with a shape reads, in tree
/// order: null for a layer that takes a copy of its own.
List<BackdropKey?> glassBackdropKeys(WidgetTester tester) => [
  for (final shape in _layerShapes())
    shape.getInheritedWidgetOfExactType<LiquidGlassRenderScope>()?.backdropKey,
];
