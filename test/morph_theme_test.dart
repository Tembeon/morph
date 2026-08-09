import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';
import 'package:morph/src/skin.dart';

Widget host({MorphTheme? theme, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(extensions: <ThemeExtension<Object?>>[?theme]),
    builder: (BuildContext context, Widget? c) => MorphScope(child: c!),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('MorphSurfaceSpec / specOf', () {
    testWidgets('descendants read the declared spec and the flight model '
        'follows it', (WidgetTester tester) async {
      const MorphSurfaceSpec spec = MorphSurfaceSpec(
        shape: StadiumBorder(),
        color: Color(0xFF123456),
        elevation: 4,
      );
      MorphSurfaceSpec? seen;
      await tester.pumpWidget(
        host(
          child: MorphTag(
            id: 'pill',
            spec: spec,
            child: Builder(
              builder: (BuildContext context) {
                seen = MorphTag.specOf(context);
                return const SizedBox(width: 80, height: 40);
              },
            ),
          ),
        ),
      );
      expect(seen, spec);
      final MorphTagState tag = tester.state<MorphTagState>(
        find.byType(MorphTag),
      );
      expect(tag.shape, isA<StadiumBorder>());
      expect(tag.surfaceColor, const Color(0xFF123456));
      expect(tag.elevation, 4);
    });

    testWidgets('spec wins over the individual fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          child: const MorphTag(
            id: 'pill',
            spec: MorphSurfaceSpec(
              shape: CircleBorder(),
              color: Color(0xFF00FF00),
              elevation: 7,
            ),
            shape: StadiumBorder(),
            surfaceColor: Color(0xFFFF0000),
            elevation: 1,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      );
      final MorphTagState tag = tester.state<MorphTagState>(
        find.byType(MorphTag),
      );
      expect(tag.shape, isA<CircleBorder>());
      expect(tag.surfaceColor, const Color(0xFF00FF00));
      expect(tag.elevation, 7);
    });

    testWidgets('legacy fields surface through specOf unchanged', (
      WidgetTester tester,
    ) async {
      MorphSurfaceSpec? seen;
      await tester.pumpWidget(
        host(
          child: MorphTag(
            id: 'pill',
            shape: const StadiumBorder(),
            surfaceColor: const Color(0xFFABCDEF),
            elevation: 3,
            child: Builder(
              builder: (BuildContext context) {
                seen = MorphTag.specOf(context);
                return const SizedBox(width: 40, height: 40);
              },
            ),
          ),
        ),
      );
      expect(seen!.shape, isA<StadiumBorder>());
      expect(seen!.color, const Color(0xFFABCDEF));
      expect(seen!.elevation, 3);
    });
  });

  group('MorphTargetSpec surface unification', () {
    test('surface wins over the individual fields, mirroring MorphTag', () {
      const MorphSurfaceSpec panel = MorphSurfaceSpec(
        shape: StadiumBorder(),
        color: Color(0xFF112233),
        elevation: 12,
      );
      final MorphTargetSpec spec = MorphTargetSpec.dialog(surface: panel);
      expect(spec.shape, isA<StadiumBorder>());
      expect(spec.surfaceColor, const Color(0xFF112233));
      expect(spec.elevation, 12);
      expect(spec.surface, panel);
    });

    test('without a surface the factory defaults hold', () {
      final MorphTargetSpec spec = MorphTargetSpec.dialog();
      expect(spec.shape, isA<RoundedRectangleBorder>());
      expect(spec.elevation, 24);
    });

    testWidgets('dialog content reads the target model via specOf', (
      WidgetTester tester,
    ) async {
      const MorphSurfaceSpec panel = MorphSurfaceSpec(
        shape: StadiumBorder(),
        color: Color(0xFF445566),
        elevation: 9,
      );
      MorphSurfaceSpec? seen;
      MorphFlight? flight;
      await tester.pumpWidget(
        host(
          child: MorphTag(
            id: 'pill',
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () {
                  flight = showMorph(
                    context,
                    from: 'pill',
                    target: MorphTargetSpec.dialog(surface: panel),
                    builder: (BuildContext context, MorphFlight flight) {
                      seen = MorphTag.specOf(context);
                      return const Text('dialog');
                    },
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(seen, panel);
      flight!.abort();
    });
  });

  group('MorphTheme resolution (explicit > theme > builtin)', () {
    testWidgets('flight motion falls back to the theme motion', (
      WidgetTester tester,
    ) async {
      MorphFlight? flight;
      await tester.pumpWidget(
        host(
          theme: const MorphTheme(motion: .glacial),
          child: MorphTag(
            id: 'pill',
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () {
                  flight = showMorphDialog(
                    context,
                    from: 'pill',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('dialog'),
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(flight!.controller.motion, MorphMotion.glacial);
      flight!.abort();
    });

    testWidgets('an explicit motion wins over the theme', (
      WidgetTester tester,
    ) async {
      MorphFlight? flight;
      await tester.pumpWidget(
        host(
          theme: const MorphTheme(motion: .glacial),
          child: MorphTag(
            id: 'pill',
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () {
                  flight = showMorphDialog(
                    context,
                    from: 'pill',
                    motion: .fast,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('dialog'),
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(flight!.controller.motion, MorphMotion.fast);
      flight!.abort();
    });

    testWidgets('MorphSkin picks the theme liquid style', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          theme: const MorphTheme(skinStyle: .goo),
          child: const SizedBox(
            width: 300,
            height: 200,
            child: MorphSkin(
              color: Color(0xFF2A2440),
              pieces: <MorphPiece>[
                MorphPiece(id: 'a', rect: .fromLTWH(20, 20, 100, 60)),
              ],
            ),
          ),
        ),
      );
      final RenderMorphSkin group = tester.renderObject<RenderMorphSkin>(
        find.byType(MorphSkin),
      );
      expect(group.k, MorphSkinStyle.goo.blend);
      expect(group.cell, MorphSkinStyle.goo.cell);
    });

    test('copyWith and lerp behave', () {
      const MorphTheme a = MorphTheme(bumpScale: 0.2, maxScrimOpacity: 0.2);
      const MorphTheme b = MorphTheme(bumpScale: 0.6, maxScrimOpacity: 0.6);
      expect(a.copyWith(bumpScale: 1).bumpScale, 1);
      expect(a.copyWith(bumpScale: 1).maxScrimOpacity, 0.2);
      final MorphTheme mid = a.lerp(b, 0.5);
      expect(mid.bumpScale, closeTo(0.4, 1e-9));
      expect(mid.maxScrimOpacity, closeTo(0.4, 1e-9));
    });

    test('runtime-built profiles and styles compare by value', () {
      // MorphTheme compares by ==: a runtime-tuned profile that only
      // compared by identity would turn every ThemeData rebuild into
      // "a theme change" and every motion re-install into a spurious
      // retarget.
      // Deliberately non-const (the runtime-built name forbids it):
      // canonicalized instances would be identical and prove nothing.
      final String tuned = 'tuned-${1 + 1}';
      MorphMotion profile() => MorphMotion(
        name: tuned,
        openMotion: const CupertinoMotion.smooth(
          duration: Duration(milliseconds: 300),
        ),
        closeMotion: const CupertinoMotion(
          duration: Duration(milliseconds: 500),
          bounce: 0.2,
        ),
        closeVelocityHint: -1,
      );
      expect(identical(profile(), profile()), isFalse);
      expect(profile(), profile());
      expect(profile().hashCode, profile().hashCode);
      expect(profile(), isNot(MorphMotion.normal));

      MorphSkinStyle style() =>
          MorphSkinStyle(name: tuned, blend: 30, cell: 5);
      expect(style(), style());
      expect(style(), isNot(MorphSkinStyle.goo));
      expect(
        MorphTheme(motion: profile(), skinStyle: style()),
        MorphTheme(motion: profile(), skinStyle: style()),
      );
    });
  });
}
