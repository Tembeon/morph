import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Every text on screen that fell through to the gallery's fallback text
/// style instead of taking its style from a morph surface.
List<String> unstyledTexts() => [
  for (final element in find.byType(RichText).evaluate())
    if ((element.widget as RichText).text.style?.debugLabel?.contains(
          galleryFallbackTextLabel,
        ) ??
        false)
      (element.widget as RichText).text.toPlainText(),
];
