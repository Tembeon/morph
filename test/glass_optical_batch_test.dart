import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_liquid_draw.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

class _ReadyRenderer extends MorphGlassRenderer {
  const _ReadyRenderer();

  @override
  MorphGlassTier get effectiveTier => MorphGlassTier.liquid;
}

void main() {
  const renderer = _ReadyRenderer();
  MorphGlassFrame frame({
    double firstX = 0,
    double opacity = 1,
    bool shadow = false,
  }) => MorphGlassFrame([
    MorphGlassSurface(
      kind: MorphGlassKind.bar,
      shape: RRect.fromRectAndRadius(
        Rect.fromLTWH(firstX, 0, 48, 48),
        const Radius.circular(24),
      ),
      color: const Color(0xFF222222),
      brightness: Brightness.dark,
      opacity: opacity,
      shadows: shadow ? const [BoxShadow(blurRadius: 5)] : null,
    ),
    const MorphGlassSurface(
      kind: MorphGlassKind.bar,
      shape: RRect.fromLTRBXY(200, 0, 248, 48, 24, 24),
      color: Color(0xFF334455),
      brightness: Brightness.dark,
    ),
    const MorphGlassSurface(
      kind: MorphGlassKind.bar,
      shape: RRect.fromLTRBXY(255, 0, 303, 48, 24, 24),
      color: Color(0xFF223344),
      brightness: Brightness.dark,
    ),
  ], spacing: 16);

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    morphDebugOpticalBatch = true;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    morphDebugOpticalBatch = false;
  });

  test(
    'disjoint compatible chrome qualifies and overlap changes live structure',
    () {
      final before = frame();
      final after = frame(firstX: 140);
      expect(morphCanBatchOptics(renderer, before.parts), isTrue);
      expect(morphCanBatchOptics(renderer, after.parts), isFalse);
      expect(
        renderer.structureOf(MorphGlassMode.layer, before, content: true),
        isNot(renderer.structureOf(MorphGlassMode.layer, after, content: true)),
      );
    },
  );

  test(
    'different visibility and exterior shadows retain independent hosts',
    () {
      expect(morphCanBatchOptics(renderer, frame(opacity: .5).parts), isFalse);
      expect(morphCanBatchOptics(renderer, frame(shadow: true).parts), isFalse);
    },
  );

  test('sparse chrome union retains independent hosts', () {
    expect(morphCanBatchOptics(renderer, frame(firstX: -1000).parts), isFalse);
  });

  test('overlay translation preserves independently owned node grids', () {
    final nodes = Float32List(16);
    final field = GlassField(
      samples: nodes,
      cols: 2,
      rows: 2,
      origin: const Offset(4, 7),
      step: 3,
    );
    final batch = GlassField.withOverlays([field], Path());
    final shifted = batch.shift(const Offset(10, 20));
    expect(shifted.overlays.single.samples, same(nodes));
    expect(shifted.overlays.single.origin, const Offset(14, 27));
    expect(shifted.overlays.single.step, 3);
    expect(field.origin, const Offset(4, 7));
  });
}
