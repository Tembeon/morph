import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/morph.dart';

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

void _keyboardHighlights() {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
}

Finder _ringIn(Finder control) =>
    find.descendant(of: control, matching: find.byType(MorphFocusRing));

/// The focus node of the nearest focusable ancestor of [element].
FocusNode _focusOf(Element element) {
  final nodes = <BuildContext, FocusNode>{
    for (final node in FocusManager.instance.rootScope.descendants)
      ?node.context: node,
  };
  FocusNode? found;
  element.visitAncestorElements((Element ancestor) {
    found = nodes[ancestor];
    return found == null;
  });
  return found!;
}

void main() {
  testWidgets('the menu button takes focus, rings it and opens on Enter', (
    WidgetTester tester,
  ) async {
    _keyboardHighlights();
    final chosen = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MorphMenuButton(
            menu: [
              MorphMenuItem(title: 'Copy', onSelected: () => chosen.add('c')),
            ],
          ),
        ),
      ),
    );
    final button = find.byType(MorphMenuButton);
    expect(_ringIn(button), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_ringIn(button), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    expect(chosen, isEmpty);
  });

  testWidgets('a disabled menu button is not focusable', (
    WidgetTester tester,
  ) async {
    _keyboardHighlights();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MorphMenuButton(
            enabled: false,
            menu: [MorphMenuItem(title: 'Copy', onSelected: () {})],
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    expect(_ringIn(find.byType(MorphMenuButton)), findsNothing);
  });

  testWidgets('bar buttons take focus in turn and Space presses them', (
    WidgetTester tester,
  ) async {
    _keyboardHighlights();
    final pressed = <String>[];
    MorphBarButton icon(String id, {bool enabled = true}) => MorphBarButton(
      id: id,
      icon: const SizedBox.square(dimension: 24),
      semanticLabel: id,
      enabled: enabled,
      onPressed: () => pressed.add(id),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MorphToolbar(
                  trailing: [
                    MorphBarButtonGroup([
                      icon('a'),
                      icon('off', enabled: false),
                      icon('b'),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);
    final toolbar = find.byType(MorphToolbar);
    expect(_ringIn(toolbar), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_ringIn(toolbar), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(pressed, ['a', 'b'], reason: 'the disabled button is skipped');
  });

  testWidgets('the search circles take focus and Enter taps them', (
    WidgetTester tester,
  ) async {
    _keyboardHighlights();
    var searching = false;
    final asked = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => Stack(
            children: [
              Positioned.fill(
                child: MorphSearchTabBar(
                  items: const [
                    MorphTabItem(icon: Icons.home, label: 'Home'),
                    MorphTabItem(icon: Icons.book, label: 'Library'),
                  ],
                  selected: 0,
                  onChanged: (_) {},
                  active: searching,
                  onActiveChanged: (bool v) {
                    asked.add(v);
                    setState(() => searching = v);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);
    final magnifier = find.byWidgetPredicate(
      (Widget w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_MagnifierGlyph',
    );
    _focusOf(tester.element(magnifier)).requestFocus();
    await tester.pump();
    expect(_ringIn(find.byType(MorphSearchTabBar)), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(asked, [true]);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    final tab = find.byWidgetPredicate(
      (Widget w) =>
          w is Semantics && w.properties.label == 'Home' && w.excludeSemantics,
    );
    _focusOf(
      tester.element(
        find.descendant(of: tab, matching: find.byType(Stack)).first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(asked, [true, false], reason: 'the tab circle ends the search');
    await _settle(tester);
  });
}
