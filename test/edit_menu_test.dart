import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

/// Runs [body] as iOS with the system edit menu available and returns the
/// platform calls that showed it.
Future<List<MethodCall>> _onIOS(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  final shown = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'ContextMenu.showSystemContextMenu') shown.add(call);
      return null;
    },
  );
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  }
  return shown;
}

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF0088FF),
  pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
      PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (BuildContext context, _, _) => builder(context),
      ),
  builder: (BuildContext context, Widget? navigator) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(supportsShowingSystemContextMenu: true),
    child: MorphTheme(data: const MorphThemeData(), child: navigator!),
  ),
  home: Center(child: child),
);

void main() {
  testWidgets('a long press in a search field shows the system edit menu', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'Lisbon');
    addTearDown(controller.dispose);
    final shown = await _onIOS(tester, () async {
      await tester.pumpWidget(
        _app(
          SizedBox(width: 300, child: MorphSearchField(controller: controller)),
        ),
      );
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(EditableText));
      await tester.pumpAndSettle();
    });
    expect(find.byType(SystemContextMenu), findsOneWidget);
    expect(shown, isNotEmpty);
  });

  testWidgets('a long press in an alert text field shows the system edit '
      'menu', (WidgetTester tester) async {
    final shown = await _onIOS(tester, () async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (BuildContext context) => GestureDetector(
              onTap: () => unawaited(
                showMorphAlert(
                  context,
                  title: 'Rename',
                  textFields: const [MorphAlertTextField(placeholder: 'Name')],
                  actions: [MorphAlertAction(title: 'OK', onPressed: () {})],
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Draft');
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(EditableText));
      await tester.pumpAndSettle();
    });
    expect(find.byType(SystemContextMenu), findsOneWidget);
    expect(shown, isNotEmpty);
  });
}
