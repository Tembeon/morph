import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/sheet.dart';
import 'package:morph/src/widgets/sheet_motion.dart';

void main() {
  testWidgets('sheet lookups outside a sheet throw FlutterError', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      () => MorphSheet.of(context),
      throwsA(
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('MorphSheet.of'),
        ),
      ),
    );
    expect(
      () => MorphSheet.scrollControllerOf(context),
      throwsA(
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('MorphSheet.scrollControllerOf'),
        ),
      ),
    );
    expect(MorphSheet.maybeOf(context), isNull);
  });

  testWidgets('detent readers rebuild for programmatic and grabber changes', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    late MorphSheet sheet;
    final seen = <MorphSheetDetent>[];
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const SizedBox()),
    );
    nav.currentState!.push<void>(
      MorphSheetRoute<void>(
        detents: const [MorphSheetDetent.large, MorphSheetDetent.medium],
        initialDetent: MorphSheetDetent.medium,
        grabberVisible: true,
        builder: (context) {
          sheet = MorphSheet.of(context);
          seen.add(sheet.detent);
          return Text(
            sheet.detent == MorphSheetDetent.medium ? 'medium' : 'large',
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(seen.last, MorphSheetDetent.medium);
    sheet.animateTo(MorphSheetDetent.large);
    await tester.pumpAndSettle();
    expect(seen.last, MorphSheetDetent.large);
    final largeBuilds = seen.length;
    await tester.tap(find.byType(Container));
    await tester.pumpAndSettle();
    expect(seen.last, MorphSheetDetent.medium);
    expect(seen.length, greaterThan(largeBuilds));
  });
}
