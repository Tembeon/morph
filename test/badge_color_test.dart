import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/badge.dart';

Color _fill(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(MorphBadged),
      matching: find.byType(Container),
    ),
  );
  return (box.decoration! as ShapeDecoration).color!;
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  bool highContrast = false,
  MorphBadge badge = const MorphBadge.count(3),
}) => tester.pumpWidget(
  MediaQuery(
    data: MediaQueryData(highContrast: highContrast),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MorphTheme(
        data: MorphThemeData(brightness: brightness),
        child: Center(
          child: MorphBadged.glyph(
            badge: badge,
            glyphSize: const Size(24, 24),
            child: const SizedBox(width: 24, height: 24),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the default fill is the iOS 27 systemRed of the brightness '
      'and contrast', (WidgetTester tester) async {
    await _pump(tester, brightness: Brightness.light);
    expect(_fill(tester), const Color(0xFFFF383C));
    await _pump(tester, brightness: Brightness.dark);
    expect(_fill(tester), const Color(0xFFFF4245));
    await _pump(tester, brightness: Brightness.light, highContrast: true);
    expect(_fill(tester), const Color(0xFFE9152D));
    await _pump(tester, brightness: Brightness.dark, highContrast: true);
    expect(_fill(tester), const Color(0xFFFF6165));
  });

  testWidgets('a badge color wins over systemRed', (WidgetTester tester) async {
    await _pump(
      tester,
      brightness: Brightness.dark,
      badge: const MorphBadge.indicator(backgroundColor: Color(0xFF34C759)),
    );
    expect(_fill(tester), const Color(0xFF34C759));
  });
}
