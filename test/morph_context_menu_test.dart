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

/// Pumps [span] in 8 ms frames: the hold clock is a ticker, and a
/// growth read at a coarse step would lag by the gap before its first
/// tick.
Future<void> frames(WidgetTester tester, Duration span) async {
  const Duration step = Duration(milliseconds: 8);
  for (Duration t = Duration.zero; t < span; t += step) {
    await tester.pump(step);
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
const double _gap = MorphContextMenuRegion.measuredMenuGap;
const double _menuHeight = _aboveHeight + _gap + 48 + _gap + _belowHeight;

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
      final longest = math.max(width, card[1].toDouble());
      final lift = math.min(
        (MorphContextMenuRegion.measuredLiftScale - 1) * longest,
        MorphContextMenuRegion.measuredLiftPoints,
      );
      expect(
        preview[2].toDouble(),
        closeTo(width * (1 + lift / longest), 0.05),
      );
    }
    expect(opened, 4);
  });

  group('device growth', () {
    final data =
        (jsonDecode(
                  File(
                    'test/fixtures/ios27-device/context_menu/growth.json',
                  ).readAsStringSync(),
                )
                as Map)
            .cast<String, Object?>();
    final cases = (data['cases']! as List).cast<Map<String, Object?>>();
    Size card(Map<String, Object?> c) {
      final size = (c['card']! as List).cast<num>();
      return Size(size[0].toDouble(), size[1].toDouble());
    }

    List<(double, double)> ramp(Map<String, Object?> c) => <(double, double)>[
      for (final sample in (c['ramp']! as List).cast<List<Object?>>())
        ((sample[0]! as num).toDouble(), (sample[1]! as num).toDouble()),
    ];

    Duration seconds(double t) => Duration(microseconds: (t * 1e6).round());

    test('the growth law replays every held frame on four preview sizes', () {
      var count = 0;
      var squares = 0.0;
      for (final c in cases) {
        // The first frames hold the configuration's value while the
        // render server catches up (a 1 - 1.5 point step on one frame).
        for (final (t, growth) in ramp(c).where(((double, double) s) {
          return s.$1 > 0.235;
        })) {
          final error =
              MorphContextMenuRegion.measuredHoldGrowth(seconds(t)) - growth;
          expect(error.abs(), lessThan(0.25), reason: '${c['name']} at $t');
          squares += error * error;
          count++;
        }
      }
      expect(count, greaterThan(900));
      expect(math.sqrt(squares / count), lessThan(0.1));
    });

    test('the growth is the same number of points for every size', () {
      for (final c in cases.where(
        (Map<String, Object?> c) => (c['name']! as String).endsWith('-1200'),
      )) {
        final (t, growth) = ramp(c).last;
        expect(t, greaterThan(0.73), reason: '${c['name']}');
        expect(growth, closeTo(14.1, 0.2), reason: '${c['name']}');
      }
      expect(
        MorphContextMenuRegion.measuredHoldGrowth(
          MorphContextMenuRegion.measuredHoldDuration,
        ),
        closeTo(14.92, 0.01),
      );
      expect(
        MorphContextMenuRegion.measuredHoldGrowth(const Duration(seconds: 2)),
        MorphContextMenuRegion.measuredHoldGrowthPoints,
      );
    });

    test('a release before the commit point cancels, after it opens', () {
      final commit =
          MorphContextMenuRegion.measuredCommitDuration.inMicroseconds / 1e6;
      var opened = 0;
      var cancelled = 0;
      for (final c in cases) {
        final up = (c['liftUp']! as num).toDouble();
        final events = (c['events']! as Map).cast<String, Object?>();
        final shown = events['willDisplay'] as num?;
        if (up < commit) {
          expect(shown, isNull, reason: '${c['name']} let go at $up');
          cancelled++;
        } else {
          expect(shown, isNotNull, reason: '${c['name']} let go at $up');
          expect(
            shown!.toDouble(),
            lessThan(
              math.min(
                up + 0.06,
                MorphContextMenuRegion.measuredHoldDuration.inMicroseconds /
                        1e6 +
                    0.025,
              ),
            ),
            reason: '${c['name']}',
          );
          opened++;
        }
      }
      expect(cancelled, 7);
      expect(opened, 20);
    });

    test('the open preview lifts along its longest side; the menu stands '
        '16 points off it and grows out of a blob at its center', () {
      for (final c in cases.where((Map<String, Object?> c) {
        return c['preview'] != null;
      })) {
        final size = card(c);
        final preview = (c['preview']! as List).cast<num>();
        final lift = math.min(
          (MorphContextMenuRegion.measuredLiftScale - 1) * size.longestSide,
          MorphContextMenuRegion.measuredLiftPoints,
        );
        final scale = 1 + lift / size.longestSide;
        expect(preview[2], closeTo(size.width * scale, 0.05));
        expect(preview[3], closeTo(size.height * scale, 0.05));
        final menu = (c['menu']! as List).cast<num>();
        final gap = (menu[1] - menu[3] / 2) - (preview[1] + preview[3] / 2);
        expect(
          gap,
          closeTo(MorphContextMenuRegion.measuredMenuGap, 0.01),
          reason: '${c['name']}',
        );
        final blob = (c['blob'] as List?)?.cast<num>();
        if (blob == null) {
          continue;
        }
        // The blob is 0.4 of the shorter side tall everywhere; landscape
        // previews up to 1.5 : 1 keep their aspect in it (the model's
        // uniform 0.4), the 300 x 200 one narrows to 83 x 80 and the
        // portrait one squares off at 32 x 32.
        expect(
          blob[1],
          closeTo(
            MorphContextMenuRegion.measuredRetractScale * size.shortestSide,
            0.4,
          ),
          reason: '${c['name']}',
        );
        if (size.width <= 120) {
          expect(
            blob[0],
            closeTo(
              MorphContextMenuRegion.measuredRetractScale * size.width,
              0.4,
            ),
            reason: '${c['name']}',
          );
        }
      }
    });

    testWidgets('a held 120 x 80 hero replays the device frames', (
      WidgetTester tester,
    ) async {
      frame(tester);
      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              MorphScope(child: child!),
          home: Center(
            child: MorphContextMenuRegion(
              below: MorphSatellite(
                height: 40,
                builder: (BuildContext context, MorphFlight flight) =>
                    const Text('below'),
              ),
              child: const SizedBox(
                key: _heroBox,
                width: 120,
                height: 80,
                child: ColoredBox(color: Color(0xFF0088FF)),
              ),
            ),
          ),
        ),
      );
      final c = cases.firstWhere(
        (Map<String, Object?> c) => c['name'] == 'ctxg-m-1200',
      );
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_heroBox)),
      );
      // The hold clock starts on the first frame after the touch.
      await tester.pump();
      var now = 0.0;
      for (final (t, growth) in ramp(c).where(((double, double) s) {
        return s.$1 > 0.235;
      })) {
        await tester.pump(seconds(t - now));
        now = t;
        expect(
          tester.getRect(find.byKey(_heroBox)).width - 120,
          closeTo(growth, 0.35),
          reason: 'at $t',
        );
      }
      await gesture.up();
      await settle(tester);
      expect(find.text('below'), findsOneWidget);
    });
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
    // The growth: nothing for UIKit's first 0.184 s, then the measured
    // ramp under the resting finger, a function of the time held.
    await frames(tester, const Duration(milliseconds: 160));
    expect(tester.getRect(find.byKey(_heroBox)).width, _heroSize.width);
    await frames(tester, const Duration(milliseconds: 240));
    expect(
      tester.getRect(find.byKey(_heroBox)).width,
      moreOrLessEquals(
        _heroSize.width +
            MorphContextMenuRegion.measuredHoldGrowth(
              const Duration(milliseconds: 400),
            ),
        epsilon: 0.3,
      ),
    );
    expect(_host(tester).holds, 0);
    // The hold threshold (UIKit's 0.78 s): the menu takes off from the
    // grown hero.
    await frames(tester, const Duration(milliseconds: 384));
    expect(_host(tester).holds, 1);
    final MorphFlight flight = _host(tester).flight!;
    final double liftedSourceWidth = flight.sourceRect.width;
    expect(
      liftedSourceWidth,
      moreOrLessEquals(
        _heroSize.width +
            MorphContextMenuRegion.measuredHoldGrowth(
              MorphContextMenuRegion.measuredHoldDuration,
            ),
        epsilon: 0.3,
      ),
    );
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

  testWidgets('a release past the commit point opens the menu; one before '
      'it drops the grown hero at once', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    final Offset hero = tester.getCenter(find.text('hero'));

    TestGesture gesture = await tester.startGesture(hero);
    await frames(tester, const Duration(milliseconds: 360));
    expect(tester.getRect(find.byKey(_heroBox)).width, greaterThan(161));
    await gesture.up();
    await tester.pump();
    expect(
      tester.getRect(find.byKey(_heroBox)).width,
      _heroSize.width,
      reason: 'UIKit drops a preview let go early on the next frame',
    );
    await settle(tester);
    expect(find.text('above'), findsNothing);
    expect(_host(tester).holds, 0);
    expect(_host(tester).taps, 1, reason: 'an early release is a tap');

    gesture = await tester.startGesture(hero);
    await frames(tester, const Duration(milliseconds: 480));
    expect(_host(tester).holds, 0, reason: 'committed, not yet held');
    final double grown = tester.getRect(find.byKey(_heroBox)).width;
    expect(grown, greaterThan(_heroSize.width + 8));
    await gesture.up();
    await tester.pump();
    expect(_host(tester).holds, 1);
    final MorphFlight flight = _host(tester).flight!;
    expect(
      flight.sourceRect.width,
      moreOrLessEquals(grown, epsilon: 0.3),
      reason: 'the flight takes off from the grown hero',
    );
    await settle(tester);
    expect(find.text('above'), findsOneWidget);
    expect(_host(tester).taps, 1, reason: 'a committed release is no tap');
    flight.close();
    await settle(tester);
  });

  testWidgets('the satellites grow out of the hero and retract into it', (
    WidgetTester tester,
  ) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    Rect hero() => tester.getRect(find.byKey(_heroBox).last);
    final Rect rest = tester.getRect(find.text('reply'));
    flight.close();
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final double value = flight.controller.value;
    expect(value, inExclusiveRange(0.05, 0.95));
    final Rect now = tester.getRect(find.text('reply'));
    // The below slot (100 tall) squeezes toward a blob 0.4 of the
    // 48-point hero; the shuttle's own reveal scale (0.95 - 1) rides on
    // top of it.
    const double blob =
        MorphContextMenuRegion.measuredRetractScale * 48 / _belowHeight;
    final double squeezed = rest.height * (blob + (1 - blob) * value);
    expect(now.height, inInclusiveRange(squeezed * 0.95, squeezed + 0.01));
    expect(
      (now.center.dy - hero().center.dy).abs(),
      lessThan((rest.center.dy - hero().center.dy).abs()),
      reason: 'the actions retract toward the hero',
    );
    await settle(tester);
    expect(find.text('reply'), findsNothing);
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
