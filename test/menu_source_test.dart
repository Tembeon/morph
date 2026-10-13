import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

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
          items: _items(log),
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
          items: _items(log),
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
}
