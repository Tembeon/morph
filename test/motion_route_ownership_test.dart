import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/alert.dart';
import 'package:morph/src/widgets/navigation_stack.dart';
import 'package:morph/src/widgets/sheet.dart';
import 'package:morph/src/widgets/sheet_motion.dart';

Route<void> _cover() => RawDialogRoute<void>(
  pageBuilder: (_, _, _) => const Center(child: Text('cover')),
  transitionDuration: Duration.zero,
);

void main() {
  testWidgets('a covered sheet dismisses its own route', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const SizedBox()),
    );
    final sheet = MorphSheetRoute<void>(
      detents: const [MorphSheetDetent.medium],
      builder: (_) => const Text('sheet'),
    );
    nav.currentState!.push<void>(sheet);
    await tester.pumpAndSettle();
    final dismiss = tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .firstWhere((w) => w.onTap != null)
        .onTap!;
    final cover = _cover();
    nav.currentState!.push<void>(cover);
    await tester.pump();
    dismiss();
    await tester.pumpAndSettle();
    expect(cover.isCurrent, isTrue);
    expect(sheet.isActive, isFalse);
    expect(find.text('cover'), findsOneWidget);
  });

  testWidgets('a covered alert chooses on its own route', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    var chosen = 0;
    final accept = MorphAlertAction(title: 'Accept', onPressed: () => chosen++);
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const SizedBox()),
    );
    final alert = MorphAlertRoute(title: 'Alert', actions: [accept]);
    final result = nav.currentState!.push<MorphAlertAction>(alert);
    await tester.pumpAndSettle();
    final choose = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .firstWhere((w) => w.properties.label == 'Accept')
        .properties
        .onTap!;
    final cover = _cover();
    nav.currentState!.push<void>(cover);
    await tester.pump();
    choose();
    await tester.pumpAndSettle();
    expect(cover.isCurrent, isTrue);
    expect(alert.isActive, isFalse);
    expect(await result, same(accept));
    expect(chosen, 1);
  });

  testWidgets('an outside cancel handler can push above its action sheet', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final cover = _cover();
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const SizedBox()),
    );
    final alert = MorphAlertRoute(
      actionSheet: true,
      title: 'Actions',
      actions: [
        MorphAlertAction(
          title: 'Cancel',
          style: MorphAlertActionStyle.cancel,
          onPressed: () {
            cancelled++;
            nav.currentState!.push<void>(cover);
          },
        ),
      ],
    );
    nav.currentState!.push<MorphAlertAction>(alert);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(cover.isCurrent, isTrue);
    expect(alert.isActive, isFalse);
    expect(cancelled, 1);
  });

  testWidgets('a zoom drag commits its own route after another push', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    late BuildContext sourceContext;
    await tester.pumpWidget(
      MorphScope(
        child: MaterialApp(
          navigatorKey: nav,
          home: Builder(
            builder: (context) {
              sourceContext = context;
              return const Center(
                child: MorphTag(
                  id: 'source',
                  child: SizedBox(
                    width: 120,
                    height: 80,
                    child: Text('source'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    unawaited(
      pushMorphZoom<void>(
        sourceContext,
        from: 'source',
        builder: (_) => const SizedBox.expand(child: Text('zoom page')),
      ),
    );
    await tester.pumpAndSettle();
    final zoom = ModalRoute.of(tester.element(find.text('zoom page')))!;
    final gesture = await tester.startGesture(const Offset(400, 200));
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 300));
    final cover = _cover();
    nav.currentState!.push<void>(cover);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(cover.isCurrent, isTrue);
    expect(zoom.isActive, isFalse);
  });
}
