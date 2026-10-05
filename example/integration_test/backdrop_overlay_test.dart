import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// Whether glass in overlays and lifted lenses reads what lies under it
/// when it shares the root [BackdropGroup] with body glass painted
/// before it.
///
/// Scenes: `body` (a second resting glass button over the stripes),
/// `hero` (a glass button as a context menu hero, menu open),
/// `lens` (a slider's lifted thumb, finger down), `dialog` (a glass
/// button inside a morph dialog's content) and `alert` (an alert
/// over the page), each over bright stripes, on the liquid and fake
/// tiers. Variants: `shared` (a resting glass button in the page's root
/// group painted first), `none` (no such button) and `own` (the scene's
/// glass wrapped in a group of its own). Build a profile app (`flutter
/// build ios --profile -t integration_test/backdrop_overlay_test.dart`),
/// launch it with devicectl and pull `tmp/backdrop-overlay/` from the
/// app's data container: one screenshot per tier, scene and variant and
/// `report.json` with the scene rects in logical px.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('backdrop overlay', semanticsEnabled: false, (
    WidgetTester tester,
  ) async {
    final out = Directory('${Directory.systemTemp.path}/backdrop-overlay');
    out.createSync(recursive: true);
    await MorphGlassRenderer.precache();
    final setup = ValueNotifier<_Setup>(
      const _Setup(MorphGlassTier.liquid, 'hero', 'shared'),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_App(setup: setup, navigator: navigator));
    await tester.pump(const Duration(seconds: 2));
    final report = <String, Object?>{
      'liquid_available': MorphGlassRenderer.liquidAvailable,
      'dpr': tester.view.devicePixelRatio,
    };
    for (final tier in [MorphGlassTier.liquid, MorphGlassTier.fake]) {
      for (final scene in ['body', 'hero', 'lens', 'dialog', 'alert']) {
        for (final variant in ['shared', 'none', 'own']) {
          setup.value = _Setup(tier, scene, variant);
          await tester.pump(const Duration(seconds: 1));
          final name = '${tier.name}-$scene-$variant';
          final target = find.byKey(const Key('target'));
          report['$name-target'] = _rect(tester.getRect(target.first));
          switch (scene) {
            case 'body':
              await _shoot(binding, out, name);
            case 'hero':
              MorphContextMenuRegion.open(tester.element(target.first));
              await tester.pump(const Duration(milliseconds: 1500));
              report['$name-open'] = _rect(tester.getRect(target.last));
              await _shoot(binding, out, name);
              await tester.tapAt(const Offset(30, 820));
              await tester.pump(const Duration(milliseconds: 1500));
            case 'lens':
              final thumb = tester.getRect(target.first);
              final at = Offset(
                thumb.left + thumb.width * 0.5,
                thumb.center.dy,
              );
              final gesture = await tester.startGesture(at);
              await tester.pump(const Duration(milliseconds: 100));
              await gesture.moveBy(const Offset(12, 0));
              await tester.pump(const Duration(milliseconds: 900));
              await _shoot(binding, out, name);
              await gesture.up();
              await tester.pump(const Duration(milliseconds: 1200));
            case 'dialog':
              final flight = showMorphDialog(
                tester.element(target.first),
                from: 'dialog',
                width: 300,
                height: 200,
                builder: (BuildContext context, MorphFlight flight) => Center(
                  child: MorphGlassButton(
                    onPressed: () {},
                    child: const Text('Dialog glass'),
                  ),
                ),
              );
              await tester.pump(const Duration(milliseconds: 1500));
              await _shoot(binding, out, name);
              flight.close();
              await tester.pump(const Duration(milliseconds: 1500));
            case _:
              unawaited(
                showMorphAlert(
                  navigator.currentContext!,
                  title: 'Alert over glass',
                  message: 'The platter reads the stripes under it.',
                  actions: const [MorphAlertAction(title: 'OK')],
                ),
              );
              await tester.pump(const Duration(milliseconds: 1500));
              await _shoot(binding, out, name);
              navigator.currentState!.pop();
              await tester.pump(const Duration(milliseconds: 1500));
          }
        }
      }
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

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height];

@immutable
class _Setup {
  const _Setup(this.tier, this.scene, this.variant);

  final MorphGlassTier tier;
  final String scene;
  final String variant;
}

class _App extends StatelessWidget {
  const _App({required this.setup, required this.navigator});

  final ValueNotifier<_Setup> setup;
  final GlobalKey<NavigatorState> navigator;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Setup>(
      valueListenable: setup,
      builder: (BuildContext context, _Setup value, Widget? _) => MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark),
        builder: (BuildContext context, Widget? child) => MorphAdaptiveGlass(
          tier: value.tier,
          child: BackdropGroup(child: MorphScope(child: child!)),
        ),
        home: _Page(setup: value),
      ),
    );
  }
}

class _Page extends StatefulWidget {
  const _Page({required this.setup});

  final _Setup setup;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  double _value = 0.5;

  Widget _scene() {
    switch (widget.setup.scene) {
      case 'body':
        return MorphGlassButton(
          key: const Key('target'),
          onPressed: () {},
          child: const Text('Body glass'),
        );
      case 'hero':
        return MorphContextMenuRegion(
          below: MorphSatellite(
            builder: (BuildContext context, MorphFlight flight) =>
                const SizedBox(
                  width: 200,
                  height: 120,
                  child: ColoredBox(color: Color(0xFF3A3A3C)),
                ),
          ),
          child: MorphGlassButton(
            key: const Key('target'),
            onPressed: () {},
            child: const Text('Hero glass'),
          ),
        );
      case 'lens':
        return SizedBox(
          width: 300,
          child: MorphSlider(
            key: const Key('target'),
            value: _value,
            onChanged: (double v) => setState(() => _value = v),
          ),
        );
      case 'dialog':
        return const MorphTag(
          id: 'dialog',
          surfaceColor: Color(0xFF3A3A3C),
          child: SizedBox(key: Key('target'), width: 300, height: 44),
        );
      case _:
        return const SizedBox(key: Key('target'), width: 300, height: 44);
    }
  }

  @override
  Widget build(BuildContext context) {
    final variant = widget.setup.variant;
    final scene = _scene();
    return ColoredBox(
      color: const Color(0xFF1C1C1E),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 120,
            child: Center(
              child: variant == 'none'
                  ? const SizedBox(height: 44)
                  : MorphGlassButton(
                      onPressed: () {},
                      child: const Text('Body glass'),
                    ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 260,
            height: 360,
            child: _Stripes(),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 420,
            child: Center(
              child: variant == 'own' ? BackdropGroup(child: scene) : scene,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stripes extends StatelessWidget {
  const _Stripes();

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
