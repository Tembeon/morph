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

  testWidgets('G5 bars share a backdrop group apart from the page glass', (
    tester,
  ) async {
    final root = BackdropKey();
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (BuildContext context, Widget? _) => MediaQuery(
          data: const MediaQueryData(size: Size(402, 874)),
          child: BackdropGroup(
            backdropKey: root,
            child: MorphGlass(
              painter: const MorphGlassRenderer(tier: MorphGlassTier.frosted),
              child: MorphNavigationScaffold(
                title: 'Page',
                trailing: [
                  MorphBarButtonGroup([
                    MorphBarButton(id: 'top', label: 'Top', onPressed: () {}),
                  ]),
                ],
                toolbarTrailing: [
                  MorphBarButtonGroup([
                    MorphBarButton(
                      id: 'bottom',
                      label: 'Bottom',
                      onPressed: () {},
                    ),
                  ]),
                ],
                slivers: [
                  SliverToBoxAdapter(
                    child: MorphGlassButton(
                      onPressed: () {},
                      child: const Text('Body'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    List<BackdropKey?> keys(Type type) => [
      for (final f in tester.widgetList<BackdropFilter>(
        find.descendant(
          of: find.byType(type),
          matching: find.byType(BackdropFilter),
        ),
      ))
        f.backdropGroupKey,
    ];
    final body = keys(MorphGlassButton);
    final top = keys(MorphNavigationBar).nonNulls.toSet();
    final toolbar = keys(MorphToolbar);
    expect(body, isNotEmpty);
    expect(body.every((k) => identical(k, root)), isTrue);
    expect(top, hasLength(1));
    expect(top.single, isNot(same(root)));
    expect(toolbar, isNotEmpty);
    expect(toolbar.every((k) => identical(k, top.single)), isTrue);
  });

  testWidgets('G6 frosted chrome surfaces take a backdrop copy of their own', (
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
              builder: (context) =>
                  const MorphGlassRenderer(
                    tier: MorphGlassTier.frosted,
                  ).buildSurface(
                    context,
                    const MorphGlassSurface(
                      kind: MorphGlassKind.menu,
                      shape: RRect.fromLTRBXY(0, 0, 300, 80, 20, 20),
                      color: Color(0xFFFFFFFF),
                      brightness: Brightness.light,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.backdropGroupKey, isNull);
  });
}
