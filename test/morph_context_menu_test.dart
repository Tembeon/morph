import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

const Key _heroBox = ValueKey<String>('hero-box');
const Size _heroSize = Size(160, 48);
const double _aboveHeight = 40;
const double _belowHeight = 100;

/// A scrollable page with one held hero, which can be deleted from its
/// own menu - the archived-row case.
class _Host extends StatefulWidget {
  const _Host({this.heroTop = 200, this.enabled = true});

  /// Space above the hero, to place it near an edge.
  final double heroTop;
  final bool enabled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int taps = 0;
  int holds = 0;
  int opens = 0;
  String? picked;
  MorphFlight? flight;
  bool heroMounted = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(brightness: .dark),
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            SizedBox(height: widget.heroTop),
            if (heroMounted)
              Center(
                child: MorphContextMenuRegion(
                  enabled: widget.enabled,
                  onHold: () => holds++,
                  onOpen: (MorphFlight f) {
                    opens++;
                    flight = f;
                  },
                  above: MorphSatellite(
                    height: _aboveHeight,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('above'),
                  ),
                  below: MorphSatellite(
                    height: _belowHeight,
                    builder: (BuildContext context, MorphFlight flight) =>
                        Column(
                          children: <Widget>[
                            TextButton(
                              onPressed: () {
                                picked = 'reply';
                                flight.close();
                              },
                              child: const Text('reply'),
                            ),
                            TextButton(
                              onPressed: () {
                                picked = 'delete';
                                flight.close();
                                setState(() => heroMounted = false);
                              },
                              child: const Text('delete'),
                            ),
                          ],
                        ),
                  ),
                  child: GestureDetector(
                    onTap: () => taps++,
                    child: Container(
                      key: _heroBox,
                      width: _heroSize.width,
                      height: _heroSize.height,
                      color: const Color(0xFF334455),
                      child: Row(
                        children: <Widget>[
                          const Text('hero'),
                          Builder(
                            builder: (BuildContext context) => GestureDetector(
                              onTap: () => MorphContextMenuRegion.open(context),
                              child: const Text('more'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 900),
          ],
        ),
      ),
    );
  }
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

_HostState _host(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host));

void frame(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The width of the menu column: the hero is narrower than the default
/// minimum, so the minimum wins.
const double _menuWidth = 250;
const double _menuHeight =
    _aboveHeight + 8 + 48 + 8 + _belowHeight; // above, gap, hero, gap, below

void main() {
  test('the hold and the lift match an iPhone 16 Pro', () {
    final data =
        (jsonDecode(
                  File(
                    'test/fixtures/ios27-device/context_menu/holds.json',
                  ).readAsStringSync(),
                )
                as Map)
            .cast<String, Object?>();
    final cases = (data['cases']! as List).cast<Map<String, Object?>>();
    final hold =
        MorphContextMenuRegion.measuredHoldDuration.inMicroseconds / 1e6;
    var opened = 0;
    for (final c in cases) {
      final events = (c['events']! as Map).cast<String, Object?>();
      final shown = events['willDisplay'] as num?;
      final up = (c['liftUp']! as num).toDouble();
      if (shown == null) {
        expect(up, lessThan(hold), reason: '${c['name']} let go early');
        continue;
      }
      opened++;
      expect(shown.toDouble(), closeTo(hold, 0.025), reason: '${c['name']}');
      final card = (c['card']! as List).cast<num>();
      final preview = (c['preview']! as List).cast<num>();
      final width = card[0].toDouble();
      final lift = math.min(
        (MorphContextMenuRegion.measuredLiftScale - 1) * width,
        MorphContextMenuRegion.measuredLiftPoints,
      );
      expect(preview[2].toDouble(), closeTo(width + lift, 0.05));
    }
    expect(opened, 4);
  });

  testWidgets('a tap passes through; a hold lifts the hero, then opens the '
      'menu; an action closes it', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('hero'));
    await tester.pump();
    expect(_host(tester).taps, 1);
    expect(find.text('above'), findsNothing);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('hero')),
    );
    // The lift: the hero grows under the finger before anything opens.
    // Inside a scrollable the press waits for the touch deadline; the
    // spring's first tick after its start reads t = 0, so the growth
    // shows on the frame after.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(find.byKey(_heroBox)).width, greaterThan(161));
    expect(_host(tester).holds, 0);
    // The hold threshold (UIKit's 0.78 s): the menu takes off.
    await tester.pump(const Duration(milliseconds: 530));
    expect(_host(tester).holds, 1);
    final MorphFlight flight = _host(tester).flight!;
    final double liftedSourceWidth = flight.sourceRect.width;
    expect(liftedSourceWidth, greaterThan(_heroSize.width + 1));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      flight.sourceRect.width,
      moreOrLessEquals(liftedSourceWidth, epsilon: 0.1),
      reason: 'the flight owns one stable press lift after the hold wins',
    );
    await gesture.up();
    await settle(tester);
    expect(_host(tester).taps, 1, reason: 'the hold is not a tap');
    expect(find.text('above'), findsOneWidget);
    expect(find.text('reply'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(_heroBox).first).width,
      moreOrLessEquals(_heroSize.width, epsilon: 0.1),
      reason: 'after takeoff the hidden source returns to its rest endpoint',
    );
    expect(flight.lastTargetRect.size, const Size(_menuWidth, _menuHeight));
    // The satellites stand above and below the hero's slot.
    final Rect menu = flight.lastTargetRect;
    expect(tester.getTopLeft(find.text('above')).dy, menu.top);
    expect(
      tester.getTopLeft(find.text('reply')).dy,
      greaterThan(menu.top + 96),
    );

    await tester.tap(find.text('reply'));
    await tester.pump();
    expect(_host(tester).picked, 'reply');
    expect(
      flight.sourceRect.width,
      moreOrLessEquals(_heroSize.width, epsilon: 0.1),
      reason: 'close refreshes the natural source before flying home',
    );
    await settle(tester);
    expect(find.text('above'), findsNothing);
    expect(flight.isFinished, isTrue);
    // Home again, at its natural size (the press spring's settle
    // tolerance leaves a fraction of a pixel).
    expect(
      tester.getRect(find.byKey(_heroBox)).width,
      moreOrLessEquals(_heroSize.width, epsilon: 0.1),
    );
  });

  testWidgets('the visible door opens without a hold, and a second open '
      'retargets the same flight', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await settle(tester);
    expect(_host(tester).holds, 0);
    expect(_host(tester).opens, 1);
    expect(find.text('above'), findsOneWidget);
    final MorphFlight first = _host(tester).flight!;
    final BuildContext door = tester.element(find.text('more').first);
    final MorphFlight again = MorphContextMenuRegion.open(door);
    await settle(tester);
    expect(identical(again, first), isTrue);
    expect(_host(tester).opens, 1);
    first.close();
    await settle(tester);
  });

  testWidgets('a scroll cancels the press and never opens', (
    WidgetTester tester,
  ) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('hero')),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await settle(tester);
    expect(_host(tester).holds, 0);
    expect(find.text('above'), findsNothing);
    expect(
      tester.getRect(find.byKey(_heroBox)).width,
      moreOrLessEquals(_heroSize.width, epsilon: 0.1),
    );
  });

  testWidgets('a secondary click opens; a hero near the bottom shifts up so '
      'the menu fits', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host(heroTop: 500));
    final Rect home = tester.getRect(find.byKey(_heroBox));
    expect(home.top, 500);
    await tester.tap(find.text('hero'), buttons: kSecondaryButton);
    await settle(tester);
    expect(_host(tester).holds, 0);
    expect(find.text('above'), findsOneWidget);
    final Rect menu = _host(tester).flight!.lastTargetRect;
    // Clamped to the overlay's bottom margin; the hero travelled up
    // with its column instead of staying put.
    expect(menu.bottom, 600 - 12);
    expect(menu.top, 600 - 12 - _menuHeight);
    expect(menu.left, home.left, reason: 'start-aligned: the hero keeps x');
    expect(tester.getTopLeft(find.text('above')).dy, menu.top);
    _host(tester).flight!.close();
    await settle(tester);
    final Rect back = tester.getRect(find.byKey(_heroBox));
    expect((back.center - home.center).distance, lessThan(0.1));
    expect(back.width, moreOrLessEquals(home.width, epsilon: 0.1));
  });

  testWidgets('the hero flies as one shared element', (
    WidgetTester tester,
  ) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      find.byKey(
        const ValueKey<String>('morph-shared-fly-morph-context-menu-hero'),
      ),
      findsOneWidget,
    );
    await settle(tester);
    _host(tester).flight!.close();
    await settle(tester);
  });

  testWidgets('deleting the hero from its own menu: the source unmounts '
      'mid-close and the flight dissolves', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await settle(tester);
    await tester.tap(find.text('delete'));
    await tester.pump();
    final MorphFlight flight = _host(tester).flight!;
    // The live hero is gone from the page; the shuttle's copies (the
    // ghost, the slot, the flying layer) keep the menu flying home.
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byKey(_heroBox),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(flight.isSourceLost, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(find.text('above'), findsNothing);
  });

  testWidgets('a source that moves with its scrollable is the live return '
      'endpoint', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    final double before = flight.sourceRect.top;
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(80);
    await tester.pump();
    flight.close();
    await tester.pump();
    expect(flight.sourceRect.top, moreOrLessEquals(before - 80));
    await settle(tester);
    expect(
      tester.getRect(find.byKey(_heroBox)).top,
      moreOrLessEquals(before - 80),
    );
  });

  testWidgets('a disabled region ignores the hold but the door still opens', (
    WidgetTester tester,
  ) async {
    frame(tester);
    await tester.pumpWidget(const _Host(enabled: false));
    await tester.longPress(find.text('hero'));
    await settle(tester);
    expect(find.text('above'), findsNothing);
    expect(_host(tester).taps, 1, reason: 'the tap reached the child');
    await tester.tap(find.text('more'));
    await settle(tester);
    expect(find.text('above'), findsOneWidget);
    _host(tester).flight!.close();
    await settle(tester);
  });

  group('live slots', liveSlots);
}

