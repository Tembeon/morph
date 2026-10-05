import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// One scene of the perf counts and the glass frame identity tests: a page
/// and the gesture that animates its glass.
class GlassScene {
  /// Creates a scene.
  const GlassScene(this.name, this.build, this.run);

  /// The scene's name in the fixtures.
  final String name;

  /// Builds the page.
  final Widget Function() build;

  /// Animates the page's glass.
  final Future<void> Function(WidgetTester tester) run;
}

Future<void> _drag(
  WidgetTester tester,
  Offset from,
  List<Offset> path, {
  Duration hold = const Duration(milliseconds: 120),
  Duration step = const Duration(milliseconds: 8),
}) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(hold);
  for (final p in path) {
    await gesture.moveTo(p);
    await tester.pump(step);
  }
  await gesture.up();
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 8));
  }
}

List<Offset> _line(Offset a, Offset b, int n) => [
  for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!,
];

Widget _page(Widget child) => Scaffold(
  backgroundColor: const Color(0xFFF2F2F7),
  body: Stack(
    children: [
      for (var i = 0; i < 12; i++)
        Positioned(
          left: 0,
          right: 0,
          top: i * 80.0,
          height: 40,
          child: ColoredBox(color: Color(0xFF000000 | (i * 0x153F7B))),
        ),
      Center(child: child),
    ],
  ),
);

class _Controlled extends StatefulWidget {
  const _Controlled(this.builder);

  final Widget Function(Object? value, ValueChanged<Object?> onChanged) builder;

  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  Object? _value;

  @override
  Widget build(BuildContext context) =>
      widget.builder(_value, (Object? value) => setState(() => _value = value));
}

/// A page of controls under one parent state, as an app holds them: a
/// change of any control rebuilds all of them.
class _ControlsPage extends StatefulWidget {
  const _ControlsPage();

  @override
  State<_ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<_ControlsPage> {
  bool _on = false;
  double _wide = 0.5;
  double _ticked = 0.25;
  double _steps = 2;
  int _segment = 0;
  int _taps = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('${(_wide * 100).round()} $_taps'),
      SizedBox(
        width: 340,
        child: MorphSlider(
          value: _wide,
          onChanged: (double v) => setState(() => _wide = v),
        ),
      ),
      SizedBox(
        width: 200,
        child: MorphSlider(
          value: _ticked,
          ticks: 5,
          onChanged: (double v) => setState(() => _ticked = v),
        ),
      ),
      MorphSwitch(value: _on, onChanged: (bool v) => setState(() => _on = v)),
      MorphStepper(
        value: _steps,
        max: 10,
        onChanged: (double v) => setState(() => _steps = v),
      ),
      SizedBox(
        width: 300,
        child: MorphSegmentedControl(
          segments: const ['A', 'B', 'C'],
          selected: _segment,
          onChanged: (int v) => setState(() => _segment = v),
        ),
      ),
      for (var i = 0; i < 3; i++)
        SizedBox(
          width: 100,
          height: 44,
          child: MorphGlassButton(
            onPressed: () => setState(() => _taps++),
            child: const SizedBox.square(dimension: 20),
          ),
        ),
    ],
  );
}

const _menuEntries = <MorphMenuEntry>[
  MorphMenuItem(title: 'Copy'),
  MorphMenuItem(title: 'Share'),
  MorphSubmenu(
    title: 'More',
    children: [
      MorphMenuItem(title: 'Sub one'),
      MorphMenuItem(title: 'Sub two'),
    ],
  ),
  MorphMenuItem(title: 'Delete'),
];

MorphBarButton _barIcon(String id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: () {},
);

/// The density page: [count] standalone glass buttons on one plane over a
/// list of coloured rows (example/integration_test/glass_density_test.dart).
Widget _density(int count) => Scaffold(
  backgroundColor: const Color(0xFF000000),
  body: Stack(
    children: [
      Positioned.fill(
        child: ListView.builder(
          itemCount: 400,
          itemBuilder: (BuildContext context, int i) => SizedBox(
            height: 56,
            child: ColoredBox(
              color: Color(0xFF000000 | ((i * 0x2A3F1B) & 0xFFFFFF)),
              child: Text('Row $i'),
            ),
          ),
        ),
      ),
      for (var i = 0; i < count; i++)
        Positioned.fromRect(
          rect: Rect.fromCenter(
            center: _densityButton(i),
            width: 80,
            height: 44,
          ),
          child: MorphGlassButton(onPressed: () {}, child: Text('$i')),
        ),
    ],
  ),
);

Offset _densityButton(int i) =>
    Offset(57 + (i % 4) * 96.0, 120 + (i ~/ 4) * 60.0);

/// Presses [count] density buttons in a wave: finger i lands two frames
/// after finger i - 1 and lifts 25 frames after it landed.
Future<void> _wave(WidgetTester tester, int count) async {
  const down = 25;
  final gestures = <int, TestGesture>{};
  final last = (count - 1) * 2 + down;
  for (var frame = 0; frame <= last; frame++) {
    for (var i = 0; i < count; i++) {
      if (frame == i * 2) {
        gestures[i] = await tester.startGesture(
          _densityButton(i),
          pointer: 100 + i,
        );
      } else if (frame == i * 2 + down) {
        await gestures.remove(i)!.up();
      }
    }
    await tester.pump(const Duration(milliseconds: 8));
  }
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 8));
  }
}

const _densities = [1, 4, 8, 16, 32];

