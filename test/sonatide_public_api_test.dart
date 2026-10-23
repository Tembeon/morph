import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

Widget _app(Widget child, {MorphGlassTier tier = .flat, String? fontFamily}) =>
    WidgetsApp(
      color: const Color(0xFF007AFF),
      builder: (context, child) => MorphTheme(
        data: MorphThemeData(
          glass: MorphGlassRenderer.tier(tier),
          fontFamily: fontFamily,
        ),
        child: child!,
      ),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
      ),
      home: Center(child: child),
    );

void main() {
  setUpAll(() async {
    final report = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library != 'morph glass') report?.call(details);
    };
    await MorphTheme.precacheGlass();
    FlutterError.onError = report;
  });
  for (final tier in MorphGlassTier.values) {
    testWidgets(
      'custom segments commit on up, re-tap clears, preview cancels ($tier)',
      (tester) async {
        int? selected;
        final previews = <int?>[];
        var cancels = 0;
        var changes = 0;
        var builds = 0;
        await tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 300,
                child: MorphSegmentedControl(
                  segments: [
                    for (var i = 0; i < 3; i++)
                      MorphSegment.custom(
                        semanticLabel: 'Reaction $i',
                        child: Text('Glyph $i'),
                        builder: (context, state, child) {
                          builds++;
                          return child!;
                        },
                      ),
                  ],
                  selectedIndex: selected,
                  onChanged: (_) => changes++,
                  onActivated: (index) => setState(
                    () => selected = selected == index ? null : index,
                  ),
                  onPreviewChanged: previews.add,
                  onPreviewCancelled: () => cancels++,
                  track: const ColoredBox(color: Color(0xFF5544AA)),
                  lensColorAt: (position) => Color.lerp(
                    const Color(0xFF112244),
                    const Color(0xFFAABBCC),
                    position / 2,
                  )!,
                ),
              ),
            ),
            tier: tier,
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Glyph 1')),
        );
        expect(selected, isNull);
        expect(previews, [1]);
        await tester.pump();
        final heldBuilds = builds;
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(builds, heldBuilds);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(changes, 1);
        await tester.tap(find.text('Glyph 1'));
        await tester.pumpAndSettle();
        expect(selected, isNull);
        expect(changes, 1);
        final drag = await tester.startGesture(
          tester.getCenter(find.text('Glyph 0')),
        );
        await drag.moveTo(tester.getCenter(find.text('Glyph 2')));
        expect(previews.last, 2);
        await drag.cancel();
        await tester.pumpAndSettle();
        expect(previews.last, isNull);
        expect(cancels, 1);
        expect(selected, isNull);
      },
    );

    testWidgets(
      'tab glyph primary key mounts once through selection and minimize ($tier)',
      (tester) async {
        final primary = GlobalKey();
        final portal = OverlayPortalController();
        final scroll = MorphContentScroll();
        var selected = 0;
        var replicas = 0;
        await tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) => Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: scroll.handle,
                    child: ListView(children: const [SizedBox(height: 2000)]),
                  ),
                  Align(
                    alignment: .bottomCenter,
                    child: MorphTabBar(
                      items: [
                        MorphTabItem.custom(
                          label: 'Письма',
                          semanticValue: '3 непрочитанных письма',
                          glyph: OverlayPortal(
                            key: primary,
                            controller: portal,
                            overlayChildBuilder: (_) => const SizedBox(),
                            child: const Text('Primary'),
                          ),
                          replicaBuilder:
                              (
                                context, {
                                required selected,
                                required minimized,
                              }) {
                                replicas++;
                                return Text(minimized ? 'Mini' : 'Selected');
                              },
                        ),
                        const MorphTabItem(
                          icon: IconData(0xe318),
                          label: 'Search',
                        ),
                      ],
                      selected: selected,
                      onChanged: (index) => setState(() => selected = index),
                      contentScroll: scroll,
                      minimizeBehavior: .onScrollDown,
                    ),
                  ),
                ],
              ),
            ),
            tier: tier,
          ),
        );
        final state = tester.element(find.byKey(primary));
        expect(find.byKey(primary), findsOneWidget);
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Search').first),
        );
        expect(selected, 1);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.element(find.byKey(primary)), same(state));
        final before = replicas;
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(replicas, before);
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(primary), findsOneWidget);
      },
    );
  }

  testWidgets('disabling a segment preview safely updates its consumer', (
    tester,
  ) async {
    var enabled = true;
    int? preview;
    late StateSetter update;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 300,
              child: MorphSegmentedControl(
                segments: const [
                  MorphSegment.custom(
                    semanticLabel: 'Like',
                    child: Text('Reaction'),
                  ),
                ],
                selectedIndex: null,
                onChanged: enabled ? (_) {} : null,
                onPreviewChanged: (index) => setState(() => preview = index),
              ),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Reaction')),
    );
    await tester.pump();
    expect(preview, 0);
    update(() => enabled = false);
    await tester.pump();
    await tester.pump();
    expect(preview, isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'touch target separates hit size, cancels, re-enters and keeps child builds flat',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var taps = 0;
      var builds = 0;
      var paints = 0;
      var enabled = true;
      late StateSetter update;
      final painted = GlobalKey();
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MorphTouchTarget(
                focusNode: focus,
                autofocus: true,
                enabled: enabled,
                semanticLabel: 'Like',
                semanticValue: 'New',
                onTap: () => taps++,
                builder: (context, state, child) {
                  builds++;
                  return child!;
                },
                child: MorphTouchFeedback(
                  shape: const BeveledRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: SizedBox(
                    key: painted,
                    width: 24,
                    height: 24,
                    child: CustomPaint(painter: _CountPaint(() => paints++)),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(painted)), const Size(24, 24));
      final target = find.byType(MorphTouchTarget);
      expect(tester.getSize(target), const Size(48, 48));
      final center = tester.getCenter(target);
      final gesture = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump();
      final before = builds;
      final beforePaints = paints;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(builds, before);
      expect(paints, beforePaints);
      await gesture.moveTo(center + const Offset(150, 0));
      await gesture.moveTo(center);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      final outside = await tester.startGesture(center);
      await outside.moveTo(center + const Offset(150, 0));
      await outside.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      final cancelled = await tester.startGesture(center);
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(taps, 1);
      final disabled = await tester.startGesture(center);
      update(() => enabled = false);
      await tester.pump();
      await disabled.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      update(() => enabled = true);
      await tester.pump();
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, 3);
      final unmount = await tester.startGesture(center);
      await tester.pumpWidget(const SizedBox());
      await unmount.up();
      await tester.pumpAndSettle();
      expect(taps, 3);
    },
  );

  testWidgets('touch target loses scroll arbitration and hold suppresses tap', (
    tester,
  ) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      _app(
        ListView(
          children: [
            MorphTouchTarget(
              onTap: () => taps++,
              onLongPress: () => holds++,
              child: const MorphTouchFeedback(
                child: SizedBox(height: 80, width: 150),
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    await tester.drag(find.byType(MorphTouchTarget), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(holds, 0);
    await tester.pumpWidget(
      _app(
        MorphTouchTarget(
          onTap: () => taps++,
          onLongPress: () => holds++,
          child: const MorphTouchFeedback(
            child: SizedBox(height: 40, width: 100),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphTouchTarget)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(holds, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('a scroll-delayed touch cannot arrive after unmount', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        ListView(
          children: [
            MorphTouchTarget(
              onTap: () => taps++,
              child: const MorphTouchFeedback(
                child: SizedBox(width: 100, height: 40),
              ),
            ),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphTouchTarget)),
    );
    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });

  for (final archive in [false, true]) {
    testWidgets(
      'context menu completes after its source is ${archive ? 'archived' : 'disabled'}',
      (tester) async {
        final controller = MorphMenuPresentationController();
        addTearDown(controller.dispose);
        var enabled = true;
        var archived = false;
        late StateSetter update;
        await tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return archived
                    ? const SizedBox()
                    : MorphContextMenuRegion(
                        controller: controller,
                        enabled: enabled,
                        menu: [
                          MorphMenuItem(
                            title: 'Archive',
                            onSelected: () => setState(() => archived = true),
                          ),
                        ],
                        child: const SizedBox(
                          width: 120,
                          height: 40,
                          child: Text('Hero'),
                        ),
                      );
              },
            ),
          ),
        );
        controller.open();
        await tester.pumpAndSettle();
        final done = controller.closed;
        if (archive) {
          await tester.tap(find.text('Archive'));
        } else {
          update(() => enabled = false);
        }
        await tester.pumpAndSettle();
        await done;
        expect(controller.isOpen, isFalse);
        expect(find.text('Archive'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('menuBuilder refreshes while a source is arming its hold', (
    tester,
  ) async {
    var title = 'Before hold';
    late StateSetter update;
    final controller = MorphMenuPresentationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MorphMenuSource(
              controller: controller,
              menuBuilder: (_) => [MorphMenuItem(title: title)],
              child: const SizedBox(
                width: 100,
                height: 40,
                child: Text('Hold source'),
              ),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hold source')),
    );
    await tester.pump(const Duration(milliseconds: 50));
    update(() => title = 'During hold');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('During hold'), findsOneWidget);
    expect(find.text('Before hold'), findsNothing);
    controller.close();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'menu controller observes fresh entries, updates and completed close',
    (tester) async {
      final controller = MorphMenuPresentationController();
      addTearDown(controller.dispose);
      var title = 'Old';
      var archived = false;
      late StateSetter update;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return archived
                  ? const SizedBox()
                  : MorphMenuSource(
                      controller: controller,
                      menuBuilder: (_) => [
                        MorphMenuItem(
                          title: title,
                          subtitle: 'Details',
                          state: .on,
                          onSelected: () => setState(() => archived = true),
                        ),
                      ],
                      child: const SizedBox(
                        width: 100,
                        height: 40,
                        child: Text('Source'),
                      ),
                    );
            },
          ),
        ),
      );
      title = 'Fresh';
      controller.open();
      await tester.pumpAndSettle();
      expect(controller.isOpen, isTrue);
      expect(find.text('Fresh'), findsOneWidget);
      update(() => title = 'Updated');
      await tester.pumpAndSettle();
      expect(find.text('Updated'), findsOneWidget);
      var closed = false;
      final done = controller.closed.then((_) => closed = true);
      controller.close();
      controller.open();
      expect(closed, isFalse);
      await tester.pumpAndSettle();
      await done;
      expect(controller.isOpen, isFalse);
      controller.open();
      await tester.pumpAndSettle();
      final archivedDone = controller.closed;
      await tester.tap(find.text('Updated'));
      await tester.pumpAndSettle();
      await archivedDone;
      expect(archived, isTrue);
      expect(controller.isOpen, isFalse);
      expect(find.text('Updated'), findsNothing);
    },
  );

  for (final explicit in [false, true]) {
    testWidgets(
      'custom shell boundary and context controller use correct overlay (local=$explicit)',
      (tester) async {
        final controller = MorphMenuPresentationController();
        addTearDown(controller.dispose);
        final root = GlobalKey<NavigatorState>();
        OverlayState? local;
        var title = 'First';
        await tester.pumpWidget(
          WidgetsApp(
            navigatorKey: root,
            color: const Color(0xFF007AFF),
            pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, animation, secondaryAnimation) =>
                  builder(context),
            ),
            home: MorphPresentationBoundary(
              child: Navigator(
                onGenerateRoute: (_) => PageRouteBuilder<void>(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      Builder(
                        builder: (context) {
                          local = Overlay.of(context);
                          return Center(
                            child: MorphContextMenuRegion(
                              controller: controller,
                              overlay: explicit ? local : null,
                              menuBuilder: (_) => [MorphMenuItem(title: title)],
                              child: const SizedBox(
                                width: 120,
                                height: 40,
                                child: Text('Held'),
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ),
            ),
          ),
        );
        title = 'Fresh context';
        controller.open();
        await tester.pumpAndSettle();
        expect(find.text('Fresh context'), findsOneWidget);
        final overlay = tester.state<OverlayState>(
          find
              .ancestor(
                of: find.text('Fresh context'),
                matching: find.byType(Overlay),
              )
              .first,
        );
        expect(overlay, same(explicit ? local : root.currentState!.overlay));
        controller.close();
        await tester.pumpAndSettle();
        await controller.closed;
        expect(controller.isOpen, isFalse);
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'custom font, RU/EN, text scale and tab semantic value ($direction)',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(
          _app(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Directionality(
                textDirection: direction,
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    MorphTabBar(
                      items: const [
                        MorphTabItem(
                          icon: IconData(0xe318),
                          label: 'Письма',
                          semanticValue: '3 новых',
                        ),
                        MorphTabItem(icon: IconData(0xe318), label: 'Library'),
                      ],
                      selected: 0,
                      onChanged: (_) {},
                      appearance: const MorphTabBarAppearance(
                        textStyle: TextStyle(fontSize: 11),
                        selectedTextStyle: TextStyle(fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: MorphSegmentedControl(
                        segments: const [
                          MorphSegment('Реакции'),
                          MorphSegment('Reaction'),
                        ],
                        selectedIndex: 0,
                        onChanged: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
            fontFamily: 'SourceCodePro',
          ),
        );
        final text = tester.widget<Text>(find.text('Письма').first);
        expect(text.style!.fontFamily, 'SourceCodePro');
        expect(text.textScaler!.scale(10), 12.5);
        final node = tester.getSemantics(find.bySemanticsLabel('Письма').first);
        expect(node.getSemanticsData().value, '3 новых');
        expect(node.getSemanticsData().role, SemanticsRole.tab);
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('clear search default comes from MorphLocalizations', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    final text = TextEditingController(text: 'query');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF007AFF),
        localizationsDelegates: const [_StringsDelegate()],
        home: Center(child: MorphSearchField(controller: text)),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Очистить'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Очистить'));
    await tester.pumpAndSettle();
    expect(text.text, isEmpty);
    semantics.dispose();
  });
}

class _Strings extends DefaultMorphLocalizations {
  const _Strings();
  @override
  String get clearTextLabel => 'Очистить';
}

class _StringsDelegate extends LocalizationsDelegate<MorphLocalizations> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MorphLocalizations> load(Locale locale) =>
      SynchronousFuture(const _Strings());
  @override
  bool shouldReload(_StringsDelegate old) => false;
}

class _CountPaint extends CustomPainter {
  _CountPaint(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) => onPaint();
  @override
  bool shouldRepaint(_CountPaint oldDelegate) => false;
}
