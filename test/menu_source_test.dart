import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/menu.dart' show MorphMenuLayer;
import 'package:morph/src/widgets/menu_motion.dart';

Widget _app(Widget body) => WidgetsApp(
  color: const Color(0xFF007AFF),
  pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
      PageRouteBuilder<T>(
        settings: settings,
        pageBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
            ) => builder(context),
      ),
  home: Center(child: body),
);

List<MorphMenuEntry> _items(List<String> log) => [
  for (final title in const ['Copy', 'Share', 'Rename'])
    MorphMenuItem(title: title, onSelected: () => log.add(title)),
];

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

class _Counted extends StatefulWidget {
  const _Counted();

  static final List<State<_Counted>> states = [];

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    _Counted.states.add(this);
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 120, height: 40, child: Text('Source'));
}

Iterable<RenderCustomPaint> _menuGlass(Finder within) => find
    .descendant(
      of: within,
      matching: find.byWidgetPredicate((Widget _) => true),
    )
    .evaluate()
    .map((Element element) => element.renderObject)
    .whereType<RenderCustomPaint>()
    .toSet()
    .where(
      (RenderCustomPaint box) =>
          box.painter.runtimeType.toString() == '_GlassPainter',
    );

void main() {
  test('the source shape keeps the corners of a rounded source', () {
    MorphMenuMotion motion({double? radius}) => MorphMenuMotion(
      button: const Rect.fromLTWH(100, 100, 120, 40),
      itemCount: 3,
      bounds: const Size(390, 844),
      sourceRadius: radius,
    );
    expect(motion().buttonBlob.radius, 20);
    expect(motion(radius: 10).buttonBlob.radius, 10);
    expect(motion(radius: 40).buttonBlob.radius, 20);
  });

  testWidgets('any widget opens its menu on tap and keeps its state', (
    WidgetTester tester,
  ) async {
    _Counted.states.clear();
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        MorphMenuSource(
          menu: _items(log),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: const _Counted(),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MorphMenuSource)), const Size(120, 40));
    final source = _Counted.states.single;
    await tester.tap(find.byType(MorphMenuSource));
    await _settle(tester);
    expect(find.text('Share'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.text('Share')));
    await _settle(tester);
    expect(log, ['Share']);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Source'), findsOneWidget);
    expect(source.mounted, isTrue, reason: 'the source keeps its state');
    expect(
      tester.state(find.byType(_Counted)),
      same(source),
      reason: 'the looks carried by the menu are gone',
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a hold source taps through and opens only when held', (
    WidgetTester tester,
  ) async {
    var taps = 0;
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        MorphMenuSource(
          menu: _items(log),
          trigger: MorphMenuTrigger.hold,
          onTap: () => taps++,
          child: const SizedBox(width: 80, height: 44),
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuSource));
    await _settle(tester);
    expect(taps, 1);
    expect(find.text('Copy'), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphMenuSource)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Copy'), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(taps, 1);
    expect(find.text('Copy'), findsOneWidget, reason: 'released on source');
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a glass button with a menu opens it from the button', (
    WidgetTester tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        MorphGlassButton(
          onPressed: null,
          menu: _items(log),
          child: const Text('Sort'),
        ),
      ),
    );
    await tester.tap(find.byType(MorphGlassButton));
    await _settle(tester);
    expect(find.text('Rename'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.text('Rename')));
    await _settle(tester);
    expect(log, ['Rename']);
    expect(find.text('Rename'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a glass button with an action presses and holds its menu', (
    WidgetTester tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _app(
        MorphGlassButton(
          onPressed: () => presses++,
          menu: _items(<String>[]),
          child: const Text('Back'),
        ),
      ),
    );
    await tester.tap(find.byType(MorphGlassButton));
    await _settle(tester);
    expect(presses, 1);
    expect(find.text('Copy'), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphGlassButton)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await _settle(tester);
    expect(presses, 1);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('a pressed button with a menu keeps its touch-up-inside slop', (
    WidgetTester tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _app(
        MorphGlassButton(
          onPressed: () => presses++,
          menu: _items(<String>[]),
          child: const Text('Back'),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(MorphGlassButton));
    Future<void> drift(Offset to) async {
      final gesture = await tester.startGesture(rect.center);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await _settle(tester);
    }

    await drift(rect.bottomCenter + const Offset(0, 10));
    expect(presses, 1, reason: '10 pt outside still activates');
    await drift(rect.bottomCenter + const Offset(0, 100));
    expect(presses, 1, reason: '100 pt outside does not');
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('every tap-trigger source opens only within its slop', (
    WidgetTester tester,
  ) async {
    final sources = <String, Widget>{
      'menu button': MorphMenuButton(menu: _items(<String>[])),
      'source': MorphMenuSource(
        menu: _items(<String>[]),
        child: const SizedBox(width: 120, height: 40),
      ),
      'glass button': MorphGlassButton(
        onPressed: null,
        menu: _items(<String>[]),
        child: const Text('Sort'),
      ),
    };
    for (final MapEntry(key: name, value: source) in sources.entries) {
      await tester.pumpWidget(
        _app(KeyedSubtree(key: ValueKey(name), child: source)),
      );
      final rect = tester.getRect(find.byKey(ValueKey(name)));
      Future<bool> drift(Offset to, {int heldFrames = 3}) async {
        final gesture = await tester.startGesture(rect.center);
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveTo(to);
        for (var i = 0; i < heldFrames; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await _settle(tester);
        final opened = find.text('Copy').evaluate().isNotEmpty;
        if (opened) {
          await tester.tapAt(const Offset(5, 5));
          await _settle(tester);
        }
        return opened;
      }

      expect(
        await drift(rect.bottomCenter + const Offset(0, 100)),
        isFalse,
        reason: '$name: a release 100 pt off cancels',
      );
      expect(
        await drift(rect.topCenter - const Offset(0, 100)),
        isFalse,
        reason: '$name: in any direction',
      );
      expect(
        await drift(rect.bottomCenter + const Offset(0, 100), heldFrames: 20),
        isFalse,
        reason: '$name: a finger off past the hold duration opens nothing',
      );
      expect(
        await drift(rect.bottomCenter + const Offset(0, 10)),
        isTrue,
        reason: '$name: a release 10 pt off still opens',
      );
    }
  });

  testWidgets('a glass button with a menu is focusable and keyboard driven', (
    WidgetTester tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MorphGlassButton(
              onPressed: null,
              menu: _items(<String>[]),
              child: const Text('Sort'),
            ),
            MorphGlassButton(
              onPressed: () => presses++,
              menu: _items(<String>[]),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget, reason: 'Enter opens the menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(presses, 1, reason: 'Space presses the button with an action');
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a disabled glass button with a menu keeps its tree', (
    WidgetTester tester,
  ) async {
    Widget button({required bool enabled}) => _app(
      MorphGlassButton(
        onPressed: null,
        enabled: enabled,
        menu: _items(<String>[]),
        child: const _Counted(),
      ),
    );
    _Counted.states.clear();
    await tester.pumpWidget(button(enabled: true));
    final source = _Counted.states.single;
    await tester.tap(find.byType(MorphGlassButton));
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.pumpWidget(button(enabled: false));
    await _settle(tester);
    expect(find.text('Copy'), findsNothing, reason: 'disabling closes it');
    expect(tester.state(find.byType(_Counted)), same(source));
    await tester.tap(find.byType(MorphGlassButton), warnIfMissed: false);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing, reason: 'a disabled button');
    final style = MorphGlassButtonAppearance.resolve(
      tester.element(find.byType(_Counted)),
      null,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.byType(_Counted))).style.color,
      style.disabledForegroundColor,
    );
  });

  testWidgets('the source shape starts and lands in the button tint', (
    WidgetTester tester,
  ) async {
    const tint = Color(0xFF0088FF);
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        MorphGlassButton.prominent(
          onPressed: null,
          tint: tint,
          menu: _items(log),
          child: const Text('Sort'),
        ),
      ),
    );
    await tester.tap(find.byType(MorphGlassButton));
    Iterable<RenderCustomPaint> overlay() =>
        _menuGlass(find.byType(MorphMenuLayer));
    for (var i = 0; i < 30 && overlay().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 4));
    }
    expect(overlay(), isNotEmpty);
    expect(overlay().first, paints..path(color: tint));
    await _settle(tester);
    expect(overlay().first, isNot(paints..path(color: tint)));
    await tester.tapAt(tester.getCenter(find.text('Copy')));
    var landed = 0;
    for (var i = 0; i < 200 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      for (final glass in _menuGlass(find.byType(MorphMenuSource))) {
        expect(glass, paints..path(color: tint));
        landed++;
      }
    }
    expect(log, ['Copy']);
    expect(landed, greaterThan(0), reason: 'the landing was drawn');
  });
}
