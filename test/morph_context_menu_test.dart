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

/// The width of the menu column: the lifted hero (184 wide) is narrower
/// than the default minimum, so the minimum wins.
const double _menuWidth = 250;
const double _gap = MorphContextMenuRegion.measuredMenuGap;

/// The open menu holds the hero at UIKit's preview size: 1.15 for a
/// 160 x 48 hero (24 points on its 160-point side, under the 26-point
/// cap), so its slot is 184 x 55.2 - the satellites stand 16 points off
/// the lifted hero, as the device menu stands off the lifted preview.
final double _lift = MorphContextMenuRegion.measuredPreviewScale(_heroSize);
final double _slotHeight = _heroSize.height * _lift;
final double _menuHeight =
    _aboveHeight + _gap + _slotHeight + _gap + _belowHeight;

Matcher _near(double value) => moreOrLessEquals(value, epsilon: 1e-9);

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
      final size = Size(card[0].toDouble(), card[1].toDouble());
      expect(
        preview[2].toDouble(),
        closeTo(
          size.width * MorphContextMenuRegion.measuredPreviewScale(size),
          0.05,
        ),
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
        final scale = MorphContextMenuRegion.measuredPreviewScale(size);
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

  group('device preview', devicePreview);

  group('device morph', deviceMorph);

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
    expect(flight.lastTargetRect.width, _menuWidth);
    expect(flight.lastTargetRect.height, _near(_menuHeight));
    // The satellites stand above and below the hero's slot, and the open
    // hero is lifted about the center it rested at.
    final Rect menu = flight.lastTargetRect;
    expect(tester.getTopLeft(find.text('above')).dy, _near(menu.top));
    final Rect home = tester.getRect(find.byKey(_heroBox).first);
    final Rect open = tester.getRect(
      find.descendant(of: find.byType(Column), matching: find.byKey(_heroBox)),
    );
    expect(open.width, _near(_heroSize.width * _lift));
    expect(open.height, _near(_slotHeight));
    expect((open.center - home.center).distance, lessThan(1e-9));
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
    expect(
      now.height,
      inInclusiveRange(squeezed * 0.95 - 0.01, squeezed + 0.01),
    );
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
    expect(menu.top, _near(600 - 12 - _menuHeight));
    // Start-aligned, the lifted hero keeps its center x: it grows by
    // (1.15 - 1) * 160 / 2 = 12 points to each side, as UIKit's preview
    // grows about the held view's center.
    expect(
      menu.left,
      _near(home.left - (_lift - 1) * _heroSize.width / 2),
      reason: 'start-aligned: the hero keeps its center x',
    );
    expect(tester.getTopLeft(find.text('above')).dy, _near(menu.top));
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
    expect(flight.lastTargetRect.width, _menuWidth);
    expect(flight.lastTargetRect.height, _near(_menuHeight));
    expect(
      tester.getTopLeft(find.text('above')).dy,
      _near(flight.lastTargetRect.top),
    );
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
    // The copy lays out at its natural 72 at once and shows lifted: the
    // 160 x 72 hero keeps the 1.15 scale (its long side is still 160).
    expect(
      heroCopy(tester).height,
      _near(72 * _lift),
      reason: 'content at its natural size, lifted',
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    final double replyMid = tester.getTopLeft(find.text('reply')).dy;
    expect(replyMid, greaterThan(replyBefore));
    expect(replyMid, lessThan(replyBefore + 24 * _lift));
    await settle(tester);
    // The lifted slot grows by the lifted 24 points of the badge.
    expect(
      flight.lastTargetRect.height,
      moreOrLessEquals(before.height + 24 * _lift, epsilon: 0.01),
    );
    expect(
      tester.getTopLeft(find.text('reply')).dy,
      moreOrLessEquals(replyBefore + 24 * _lift, epsilon: 0.01),
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
    expect(shifted.height, _near(before.height));
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
    // 40 + 8 + the 160 x 48 hero lifted to 55.2 + 8 + 100.
    expect(flight!.lastTargetRect.width, 250);
    expect(flight!.lastTargetRect.height, _near(211.2));

    rebuild(() => changed = true);
    await tester.pump();
    await settle(tester);
    expect(find.text('old-above'), findsNothing);
    expect(find.text('old-below'), findsNothing);
    expect(find.text('new-above'), findsOneWidget);
    expect(flight!.lastTargetRect.width, moreOrLessEquals(280, epsilon: 0.01));
    expect(
      flight!.lastTargetRect.height,
      moreOrLessEquals(80 + 4 + 55.2, epsilon: 0.01),
    );
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

const Key _deviceMenu = ValueKey<String>('device-menu');
const ValueKey<String> _flyingHero = ValueKey<String>(
  'morph-shared-fly-morph-context-menu-hero',
);

/// The response and damping ratio of the spring UIKit resizes its open
/// preview on, both ways: fitted to every presentation and close frame of
/// preview.json (iPhone 16 Pro), each from its own start.
const double _previewResponse = 0.284;
const double _previewDamping = 0.81;

/// The progress of a spring of [response] and [damping] released from
/// rest [t] seconds ago.
double _springProgress(double response, double damping, double t) {
  if (t <= 0) {
    return 0;
  }
  final double omega = 2 * math.pi / response;
  final double decay = damping * omega;
  final double damped = omega * math.sqrt(1 - damping * damping);
  return 1 -
      math.exp(-decay * t) *
          (math.cos(damped * t) + decay / damped * math.sin(damped * t));
}

/// The progress of a spring of [_previewResponse] / [_previewDamping]
/// released from rest [t] seconds ago.
double _previewSpring(double t) =>
    _springProgress(_previewResponse, _previewDamping, t);

/// The rms error of [samples] (`(t, progress)`) against a spring of
/// [response] / [damping] released from rest at its best start, from
/// 0.2 s before the first sample to 0.1 s after it, and that start.
(double, double) _springFit(
  List<(double, double)> samples, {
  double response = _previewResponse,
  double damping = _previewDamping,
}) {
  var best = (double.infinity, 0.0);
  for (int i = -200; i < 400; i++) {
    final double start = samples.first.$1 - i / 2000;
    var squares = 0.0;
    for (final (t, progress) in samples) {
      final double error =
          _springProgress(response, damping, t - start) - progress;
      squares += error * error;
    }
    final double rms = math.sqrt(squares / samples.length);
    if (rms < best.$1) {
      best = (rms, start);
    }
  }
  return best;
}

/// The start of a preview spring of [_previewResponse] / [_previewDamping]
/// that grows from an unknown frozen growth to [lifted] through [samples]
/// (`(t, growth)`): for each start the frozen growth is solved by least
/// squares, and the start with the least error wins.
double _frozenStartFit(List<(double, double)> samples, double lifted) {
  var best = (double.infinity, 0.0);
  for (int i = -200; i < 400; i++) {
    final double start = samples.first.$1 - i / 2000;
    var num = 0.0;
    var den = 0.0;
    for (final (t, growth) in samples) {
      final double x = _previewSpring(t - start);
      num += (growth - lifted * x) * (1 - x);
      den += (1 - x) * (1 - x);
    }
    final double frozen = den == 0 ? 0 : num / den;
    var squares = 0.0;
    for (final (t, growth) in samples) {
      final double x = _previewSpring(t - start);
      final double error = frozen + (lifted - frozen) * x - growth;
      squares += error * error;
    }
    if (squares < best.$1) {
      best = (squares, start);
    }
  }
  return best.$2;
}

/// The rms error of [device] samples (`(t, value)`) against [ours] (`(t,
/// value)`, dense from our own clock's zero), at the best placement of
/// our zero on the device clock within 0.25 s before the first device
/// sample.
double _replayError(
  List<(double, double)> device,
  List<(double, double)> ours,
) {
  double at(double t) {
    if (t <= ours.first.$1) {
      return ours.first.$2;
    }
    for (int i = 1; i < ours.length; i++) {
      final (double t1, double v1) = ours[i];
      if (t <= t1) {
        final (double t0, double v0) = ours[i - 1];
        return v0 + (v1 - v0) * (t - t0) / (t1 - t0);
      }
    }
    return ours.last.$2;
  }

  var best = double.infinity;
  for (int i = 0; i < 500; i++) {
    final double zero = device.first.$1 - i / 2000;
    var squares = 0.0;
    for (final (t, value) in device) {
      final double error = at(t - zero) - value;
      squares += error * error;
    }
    best = math.min(best, math.sqrt(squares / device.length));
  }
  return best;
}

/// The rms error of [samples] (`[t, growth]`) against the preview spring
/// from [from] to [to] points of growth, at its best start time.
double _previewSpringError(
  List<(double, double)> samples, {
  required double from,
  required double to,
}) {
  var best = double.infinity;
  for (int i = 0; i < 160; i++) {
    final double start = samples.first.$1 - i / 2000;
    var squares = 0.0;
    for (final (t, growth) in samples) {
      final double error =
          from + (to - from) * _previewSpring(t - start) - growth;
      squares += error * error;
    }
    best = math.min(best, math.sqrt(squares / samples.length));
  }
  return best;
}

void devicePreview() {
  final data =
      (jsonDecode(
                File(
                  'test/fixtures/ios27-device/context_menu/preview.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final cases = (data['cases']! as List).cast<Map<String, Object?>>();
  Size card(Map<String, Object?> c) {
    final size = (c['card']! as List).cast<num>();
    return Size(size[0].toDouble(), size[1].toDouble());
  }

  List<List<double>> samples(Map<String, Object?> c, String key) =>
      <List<double>>[
        for (final sample in (c[key]! as List).cast<List<Object?>>())
          <double>[for (final value in sample) (value! as num).toDouble()],
      ];

  test('UIKit keeps the open preview lifted about the held view\'s center '
      'until the close, on one spring each way', () {
    expect(cases, hasLength(20));
    for (final c in cases) {
      final size = card(c);
      final longest = size.longestSide;
      final lifted =
          (MorphContextMenuRegion.measuredPreviewScale(size) - 1) * longest;
      final frozen = ((c['frozen']! as List)[1]! as num).toDouble();
      final open = samples(c, 'open');
      final close = samples(c, 'close');
      double growth(List<double> f) => math.max(f[3], f[4]) - longest;
      for (final f in <List<double>>[...open, ...close]) {
        expect(
          (Offset(f[1], f[2]) - const Offset(201, 300)).distance,
          lessThan(0.4),
          reason: '${c['name']} at ${f[0]}',
        );
      }
      // From the held size straight to the lifted one: a small preview
      // shrinks (60 x 40: 74 to 69), a large one keeps growing (300 x 200:
      // 314 to 326), and none returns to its natural size while open.
      final span = (lifted - frozen).abs();
      for (final f in open) {
        expect(
          growth(f),
          inInclusiveRange(
            math.min(frozen, lifted) - 0.03 * span - 0.05,
            math.max(frozen, lifted) + 0.03 * span + 0.05,
          ),
          reason: '${c['name']} at ${f[0]}',
        );
      }
      expect(growth(open.last), closeTo(lifted, 0.01), reason: '${c['name']}');
      expect(
        _previewSpringError(
          <(double, double)>[for (final f in open) (f[0], growth(f))],
          from: frozen,
          to: lifted,
        ),
        lessThan(0.12),
        reason: '${c['name']} open',
      );
      expect(growth(close.first), closeTo(lifted, 0.9), reason: '${c['name']}');
      expect(growth(close.last), closeTo(0, 0.01), reason: '${c['name']}');
      expect(
        _previewSpringError(
          <(double, double)>[for (final f in close) (f[0], growth(f))],
          from: lifted,
          to: 0,
        ),
        lessThan(0.25),
        reason: '${c['name']} close',
      );
    }
  });

  for (final String name in <String>[
    'ctxg-s-1200',
    'ctxg-m-1200',
    'ctxg-t-1200',
    'ctxg-l-1200',
  ]) {
    testWidgets('$name: the held hero takes off from its grown size, opens at '
        'the device preview with the menu 16 points off it, and lands at its '
        'natural size', (WidgetTester tester) async {
      final c = cases.firstWhere((Map<String, Object?> c) => c['name'] == name);
      final size = card(c);
      final open = samples(c, 'open').last;
      final menu = (c['menu']! as List).cast<num>();
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      MorphFlight? flight;
      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              MorphScope(child: child!),
          home: Stack(
            children: <Widget>[
              Positioned(
                left: 201 - size.width / 2,
                top: 300 - size.height / 2,
                child: MorphContextMenuRegion(
                  alignment: Alignment.center,
                  onOpen: (MorphFlight f) => flight = f,
                  below: MorphSatellite(
                    height: menu[3].toDouble(),
                    builder: (BuildContext context, MorphFlight flight) =>
                        Center(
                          child: SizedBox(
                            key: _deviceMenu,
                            width: menu[2].toDouble(),
                            height: menu[3].toDouble(),
                          ),
                        ),
                  ),
                  child: SizedBox.fromSize(
                    key: _heroBox,
                    size: size,
                    child: const ColoredBox(color: Color(0xFF0088FF)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      // What is on screen: the flying copy while the hero travels, the
      // source ghost on the launch frame (the flying copy needs one layout
      // to measure), the slot copy in the open menu, the page's own hero
      // otherwise.
      Rect visible() {
        final Finder flying = find.byKey(_flyingHero);
        if (flying.evaluate().isNotEmpty) {
          return tester.getRect(flying);
        }
        final MorphFlight? live = flight;
        if (live != null && !live.isFinished && live.controller.value < 0.5) {
          return live.sourceRect;
        }
        final Finder slot = find.descendant(
          of: find.byType(Column),
          matching: find.byKey(_heroBox),
        );
        if (slot.evaluate().isNotEmpty) {
          return tester.getRect(slot);
        }
        return tester.getRect(find.byKey(_heroBox).first);
      }

      double growth(Rect r) => r.longestSide - size.longestSide;
      final lifted =
          (MorphContextMenuRegion.measuredPreviewScale(size) - 1) *
          size.longestSide;
      final TestGesture gesture = await tester.startGesture(
        const Offset(201, 300),
      );
      await tester.pump();
      double? grown;
      final release = (c['liftUp']! as num).toDouble();
      var down = true;
      for (int i = 0; i < 300; i++) {
        if (down && i * 8 >= release * 1000) {
          down = false;
          await gesture.up();
        }
        await tester.pump(const Duration(milliseconds: 8));
        expect(tester.takeException(), isNull);
        final Rect hero = visible();
        expect(
          (hero.center - const Offset(201, 300)).distance,
          lessThan(1e-3),
          reason: 'the hero stays centered where it was held, at ${i * 8} ms',
        );
        if (flight == null) {
          continue;
        }
        // From the takeoff on, the hero travels from the grown size to
        // the lifted one and never back through its natural size.
        grown ??= growth(flight!.sourceRect);
        final span = (lifted - grown).abs();
        expect(
          growth(hero),
          inInclusiveRange(
            math.min(grown, lifted) - 0.03 * span - 0.05,
            math.max(grown, lifted) + 0.03 * span + 0.05,
          ),
          reason: 'takeoff at ${i * 8} ms',
        );
      }
      expect(grown, closeTo(14.92, 0.3), reason: 'took off at 0.78 s');
      expect(flight!.controller.isAnimating, isFalse);
      final Rect hero = visible();
      expect(hero.center.dx, closeTo(open[1], 0.4));
      expect(hero.center.dy, closeTo(open[2], 0.01));
      expect(hero.width, closeTo(open[3], 0.01));
      expect(hero.height, closeTo(open[4], 0.01));
      final Rect actions = tester.getRect(find.byKey(_deviceMenu));
      expect(actions.center.dx, closeTo(menu[0].toDouble(), 0.01));
      expect(actions.center.dy, closeTo(menu[1].toDouble(), 0.01));
      expect(
        actions.top - hero.bottom,
        closeTo(MorphContextMenuRegion.measuredMenuGap, 0.01),
      );

      flight!.close();
      for (int i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        final Rect now = visible();
        expect((now.center - const Offset(201, 300)).distance, lessThan(1e-3));
        expect(
          growth(now),
          inInclusiveRange(-0.05 * lifted, lifted + 0.01),
          reason: 'close at ${i * 8} ms',
        );
      }
      expect(flight!.isFinished, isTrue);
      final Rect home = tester.getRect(find.byKey(_heroBox));
      expect((home.center - const Offset(201, 300)).distance, lessThan(1e-3));
      expect(home.width, moreOrLessEquals(size.width, epsilon: 0.01));
      expect(home.height, moreOrLessEquals(size.height, epsilon: 0.01));
    });
  }
}

/// One frame of a replayed dimming: our clock, the flight value, the
/// scrim channel's value and the painted scrim opacity.
typedef _DimFrame = (double t, double value, double dim, double painted);

/// Holds a [size] hero centered at 201, 300 with a [menu] below it for
/// 1.0 s in [brightness], lets the menu settle, closes it and returns
/// every 4 ms frame from the first flight frame on (`open`) and from the
/// close on (`close`).
Future<({List<_DimFrame> open, List<_DimFrame> close})> _replayDim(
  WidgetTester tester, {
  required Size size,
  required List<num> menu,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  MorphFlight? flight;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Stack(
        children: <Widget>[
          Positioned(
            left: 201 - size.width / 2,
            top: 300 - size.height / 2,
            child: MorphContextMenuRegion(
              alignment: Alignment.center,
              onOpen: (MorphFlight f) => flight = f,
              below: MorphSatellite(
                height: menu[3].toDouble(),
                builder: (BuildContext context, MorphFlight flight) =>
                    SizedBox(width: menu[2].toDouble()),
              ),
              child: SizedBox.fromSize(
                size: size,
                child: const ColoredBox(color: Color(0xFF0088FF)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  double painted() {
    final Iterable<ColoredBox> boxes = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where(
          (ColoredBox box) =>
              box.color.r == 0 &&
              box.color.g == 0 &&
              box.color.b == 0 &&
              box.color.a > 0,
        );
    return boxes.isEmpty ? 0 : boxes.last.color.a;
  }

  final TestGesture gesture = await tester.startGesture(const Offset(201, 300));
  final open = <_DimFrame>[];
  double clock = 0;
  for (int i = 0; i < 500; i++) {
    if (i == 250) {
      await gesture.up();
    }
    await tester.pump(const Duration(milliseconds: 4));
    final MorphFlight? live = flight;
    if (live == null) {
      continue;
    }
    open.add((clock, live.controller.value, live.scrimValue!, painted()));
    clock += 0.004;
  }
  expect(flight!.controller.isAnimating, isFalse);
  expect(flight!.scrimValue, 1);
  flight!.close();
  final close = <_DimFrame>[
    (0, flight!.controller.value, flight!.scrimValue!, painted()),
  ];
  for (int i = 1; i <= 250; i++) {
    await tester.pump(const Duration(milliseconds: 4));
    final double dim = flight!.isFinished ? 0 : flight!.scrimValue!;
    close.add((i * 0.004, flight!.controller.value, dim, painted()));
  }
  expect(flight!.isFinished, isTrue);
  expect(painted(), 0);
  return (open: open, close: close);
}

/// One frame of a replayed hold: our clock, the visible hero and the
/// menu satellite (null once the menu has left the screen).
typedef _ReplayFrame = (double t, Rect hero, Rect? menu);

/// Holds a [size] hero centered at 201, 300 on a 402 x 874 screen with a
/// [menu] (`[center x, center y, width, height]`) below it, lets go after
/// [release] seconds and closes the menu once it has settled. Returns
/// every 8 ms frame from the launch on (`open`, our clock zero at the
/// launch frame) and from the close on (`close`, zero at the close), and
/// the hero's growth at takeoff.
Future<({List<_ReplayFrame> open, List<_ReplayFrame> close, double grown})>
_replayHold(
  WidgetTester tester, {
  required Size size,
  required List<num> menu,
  required double release,
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  MorphFlight? flight;
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Stack(
        children: <Widget>[
          Positioned(
            left: 201 - size.width / 2,
            top: 300 - size.height / 2,
            child: MorphContextMenuRegion(
              alignment: Alignment.center,
              onOpen: (MorphFlight f) => flight = f,
              below: MorphSatellite(
                height: menu[3].toDouble(),
                builder: (BuildContext context, MorphFlight flight) => Center(
                  child: SizedBox(
                    key: _deviceMenu,
                    width: menu[2].toDouble(),
                    height: menu[3].toDouble(),
                  ),
                ),
              ),
              child: SizedBox.fromSize(
                key: _heroBox,
                size: size,
                child: const ColoredBox(color: Color(0xFF0088FF)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Rect hero() {
    final Finder flying = find.byKey(_flyingHero);
    if (flying.evaluate().isNotEmpty) {
      return tester.getRect(flying);
    }
    final MorphFlight? live = flight;
    if (live != null && live.isLanding) {
      return tester.getRect(find.byKey(_heroBox).first);
    }
    if (live != null && !live.isFinished && live.controller.value < 0.5) {
      return live.sourceRect;
    }
    final Finder slot = find.descendant(
      of: find.byType(Column),
      matching: find.byKey(_heroBox),
    );
    if (slot.evaluate().isNotEmpty) {
      return tester.getRect(slot);
    }
    return tester.getRect(find.byKey(_heroBox).first);
  }

  Rect? menuRect() {
    final Finder found = find.byKey(_deviceMenu);
    return found.evaluate().isEmpty ? null : tester.getRect(found);
  }

  final TestGesture gesture = await tester.startGesture(const Offset(201, 300));
  await tester.pump();
  final open = <_ReplayFrame>[];
  double? grown;
  var down = true;
  for (int i = 0; i < 300; i++) {
    if (down && i * 8 >= release * 1000) {
      down = false;
      await gesture.up();
    }
    await tester.pump(const Duration(milliseconds: 8));
    final MorphFlight? live = flight;
    if (live == null) {
      continue;
    }
    grown ??= live.sourceRect.longestSide - size.longestSide;
    open.add((open.length * 0.008, hero(), menuRect()));
  }
  expect(flight!.controller.isAnimating, isFalse);
  flight!.close();
  final close = <_ReplayFrame>[(0, hero(), menuRect())];
  for (int i = 1; i <= 120; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    close.add((i * 0.008, hero(), menuRect()));
  }
  expect(flight!.isFinished, isTrue);
  return (open: open, close: close, grown: grown!);
}

void deviceMorph() {
  final data =
      (jsonDecode(
                File(
                  'test/fixtures/ios27-device/context_menu/morph.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final cases = (data['cases']! as List).cast<Map<String, Object?>>();
  final preview =
      (jsonDecode(
                File(
                  'test/fixtures/ios27-device/context_menu/preview.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final previewCases = (preview['cases']! as List).cast<Map<String, Object?>>();
  List<List<double>>? frames(Object? raw) => raw == null
      ? null
      : <List<double>>[
          for (final sample in (raw as List).cast<List<Object?>>())
            <double>[for (final value in sample) (value! as num).toDouble()],
        ];
  List<num> numbers(Map<String, Object?> c, String key) =>
      (c[key]! as List).cast<num>();
  Size card(Map<String, Object?> c) {
    final size = numbers(c, 'card');
    return Size(size[0].toDouble(), size[1].toDouble());
  }

  double lift(Size size) =>
      (MorphContextMenuRegion.measuredPreviewScale(size) - 1) *
      size.longestSide;

  test('UIKit moves the preview and the menu on one spring each way; the '
      'dimming runs on its own, a frame later', () {
    const MorphSpring spring = MorphContextMenuRegion.measuredSpring;
    expect(spring.response, _previewResponse);
    expect(spring.dampingRatio, _previewDamping);
    expect(
      MorphContextMenuRegion.measuredMotion.openSpring,
      same(MorphContextMenuRegion.measuredMotion.closeSpring),
    );
    expect(cases, hasLength(4));
    for (final c in cases) {
      final String name = c['name']! as String;
      final size = card(c);
      final double lifted = lift(size);
      final double menuY = numbers(c, 'menuRect')[1].toDouble();
      final menu = (c['menu']! as Map).cast<String, Object?>();
      final previewParts = (c['preview']! as Map).cast<String, Object?>();
      final dim = (c['dim']! as Map).cast<String, Object?>();
      // The menu grows out of the preview's center and retracts into it.
      final menuOpen = <(double, double)>[
        for (final f in frames(menu['open'])!)
          (f[0], (f[2] - 300) / (menuY - 300)),
      ];
      final menuClose = <(double, double)>[
        for (final f in frames(menu['close'])!)
          (f[0], (menuY - f[2]) / (menuY - 300)),
      ];
      final previewClose = <(double, double)>[
        for (final f in frames(previewParts['close'])!)
          (f[0], 1 - (math.max(f[3], f[4]) - size.longestSide) / lifted),
      ];
      final (double menuOpenError, double menuOpenStart) = _springFit(menuOpen);
      final (double menuCloseError, double menuCloseStart) = _springFit(
        menuClose,
      );
      final (double previewCloseError, double previewCloseStart) = _springFit(
        previewClose,
      );
      expect(menuOpenError, lessThan(0.006), reason: '$name menu open');
      expect(menuCloseError, lessThan(0.006), reason: '$name menu close');
      expect(previewCloseError, lessThan(0.007), reason: '$name preview close');
      expect(
        (menuCloseStart - previewCloseStart).abs(),
        lessThan(0.004),
        reason: '$name: the preview and the menu close together',
      );
      // The generic flight springs miss the same frames by several
      // percent of the travel.
      for (final MorphSpring other in <MorphSpring>[
        MorphMotion.liquid.openSpring!,
        MorphMotion.liquid.closeSpring!,
      ]) {
        expect(
          _springFit(
            menuClose,
            response: other.response,
            damping: other.dampingRatio,
          ).$1,
          greaterThan(0.015),
          reason: name,
        );
      }
      // The dimming: black at 0.2 with its alpha on a slower spring each
      // way, launched about 12 ms after the geometry.
      final dimOpen = <(double, double)>[
        for (final f in frames(dim['open'])!) (f[0], f[1]),
      ];
      final dimClose = <(double, double)>[
        for (final f in frames(dim['close'])!) (f[0], 1 - f[1]),
      ];
      final (double dimOpenError, double dimOpenStart) = _springFit(
        dimOpen,
        response: 0.32,
        damping: 0.80,
      );
      final (double dimCloseError, double dimCloseStart) = _springFit(
        dimClose,
        response: 0.35,
        damping: 0.85,
      );
      expect(dimOpenError, lessThan(0.004), reason: '$name dim open');
      expect(dimCloseError, lessThan(0.003), reason: '$name dim close');
      expect(_springFit(dimOpen).$1, greaterThan(0.012), reason: name);
      expect(_springFit(dimClose).$1, greaterThan(0.04), reason: name);
      expect(
        dimOpenStart - menuOpenStart,
        inInclusiveRange(0.008, 0.016),
        reason: name,
      );
      expect(
        dimCloseStart - menuCloseStart,
        inInclusiveRange(0.008, 0.016),
        reason: name,
      );
    }
  });

  test('the measured close dips below its rest, so the handoff latch '
      'fires on its zero crossing', () {
    final Simulation close = MorphContextMenuRegion.measuredMotion.closeMotion
        .createSimulation(start: 1, end: 0);
    var lowest = 1.0;
    double? crossing;
    for (int i = 1; i <= 1000; i++) {
      final double t = i / 1000;
      final double x = close.x(t);
      if (crossing == null && x < 0) {
        crossing = t;
      }
      lowest = math.min(lowest, x);
    }
    expect(crossing, isNotNull);
    expect(crossing, closeTo(0.19, 0.01));
    expect(lowest, closeTo(-0.013, 0.002));
  });

  for (final String name in <String>['ctxd-m-1', 'ctxd-l-1']) {
    testWidgets('$name: the hero and the menu replay the device morph, open '
        'and close', (WidgetTester tester) async {
      final c = cases.firstWhere((Map<String, Object?> c) => c['name'] == name);
      final size = card(c);
      final double lifted = lift(size);
      final List<num> menu = numbers(c, 'menuRect');
      final double menuY = menu[1].toDouble();
      final run = await _replayHold(
        tester,
        size: size,
        menu: menu,
        release: 1.0,
      );
      double growth(Rect r) => r.longestSide - size.longestSide;
      final parts = (c['menu']! as Map).cast<String, Object?>();
      final previewParts = (c['preview']! as Map).cast<String, Object?>();
      // Normalized by the DEVICE endpoints: the menu grows out of the
      // held view's center (201, 300) and stands at the device's rect.
      final ourMenuOpen = <(double, double)>[
        for (final (t, _, menuRect) in run.open)
          if (menuRect != null) (t, (menuRect.center.dy - 300) / (menuY - 300)),
      ];
      final ourMenuClose = <(double, double)>[
        for (final (t, _, menuRect) in run.close)
          if (menuRect != null)
            (t, (menuY - menuRect.center.dy) / (menuY - 300)),
      ];
      expect(run.open.first.$3!.center.dy, closeTo(300, 0.05));
      expect(run.close.first.$3!.center.dy, closeTo(menuY, 0.05));
      expect(
        run.close.lastWhere((_ReplayFrame f) => f.$3 != null).$3!.center.dy,
        closeTo(300, 1),
        reason: 'the menu retracts into the held view\'s center',
      );
      final ourHeroClose = <(double, double)>[
        for (final (t, hero, _) in run.close) (t, 1 - growth(hero) / lifted),
      ];
      final deviceMenuOpen = <(double, double)>[
        for (final f in frames(parts['open'])!)
          (f[0], (f[2] - 300) / (menuY - 300)),
      ];
      final deviceMenuClose = <(double, double)>[
        for (final f in frames(parts['close'])!)
          if (f[2] > 300 + 0.05 * (menuY - 300))
            (f[0], (menuY - f[2]) / (menuY - 300)),
      ];
      final deviceHeroClose = <(double, double)>[
        for (final f in frames(previewParts['close'])!)
          (f[0], 1 - (math.max(f[3], f[4]) - size.longestSide) / lifted),
      ];
      expect(
        _replayError(deviceMenuOpen, ourMenuOpen),
        lessThan(0.01),
        reason: 'menu open',
      );
      expect(
        _replayError(deviceMenuClose, ourMenuClose),
        lessThan(0.01),
        reason: 'menu close',
      );
      expect(
        _replayError(deviceHeroClose, ourHeroClose),
        lessThan(0.01),
        reason: 'hero close',
      );
    });
  }

  final dimData =
      (jsonDecode(
                File(
                  'test/fixtures/ios27-device/context_menu/dim.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final dimCases = (dimData['cases']! as List).cast<Map<String, Object?>>();

  test('the dimming is black at 0.2 in light and 0.48 in dark, on the same '
      'springs in both appearances', () {
    expect(dimCases, hasLength(4));
    final MorphMotion dim = MorphContextMenuRegion.measuredDim.motion;
    for (final c in dimCases) {
      final String name = c['name']! as String;
      final bool dark = name.contains('dark');
      final color = (c['color']! as List).cast<num>();
      expect(color.take(3), everyElement(0), reason: name);
      expect(
        color[3],
        MorphContextMenuRegion.measuredDimOpacity(
          dark ? Brightness.dark : Brightness.light,
        ),
        reason: name,
      );
      final parts = (c['dim']! as Map).cast<String, Object?>();
      final open = <(double, double)>[
        for (final f in frames(parts['open'])!) (f[0], f[1]),
      ];
      final close = <(double, double)>[
        for (final f in frames(parts['close'])!) (f[0], 1 - f[1]),
      ];
      expect(
        _springFit(
          open,
          response: dim.openSpring!.response,
          damping: dim.openSpring!.dampingRatio,
        ).$1,
        lessThan(0.004),
        reason: '$name open',
      );
      expect(
        _springFit(
          close,
          response: dim.closeSpring!.response,
          damping: dim.closeSpring!.dampingRatio,
        ).$1,
        lessThan(0.002),
        reason: '$name close',
      );
    }
  });

  for (final String name in <String>['ctxd-m-1', 'ctxd-l-1']) {
    for (final bool dark in <bool>[false, true]) {
      testWidgets('$name${dark ? ' (dark)' : ''}: the dimming replays the '
          'device on its own springs, a beat after the geometry', (
        WidgetTester tester,
      ) async {
        final c = cases.firstWhere(
          (Map<String, Object?> c) => c['name'] == name,
        );
        final size = card(c);
        final List<num> menu = numbers(c, 'menuRect');
        final run = await _replayDim(
          tester,
          size: size,
          menu: menu,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        final double ceiling = dark ? 0.48 : 0.2;
        for (final f in <_DimFrame>[...run.open, ...run.close]) {
          expect(f.$4, lessThanOrEqualTo(ceiling + 1e-6));
          expect(
            f.$4,
            moreOrLessEquals(ceiling * f.$3.clamp(0, 1), epsilon: 0.003),
          );
        }
        final dim = (c['dim']! as Map).cast<String, Object?>();
        // Both clocks start at their own geometry: the device's preview
        // spring (opening from the size frozen at the presentation) and
        // our flight value.
        final previewParts = (c['preview']! as Map).cast<String, Object?>();
        final double lifted = lift(size);
        final double deviceOpenStart = _frozenStartFit(<(double, double)>[
          for (final f in frames(previewParts['open'])!)
            (f[0], math.max(f[3], f[4]) - size.longestSide),
        ], lifted);
        final double deviceCloseStart = _springFit(<(double, double)>[
          for (final f in frames(previewParts['close'])!)
            (f[0], 1 - (math.max(f[3], f[4]) - size.longestSide) / lifted),
        ]).$2;
        final double ourOpenStart = _springFit(<(double, double)>[
          for (final f in run.open)
            if (f.$2 > 0.02 && f.$1 < 0.15) (f.$1, f.$2),
        ]).$2;
        final double ourCloseStart = _springFit(<(double, double)>[
          for (final f in run.close)
            if (f.$2 < 0.98 && f.$1 < 0.15) (f.$1, 1 - f.$2),
        ]).$2;
        double at(List<_DimFrame> ours, double t) {
          for (int i = 1; i < ours.length; i++) {
            if (t <= ours[i].$1) {
              final _DimFrame a = ours[i - 1];
              final _DimFrame b = ours[i];
              return a.$3 + (b.$3 - a.$3) * (t - a.$1) / (b.$1 - a.$1);
            }
          }
          return ours.last.$3;
        }

        double rms(
          List<List<double>> device,
          double deviceStart,
          List<_DimFrame> ours,
          double ourStart, {
          double Function(double t)? model,
        }) {
          var squares = 0.0;
          for (final f in device) {
            final double t = f[0] - deviceStart + ourStart;
            final double error = (model?.call(t) ?? at(ours, t)) - f[1];
            squares += error * error;
          }
          return math.sqrt(squares / device.length);
        }

        final List<List<double>> deviceOpen = frames(dim['open'])!;
        expect(
          rms(deviceOpen, deviceOpenStart, run.open, ourOpenStart),
          lessThan(0.004),
          reason: 'dim open',
        );
        expect(
          rms(
            frames(dim['close'])!,
            deviceCloseStart,
            run.close,
            ourCloseStart,
          ),
          lessThan(0.004),
          reason: 'dim close',
        );
        // The engine's value-driven fade (full at 70 percent of the
        // travel) misses the device dimming by far.
        double valueAt(double t) {
          final _DimFrame f = run.open.lastWhere(
            (_DimFrame f) => f.$1 <= t,
            orElse: () => run.open.first,
          );
          return (f.$2 / 0.7).clamp(0, 1).toDouble();
        }

        expect(
          rms(
            deviceOpen,
            deviceOpenStart,
            run.open,
            ourOpenStart,
            model: valueAt,
          ),
          greaterThan(0.05),
        );
      });
    }
  }

  for (final String name in <String>[
    'ctxg-s-1200',
    'ctxg-m-1200',
    'ctxg-t-1200',
    'ctxg-l-1200',
  ]) {
    testWidgets('$name: the hero replays the device preview, open and '
        'close', (WidgetTester tester) async {
      final c = previewCases.firstWhere(
        (Map<String, Object?> c) => c['name'] == name,
      );
      final size = card(c);
      final double lifted = lift(size);
      final double frozen = ((c['frozen']! as List)[1]! as num).toDouble();
      final run = await _replayHold(
        tester,
        size: size,
        menu: numbers(c, 'menu'),
        release: (c['liftUp']! as num).toDouble(),
      );
      double growth(Rect r) => r.longestSide - size.longestSide;
      final double grown = run.grown;
      final ourOpen = <(double, double)>[
        for (final (t, hero, _) in run.open)
          (t, (growth(hero) - grown) / (lifted - grown)),
      ];
      final ourClose = <(double, double)>[
        for (final (t, hero, _) in run.close) (t, 1 - growth(hero) / lifted),
      ];
      final deviceOpen = <(double, double)>[
        for (final f in frames(c['open'])!)
          (
            f[0],
            (math.max(f[3], f[4]) - size.longestSide - frozen) /
                (lifted - frozen),
          ),
      ];
      final deviceClose = <(double, double)>[
        for (final f in frames(c['close'])!)
          (f[0], 1 - (math.max(f[3], f[4]) - size.longestSide) / lifted),
      ];
      // In points of the device's own travel.
      expect(
        _replayError(deviceOpen, ourOpen) * (lifted - frozen).abs(),
        lessThan(0.12),
        reason: 'open',
      );
      expect(
        _replayError(deviceClose, ourClose) * lifted,
        lessThan(0.25),
        reason: 'close',
      );
    });
  }
}
