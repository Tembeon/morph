import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

/// Whether [painter] drew a stroked rounded rectangle whose color passes
/// [test]: the rim of a lifted lens.
PaintPattern _drawsRim(bool Function(Color color) test) {
  final pattern = paints;
  pattern.something((Symbol method, List<Object?> arguments) {
    if (method != #drawRRect) return false;
    final paint = arguments[1]! as Paint;
    return paint.style == PaintingStyle.stroke && test(paint.color);
  });
  return pattern;
}

bool _light(Color c) => c.r > 0.9 && c.g > 0.9 && c.b > 0.9 && c.a > 0.15;

bool _dark(Color c) => c.r < 0.1 && c.g < 0.1 && c.b < 0.1 && c.a > 0.1;

Widget _host(Widget child, Brightness brightness) => MediaQuery(
  data: MediaQueryData(platformBrightness: brightness),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

Finder _painter(Type control) => find
    .descendant(of: find.byType(control), matching: find.byType(CustomPaint))
    .last;

void main() {
  for (final (brightness, rim) in [
    (Brightness.dark, _light),
    (Brightness.light, _dark),
  ]) {
    testWidgets(
      'a held slider thumb keeps a visible rim in ${brightness.name}',
      (tester) async {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 300,
              child: MorphSlider(value: 0, onChanged: (_) {}),
            ),
            brightness,
          ),
        );
        final r = tester.getRect(find.byType(MorphSlider));
        final gesture = await tester.startGesture(
          Offset(r.left + 18.5, r.center.dy),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(_painter(MorphSlider), _drawsRim(rim));
        await gesture.up();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a held switch knob keeps a visible rim in ${brightness.name}',
      (tester) async {
        await tester.pumpWidget(
          _host(MorphSwitch(value: false, onChanged: (_) {}), brightness),
        );
        final r = tester.getRect(find.byType(MorphSwitch));
        final gesture = await tester.startGesture(
          r.centerLeft + const Offset(15, 0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(_painter(MorphSwitch), _drawsRim(rim));
        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  }
}
