import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_page.dart';
import 'package:morph_example/gallery/liquid_glass_painter.dart';

/// The glass displacement audit on a device: glass of every kind over the
/// measurement grid ([GlassGrid]) at the rects the UIKit probe's
/// `glassGrid` scene uses, resting and with the tab bar lens held.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/glass_grid_test.dart`), launch it with devicectl and
/// pull `tmp/glassgrid/` from the app's data container; the shots and
/// `rects.json` (logical rects of every glass) go there.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('glass grid', (WidgetTester tester) async {
    final out = Directory('${Directory.systemTemp.path}/glassgrid');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);

    Future<void> shot(String name) async {
      await tester.pump();
      final data = await binding.callbackManager.takeScreenshot(name);
      final bytes = (data['bytes']! as List<Object?>).cast<int>();
      File('${out.path}/$name.png').writeAsBytesSync(bytes);
    }

    await LiquidGlass.precache();
    runApp(const _Harness());
    await tester.pump(const Duration(milliseconds: 1500));
    await shot('grid-resting');

    final bar = find.byType(MorphTabBar);
    final library = tester.getCenter(
      find.descendant(of: bar, matching: find.text('Library')),
    );
    final gesture = await tester.createGesture();
    await gesture.down(library);
    await tester.pump(const Duration(milliseconds: 700));
    await shot('grid-lens-held');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 900));
    final segmented = tester.getRect(find.byType(MorphSegmentedControl));
    final press = await tester.createGesture();
    await press.down(
      Offset(segmented.left + segmented.width / 6, segmented.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await shot('grid-segmented-held');
    await press.up();
    await tester.pump(const Duration(milliseconds: 900));

    final rects = <String, Object>{
      for (final (name, rect) in _Harness.surfaces)
        name: [rect.left, rect.top, rect.width, rect.height],
      'tabbar': _ltwh(tester.getRect(bar)),
      'segmented': _ltwh(segmented),
      'glassbutton': _ltwh(tester.getRect(find.byType(MorphGlassButton))),
    };

    for (final dark in [false, true]) {
      final suffix = dark ? 'd1' : 'd0';
      for (final slider in [true, false]) {
        runApp(_Controls(dark: dark, slider: slider));
        await tester.pump(const Duration(milliseconds: 1200));
        final control = slider
            ? find.byType(MorphSlider)
            : find.byType(MorphSwitch);
        final r = tester.getRect(control);
        final name = slider ? 'slider' : 'switch';
        rects['$name-$suffix'] = _ltwh(r);
        final at = slider
            ? Offset(r.left + 18.5 + 0.3 * (r.width - 37), r.center.dy)
            : Offset(r.center.dx - 11, r.center.dy);
        final finger = await tester.createGesture();
        await finger.down(at);
        await tester.pump(const Duration(milliseconds: 700));
        await shot('$name-held-$suffix');
        await finger.up();
        await tester.pump(const Duration(milliseconds: 900));
      }
    }

    runApp(const GalleryApp());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Glass renderer'));
    await tester.pump(const Duration(milliseconds: 900));
    final grid = find.byType(GlassGrid);
    final toggle = find.byType(MorphSwitch).at(_debugGridSwitch(tester));
    await tester.ensureVisible(toggle);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pump(const Duration(milliseconds: 1200));

    Future<void> page(String name) async {
      await shot(name);
      final glass = find.byType(MorphGlassButton);
      rects[name] = {
        'grid': _ltwh(tester.getRect(grid)),
        'tabbar': _ltwh(tester.getRect(find.byType(MorphTabBar).first)),
        'buttons': [
          for (var i = 0; i < glass.evaluate().length; i++)
            _ltwh(tester.getRect(glass.at(i))),
        ],
      };
    }

    await page('page-top');
    await tester.drag(find.byType(ListView), const Offset(0, -37));
    await tester.pump(const Duration(milliseconds: 1200));
    await page('page-scrolled');
    final tabs = find.byType(MorphTabBar).first;
    final forYou = tester.getCenter(
      find.descendant(of: tabs, matching: find.text('For You')),
    );
    final hold = await tester.createGesture();
    await hold.down(forYou);
    await tester.pump(const Duration(milliseconds: 700));
    await page('page-lens-held');
    await hold.up();
    await tester.pump(const Duration(milliseconds: 900));
    File('${out.path}/rects.json').writeAsStringSync(jsonEncode(rects));
  });
}

