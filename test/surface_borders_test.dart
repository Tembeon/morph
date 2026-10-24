import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:morph/morph.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_border.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

const _red = Color(0xFFFF0000);
const _border = BorderSide(color: _red, width: 2);
const _borders = MorphSurfaceBorders.all(_border);
const _liquidBorders = MorphSurfaceBorders(track: _border);

MorphGlassSurface _surface(
  MorphGlassKind kind, {
  double opacity = 1,
  double left = 0,
}) => MorphGlassSurface(
  kind: kind,
  shape: RRect.fromRectAndRadius(
    Rect.fromLTWH(left, 0, 80, 40),
    const Radius.circular(20),
  ),
  color: const Color(0xFFFFFFFF),
  brightness: Brightness.light,
  opacity: opacity,
  glass: kind != MorphGlassKind.track,
);

void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  test('borders are opt-in and participate in theme and renderer equality', () {
    expect(const MorphSurfaceBorders().isEmpty, isTrue);
    expect(
      const MorphSurfaceBorders.all(
        BorderSide(color: Color(0x00000000)),
      ).isEmpty,
      isTrue,
    );
    expect(_borders.copyWith(menu: BorderSide.none), isNot(_borders));
    const theme = MorphThemeData();
    final bordered = theme.copyWith(borders: _borders);
    expect(bordered, isNot(theme));
    expect(bordered.copyWith(), bordered);
    expect(theme.copyWith(liquidBorders: _liquidBorders), isNot(theme));
    expect(
      const GlassBuiltInPainter(liquidBorders: _liquidBorders),
      isNot(const GlassBuiltInPainter()),
    );
    const painter = GlassBuiltInPainter(tier: .flat);
    expect(painter.copyWith(borders: _borders), isNot(painter));
    expect(
      painter.copyWith(borders: _borders).copyWith(tier: .liquid).borders,
      _borders,
    );
  });

  for (final kind in MorphGlassKind.values) {
    testWidgets(
      '${kind.name} border follows opacity and the surface coordinates',
      (tester) async {
        final channel = MorphGlassChannel(
          MorphGlassFrame([_surface(kind, opacity: .5, left: 20)]),
        );
        addTearDown(channel.dispose);
        final painter = MorphSurfaceBorderPainter(
          source: channel,
          borders: _borders,
          tier: .flat,
          mode: .surface,
        );
        await tester.pumpWidget(
          Center(
            child: SizedBox(
              width: 80,
              height: 40,
              child: CustomPaint(painter: painter),
            ),
          ),
        );
        final expected = paints;
        expected.rrect(
          rrect: const RRect.fromLTRBXY(1, 1, 79, 39, 19, 19),
          color: _red.withValues(alpha: .5),
          style: PaintingStyle.stroke,
          strokeWidth: 2,
        );
        expect(tester.renderObject(find.byType(CustomPaint)), expected);
      },
    );
  }

  testWidgets(
    'fused menu draws its shared outline once and fades with the body',
    (tester) async {
      final path = Path();
      path.addRRect(const RRect.fromLTRBXY(0, 0, 80, 40, 12, 12));
      final channel = MorphGlassChannel(
        MorphGlassFrame([
          _surface(.button, opacity: .25),
          _surface(.menu, opacity: .5),
        ], outline: MorphGlassOutline(path)),
      );
      addTearDown(channel.dispose);
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 80,
            height: 40,
            child: CustomPaint(
              painter: MorphSurfaceBorderPainter(
                source: channel,
                borders: const MorphSurfaceBorders(menu: _border),
                tier: .flat,
                mode: .body,
              ),
            ),
          ),
        ),
      );
      final expected = paints;
      expected.path(
        color: _red.withValues(alpha: .25),
        style: PaintingStyle.stroke,
        strokeWidth: 4,
      );
      expect(tester.renderObject(find.byType(CustomPaint)), expected);
      channel.push(
        MorphGlassFrame([
          _surface(.menu, opacity: 0),
        ], outline: MorphGlassOutline(path)),
      );
      await tester.pump();
      expect(
        tester.renderObject(find.byType(CustomPaint)),
        paintsExactlyCountTimes(#drawPath, 0),
      );
    },
  );

  testWidgets(
    'geometry ticks repaint borders without rebuilding the glass host',
    (tester) async {
      final geometry = ValueNotifier(0.0);
      addTearDown(geometry.dispose);
      var frames = 0;
      var builds = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: .ltr,
          child: Center(
            child: SizedBox(
              width: 120,
              height: 40,
              child: Builder(
                builder: (context) {
                  builds++;
                  return MorphGlassHost(
                    mode: .layer,
                    painter: const GlassBuiltInPainter(
                      tier: .flat,
                      borders: _borders,
                    ),
                    frames: geometry,
                    frame: () {
                      frames++;
                      return MorphGlassFrame([
                        _surface(.track, left: geometry.value),
                      ]);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      final contour = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is MorphSurfaceBorderPainter,
      );
      expect(contour, findsOneWidget);
      final element = contour.evaluate().single;
      geometry.value = 20;
      await tester.pump();
      expect(builds, 1);
      expect(frames, greaterThan(1));
      expect(contour.evaluate().single, same(element));
      final expected = paints;
      expected.rrect();
      expected.rrect(
        rrect: const RRect.fromLTRBXY(21, 1, 99, 39, 19, 19),
        color: _red,
        style: PaintingStyle.stroke,
      );
      expect(tester.renderObject(contour), expected);
    },
  );

  testWidgets(
    'nested theme inherits and can explicitly clear contours without replacing glass',
    (tester) async {
      late GlassBuiltInPainter inherited;
      late GlassBuiltInPainter cleared;
      await tester.pumpWidget(
        MorphTheme(
          data: const MorphThemeData(
            glass: .tier(.flat),
            borders: _borders,
            liquidBorders: _liquidBorders,
          ),
          child: MorphTheme(
            data: const MorphThemeData(tint: _red),
            child: Builder(
              builder: (context) {
                inherited =
                    MorphGlassScope.maybeOf(context)! as GlassBuiltInPainter;
                return MorphTheme(
                  data: const MorphThemeData(
                    borders: MorphSurfaceBorders(),
                    liquidBorders: MorphSurfaceBorders(),
                  ),
                  child: Builder(
                    builder: (context) {
                      cleared =
                          MorphGlassScope.maybeOf(context)!
                              as GlassBuiltInPainter;
                      return const SizedBox();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(inherited.borders, _borders);
      expect(inherited.liquidBorders, _liquidBorders);
      expect(cleared.borders.isEmpty, isTrue);
      expect(cleared.liquidBorders!.isEmpty, isTrue);
      expect(cleared.tier, inherited.tier);
    },
  );

  testWidgets('a liquid request using flat fallback keeps the flat contours', (
    tester,
  ) async {
    isLocalTest = false;
    addTearDown(() => isLocalTest = true);
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library == 'morph glass' &&
          details.exception.toString().contains(
            'Impeller shader filters are unavailable',
          )) {
        return;
      }
      previous?.call(details);
    };
    try {
      await tester.runAsync(MorphTheme.precacheGlass);
    } finally {
      FlutterError.onError = previous;
    }
    const renderer = GlassBuiltInPainter(
      tier: .liquid,
      borders: _borders,
      liquidBorders: MorphSurfaceBorders(),
    );
    expect(renderer.effectiveTier, MorphGlassTier.flat);
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Center(
          child: SizedBox(
            width: 80,
            height: 40,
            child: Builder(
              builder: (context) =>
                  renderer.buildSurface(context, _surface(.button)),
            ),
          ),
        ),
      ),
    );
    final contour = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is MorphSurfaceBorderPainter,
      ),
    );
    expect(
      (contour.foregroundPainter! as MorphSurfaceBorderPainter).borders,
      _borders,
    );
  });

  testWidgets('menu overlay carries the source contours on both tiers', (
    tester,
  ) async {
    final controller = MorphMenuPresentationController();
    addTearDown(controller.dispose);
    for (final tier in MorphGlassTier.values) {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MorphTheme(
            data: MorphThemeData(
              glass: MorphGlassRenderer.tier(tier),
              borders: _borders,
              liquidBorders: _liquidBorders,
            ),
            child: child!,
          ),
          home: Center(
            child: MorphMenuButton(
              controller: controller,
              menu: [
                MorphMenuWidget(
                  builder: (context) {
                    final painter =
                        MorphGlassScope.maybeOf(context)!
                            as GlassBuiltInPainter;
                    expect(painter.borders, _borders);
                    expect(painter.liquidBorders, _liquidBorders);
                    return const Text('Action');
                  },
                ),
              ],
            ),
          ),
        ),
      );
      controller.open();
      await tester.pumpAndSettle();
      expect(find.text('Action'), findsOneWidget);
      controller.close();
      await tester.pumpAndSettle();
    }
  });
}
