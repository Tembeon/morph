import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);

/// Every text on screen that fell through to the fallback text style (the
/// yellow double underline of text with no DefaultTextStyle above it).
Set<String> _unstyled(WidgetTester tester) => {
  for (final element in find.byType(RichText).evaluate())
    if ((element.widget as RichText).text.style?.decorationStyle ==
        TextDecorationStyle.double)
      (element.widget as RichText).text.toPlainText(),
};

/// Pumps [frames] frames of 16 ms and collects every unstyled text seen
/// on any of them (a glyph may show only mid-morph).
Future<Set<String>> _watch(WidgetTester tester, {int frames = 60}) async {
  final seen = <String>{..._unstyled(tester)};
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    seen.addAll(_unstyled(tester));
  }
  return seen;
}

/// The text style MaterialApp gives text outside any Material.
const _fallback = TextStyle(
  color: Color(0xD0FF0000),
  fontFamily: 'monospace',
  fontSize: 48,
  fontWeight: FontWeight.w900,
  decoration: TextDecoration.underline,
  decorationColor: Color(0xFFFFFF00),
  decorationStyle: TextDecorationStyle.double,
);

/// A bare WidgetsApp: no Material and no theme; text that does not set
/// its own style falls back to MaterialApp's error style.
Widget _app(Widget home) => WidgetsApp(
  color: const Color(0xFF007AFF),
  textStyle: _fallback,
  builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
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
  home: home,
);

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(home));
  await tester.pumpAndSettle();
}

/// App content that brings its own text style, so only the text morph
/// draws itself can fall back.
Widget _styled(String text) => DefaultTextStyle(
  style: const TextStyle(fontSize: 17, color: Color(0xFF000000)),
  child: Text(text),
);

Widget _page(String title) => MorphNavigationScaffold(
  title: title,
  slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
);

void main() {
  testWidgets('the menu button draws its rows in its own text style', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const Center(
        child: MorphMenuButton(
          items: [
            MorphMenuItem(title: 'Copy', icon: Icons.copy),
            MorphMenuItem(title: 'Delete', destructive: true),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    expect(await _watch(tester), isEmpty);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the back menu draws its rows and the label in its own style', (
    WidgetTester tester,
  ) async {
    late BuildContext home;
    await _pump(
      tester,
      MorphNavigationStack(
        home: Builder(
          builder: (BuildContext context) {
            home = context;
            return _page('Mailboxes');
          },
        ),
      ),
    );
    final navigator = Navigator.of(home);
    for (final title in ['Inbox', 'Message']) {
      unawaited(
        navigator.push(
          MorphNavigationRoute<void>(builder: (_) => _page(title)),
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(_unstyled(tester), isEmpty);
    final gesture = await tester.startGesture(const Offset(40, 84));
    final seen = await _watch(tester);
    expect(find.text('Mailboxes'), findsOneWidget);
    expect(seen, isEmpty);
    await gesture.moveTo(const Offset(300, 700));
    await gesture.up();
    expect(await _watch(tester), isEmpty);
  });

  testWidgets('the context menu keeps its column styled', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      Center(
        child: MorphContextMenuRegion(
          below: MorphSatellite(
            height: 88,
            builder: (BuildContext context, MorphFlight flight) =>
                _styled('reply'),
          ),
          child: SizedBox(width: 200, height: 80, child: _styled('hero')),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('hero')),
    );
    final seen = await _watch(tester, frames: 90);
    expect(find.text('reply'), findsWidgets);
    expect(seen, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  Future<void> present(
    WidgetTester tester,
    void Function(BuildContext context, BuildContext anchor) show,
  ) async {
    late BuildContext page;
    late BuildContext anchor;
    await _pump(
      tester,
      Builder(
        builder: (BuildContext context) {
          page = context;
          return Align(
            alignment: const Alignment(0, -0.5),
            child: Builder(
              builder: (BuildContext context) {
                anchor = context;
                return const SizedBox(width: 44, height: 44);
              },
            ),
          );
        },
      ),
    );
    show(page, anchor);
    await tester.pump();
  }

  const actions = [
    MorphAlertAction(title: 'Cancel', style: MorphAlertActionStyle.cancel),
    MorphAlertAction(title: 'Delete', style: MorphAlertActionStyle.destructive),
  ];

  testWidgets('an alert is styled on its own', (WidgetTester tester) async {
    await present(
      tester,
      (BuildContext page, BuildContext anchor) => unawaited(
        showMorphAlert(
          page,
          title: 'Title',
          message: 'Message',
          actions: actions,
          textFields: const [MorphAlertTextField(placeholder: 'Name')],
        ),
      ),
    );
    expect(await _watch(tester), isEmpty);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('an action sheet is styled on its own', (
    WidgetTester tester,
  ) async {
    await present(
      tester,
      (BuildContext page, BuildContext anchor) => unawaited(
        showMorphActionSheet(page, title: 'Title', actions: actions),
      ),
    );
    expect(await _watch(tester), isEmpty);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a popover is styled on its own', (WidgetTester tester) async {
    await present(
      tester,
      (BuildContext page, BuildContext anchor) => unawaited(
        showMorphActionSheet(
          page,
          title: 'Title',
          message: 'Message',
          actions: actions,
          anchor: anchor,
        ),
      ),
    );
    expect(await _watch(tester), isEmpty);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a sheet is styled on its own', (WidgetTester tester) async {
    await present(
      tester,
      (BuildContext page, BuildContext anchor) => unawaited(
        presentMorphSheet<void>(
          page,
          grabberVisible: true,
          detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
          builder: (BuildContext context) => _styled('sheet'),
        ),
      ),
    );
    expect(await _watch(tester), isEmpty);
    expect(find.text('sheet'), findsOneWidget);
  });

  for (final mode in MorphDatePickerMode.values) {
    testWidgets('the ${mode.name} picker overlay is styled on its own', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        Align(
          alignment: const Alignment(0, -0.4),
          child: MorphDatePicker(
            value: DateTime(2026, 10, 3, 9, 41),
            mode: mode,
            today: DateTime(2026, 10, 3),
            onChanged: (DateTime value) {},
          ),
        ),
      );
      expect(_unstyled(tester), isEmpty);
      await tester.tapAt(
        tester.getTopLeft(find.byType(MorphDatePicker)) + const Offset(20, 17),
      );
      expect(await _watch(tester), isEmpty);
      expect(
        find.text(mode == MorphDatePickerMode.time ? '37' : 'October 2026'),
        findsWidgets,
      );
    });
  }

  testWidgets('the search toolbar is styled on its own', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const MorphSearchToolbar());
    expect(_unstyled(tester), isEmpty);
    await tester.tap(find.text('Search'));
    expect(await _watch(tester), isEmpty);
  });

  testWidgets('a push zoom is styled on its own', (WidgetTester tester) async {
    late BuildContext home;
    await _pump(
      tester,
      MorphNavigationStack(
        home: Builder(
          builder: (BuildContext context) {
            home = context;
            return const Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: MorphTag(
                  id: 'card',
                  child: ColoredBox(color: Color(0xFFFF00FF)),
                ),
              ),
            );
          },
        ),
      ),
    );
    unawaited(
      pushMorphZoom<void>(
        home,
        from: 'card',
        builder: (BuildContext context) => _page('Photo'),
      ),
    );
    expect(await _watch(tester), isEmpty);
    expect(find.text('Photo'), findsWidgets);
  });
}