/// The scenes, in fixture order.
final glassScenes = <GlassScene>[
  GlassScene(
    'segmented-drag',
    () => _page(
      _Controlled(
        (value, onChanged) => SizedBox(
          width: 300,
          child: MorphSegmentedControl(
            segments: const ['A', 'B', 'C'],
            selected: value as int? ?? 0,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
    (tester) async {
      final a = tester.getCenter(find.text('A'));
      final c = tester.getCenter(find.text('C'));
      await _drag(tester, a, [..._line(a, c, 40), ..._line(c, a, 40)]);
    },
  ),
  GlassScene(
    'lens-held',
    () => _page(
      _Controlled(
        (value, onChanged) => SizedBox(
          width: 300,
          child: MorphSegmentedControl(
            segments: const ['A', 'B', 'C'],
            selected: value as int? ?? 0,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
    (tester) async {
      final a = tester.getCenter(find.text('A'));
      await _drag(tester, a, [
        for (var i = 0; i < 60; i++) a,
      ], hold: const Duration(milliseconds: 8));
    },
  ),
  GlassScene(
    'tab-bar',
    () => _page(
      _Controlled(
        (value, onChanged) => MorphTabBar(
          items: const [
            MorphTabItem(icon: Icons.home, label: 'Home'),
            MorphTabItem(icon: Icons.search, label: 'Search'),
            MorphTabItem(icon: Icons.radio, label: 'Radio'),
          ],
          selected: value as int? ?? 0,
          onChanged: onChanged,
        ),
      ),
    ),
    (tester) async {
      final home = tester.getCenter(find.text('Home'));
      final radio = tester.getCenter(find.text('Radio'));
      await _drag(tester, home, [
        ..._line(home, radio, 50),
        ..._line(radio, home, 50),
      ], hold: const Duration(milliseconds: 150));
    },
  ),
  GlassScene(
    'switch',
    () => _page(
      _Controlled(
        (value, onChanged) =>
            MorphSwitch(value: value as bool? ?? false, onChanged: onChanged),
      ),
    ),
    (tester) async {
      final s = tester.getRect(find.byType(MorphSwitch));
      await _drag(tester, s.center, [
        ..._line(s.center, s.centerLeft, 10),
        ..._line(s.centerLeft, s.centerRight, 20),
      ]);
    },
  ),
  GlassScene(
    'slider',
    () => _page(
      _Controlled(
        (value, onChanged) => SizedBox(
          width: 340,
          child: MorphSlider(
            value: value as double? ?? 0.5,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
    (tester) async {
      final w = tester.getRect(find.byType(MorphSlider));
      await _drag(tester, w.center, [
        ..._line(w.center, w.centerLeft, 30),
        ..._line(w.centerLeft, w.center, 30),
      ], step: const Duration(milliseconds: 16));
    },
  ),
  GlassScene('controls-page', () => _page(const _ControlsPage()), (
    tester,
  ) async {
    final w = tester.getRect(find.byType(MorphSlider).first);
    await _drag(tester, w.center, [
      ..._line(w.center, w.centerLeft, 30),
      ..._line(w.centerLeft, w.center, 30),
    ], step: const Duration(milliseconds: 16));
  }),
  GlassScene(
    'menu-card',
    () => _page(const MorphMenuButton(items: _menuEntries)),
    (tester) async {
      await tester.tap(find.byType(MorphMenuButton));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.tapAt(tester.getCenter(find.text('More').last));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.tapAt(const Offset(20, 840));
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
    },
  ),
  GlassScene(
    'menu-held',
    () => _page(const MorphMenuButton(items: _menuEntries)),
    (tester) async {
      await tester.tap(find.byType(MorphMenuButton));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      final row = tester.getCenter(find.text('Share').last);
      final gesture = await tester.startGesture(row);
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.moveTo(row + const Offset(0, 4));
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
    },
  ),
  GlassScene(
    'nav-scroll',
    () => MorphNavigationStack(
      home: MorphNavigationScaffold(
        title: 'Inbox',
        largeTitle: true,
        trailing: [
          MorphBarButtonGroup([_barIcon('add'), _barIcon('more')]),
        ],
        toolbarLeading: [
          MorphBarButtonGroup([_barIcon('filter')], id: 'tbL'),
        ],
        slivers: [
          SliverList.builder(
            itemCount: 60,
            itemBuilder: (BuildContext context, int i) => SizedBox(
              height: 44,
              child: ColoredBox(
                color: Color(0xFF000000 | (i * 0x2A3F1B)),
                child: Text('Row $i'),
              ),
            ),
          ),
        ],
      ),
    ),
    (tester) async {
      await _drag(
        tester,
        const Offset(200, 600),
        _line(const Offset(200, 600), const Offset(200, 300), 40),
      );
    },
  ),
  GlassScene(
    'search-press',
    () => _page(const SizedBox(width: 360, child: MorphSearchField())),
    (tester) async {
      final field = tester.getCenter(find.byType(MorphSearchField));
      await _drag(tester, field, [
        for (var i = 0; i < 30; i++) field,
      ], hold: const Duration(milliseconds: 8));
    },
  ),
  GlassScene(
    'sheet',
    () => _page(
      Builder(
        builder: (BuildContext context) => GestureDetector(
          key: const ValueKey<String>('source'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(
            presentMorphSheet<void>(
              context,
              detents: const [MorphSheetDetent.medium],
              builder: (BuildContext context) =>
                  const Center(child: Text('Sheet')),
            ),
          ),
          child: const SizedBox(width: 120, height: 48),
        ),
      ),
    ),
    (tester) async {
      await tester.tap(find.byKey(const ValueKey<String>('source')));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.tapAt(const Offset(200, 100));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
    },
  ),
  for (final n in _densities) ...[
    GlassScene('density-rest-$n', () => _density(n), (tester) async {
      await _drag(
        tester,
        const Offset(201, 800),
        _line(const Offset(201, 800), const Offset(201, 500), 40),
      );
    }),
    GlassScene(
      'density-wave-$n',
      () => _density(n),
      (tester) => _wave(tester, n),
    ),
  ],
];
