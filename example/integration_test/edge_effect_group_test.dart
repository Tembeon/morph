import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// The bars of a [MorphNavigationStack] over a high-contrast page scrolled
/// under them, for comparing builds that group the scroll edge effect's
/// backdrop differently.
///
/// The page is red / green / white / black stripes; the navigation bar
/// (hard edge effect, two trailing buttons) and the toolbar (one button)
/// float over it, scrolled past the large title. One screenshot per tier
/// (liquid, fake) at rest and one mid-scroll. Build a profile app
/// (`flutter build ios --profile -t
/// integration_test/edge_effect_group_test.dart`), launch it with
/// devicectl and pull `tmp/edge-effect/` from the app's data container:
/// the screenshots and `report.json`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('edge effect group', semanticsEnabled: false, (
    WidgetTester tester,
  ) async {
    final out = Directory('${Directory.systemTemp.path}/edge-effect');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    await MorphGlassRenderer.precache();
    final tier = ValueNotifier<MorphGlassTier>(MorphGlassTier.liquid);
    final controller = ScrollController();
    await tester.pumpWidget(_App(tier: tier, controller: controller));
    await tester.pump(const Duration(seconds: 2));
    final report = <String, Object?>{
      'liquid_available': MorphGlassRenderer.liquidAvailable,
      'dpr': tester.view.devicePixelRatio,
    };
    for (final value in [MorphGlassTier.liquid, MorphGlassTier.fake]) {
      tier.value = value;
      controller.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 500));
      controller.jumpTo(300);
      await tester.pump(const Duration(seconds: 1));
      await _shoot(binding, out, '${value.name}-rest');
      controller.jumpTo(347);
      await tester.pump(const Duration(milliseconds: 300));
      await _shoot(binding, out, '${value.name}-moved');
    }
    File(
      '${out.path}/report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  });
}

Future<void> _shoot(
  IntegrationTestWidgetsFlutterBinding binding,
  Directory out,
  String name,
) async {
  final Map<String, Object?> data;
  try {
    data = await binding.callbackManager.takeScreenshot(name);
  } on MissingPluginException {
    return;
  }
  final bytes = (data['bytes']! as List<Object?>).cast<int>();
  File('${out.path}/$name.png').writeAsBytesSync(bytes);
}

class _App extends StatelessWidget {
  const _App({required this.tier, required this.controller});

  final ValueNotifier<MorphGlassTier> tier;
  final ScrollController controller;

  MorphBarButton _button(String id) => MorphBarButton(
    id: id,
    icon: const Icon(Icons.star),
    semanticLabel: id,
    onPressed: () {},
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MorphGlassTier>(
      valueListenable: tier,
      builder: (BuildContext context, MorphGlassTier value, Widget? _) =>
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(brightness: Brightness.dark),
            builder: (BuildContext context, Widget? child) =>
                MorphAdaptiveGlass(
                  tier: value,
                  child: MorphScope(child: child!),
                ),
            home: MorphNavigationStack(
              home: MorphNavigationScaffold(
                title: 'Edge',
                largeTitle: true,
                controller: controller,
                trailing: [
                  MorphBarButtonGroup([_button('add'), _button('more')]),
                ],
                toolbarLeading: [
                  MorphBarButtonGroup([_button('filter')], id: 'tools'),
                ],
                slivers: [
                  SliverList.builder(
                    itemCount: 120,
                    itemBuilder: (BuildContext context, int i) => SizedBox(
                      height: 22,
                      child: ColoredBox(
                        color: const [
                          Color(0xFFFF2020),
                          Color(0xFF20E020),
                          Color(0xFFFFFFFF),
                          Color(0xFF000000),
                        ][i % 4],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
