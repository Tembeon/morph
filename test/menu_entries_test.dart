import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

Widget _app(
  Widget button, {
  bool rtl = false,
  Alignment alignment = const Alignment(0, -0.6),
}) => MaterialApp(
  builder: (BuildContext context, Widget? child) => Directionality(
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    child: child!,
  ),
  home: Scaffold(
    body: Align(alignment: alignment, child: button),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(MorphMenuButton));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

Future<void> _tapRow(WidgetTester tester, String title) async {
  await tester.tapAt(tester.getCenter(find.text(title).last));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

List<MorphMenuEntry> _entries(List<String> log, {String sort = 'Name'}) => [
  MorphMenuSection(
    title: 'Sort by',
    singleSelection: true,
    children: [
      for (final name in const ['Name', 'Date'])
        MorphMenuItem(
          title: name,
          icon: Icons.sort,
          state: name == sort ? MorphMenuState.on : MorphMenuState.off,
          keepsMenuOpen: true,
          onSelected: () => log.add('sort $name'),
        ),
    ],
  ),
  MorphSubmenu(
    title: 'More',
    icon: Icons.folder,
    children: [
      MorphMenuItem(title: 'Sub one', onSelected: () => log.add('Sub one')),
      MorphSubmenu(
        title: 'Deeper',
        children: [
          MorphMenuItem(title: 'Deep', onSelected: () => log.add('Deep')),
        ],
      ),
    ],
  ),
  MorphMenuItem(
    title: 'Disabled',
    enabled: false,
    onSelected: () => log.add('Disabled'),
  ),
  const MorphMenuItem(title: 'Hidden', hidden: true),
  MorphMenuItem(
    title: 'Delete',
    destructive: true,
    subtitle: 'Cannot be undone',
    onSelected: () => log.add('Delete'),
  ),
];

class _Sorter extends StatefulWidget {
  const _Sorter({required this.log});

  final List<String> log;

  @override
  State<_Sorter> createState() => _SorterState();
}

class _SorterState extends State<_Sorter> {
  String sort = 'Name';

  @override
  Widget build(BuildContext context) => MorphMenuButton(
    items: _entries(widget.log, sort: sort).map((MorphMenuEntry entry) {
      if (entry is! MorphMenuSection) return entry;
      return MorphMenuSection(
        title: entry.title,
        singleSelection: true,
        children: [
          for (final name in const ['Name', 'Date', 'Size'])
            if (name != 'Size' || sort == 'Date')
              MorphMenuItem(
                title: name,
                state: name == sort ? MorphMenuState.on : MorphMenuState.off,
                keepsMenuOpen: true,
                onSelected: () => setState(() => sort = name),
              ),
        ],
      );
    }).toList(),
  );
}

void main() {
  testWidgets('sections, marks, subtitles, hidden and disabled rows', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(_app(MorphMenuButton(items: _entries(log))));
    await _open(tester);
    expect(find.text('Sort by'), findsOneWidget);
    expect(find.text('Cannot be undone'), findsOneWidget);
    expect(find.text('Hidden'), findsNothing);
    await _tapRow(tester, 'Disabled');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, isEmpty);
    expect(find.text('Disabled'), findsOneWidget, reason: 'still open');
  });

  testWidgets('a row that keeps the menu open runs and leaves it open', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(_app(MorphMenuButton(items: _entries(log))));
    await _open(tester);
    await _tapRow(tester, 'Date');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['sort Date']);
    expect(find.text('Date'), findsOneWidget);
    await _tapRow(tester, 'Delete');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['sort Date', 'Delete']);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('dismissOnSelect false keeps the menu after every row', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(MorphMenuButton(items: _entries(log), dismissOnSelect: false)),
    );
    await _open(tester);
    await _tapRow(tester, 'Delete');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['Delete']);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the open menu follows a rebuild and resizes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(const _Sorter(log: [])));
    await _open(tester);
    final before = tester.getRect(find.text('Delete').last).top;
    expect(find.text('Size'), findsNothing);
    await _tapRow(tester, 'Date');
    await tester.pump();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Size'), findsOneWidget, reason: 'rebuilt in place');
    final after = tester.getRect(find.text('Delete').last).top;
    expect(after - before, moreOrLessEquals(42, epsilon: 0.5));
  });

  testWidgets('a submenu opens as a card, its row fires and closes all', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(_app(MorphMenuButton(items: _entries(log))));
    await _open(tester);
    expect(find.text('Sub one'), findsNothing);
    await _tapRow(tester, 'More');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Sub one'), findsOneWidget);
    expect(find.text('More'), findsNWidgets(2), reason: 'row and header');
    await _tapRow(tester, 'Deeper');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Deep'), findsOneWidget);
    await _tapRow(tester, 'Deep');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['Deep']);
    expect(find.text('Sub one'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('the card header goes back, Escape too, then Escape closes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(MorphMenuButton(items: _entries([]))));
    await _open(tester);
    await _tapRow(tester, 'More');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tapAt(tester.getCenter(find.text('More').last));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Sub one'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
    await _tapRow(tester, 'More');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Sub one'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('arrows move the highlight, Enter chooses, into a submenu', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(_app(MorphMenuButton(items: _entries(log))));
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Sub one'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['Sub one']);
    expect(find.text('Sub one'), findsNothing);
  });

  testWidgets('a held finger slides onto a submenu row and its card opens', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(_app(MorphMenuButton(items: _entries(log))));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphMenuButton)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.text('More').last));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sub one'), findsNothing, reason: 'before the dwell');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sub one'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.text('Sub one').last));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['Sub one']);
  });

  testWidgets(
    'rows are buttons, a submenu row collapsed, its header expanded',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(MorphMenuButton(items: _entries([]))));
      await _open(tester);
      expect(
        tester.getSemantics(find.text('Delete').last),
        matchesSemantics(
          label: 'Delete',
          value: 'Cannot be undone',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Name').last),
        matchesSemantics(
          label: 'Name',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('More').last),
        matchesSemantics(
          label: 'More',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasExpandedState: true,
          hasTapAction: true,
        ),
      );
      await _tapRow(tester, 'More');
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(
        tester.getSemantics(find.text('More').last),
        matchesSemantics(
          label: 'More',
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets('right to left puts glyphs after titles and mirrors cells', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(MorphMenuButton(items: _entries([])), rtl: true),
    );
    await _open(tester);
    final icon = tester.getRect(find.byIcon(Icons.folder).last);
    final title = tester.getRect(find.text('More').last);
    expect(icon.left, greaterThan(title.right));
  });

  testWidgets('a deferred group shows a loading row, then its rows', (
    WidgetTester tester,
  ) async {
    final answer = Completer<List<MorphMenuEntry>>();
    var loads = 0;
    Future<List<MorphMenuEntry>> load() {
      loads++;
      return answer.future;
    }

    await tester.pumpWidget(
      _app(
        MorphMenuButton(
          items: [
            const MorphMenuItem(title: 'Copy', icon: Icons.copy),
            MorphMenuDeferred(load, id: 'recent'),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Loading...'), findsOneWidget);
    final before = tester.getRect(find.text('Copy').last);
    answer.complete(const [
      MorphMenuItem(title: 'Recent', icon: Icons.history),
    ]);
    await tester.pump();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Loading...'), findsNothing);
    expect(find.text('Recent'), findsOneWidget);
    expect(tester.getRect(find.text('Copy').last), before);
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await _open(tester);
    expect(find.text('Recent'), findsOneWidget, reason: 'cached');
    expect(loads, 1);
  });

  testWidgets('a free-form row is measured and takes its own touches', (
    WidgetTester tester,
  ) async {
    var value = 0.0;
    await tester.pumpWidget(
      _app(
        MorphMenuButton(
          items: [
            const MorphMenuItem(title: 'Copy'),
            MorphMenuWidget(
              id: 'volume',
              builder: (BuildContext context) => SizedBox(
                height: 64,
                child: GestureDetector(
                  onTap: () => value = 1,
                  child: const ColoredBox(
                    color: Color(0xFF00FF00),
                    child: Center(child: Text('Volume')),
                  ),
                ),
              ),
            ),
            const MorphMenuItem(title: 'Paste'),
          ],
        ),
      ),
    );
    await _open(tester);
    final volume = tester.getRect(find.text('Volume'));
    final paste = tester.getRect(find.text('Paste').last);
    final copy = tester.getRect(find.text('Copy').last);
    expect(
      paste.center.dy - copy.center.dy,
      moreOrLessEquals(42 / 2 + 64 + 21, epsilon: 0.5),
    );
    await tester.tapAt(volume.center);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(value, 1);
    expect(find.text('Volume'), findsOneWidget, reason: 'stays open');
  });

  testWidgets('a palette and medium cells choose like rows', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        MorphMenuButton(
          items: [
            MorphMenuSection(
              palette: true,
              children: [
                for (final color in const ['Red', 'Blue'])
                  MorphMenuItem(
                    title: color,
                    icon: Icons.circle,
                    keepsMenuOpen: true,
                    onSelected: () => log.add(color),
                  ),
              ],
            ),
            MorphMenuSection(
              elementSize: MorphMenuElementSize.medium,
              children: [
                MorphMenuItem(
                  title: 'Bold',
                  icon: Icons.format_bold,
                  onSelected: () => log.add('Bold'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await _open(tester);
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.circle).last));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['Blue']);
    await _tapRow(tester, 'Bold');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['Blue', 'Bold']);
    expect(find.text('Bold'), findsNothing);
  });

  testWidgets('a menu taller than its cap scrolls without choosing', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        MorphMenuButton(
          items: [
            for (var i = 0; i < 30; i++)
              MorphMenuItem(title: 'Row $i', onSelected: () => log.add('$i')),
          ],
        ),
        alignment: const Alignment(0, -0.9),
      ),
    );
    await _open(tester);
    expect(find.byType(Scrollable), findsWidgets);
    final row = tester.getCenter(find.text('Row 5').last);
    await tester.dragFrom(row, const Offset(0, -200));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, isEmpty);
    expect(find.text('Row 0'), findsOneWidget, reason: 'still open');
    await _tapRow(tester, 'Row 12');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(log, ['12']);
  });
}
