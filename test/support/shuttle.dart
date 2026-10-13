import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/live.dart';

/// The Material inside a flight shuttle's surface: it hosts the ink and
/// the default text style and pins its own clock to zero, and its box is
/// the container's.
final Finder shuttleMaterial = find.byWidgetPredicate(
  (Widget w) => w is Material && w.animationDuration == Duration.zero,
);

/// The render object that draws the shuttle surface: its shape, color,
/// elevation and shadow, the nearest [RenderPhysicalShape] above
/// [shuttleMaterial].
RenderPhysicalShape shuttleSurface(WidgetTester tester, {Finder? material}) {
  RenderObject? node = tester.renderObject(material ?? shuttleMaterial);
  while (node != null && node is! RenderPhysicalShape) {
    node = node.parent;
  }
  return node! as RenderPhysicalShape;
}

/// The shape the shuttle surface draws this frame.
ShapeBorder shuttleShape(WidgetTester tester, {Finder? material}) =>
    (shuttleSurface(tester, material: material).clipper! as ShapeBorderClipper)
        .shape;

/// The colors every colored box under [finder] paints this frame, the
/// static ([ColoredBox]) and the live ones alike.
Iterable<Color> paintedBoxColors(WidgetTester tester, Finder finder) sync* {
  for (final Widget widget in tester.widgetList(finder)) {
    switch (widget) {
      case ColoredBox(:final Color color):
        yield color;
      case MorphLiveColoredBox():
        yield widget.colorOf();
    }
  }
}

/// Every colored box in the tree, static or live.
final Finder anyColoredBox = find.byWidgetPredicate(
  (Widget w) => w is ColoredBox || w is MorphLiveColoredBox,
);
