import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

void main() {
  testWidgets('G3 adaptive glass installs one shared backdrop group', (
    tester,
  ) async {
    late BackdropKey? key;
    await tester.pumpWidget(
      MorphAdaptiveGlass(
        tier: MorphGlassTier.frosted,
        child: Builder(
          builder: (context) {
            key = BackdropGroup.of(context)?.backdropKey;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(key, isNotNull);
    expect(find.byType(BackdropGroup), findsOneWidget);
  });

  testWidgets('G3 adaptive glass accepts the ancestor group', (tester) async {
    final shared = BackdropKey();
    late BackdropKey? key;
    await tester.pumpWidget(
      BackdropGroup(
        backdropKey: shared,
        child: MorphAdaptiveGlass(
          tier: MorphGlassTier.frosted,
          child: Builder(
            builder: (context) {
              key = BackdropGroup.of(context)?.backdropKey;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(key, same(shared));
    expect(find.byType(BackdropGroup), findsOneWidget);
  });

  testWidgets('G4 frosted separate and fused bodies share a backdrop key', (
    tester,
  ) async {
    final shared = BackdropKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BackdropGroup(
          backdropKey: shared,
          child: SizedBox(
            width: 300,
            height: 80,
            child: Builder(
              builder: (context) {
                MorphGlassSurface capsule(double left) => MorphGlassSurface(
                  kind: MorphGlassKind.button,
                  shape: RRect.fromLTRBXY(left, 0, left + 50, 44, 22, 22),
                  color: const Color(0xFFFFFFFF),
                  brightness: Brightness.light,
                );
                return const MorphGlassRenderer(
                  tier: MorphGlassTier.frosted,
                ).buildLayer(context, [
                  capsule(0),
                  capsule(55),
                  capsule(150),
                ], spacing: 12);
              },
            ),
          ),
        ),
      ),
    );
    final filters = tester.widgetList<BackdropFilter>(
      find.byType(BackdropFilter),
    );
    expect(filters, hasLength(2));
    expect(
      filters.every((filter) => identical(filter.backdropGroupKey, shared)),
      isTrue,
    );
  });
}
