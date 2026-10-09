import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/widgets/glass_outline.dart';

void main() {
  test('GPU descriptor preserves its grid under fractional translation', () {
    final path = Path();
    final shapes = [
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, 20, 60, 30),
        const Radius.circular(7),
      ),
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 24, 35, 24),
        const Radius.circular(12),
      ),
    ];
    for (final shape in shapes) {
      path.addRRect(shape);
    }
    final field = GlassField.fromBoxes(
      shapes: shapes,
      spacing: 14,
      cols: 29,
      rows: 15,
      origin: const Offset(-28, 2),
      step: 4,
      outline: path,
    );
    final moved = field.shift(const Offset(0.375, -48.125));
    expect(field.samples, isEmpty);
    expect(moved.analytic, same(field.analytic));
    expect(moved.origin, field.origin + const Offset(0.375, -48.125));
    expect(moved.bounds, field.bounds.shift(const Offset(0.375, -48.125)));
    expect(
      moved.outline!.getBounds(),
      path.getBounds().shift(const Offset(0.375, -48.125)),
    );
    expect(field.analytic!.boxes.take(5), [48, 33, 30, 15, 7]);
    expect(field.analytic!.boxes.skip(8).take(5), [88.5, 34, 17.5, 12, 12]);
  });

  test('opt-in fusion keeps CPU contours and falls back above four boxes', () {
    final shapes = [
      for (var i = 0; i < 5; i++)
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * 32, 0, 36, 30),
          const Radius.circular(8),
        ),
    ];
    final small = morphGlassContainerOutline(shapes.take(3).toList(), 12);
    final field = morphGlassOutlineField(small)!;
    expect(field.analytic != null, GlassField.gpuFusion);
    expect(field.samples.isEmpty, GlassField.gpuFusion);
    final silhouette = morphGlassContainerOutline(
      shapes.take(3).toList(),
      12,
      withField: false,
    );
    expect(small.path.getBounds(), silhouette.path.getBounds());
    final opticalMetrics = small.path.computeMetrics().toList();
    final flatMetrics = silhouette.path.computeMetrics().toList();
    expect(opticalMetrics.length, flatMetrics.length);
    for (var i = 0; i < opticalMetrics.length; i++) {
      expect(opticalMetrics[i].length, flatMetrics[i].length);
      for (var at = 0.0; at < opticalMetrics[i].length; at += 0.5) {
        expect(
          opticalMetrics[i].getTangentForOffset(at)!.position,
          flatMetrics[i].getTangentForOffset(at)!.position,
        );
      }
    }
    final large = morphGlassOutlineField(
      morphGlassContainerOutline(shapes, 12),
    )!;
    expect(large.analytic, isNull);
    expect(large.samples.length, large.cols * large.rows * 4);
  });
}
