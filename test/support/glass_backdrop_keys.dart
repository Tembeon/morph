import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/liquid_glass_render_scope.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';

/// Every liquid glass layer on screen that paints a shape, in tree order,
/// with the backdrop key it reads: each stands for a backdrop filter a
/// device paints. A layer whose shapes a plane's pass paints
/// ([GeometryRenderLink.lendTo]) paints none; the pass paints them.
///
/// flutter_test has no Impeller, so a layer paints no backdrop filter
/// there; a layer without shapes would paint none on a device either.
List<BackdropKey?> _painting({Finder? within}) => [
  for (final element
      in (within == null
              ? find.byType(InheritedGeometryRenderLink)
              : find.descendant(
                  of: within,
                  matching: find.byType(InheritedGeometryRenderLink),
                ))
          .evaluate())
    if ((element.widget as InheritedGeometryRenderLink).link.shapes.isNotEmpty)
      element
          .getInheritedWidgetOfExactType<LiquidGlassRenderScope>()
          ?.backdropKey,
];

/// How many liquid glass layers on screen, or [within] what it finds,
/// paint a shape: the backdrop filters a device paints for them.
int glassLayersWithShapes({Finder? within}) => _painting(within: within).length;

/// The backdrop key every liquid glass layer that paints a shape reads, in
/// tree order: null for a layer that takes a copy of its own.
List<BackdropKey?> glassBackdropKeys(WidgetTester tester) => _painting();
