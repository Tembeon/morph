import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext) show,
) async {
  await tester.binding.setSurfaceSize(const Size(440, 956));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => show(context),
            child: const SizedBox(
              key: ValueKey('source'),
              width: 120,
              height: 48,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('source')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an action follows its enabled listenable', (tester) async {
    final enabled = ValueNotifier<bool>(false);
    addTearDown(enabled.dispose);
    MorphAlertAction? chosen;
    final typed = <String>[];
    await _open(tester, (c) async {
      chosen = await showMorphAlert(
        c,
        title: 'Name',
        textFields: [
          MorphAlertTextField(
            placeholder: 'Name',
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(5)],
            onChanged: (String text) {
              typed.add(text);
              enabled.value = text.isNotEmpty;
            },
          ),
        ],
        actions: [
          const MorphAlertAction(title: 'Cancel', style: .cancel),
          MorphAlertAction(title: 'OK', enabledListenable: enabled),
        ],
      );
    });
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsOneWidget, reason: 'disabled at first');
    await tester.enterText(find.byType(EditableText), 'Morphology');
    await tester.pumpAndSettle();
    expect(typed.last, 'Morph');
    expect(enabled.value, isTrue);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(chosen?.title, 'OK');
  });

  testWidgets('autofocus picks the field', (tester) async {
    await _open(
      tester,
      (c) => showMorphAlert(
        c,
        title: 'Login',
        textFields: const [
          MorphAlertTextField(placeholder: 'User', autofocus: false),
          MorphAlertTextField(
            placeholder: 'Password',
            obscureText: true,
            autofocus: true,
          ),
        ],
        actions: const [MorphAlertAction(title: 'OK')],
      ),
    );
    final fields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList();
    expect(fields[0].autofocus, isFalse);
    expect(fields[1].autofocus, isTrue);
    expect(fields[1].obscureText, isTrue);
  });
}
