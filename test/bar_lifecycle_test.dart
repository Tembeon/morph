import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/bar_items.dart' show MorphBarItems;
import 'package:morph/morph.dart';

/// The object lifecycle of bar items during a transition, as UIKit runs
/// it on iOS 27 (lab captures of push, pop and item-set changes on an
/// iPhone 16 Pro, iOS 27.0.1; notes private): every view and layer of the
/// change is created in the transition's first frame and the leaving ones
/// are removed once at its end; in between the existing objects are only
/// updated, whether the capsules keep their membership or split and join.
///
/// Here an object is an element under a bar row ([MorphBarItems]): a frame
/// that mounts, unmounts or hands a new widget to any of them counts as a
/// building frame. A transition may build in its first frame and in one
/// cleanup frame after its motion settled, and in no other.
///
/// `BAR_LIFECYCLE_LOG=true` prints the per-frame counts.
void main() {
  final log = Platform.environment['BAR_LIFECYCLE_LOG'] == 'true';
  final platforms = const TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.iOS,
  });
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  for (final tier in [null, ...MorphGlassTier.values]) {
    final name = tier?.name ?? 'no glass';
    group('bar items build only at the start and end ($name)', () {
      testWidgets('push and pop of a navigation stack', (tester) async {
        await _setScreen(tester);
        late BuildContext inbox;
        await tester.pumpWidget(
          _app(tier, MorphNavigationStack(home: _inbox((c) => inbox = c))),
        );
        await _settle(tester);
        final push = await _record(tester, () {
          Navigator.of(
            inbox,
          ).push(MorphNavigationRoute<void>(builder: (_) => _detail()));
        });
        if (log) {
          debugPrint('push/$name/${defaultTargetPlatform.name}\n$push');
        }
        expect(find.text('Message'), findsWidgets);
        final pop = await _record(tester, () {
          Navigator.of(inbox).pop();
        });
        if (log) debugPrint('pop/$name/${defaultTargetPlatform.name}\n$pop');
        expect(find.text('Message'), findsNothing);
        push.expectLifecycle();
        pop.expectLifecycle();
      }, variant: platforms);

      testWidgets('toolbar item sets that split and join capsules', (
        tester,
      ) async {
        await _setScreen(tester);
        final set = ValueNotifier<int>(0);
        addTearDown(set.dispose);
        await tester.pumpWidget(
          _app(
            tier,
            ValueListenableBuilder<int>(
              valueListenable: set,
              builder: (BuildContext context, int value, Widget? _) {
                final (leading, trailing) = _sets[value];
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: MorphToolbar(leading: leading, trailing: trailing),
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await _settle(tester);
        for (final next in [1, 2, 0, 2, 1]) {
          final swap = await _record(tester, () => set.value = next);
          if (log) {
            debugPrint(
              'toolbar $next/$name/${defaultTargetPlatform.name}\n$swap',
            );
          }
          swap.expectLifecycle();
        }
      }, variant: platforms);
    });
  }

  for (final tier in MorphGlassTier.values) {
    testWidgets('a tap beside the capsules reaches the page while the items '
        'change (${tier.name})', (tester) async {
      await _setScreen(tester);
      var taps = 0;
      Widget page(List<MorphBarButtonGroup> leading) => _app(
        tier,
        Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MorphToolbar(
                leading: leading,
                trailing: [
                  MorphBarButtonGroup([_icon('compose')]),
                ],
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        page([
          MorphBarButtonGroup([_icon('trash'), _icon('folder')]),
        ]),
      );
      await _settle(tester);
      final row = tester.getRect(find.byType(MorphToolbar));
      final beside = Offset(row.center.dx, row.bottom - 30);
      await tester.tapAt(beside);
      expect(taps, 1);
      await tester.pumpWidget(
        page([
          MorphBarButtonGroup([_icon('trash')]),
          MorphBarButtonGroup([_icon('folder')]),
        ]),
      );
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.tapAt(beside);
      expect(taps, 2);
      await _settle(tester);
    });
  }
}

const _screen = Size(402, 874);

Future<void> _setScreen(WidgetTester tester) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _app(MorphGlassTier? tier, Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(platform: TargetPlatform.iOS),
  builder: (BuildContext context, Widget? child) => tier == null
      ? child!
      : MorphTheme(
          data: MorphThemeData(glass: .tier(tier)),
          child: child!,
        ),
  home: home,
);

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 16),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 20),
);

MorphBarButton _icon(String id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: () {},
);

Widget _inbox(void Function(BuildContext) onContext) => Builder(
  builder: (BuildContext context) {
    onContext(context);
    return MorphNavigationScaffold(
      title: 'Inbox',
      largeTitleDisplayMode: .always,
      trailing: [
        MorphBarButtonGroup([_icon('add'), _icon('more')]),
      ],
      toolbarLeading: [
        MorphBarButtonGroup([
          MorphBarButton(id: 'filter', label: 'Filter', onPressed: () {}),
        ], id: 'tbL'),
      ],
      toolbarTrailing: [
        MorphBarButtonGroup([_icon('compose')], id: 'tbR'),
      ],
      slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
    );
  },
);

Widget _detail() => MorphNavigationScaffold(
  title: 'Message',
  trailing: [
    MorphBarButtonGroup([_icon('like'), _icon('share')]),
    MorphBarButtonGroup([
      MorphBarButton(id: 'done', label: 'Done', onPressed: () {}),
    ], style: .prominent),
  ],
  toolbarLeading: [
    MorphBarButtonGroup([_icon('up'), _icon('down')], id: 'tbL'),
  ],
  toolbarTrailing: [
    MorphBarButtonGroup([_icon('reply')], id: 'tbR'),
  ],
  slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
);

final _sets = <(List<MorphBarButtonGroup>, List<MorphBarButtonGroup>)>[
  (
    [
      MorphBarButtonGroup([
        MorphBarButton(id: 'filter', label: 'Filter', onPressed: () {}),
      ], id: 'tbL'),
    ],
    [
      MorphBarButtonGroup([_icon('compose')], id: 'tbR'),
    ],
  ),
  (
    [
      MorphBarButtonGroup([_icon('trash'), _icon('folder')], id: 'tbL'),
    ],
    [
      MorphBarButtonGroup([_icon('reply'), _icon('compose')], id: 'tbR'),
    ],
  ),
  (
    [
      MorphBarButtonGroup([_icon('trash')], id: 'tbL'),
      MorphBarButtonGroup([_icon('folder')], id: 'tbM'),
    ],
    [
      MorphBarButtonGroup([_icon('compose')], id: 'tbR'),
    ],
  ),
];

/// The elements under each bar row, each with the widget it holds.
Map<Element, Map<Element, Widget>> _rowElements(WidgetTester tester) => {
  for (final row in find.byType(MorphBarItems).evaluate())
    row: () {
      final out = <Element, Widget>{};
      void visit(Element element) {
        out[element] = element.widget;
        element.visitChildren(visit);
      }

      row.visitChildren(visit);
      return out;
    }(),
};

/// Runs [change] and records, frame by frame until everything settles,
/// how many elements under each bar row mounted, unmounted or took a new
/// widget.
Future<_Lifecycle> _record(WidgetTester tester, void Function() change) async {
  var before = _rowElements(tester);
  change();
  final rows = <Element, List<(int, int, int)>>{};
  for (var i = 0; i < 400; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final after = _rowElements(tester);
    for (final MapEntry(key: row, value: now) in after.entries) {
      final was = before[row] ?? const <Element, Widget>{};
      var mounted = 0;
      var updated = 0;
      for (final MapEntry(key: element, value: widget) in now.entries) {
        final old = was[element];
        if (old == null) {
          mounted++;
        } else if (!identical(old, widget)) {
          updated++;
        }
      }
      final unmounted = was.keys.where((e) => !now.containsKey(e)).length;
      (rows[row] ??= List.filled(i, (
        0,
        0,
        0,
      ), growable: true)).add((mounted, updated, unmounted));
    }
    before = after;
    if (i > 10 && !tester.binding.hasScheduledFrame) break;
  }
  return _Lifecycle([
    for (final MapEntry(key: row, value: frames) in rows.entries)
      ('${row.widget.runtimeType}@${row.hashCode}', frames),
  ]);
}

class _Lifecycle {
  _Lifecycle(this.rows);

  /// Per row, per frame: elements mounted, updated and unmounted.
  final List<(String, List<(int, int, int)>)> rows;

  static List<int> _building(List<(int, int, int)> frames) => [
    for (final (i, (m, u, r)) in frames.indexed)
      if (m + u + r > 0) i,
  ];

  void expectLifecycle() {
    for (final (name, frames) in rows) {
      final at = _building(frames);
      expect(
        at.length,
        lessThanOrEqualTo(2),
        reason: 'bar row $name built in frames $at:\n$this',
      );
    }
  }

  @override
  String toString() => [
    for (final (name, frames) in rows) ...[
      '  row $name',
      for (final (i, (m, u, r)) in frames.indexed)
        if (m + u + r > 0) '    frame $i: +$m ~$u -$r',
    ],
  ].join('\n');
}
