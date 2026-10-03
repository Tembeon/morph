import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

Map<String, Object?> _json(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

List<Map<String, Object?>> _states(String name) => [
  for (final s
      in ((_json('test/fixtures/ios27-device/bars/scroll-edge.json')['states']!
              as Map)[name]!
          as List))
    (s as Map).cast<String, Object?>(),
];

Map<String, Object?>? _filter(Map<String, Object?> state, String type) {
  for (final f in (state['filters'] as List? ?? const [])) {
    final m = (f as Map).cast<String, Object?>();
    if (m['type'] == type) return m;
  }
  return null;
}

void main() {
  group('scroll edge effect against the device layers', () {
    test('hard: blur, saturation and brightness, uniform fade, hairline', () {
      final states = _states('hard-light');
      final pocket = states.lastWhere((s) => _filter(s, 'colorMatrix') != null);
      final look = MorphScrollEdgeEffectThemeData.light;
      expect(
        _filter(pocket, 'variableBlur')!['inputRadius'],
        look.hardBlurRadius,
      );
      final matrix =
          (_filter(pocket, 'colorMatrix')!['inputColorMatrix']! as List)
              .cast<num>();
      final ours = look.hardColorMatrix;
      for (var i = 0; i < 20; i++) {
        final expected = i % 5 == 4 ? matrix[i] * 255 : matrix[i];
        expect(ours[i], moreOrLessEquals(expected.toDouble(), epsilon: 2e-3));
      }
      final replay = states.lastWhere(
        (s) =>
            s['cls'] == 'CABackdropLayer' &&
            (s['path']! as String).endsWith('L0/L0') &&
            (s['h']! as num) > 0,
      );
      expect(replay['a'], look.fadeOpacity);
      final line = states.firstWhere(
        (s) => (s['path']! as String).endsWith('L0/L2'),
      );
      expect((line['bg']! as List).last, moreOrLessEquals(0.1));
      expect(look.separatorColor.a, moreOrLessEquals(0.1, epsilon: 0.002));
      expect(line['h'], 0.33);
    });

    test('soft: a lighter blur over a band 40 points past the bar', () {
      final states = _states('soft-light');
      final pocket = states.lastWhere(
        (s) => _filter(s, 'variableBlur') != null,
      );
      final look = MorphScrollEdgeEffectThemeData.light;
      expect(
        _filter(pocket, 'variableBlur')!['inputRadius'],
        look.softBlurRadius,
      );
      expect(pocket['h'], 62 + 54 + look.softOverhang);
      final mask = states.lastWhere(
        (s) => s['gse'] != null && (s['h']! as num) > 0,
      );
      expect((mask['gse']! as List)[1], look.softFadeStart);
    });

    test('dark fades further toward black', () {
      final states = _states('automatic-dark');
      final replay = states.lastWhere(
        (s) =>
            s['cls'] == 'CABackdropLayer' &&
            (s['path']! as String).endsWith('L0/L0') &&
            (s['h']! as num) > 100,
      );
      expect(replay['a'], MorphScrollEdgeEffectThemeData.dark.fadeOpacity);
    });

    testWidgets('the band ends at the bar, or 40 past it when soft', (
      tester,
    ) async {
      for (final style in MorphScrollEdgeEffectStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.red)),
                MorphScrollEdgeEffect(extent: 116, style: style),
              ],
            ),
          ),
        );
        final band = tester.getSize(find.byType(BackdropFilter));
        expect(
          band.height,
          style == MorphScrollEdgeEffectStyle.soft ? 156 : 116,
        );
      }
    });
  });
}