int _debugGridSwitch(WidgetTester tester) {
  final switches = tester
      .widgetList<MorphSwitch>(find.byType(MorphSwitch))
      .toList();
  return switches.indexWhere(
    (MorphSwitch s) => s.semanticLabel == 'Debug grid',
  );
}

List<double> _ltwh(Rect r) => [r.left, r.top, r.width, r.height];

class _Harness extends StatefulWidget {
  const _Harness();

  static const surfaces = <(String, Rect)>[
    ('capsule', Rect.fromLTWH(40, 120, 120, 44)),
    ('circle', Rect.fromLTWH(220, 120, 44, 44)),
    ('bar', Rect.fromLTWH(21, 220, 360, 64)),
    ('panel', Rect.fromLTWH(76, 330, 250, 220)),
  ];

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _tab = 0;
  int _segment = 0;

  static MorphGlassSurface _surface(String name, Rect rect) {
    final radius = switch (name) {
      'panel' => 34.0,
      _ => rect.shortestSide / 2,
    };
    return MorphGlassSurface(
      kind: switch (name) {
        'bar' => MorphGlassKind.bar,
        'panel' => MorphGlassKind.menu,
        _ => MorphGlassKind.button,
      },
      shape: .fromRectAndRadius(rect, .circular(radius)),
      color: const Color(0x00FFFFFF),
      brightness: .light,
    );
  }

  @override
  Widget build(BuildContext context) {
    const painter = LiquidGlassRendererPainter();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        child: MorphGlass(
          painter: painter,
          child: BackdropGroup(
            child: MorphScope(
              child: Stack(
                children: [
                  const Positioned.fill(child: GlassGrid()),
                  for (final (name, rect) in _Harness.surfaces)
                    Positioned.fill(
                      child: Builder(
                        builder: (BuildContext context) =>
                            painter.buildLayer(context, [_surface(name, rect)]),
                      ),
                    ),
                  Positioned(
                    left: 40,
                    top: 600,
                    child: MorphGlassButton(
                      onPressed: () {},
                      child: const Text('Glass'),
                    ),
                  ),
                  Positioned(
                    left: 51,
                    top: 680,
                    width: 300,
                    child: MorphSegmentedControl(
                      segments: const ['Photos', 'Albums', 'Search'],
                      selected: _segment,
                      onChanged: (int i) => setState(() => _segment = i),
                    ),
                  ),
                  Positioned(
                    left: 21,
                    right: 21,
                    bottom: 30,
                    child: MorphTabBar(
                      items: const [
                        MorphTabItem(icon: Icons.home_outlined, label: 'Home'),
                        MorphTabItem(
                          icon: Icons.book_outlined,
                          label: 'Library',
                        ),
                        MorphTabItem(icon: Icons.radio, label: 'Radio'),
                      ],
                      selected: _tab,
                      onChanged: (int i) => setState(() => _tab = i),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.dark, required this.slider});

  final bool dark;
  final bool slider;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: dark ? .dark : .light),
      home: Material(
        child: MorphGlass(
          painter: const LiquidGlassRendererPainter(),
          child: BackdropGroup(
            child: Stack(
              children: [
                const Positioned.fill(child: GlassGrid()),
                if (slider)
                  Positioned(
                    left: 51,
                    top: 383,
                    width: 300,
                    child: MorphSlider(value: 0.3, onChanged: (double v) {}),
                  )
                else
                  Positioned(
                    left: 170.67,
                    top: 386,
                    child: MorphSwitch(value: false, onChanged: (bool v) {}),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