const Key _liveHero = ValueKey<String>('live-hero');

/// A hero whose badge and a capsule whose note row are toggled by
/// notifiers INSIDE the built content: the size changes without any
/// region rebuild, as an app's state usually does.
class _LiveHost extends StatefulWidget {
  const _LiveHost({
    required this.badge,
    required this.expanded,
    this.replica,
    this.opensOnSecondaryTap = true,
    this.onOuterSecondaryTap,
  });

  final ValueNotifier<bool> badge;
  final ValueNotifier<bool> expanded;
  final Widget? replica;
  final bool opensOnSecondaryTap;
  final VoidCallback? onOuterSecondaryTap;

  @override
  State<_LiveHost> createState() => _LiveHostState();
}

class _LiveHostState extends State<_LiveHost> {
  MorphFlight? flight;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(brightness: .dark),
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            const SizedBox(height: 200),
            Center(
              child: GestureDetector(
                onSecondaryTap: widget.onOuterSecondaryTap,
                child: MorphContextMenuRegion(
                  replica: widget.replica,
                  opensOnSecondaryTap: widget.opensOnSecondaryTap,
                  onOpen: (MorphFlight f) => flight = f,
                  above: MorphSatellite(
                    builder: (BuildContext context, MorphFlight flight) =>
                        ValueListenableBuilder<bool>(
                          valueListenable: widget.expanded,
                          builder: (BuildContext context, bool on, Widget? _) =>
                              SizedBox(
                                height: on ? 100 : _aboveHeight,
                                child: const Text('above'),
                              ),
                        ),
                  ),
                  below: MorphSatellite(
                    builder: (BuildContext context, MorphFlight flight) =>
                        const SizedBox(
                          height: _belowHeight,
                          child: Text('reply'),
                        ),
                  ),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.badge,
                    builder: (BuildContext context, bool on, Widget? _) =>
                        Container(
                          key: _liveHero,
                          width: _heroSize.width,
                          height: on ? 72 : _heroSize.height,
                          color: const Color(0xFF334455),
                          child: Row(
                            children: <Widget>[
                              const Text('hero'),
                              Builder(
                                builder: (BuildContext context) =>
                                    GestureDetector(
                                      onTap: () =>
                                          MorphContextMenuRegion.open(context),
                                      child: const Text('more'),
                                    ),
                              ),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 900),
          ],
        ),
      ),
    );
  }
}

