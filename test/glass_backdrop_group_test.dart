import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

/// The backdrop keys of every filter painted on screen, in paint order
/// (null for a filter that takes a copy of its own). The glass's opacity
/// seed layer, a subclass that adds a pass only inside a fractional
/// opacity, is not one.
List<BackdropKey?> _keys() {
  final out = <BackdropKey?>[];
  void walk(Layer layer) {
    if (layer.runtimeType == BackdropFilterLayer) {
      out.add((layer as BackdropFilterLayer).backdropKey);
    }
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk(child);
      }
    }
  }

  for (final view in RendererBinding.instance.renderViews) {
    final root = view.debugLayer;
    if (root != null) walk(root);
  }
  return out;
}

void main() {
  testWidgets('G3 adaptive glass installs one shared backdrop group', (
    tester,
  ) async {
    late BackdropKey? key;
    await tester.pumpWidget(
      MorphAdaptiveGlass(
        tier: MorphGlassTier.fake,
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
          tier: MorphGlassTier.fake,
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

  testWidgets('G4 fake separate and fused bodies share a backdrop key', (
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
                  tier: MorphGlassTier.fake,
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
    tester.takeException();
    await tester.pump();
    final keys = _keys();
    expect(keys, hasLength(2));
    expect(keys.every((key) => identical(key, shared)), isTrue);
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
              painter: const MorphGlassRenderer(tier: MorphGlassTier.fake),
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
    tester.takeException();
    await tester.pump(const Duration(milliseconds: 100));
    final keys = _keys();
    final bars = keys.where((k) => !identical(k, root)).toSet();
    expect(keys.where((k) => identical(k, root)), isNotEmpty);
    expect(bars, hasLength(1));
    expect(bars.single, isNotNull);
  });

  testWidgets('G6 fake chrome surfaces take a backdrop copy of their own', (
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
                    tier: MorphGlassTier.fake,
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
    tester.takeException();
    await tester.pump();
    expect(_keys(), [null]);
  });
}
