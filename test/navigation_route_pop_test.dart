import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

void main() {
  testWidgets('a bar button pops a navigation route pushed outside a stack', (
    tester,
  ) async {
    final root = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF007AFF),
        navigatorKey: root,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
        home: const SizedBox.expand(),
      ),
    );
    final route = MorphNavigationRoute<void>(
      builder: (BuildContext context) => MorphNavigationScaffold(
        title: 'Demo',
        leading: [
          MorphBarButtonGroup([
            MorphBarButton(
              id: 'close',
              label: 'Close',
              onPressed: root.currentState!.pop,
            ),
          ]),
        ],
        slivers: const [],
      ),
    );
    unawaited(root.currentState!.push(route));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(root.currentState!.canPop(), isFalse);
    expect(route.animation!.status, AnimationStatus.dismissed);
    expect(find.text('Close'), findsNothing);
  });
}