/// The hero copy in the open menu's slot: the only hero inside the
/// menu's column (the page's own sits in the ListView, the shuttle's
/// ghost replica and the flying copy outside any Column).
Rect heroCopy(WidgetTester tester) => tester.getRect(
  find.descendant(of: find.byType(Column), matching: find.byKey(_liveHero)),
);

void liveSlots() {
  late ValueNotifier<bool> badge;
  late ValueNotifier<bool> expanded;
  setUp(() {
    badge = ValueNotifier<bool>(false);
    expanded = ValueNotifier<bool>(false);
  });
  tearDown(() {
    badge.dispose();
    expanded.dispose();
  });

  testWidgets('satellites without a height are sized by their content and '
      'seeded at launch', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(_LiveHost(badge: badge, expanded: expanded));
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = tester
        .state<_LiveHostState>(find.byType(_LiveHost))
        .flight!;
    expect(flight.lastTargetRect.size, const Size(_menuWidth, _menuHeight));
    expect(tester.getTopLeft(find.text('above')).dy, flight.lastTargetRect.top);
    flight.close();
    await settle(tester);
  });

  testWidgets('a satellite growing while the menu is open springs the column '
      'out; the hero stays put', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(_LiveHost(badge: badge, expanded: expanded));
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = tester
        .state<_LiveHostState>(find.byType(_LiveHost))
        .flight!;
    final Rect before = flight.lastTargetRect;
    final Rect hero = heroCopy(tester);
    expanded.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    final Rect mid = flight.lastTargetRect;
    expect(mid.height, greaterThan(before.height));
    expect(mid.height, lessThan(before.height + 60));
    expect(mid.top, lessThan(before.top), reason: 'the column grows upward');
    expect(mid.bottom, moreOrLessEquals(before.bottom, epsilon: 0.01));
    expect(
      (heroCopy(tester).topLeft - hero.topLeft).distance,
      lessThan(0.01),
      reason: 'the hero does not move while the capsule grows',
    );
    await settle(tester);
    final Rect after = flight.lastTargetRect;
    expect(after.height, moreOrLessEquals(before.height + 60, epsilon: 0.01));
    expect(
      tester.getTopLeft(find.text('above')).dy,
      moreOrLessEquals(after.top, epsilon: 0.01),
    );
    expect((heroCopy(tester).topLeft - hero.topLeft).distance, lessThan(0.01));
    expanded.value = false;
    await settle(tester);
    expect(
      flight.lastTargetRect.height,
      moreOrLessEquals(before.height, epsilon: 0.01),
    );
    flight.close();
    await settle(tester);
  });

  testWidgets('the hero slot follows the hero content: a badge appearing '
      'shows at once and the actions slide down on the spring', (
    WidgetTester tester,
  ) async {
    frame(tester);
    await tester.pumpWidget(_LiveHost(badge: badge, expanded: expanded));
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = tester
        .state<_LiveHostState>(find.byType(_LiveHost))
        .flight!;
    final Rect before = flight.lastTargetRect;
    final double replyBefore = tester.getTopLeft(find.text('reply')).dy;
    badge.value = true;
    await tester.pump();
    expect(heroCopy(tester).height, 72, reason: 'content at its natural size');
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    final double replyMid = tester.getTopLeft(find.text('reply')).dy;
    expect(replyMid, greaterThan(replyBefore));
    expect(replyMid, lessThan(replyBefore + 24));
    await settle(tester);
    expect(
      flight.lastTargetRect.height,
      moreOrLessEquals(before.height + 24, epsilon: 0.01),
    );
    expect(
      tester.getTopLeft(find.text('reply')).dy,
      moreOrLessEquals(replyBefore + 24, epsilon: 0.01),
    );
    // The source grew the same way: the flight lands into the grown
    // hero without a size pop.
    flight.close();
    await settle(tester);
    expect(tester.getRect(find.byKey(_liveHero)).height, 72);
  });

  testWidgets('the keyboard shifts the column, and the hero travels with '
      'it', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(_LiveHost(badge: badge, expanded: expanded));
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = tester
        .state<_LiveHostState>(find.byType(_LiveHost))
        .flight!;
    final Rect before = flight.lastTargetRect;
    final Rect hero = heroCopy(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump();
    final Rect shifted = flight.lastTargetRect;
    expect(shifted.bottom, 600 - 300 - 12);
    expect(shifted.height, before.height);
    expect(
      heroCopy(tester).top,
      moreOrLessEquals(hero.top - (before.bottom - shifted.bottom)),
    );
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump();
    expect(flight.lastTargetRect, before);
    flight.close();
    await settle(tester);
  });

  testWidgets('a replica supplies every overlay copy and leaves the live '
      'child only at its source', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(
      _LiveHost(
        badge: badge,
        expanded: expanded,
        replica: const SizedBox(
          width: 160,
          height: 48,
          child: Text('ghost-copy'),
        ),
      ),
    );
    expect(find.text('ghost-copy'), findsNothing);
    await tester.tap(find.text('more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    // Mid-flight: source ghost, target slot and shared flying layer use the
    // disposable replica. The stateful child remains a single hidden source.
    expect(find.text('ghost-copy'), findsNWidgets(3));
    expect(find.text('hero'), findsOneWidget);
    await settle(tester);
    expect(find.text('ghost-copy'), findsNWidgets(2));
    expect(find.text('hero'), findsOneWidget);
    tester.state<_LiveHostState>(find.byType(_LiveHost)).flight!.close();
    await settle(tester);
    expect(find.text('ghost-copy'), findsNothing);
  });

  testWidgets('a replica keeps an external FocusNode attached only to the '
      'source child', (WidgetTester tester) async {
    frame(tester);
    final FocusNode node = FocusNode(debugLabel: 'message-owner');
    addTearDown(node.dispose);
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphContextMenuRegion(
              replica: const SizedBox(
                width: 160,
                height: 48,
                child: Text('visual-replica'),
              ),
              below: MorphSatellite(
                height: 48,
                builder: (BuildContext context, MorphFlight flight) =>
                    const Text('action'),
              ),
              onOpen: (MorphFlight value) => flight = value,
              child: Focus(
                focusNode: node,
                child: Builder(
                  builder: (BuildContext context) => GestureDetector(
                    onTap: () => MorphContextMenuRegion.open(context),
                    child: const SizedBox(
                      width: 160,
                      height: 48,
                      child: Text('source-focus'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Finder owner() => find.byWidgetPredicate(
      (Widget candidate) =>
          candidate is Focus && identical(candidate.focusNode, node),
    );
    expect(owner(), findsOneWidget);
    await tester.tap(find.text('source-focus'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(owner(), findsOneWidget);
    expect(find.text('source-focus'), findsOneWidget);
    await settle(tester);
    expect(owner(), findsOneWidget);
    flight!.close();
    await settle(tester);
    expect(owner(), findsOneWidget);
  });

  testWidgets('a rebuilt region updates satellite structure and geometry in '
      'the same frame', (WidgetTester tester) async {
    frame(tester);
    late StateSetter rebuild;
    bool changed = false;
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return Center(
                child: MorphContextMenuRegion(
                  width: changed ? 280 : 250,
                  gap: changed ? 4 : 8,
                  above: MorphSatellite(
                    height: changed ? 80 : 40,
                    builder: (BuildContext context, MorphFlight flight) =>
                        Text(changed ? 'new-above' : 'old-above'),
                  ),
                  below: changed
                      ? null
                      : MorphSatellite(
                          height: 100,
                          builder: (BuildContext context, MorphFlight flight) =>
                              const Text('old-below'),
                        ),
                  onOpen: (MorphFlight value) => flight = value,
                  child: Builder(
                    builder: (BuildContext context) => GestureDetector(
                      onTap: () => MorphContextMenuRegion.open(context),
                      child: const SizedBox(
                        width: 160,
                        height: 48,
                        child: Text('reconfigure'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('reconfigure'));
    await settle(tester);
    expect(flight!.lastTargetRect.size, const Size(250, 204));

    rebuild(() => changed = true);
    await tester.pump();
    await settle(tester);
    expect(find.text('old-above'), findsNothing);
    expect(find.text('old-below'), findsNothing);
    expect(find.text('new-above'), findsOneWidget);
    expect(flight!.lastTargetRect.width, moreOrLessEquals(280, epsilon: 0.01));
    expect(flight!.lastTargetRect.height, moreOrLessEquals(132, epsilon: 0.01));
    flight!.close();
    await settle(tester);
  });

  testWidgets('opensOnSecondaryTap off leaves the right click to whoever '
      'else wants it', (WidgetTester tester) async {
    frame(tester);
    int outer = 0;
    await tester.pumpWidget(
      _LiveHost(
        badge: badge,
        expanded: expanded,
        onOuterSecondaryTap: () => outer++,
      ),
    );
    await tester.tap(find.text('hero'), buttons: kSecondaryButton);
    await settle(tester);
    expect(find.text('above'), findsOneWidget);
    expect(outer, 0);
    tester.state<_LiveHostState>(find.byType(_LiveHost)).flight!.close();
    await settle(tester);

    await tester.pumpWidget(
      _LiveHost(
        badge: badge,
        expanded: expanded,
        opensOnSecondaryTap: false,
        onOuterSecondaryTap: () => outer++,
      ),
    );
    await tester.tap(find.text('hero'), buttons: kSecondaryButton);
    await settle(tester);
    expect(find.text('above'), findsNothing);
    expect(outer, 1);
  });
}
