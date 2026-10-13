import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

void _ignore(Object? _) {}

int _focusableNodes(WidgetTester tester) {
  var count = 0;
  bool visit(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isFocused != Tristate.none) {
      count += 1;
    }
    node.visitChildren(visit);
    return true;
  }

  final owner = tester.renderObject(find.byType(MaterialApp)).owner!;
  visit(owner.semanticsOwner!.rootSemanticsNode!);
  return count;
}

Iterable<FocusNode> _tabStops() => FocusManager
    .instance
    .rootScope
    .traversalDescendants
    .where((FocusNode node) => node is! FocusScopeNode && node.canRequestFocus);

void main() {
  final controls = <String, Widget>{
    'switch': const MorphSwitch(value: false, onChanged: _ignore),
    'slider': const MorphSlider(value: 0.5, onChanged: _ignore),
    'stepper': const MorphStepper(value: 1, onChanged: _ignore),
    'segmented': const MorphSegmentedControl(
      segments: ['A', 'B'],
      selected: 0,
      onChanged: _ignore,
    ),
    'page control': const MorphPageControl(
      count: 3,
      page: 0,
      onChanged: _ignore,
    ),
    'tab bar': const MorphTabBar(
      items: [
        MorphTabItem(icon: IconData(0xe318), label: 'One'),
        MorphTabItem(icon: IconData(0xe318), label: 'Two'),
      ],
      selected: 0,
      onChanged: _ignore,
    ),
    'glass button': MorphGlassButton(onPressed: () {}, child: const Text('Go')),
    'menu button': MorphMenuButton(
      items: [MorphMenuItem(title: 'Copy', onSelected: () {})],
    ),
    'menu source': MorphMenuSource(
      items: [MorphMenuItem(title: 'Copy', onSelected: () {})],
      child: const SizedBox(width: 80, height: 44),
    ),
  };
  for (final MapEntry(key: name, value: control) in controls.entries) {
    testWidgets('the $name is a focusable semantics node', (
      WidgetTester tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: SizedBox(width: 320, child: control)),
        ),
      );
      expect(_focusableNodes(tester), greaterThan(0));
      semantics.dispose();
    });
  }

  testWidgets('a control follows its enclosing Focus to a new node', (
    WidgetTester tester,
  ) async {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    var useA = true;
    late StateSetter swap;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              swap = setState;
              return Focus(
                focusNode: useA ? a : b,
                child: const MorphSwitch(value: false, onChanged: _ignore),
              );
            },
          ),
        ),
      ),
    );
    expect(a.children, hasLength(1));
    swap(() => useA = false);
    await tester.pump();
    expect(a.children, isEmpty);
    expect(b.children, hasLength(1));
    b.children.single.requestFocus();
    await tester.pump();
    expect(b.hasFocus, isTrue);
  });

  testWidgets('a source that is not focusable leaves the focus to its child', (
    WidgetTester tester,
  ) async {
    final child = FocusNode(debugLabel: 'child');
    addTearDown(child.dispose);
    Widget source({required bool focusable}) => MaterialApp(
      home: Center(
        child: MorphMenuSource(
          focusable: focusable,
          items: [MorphMenuItem(title: 'Copy', onSelected: () {})],
          child: Builder(
            builder: (BuildContext context) => Focus(
              focusNode: child,
              onKeyEvent: (FocusNode node, KeyEvent event) {
                if (event is! KeyDownEvent ||
                    event.logicalKey != LogicalKeyboardKey.enter) {
                  return KeyEventResult.ignored;
                }
                MorphMenuSource.open(context);
                return KeyEventResult.handled;
              },
              child: const SizedBox(width: 80, height: 44),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(source(focusable: true));
    expect(_tabStops(), hasLength(2));
    await tester.pumpWidget(source(focusable: false));
    expect(_tabStops(), [child]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(child.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
  });
}
