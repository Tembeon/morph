import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// Whether bars sharing the root [BackdropGroup] with body glass painted
/// before them see the content painted between the two.
///
/// Impeller snapshots a shared backdrop key at its first filter in paint
/// order. The scene paints a resting glass button first, then bright
/// stripes under the navigation bar's and toolbar's capsules, then the
/// bars over a hard scroll edge effect. Variants: `shared` (the button in
/// the root group), `none` (no button) and `own` (the button in a group of
/// its own). Build a profile app (`flutter build ios --profile -t
/// integration_test/backdrop_group_test.dart`), launch it with devicectl
/// and pull `tmp/backdrop/` from the app's data container: a screenshot
/// per variant and `report.json` with the capsule rects in logical px.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('backdrop group', semanticsEnabled: false, (
    WidgetTester tester,
  ) async {
    final out = Directory('${Directory.systemTemp.path}/backdrop');
    out.createSync(recursive: true);
    await MorphGlassRenderer.precache();
    final variant = ValueNotifier<String>('shared');
    await tester.pumpWidget(_Scene(variant: variant));
    await tester.pump(const Duration(seconds: 2));
    final report = <String, Object?>{
      'liquid_available': MorphGlassRenderer.liquidAvailable,
      'dpr': tester.view.devicePixelRatio,
      'top': _rect(tester.getRect(find.text('Top'))),
      'bottom': _rect(tester.getRect(find.text('Bottom'))),
      'stripes_top': _rect(tester.getRect(find.byKey(const Key('top')))),
      'stripes_bottom': _rect(tester.getRect(find.byKey(const Key('bottom')))),
    };
    for (final name in ['shared', 'none', 'own']) {
      variant.value = name;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final data = await binding.callbackManager.takeScreenshot(name);
      final bytes = (data['bytes']! as List<Object?>).cast<int>();
      File('${out.path}/$name.png').writeAsBytesSync(bytes);
    }
    File(
      '${out.path}/report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  });
}

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height];

class _Scene extends StatelessWidget {
  const _Scene({required this.variant});

  final ValueNotifier<String> variant;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      builder: (BuildContext context, Widget? child) => MorphAdaptiveGlass(
        tier: MorphGlassTier.liquid,
        child: BackdropGroup(child: MorphScope(child: child!)),
      ),
      home: ValueListenableBuilder<String>(
        valueListenable: variant,
        builder: (BuildContext context, String name, Widget? _) {
          final button = MorphGlassButton(
            onPressed: () {},
            child: const Text('Body glass'),
          );
          return ColoredBox(
            color: const Color(0xFF1C1C1E),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 300,
                  child: Center(
                    child: switch (name) {
                      'none' => const SizedBox(height: 44),
                      'own' => BackdropGroup(child: button),
                      _ => button,
                    },
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 130,
                  child: _Stripes(key: Key('top')),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 130,
                  child: _Stripes(key: Key('bottom')),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: MorphNavigationBar(
                    title: 'Repro',
                    scrolledUnder: true,
                    trailing: [
                      MorphBarButtonGroup([
                        MorphBarButton(
                          id: 'top',
                          label: 'Top',
                          onPressed: () {},
                        ),
                      ]),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MorphToolbar(
                    trailing: [
                      MorphBarButtonGroup([
                        MorphBarButton(
                          id: 'bottom',
                          label: 'Bottom',
                          onPressed: () {},
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Stripes extends StatelessWidget {
  const _Stripes({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 24; i++)
          Expanded(
            child: ColoredBox(
              color: i.isEven
                  ? const Color(0xFFFF2020)
                  : const Color(0xFF20E020),
            ),
          ),
      ],
    );
  }
}
