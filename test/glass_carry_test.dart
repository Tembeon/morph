import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

void main() {
  Future<_Recorder> pumpPage(WidgetTester tester, Widget body) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final glass = _Recorder();
    await tester.pumpWidget(
      MaterialApp(
        home: MorphGlass(
          painter: glass,
          child: Scaffold(body: Center(child: body)),
        ),
      ),
    );
    return glass;
  }

  Widget source(void Function(BuildContext context) show) => Builder(
    builder: (BuildContext context) => GestureDetector(
      key: const ValueKey<String>('source'),
      behavior: HitTestBehavior.opaque,
      onTap: () => show(context),
      child: const SizedBox(width: 120, height: 48),
    ),
  );

  testWidgets('an alert in the root navigator draws with the page glass', (
    WidgetTester tester,
  ) async {
    final glass = await pumpPage(
      tester,
      source(
        (BuildContext context) => unawaited(
          showMorphAlert(
            context,
            title: 'Title',
            actions: const [MorphAlertAction(title: 'OK')],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('source')));
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(glass.inPopup, greaterThan(0));
  });

  testWidgets('an action sheet popover draws with its anchor glass', (
    WidgetTester tester,
  ) async {
    final glass = await pumpPage(
      tester,
      source(
        (BuildContext context) => unawaited(
          showMorphActionSheet(
            context,
            anchor: context,
            actions: const [MorphAlertAction(title: 'Share')],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('source')));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsOneWidget);
    expect(glass.inPopup, greaterThan(0));
  });

  testWidgets('a floating sheet and its content draw with the page glass', (
    WidgetTester tester,
  ) async {
    final seen = <MorphGlassPainter?>[];
    final glass = await pumpPage(
      tester,
      source(
        (BuildContext context) => unawaited(
          presentMorphSheet<void>(
            context,
            detents: const [MorphSheetDetent.medium],
            useRootNavigator: true,
            builder: (BuildContext context) => _Probe(seen),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('source')));
    await tester.pumpAndSettle();
    expect(glass.inPopup, greaterThan(0));
    expect(seen, isNotEmpty);
    expect(seen, everyElement(same(glass)));
  });

  testWidgets('the date picker overlay draws with the page glass', (
    WidgetTester tester,
  ) async {
    final glass = await pumpPage(
      tester,
      MorphDatePicker(
        value: DateTime(2026, 10, 3),
        today: DateTime(2026, 10, 3),
        onChanged: (DateTime value) {},
      ),
    );
    final before = glass.inPopup;
    await tester.tap(find.text('Oct 3, 2026'));
    await tester.pumpAndSettle();
    expect(find.text('15'), findsOneWidget);
    expect(glass.inPopup, greaterThan(before));
  });

  testWidgets('a context menu flight carries the region glass', (
    WidgetTester tester,
  ) async {
    final seen = <MorphGlassPainter?>[];
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final glass = _Recorder();
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: MorphGlass(
          painter: glass,
          child: Scaffold(
            body: Center(
              child: MorphContextMenuRegion(
                below: MorphSatellite(
                  height: 40,
                  builder: (BuildContext context, MorphFlight flight) =>
                      _Probe(seen),
                ),
                child: const SizedBox(
                  width: 120,
                  height: 48,
                  child: Text('hero'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('hero'));
    await tester.pumpAndSettle();
    expect(seen, isNotEmpty);
    expect(seen, everyElement(same(glass)));
  });

  testWidgets('a push zoom draws its source replica with the source glass', (
    WidgetTester tester,
  ) async {
    final seen = <MorphGlassPainter?>[];
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final glass = _Recorder();
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        home: MorphScope(
          child: MorphNavigationStack(
            home: Builder(
              builder: (BuildContext context) {
                home = context;
                return MorphGlass(
                  painter: glass,
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: const Rect.fromLTWH(40, 300, 160, 120),
                        child: MorphTag(id: 'card', child: _Probe(seen)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    seen.clear();
    unawaited(
      pushMorphZoom<void>(
        home,
        builder: (BuildContext context) => const SizedBox.expand(),
        from: 'card',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(seen, isNotEmpty);
    expect(seen, everyElement(same(glass)));
  });
}

class _Recorder extends MorphGlassPainter {
  int inPopup = 0;

  void _record(BuildContext context) {
    if (ModalRoute.of(context) is PopupRoute<Object?>) inPopup++;
  }

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    _record(context);
    return const SizedBox.expand();
  }

  @override
  Widget buildBody(
    BuildContext context,
    MorphGlassOutline outline,
    List<MorphGlassSurface> surfaces,
  ) {
    _record(context);
    return const SizedBox.expand();
  }
}

class _Probe extends StatelessWidget {
  const _Probe(this.seen);

  final List<MorphGlassPainter?> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(MorphGlass.maybeOf(context));
    return const SizedBox.expand();
  }
}
