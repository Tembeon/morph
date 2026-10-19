import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/glass_device.dart';
import 'package:morph/src/widgets/glass_tier.dart';
import 'package:morph/widgets.dart';

void main() {
  setUp(() => morphGlassDeviceClassProbe = () => MorphGlassDeviceClass.capable);
  tearDown(() => morphGlassDeviceClassProbe = morphProbeGlassDeviceClass);

  testWidgets('controls with no theme above them get no painter', (
    tester,
  ) async {
    late BuildContext inside;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          inside = context;
          return const SizedBox();
        },
      ),
    );
    expect(MorphGlassScope.maybeOf(inside), isNull);
    expect(MorphTheme.of(inside).glass, isNull);
  });

  testWidgets('a sheet shown below a theme draws the theme glass', (
    tester,
  ) async {
    late BuildContext home;
    late BuildContext content;
    await tester.pumpWidget(
      MaterialApp(
        home: MorphTheme(
          data: const MorphThemeData(glass: .tier(.flat)),
          child: Builder(
            builder: (context) {
              home = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    unawaited(
      showMorphSheet<void>(
        home,
        detents: const [MorphSheetDetent.medium],
        builder: (context) {
          content = context;
          return const Text('content');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(GlassAdaptiveScope.tierOf(content), MorphGlassTier.flat);
    expect(MorphTheme.of(content).glass, const MorphGlassRenderer.tier(.flat));
  });

  testWidgets('changing the theme glass redraws the controls', (tester) async {
    late BuildContext inside;
    Widget app(MorphGlassRenderer glass) => MorphTheme(
      data: MorphThemeData(glass: glass),
      child: Builder(
        builder: (context) {
          inside = context;
          MorphGlassScope.maybeOf(context);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(app(const .tier(.fake)));
    expect(GlassAdaptiveScope.tierOf(inside), MorphGlassTier.fake);
    await tester.pumpWidget(app(const .tier(.flat)));
    expect(GlassAdaptiveScope.tierOf(inside), MorphGlassTier.flat);
  });

  testWidgets('a nested theme keeps the glass above unless it picks one', (
    tester,
  ) async {
    late BuildContext outer;
    late BuildContext inner;
    await tester.pumpWidget(
      MorphTheme(
        data: const MorphThemeData(glass: .tier(.fake)),
        child: Builder(
          builder: (context) {
            outer = context;
            return MorphTheme(
              data: const MorphThemeData(tint: Color(0xFFFF0000)),
              child: MorphTheme(
                data: const MorphThemeData(glass: .tier(.flat)),
                child: Builder(
                  builder: (context) {
                    inner = context;
                    return const SizedBox();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    expect(GlassAdaptiveScope.tierOf(outer), MorphGlassTier.fake);
    expect(GlassAdaptiveScope.tierOf(inner), MorphGlassTier.flat);
    final tinted = tester.element(find.byType(MorphTheme).at(2));
    expect(GlassAdaptiveScope.tierOf(tinted), MorphGlassTier.fake);
  });
}
