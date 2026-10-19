import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> with RestorationMixin {
  final RestorableInt _taps = RestorableInt(0);

  @override
  String get restorationId => 'counter';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) =>
      registerForRestoration(_taps, 'taps');

  @override
  void dispose() {
    _taps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _taps.value++),
    child: Text('taps ${_taps.value}'),
  );
}

Widget _app() => WidgetsApp(
  color: const Color(0xFF0088FF),
  restorationScopeId: 'app',
  builder: (BuildContext context, Widget? _) => MorphNavigationStack.pages(
    restorationScopeId: 'stack',
    pages: const [
      MorphNavigationPage<void>(
        key: ValueKey<String>('home'),
        restorationId: 'home',
        child: Center(child: _Counter()),
      ),
    ],
    onDidRemovePage: (Page<Object?> page) {},
  ),
);

void main() {
  testWidgets('a page with a restoration id keeps its state across a restart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    await tester.tap(find.text('taps 1'));
    await tester.pump();
    expect(find.text('taps 2'), findsOneWidget);
    await tester.restartAndRestore();
    expect(find.text('taps 2'), findsOneWidget);
  });
}
