import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/widgets.dart';

/// Menus from 120 x 80 to 300 x 600 over a 48 pt button that overlaps
/// them, touches them, is bridged by the blur, is far, sits at a corner,
/// touches a side or lies inside, at radii from the plain-union cutoff to
/// the measured maximum.
List<(RRect, RRect, double)> _sweep() {
  const sizes = [
    Size(120, 80),
    Size(180, 140),
    Size(250, 320),
    Size(260, 440.5),
    Size(300, 600),
  ];
  const radii = [1.0, 1.7, 2.0, 4.0, 6.0, 6.5, 10.0, 12.0, 15.3, 20.0];
  final cases = <(RRect, RRect, double)>[];
  for (final size in sizes) {
    final menu = RRect.fromRectAndRadius(
      const Offset(40.25, 100.6) & size,
      Radius.circular(size.shortestSide / 2 < 32 ? size.shortestSide / 2 : 32),
    );
    final cx = menu.center.dx + 0.37;
    final bottom = menu.bottom;
    final centers = [
      Offset(cx, bottom - 30),
      Offset(cx, bottom + 24),
      Offset(cx, bottom + 24 + 7.3),
      Offset(cx, bottom + 24 + 61.9),
      Offset(menu.right + 10.1, bottom + 20.4),
      Offset(menu.left - 23.7, menu.center.dy),
      Offset(menu.center.dx - 3.1, menu.center.dy + 2.2),
    ];
    for (final center in centers) {
      final source = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 48, height: 48),
        const Radius.circular(24),
      );
      for (final radius in radii) {
        cases.add((menu, source, radius));
      }
    }
  }
  return cases;
}

/// The outlines of the fused menu bodies the glass hosts on screen draw.
List<MorphGlassOutline> _menuOutlines(WidgetTester tester) => [
  for (final host in tester.widgetList<MorphGlassHost>(
    find.byType(MorphGlassHost),
  ))
    if (host.frame() case MorphGlassFrame(
      :final outline?,
      :final surfaces,
    ) when surfaces.any((s) => s.kind == MorphGlassKind.menu))
      outline,
];

class _Painter extends MorphGlassPainter {
  const _Painter();

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) =>
      const SizedBox.expand();
}

class _FlatSubclass extends MorphGlassRenderer {
  const _FlatSubclass() : super(tier: MorphGlassTier.flat);
}

void main() {
  test('the edge alone is the full fusion edge, crossing for crossing', () {
    final cases = _sweep();
    var crossings = 0;
    for (final (menu, source, radius) in cases) {
      final full = morphMenuSilhouetteParts(menu, source, radius);
      final edge = morphMenuSilhouetteParts(
        menu,
        source,
        radius,
        withField: false,
      );
      final reason = '$menu $source at $radius';
      expect(full.hasField, isTrue, reason: reason);
      expect(edge.hasField, isFalse, reason: reason);
      expect(edge.samples, isEmpty, reason: reason);
      expect(edge.loops, full.loops, reason: reason);
      expect(edge.points.length, full.points.length, reason: reason);
      for (var k = 0; k < full.points.length; k++) {
        if (edge.points[k] != full.points[k]) {
          fail('crossing coordinate $k differs: $reason');
        }
      }
      crossings += full.points.length ~/ 2;
    }
    expect(cases.length, 350);
    expect(crossings, greaterThan(10000));
  });

  test('an edge-only outline carries no field, a full one does', () {
    final menu = RRect.fromLTRBR(70, 200, 330, 640, const Radius.circular(32));
    final button = RRect.fromLTRBR(
      177,
      652,
      225,
      700,
      const Radius.circular(24),
    );
    final edge = morphMenuSilhouette(menu, button, 10, withField: false);
    final full = morphMenuSilhouette(menu, button, 10);
    expect(morphGlassOutlineField(edge), isNull);
    expect(morphGlassOutlineShapes(edge), isNull);
    expect(morphGlassOutlineField(full), isNotNull);
  });

  group('the fusion cache', () {
    setUp(() => MorphMenuFusion.debugPrefetch = false);
    tearDown(() => MorphMenuFusion.debugPrefetch = null);

    final menu = RRect.fromLTRBR(70, 200, 330, 640, const Radius.circular(32));
    final button = RRect.fromLTRBR(
      177,
      652,
      225,
      700,
      const Radius.circular(24),
    );

    test('never serves an edge to a request for the field', () {
      final fusion = MorphMenuFusion();
      final edge = fusion.outline(menu, button, 10, withField: false)!;
      expect(morphGlassOutlineField(edge), isNull);
      final full = fusion.outline(menu, button, 10)!;
      expect(morphGlassOutlineField(full), isNotNull);
      expect(identical(fusion.outline(menu, button, 10), full), isTrue);
    });

    test('serves the full outline to a request for the edge', () {
      final fusion = MorphMenuFusion();
      final full = fusion.outline(menu, button, 10)!;
      final edge = fusion.outline(menu, button, 10, withField: false)!;
      expect(identical(edge, full), isTrue);
    });

    test('keeps an edge for repeated edge requests', () {
      final fusion = MorphMenuFusion();
      final edge = fusion.outline(menu, button, 10, withField: false)!;
      expect(
        identical(fusion.outline(menu, button, 10, withField: false), edge),
        isTrue,
      );
    });
  });

  test('only the flat renderer and no painter take the edge alone', () {
    expect(morphGlassShadesOutlines(null), isFalse);
    expect(
      morphGlassShadesOutlines(
        const MorphGlassRenderer(tier: MorphGlassTier.flat),
      ),
      isFalse,
    );
    expect(
      morphGlassShadesOutlines(
        const MorphGlassRenderer(tier: MorphGlassTier.fake),
      ),
      isTrue,
    );
    expect(morphGlassShadesOutlines(const MorphGlassRenderer()), isTrue);
    expect(morphGlassShadesOutlines(const _FlatSubclass()), isTrue);
    expect(morphGlassShadesOutlines(const _Painter()), isTrue);
  });

  for (final (tier, shaded) in [
    (MorphGlassTier.flat, false),
    (MorphGlassTier.liquid, true),
  ]) {
    testWidgets('a ${tier.name} menu opens with${shaded ? '' : 'out'} '
        'the field of its silhouette', (WidgetTester tester) async {
      isLocalTest = true;
      addTearDown(() => isLocalTest = false);
      await tester.pumpWidget(
        MaterialApp(
          home: MorphGlass(
            painter: MorphGlassRenderer(tier: tier),
            child: const Scaffold(
              body: Center(
                child: MorphMenuButton(
                  items: [
                    MorphMenuItem(title: 'One'),
                    MorphMenuItem(title: 'Two'),
                    MorphMenuItem(title: 'Three'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MorphMenuButton));
      var fused = 0;
      var withField = 0;
      for (var frame = 0; frame < 90; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        for (final outline in _menuOutlines(tester)) {
          if (morphGlassOutlineShapes(outline) != null) continue;
          fused++;
          if (morphGlassOutlineField(outline) != null) withField++;
        }
      }
      expect(fused, greaterThan(10));
      expect(withField, shaded ? fused : 0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
