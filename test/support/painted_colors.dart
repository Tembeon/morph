import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';

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
