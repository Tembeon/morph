import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/foundation.dart';

const MorphScrimMotion _scrim = MorphScrimMotion(
  motion: MorphMotion.springs(
    name: 'themeScrim',
    open: MorphSpring(0.4, 0.8),
    close: MorphSpring(0.9, 1.0),
  ),
);

Widget _app({MorphTheme? theme, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(extensions: <ThemeExtension<Object?>>[?theme]),
    builder: (BuildContext context, Widget? routed) =>
        MorphScope(child: routed!),
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _tag(ValueSetter<BuildContext> onContext) {
  return MorphTag(
    id: 'btn',
    child: Builder(
      builder: (BuildContext context) {
        onContext(context);
        return const SizedBox(width: 40, height: 40);
      },
    ),
  );
}

Widget _content(BuildContext context, MorphFlight flight) => const SizedBox();

void main() {
  testWidgets('MorphTheme.scrimMotion reaches a flight launched without one', (
    WidgetTester tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      _app(
        theme: const MorphTheme(scrimMotion: _scrim),
        child: _tag((BuildContext c) => captured = c),
      ),
    );
    final MorphFlight flight = showMorph(
      captured,
      target: MorphTargetSpec.dialog(),
      builder: _content,
    );
    expect(flight.scrimMotion, _scrim);
    expect(flight.maxScrimOpacity, MorphTheme.defaultMaxScrimOpacity);
    expect(flight.shadowColor, MorphTheme.defaultShadowColor);
    flight.abort();
    await tester.pump();
  });

  testWidgets('showMorphSheet and showMorphDialog take modal and scrimMotion', (
    WidgetTester tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      _app(child: _tag((BuildContext c) => captured = c)),
    );
    final MorphFlight sheet = showMorphSheet(
      captured,
      modal: false,
      scrimMotion: _scrim,
      builder: _content,
    );
    expect(sheet.modal, isFalse);
    expect(sheet.scrimMotion, _scrim);
    sheet.abort();
    await tester.pump();
    final MorphFlight dialog = showMorphDialog(
      captured,
      modal: false,
      scrimMotion: _scrim,
      builder: _content,
    );
    expect(dialog.modal, isFalse);
    expect(dialog.scrimMotion, _scrim);
    dialog.abort();
    await tester.pump();
  });

  testWidgets('MorphAnchor passes modal and scrimMotion, and a motion change '
      'while open reaches the live flight', (WidgetTester tester) async {
    Widget anchor(MorphMotion motion) {
      return _app(
        child: MorphAnchor(
          tagId: 'anchor',
          isOpen: true,
          onDismiss: () {},
          modal: false,
          scrimMotion: _scrim,
          motion: motion,
          target: MorphTargetSpec.dialog(),
          closedBuilder: (BuildContext context) =>
              const SizedBox(width: 40, height: 40),
          openBuilder: _content,
        ),
      );
    }

    await tester.pumpWidget(anchor(MorphMotion.liquid));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('anchor')!;
    expect(flight.modal, isFalse);
    expect(flight.scrimMotion, _scrim);
    expect(flight.controller.motion, MorphMotion.liquid);

    await tester.pumpWidget(anchor(MorphMotion.glacial));
    await tester.pump();
    expect(flight.controller.motion, MorphMotion.glacial);
    flight.abort();
    await tester.pump();
  });

  test('MorphTheme equality and lerp carry scrimMotion', () {
    const MorphTheme a = MorphTheme(scrimMotion: _scrim);
    const MorphTheme b = MorphTheme();
    expect(a == b, isFalse);
    expect(a.lerp(b, 0.2).scrimMotion, _scrim);
    expect(a.lerp(b, 0.8).scrimMotion, isNull);
    expect(b.copyWith(scrimMotion: _scrim), a);
  });

  testWidgets('a status listener added twice is fully removed by two removes', (
    WidgetTester tester,
  ) async {
    final MorphController controller = MorphController(
      vsync: tester,
      motion: MorphMotion.instant,
    );
    int calls = 0;
    void listener(AnimationStatus status) => calls++;
    controller.animation.addStatusListener(listener);
    controller.animation.addStatusListener(listener);
    controller.animation.removeStatusListener(listener);
    controller.animation.removeStatusListener(listener);
    controller.open();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    controller.dispose();
  });
}
