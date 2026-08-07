import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/liquid_field.dart';

import 'liquid_geometry_scenes.dart';

// One-off dump helper: prints the snapshot table for
// liquid_geometry_golden_test.dart. Run manually when the geometry is
// INTENTIONALLY changed, paste the output, review the diff in code
// review like any golden:
//
//   flutter test test/golden_dump_helper.dart
void main() {
  test('dump geometry snapshots', () {
    for (final MapEntry<String, LiquidField> scene in goldenScenes.entries) {
      final List<List<Offset>> loops = liquidContours(scene.value, cell: 4);
      // ignore: avoid_print
      print("'${scene.key}': <LoopSnapshot>[");
      for (final List<Offset> loop in loops) {
        double area = 0;
        double cx = 0;
        double cy = 0;
        Rect bounds = const .fromLTRB(
          .infinity,
          .infinity,
          .negativeInfinity,
          .negativeInfinity,
        );
        for (int i = 0; i < loop.length; i++) {
          final Offset a = loop[i];
          final Offset b = loop[(i + 1) % loop.length];
          area += a.dx * b.dy - b.dx * a.dy;
          cx += a.dx;
          cy += a.dy;
          bounds = .fromLTRB(
            a.dx < bounds.left ? a.dx : bounds.left,
            a.dy < bounds.top ? a.dy : bounds.top,
            a.dx > bounds.right ? a.dx : bounds.right,
            a.dy > bounds.bottom ? a.dy : bounds.bottom,
          );
        }
        area = (area / 2).abs();
        cx /= loop.length;
        cy /= loop.length;
        // ignore: avoid_print
        print(
          '  LoopSnapshot(area: ${area.toStringAsFixed(1)}, '
          'centroid: Offset(${cx.toStringAsFixed(1)}, ${cy.toStringAsFixed(1)}), '
          'bounds: Rect.fromLTRB(${bounds.left.toStringAsFixed(1)}, '
          '${bounds.top.toStringAsFixed(1)}, ${bounds.right.toStringAsFixed(1)}, '
          '${bounds.bottom.toStringAsFixed(1)})),',
        );
      }
      // ignore: avoid_print
      print('],');
    }
  });
}
