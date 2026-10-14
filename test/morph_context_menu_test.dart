import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/menu.dart' show MorphMenuLayer;
import 'package:morph/widgets.dart';

import 'support/shuttle.dart';

/// Rows of a device-sized menu: one free-form row filling a menu [height]
/// points tall with its 10-point insets.
List<MorphMenuEntry> _deviceRows(num height) => <MorphMenuEntry>[
  MorphMenuWidget(
    height: height.toDouble() - 20,
    builder: (BuildContext context) => SizedBox(height: height.toDouble() - 20),
  ),
];

/// The open menu's shape as it shows, or null while no menu does.
Rect? _menuShape(WidgetTester tester) {
  final Finder layers = find.byType(MorphMenuLayer);
  if (layers.evaluate().isEmpty) return null;
  final motion = tester.widget<MorphMenuLayer>(layers.first).host.menuMotion;
  if (motion == null || !motion.isPresented) return null;
  return motion.menuBlob.rect;
}

/// The open menu's final frame.
Rect _menuFrame(WidgetTester tester) => tester
    .widget<MorphMenuLayer>(find.byType(MorphMenuLayer).first)
    .host
    .menuMotion!
    .menuRect;

const Key _heroBox = ValueKey<String>('hero-box');
const Size _heroSize = Size(160, 48);
const double _accessoryHeight = 40;

/// The rect of the held view as it shows: the preview in the overlay
/// while a flight carries it, the page's own view otherwise.
Rect _shown(WidgetTester tester, MorphFlight? flight, {Key key = _heroBox}) {
  final Finder views = find.byKey(key);
  if (flight != null && flight.isAirborne && views.evaluate().length > 1) {
    return tester.getRect(views.last);
  }
  return tester.getRect(views.first);
}

/// A scrollable page with one held hero, which can be deleted from its
/// own menu - the archived-row case.
class _Host extends StatefulWidget {
  const _Host({this.heroTop = 200, this.enabled = true, this.rows = 2});

  /// Space above the hero, to place it near an edge.
  final double heroTop;
  final bool enabled;

  /// How many rows the menu has: reply, delete, then fillers.
  final int rows;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int taps = 0;
  int holds = 0;
  int opens = 0;
  int closes = 0;
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
                  onClose: () => closes++,
                  accessory: MorphSatellite(
                    height: _accessoryHeight,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const SizedBox(
                          height: _accessoryHeight,
                          child: Text('above'),
                        ),
                  ),
                  menu: <MorphMenuEntry>[
                    MorphMenuItem(
                      title: 'reply',
                      onSelected: () => picked = 'reply',
                    ),
                    MorphMenuItem(
                      title: 'delete',
                      destructive: true,
                      onSelected: () {
                        picked = 'delete';
                        setState(() => heroMounted = false);
                      },
                    ),
                    for (var i = 2; i < widget.rows; i++)
                      MorphMenuItem(title: 'row $i'),
                  ],
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

const double _gap = MorphContextMenuRegion.measuredMenuGap;

/// The open preview is the held view at UIKit's preview size: 1.15 for a
/// 160 x 48 view (24 points on its 160-point side, under the 26-point
/// cap), so 184 x 55.2; the menu stands 16 points off it, as the device
/// menu stands off the lifted preview.
final double _lift = MorphContextMenuRegion.measuredPreviewScale(_heroSize);

/// The height of a menu of [rows] plain rows.
double _rowsHeight(int rows) => MorphMenuTuning.standard.menuHeight(rows);

Matcher _near(double value) => moreOrLessEquals(value, epsilon: 1e-6);

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
          home: const Center(
            child: MorphContextMenuRegion(
              menu: <MorphMenuEntry>[MorphMenuItem(title: 'below')],
              child: SizedBox(
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
      'menu; a row closes it', (WidgetTester tester) async {
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
    // The preview is lifted about the center the hero rested at; the
    // accessory stands 16 points above it and the menu 16 points below.
    final Rect home = tester.getRect(find.byKey(_heroBox).first);
    final Rect open = tester.getRect(find.byKey(_heroBox).last);
    expect(open.width, _near(_heroSize.width * _lift));
    expect(open.height, _near(_heroSize.height * _lift));
    expect((open.center - home.center).distance, lessThan(1e-6));
    expect(flight.lastTargetRect, open);
    expect(tester.getRect(find.text('above')).bottom, _near(open.top - _gap));
    final Rect menu = _menuFrame(tester);
    expect(menu.top, _near(open.bottom + _gap));
    expect(menu.size, Size(250, _rowsHeight(2)));
    expect(menu.center.dx, _near(home.center.dx));

    await tester.tap(find.text('reply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_host(tester).picked, 'reply');
    await settle(tester);
    expect(find.text('above'), findsNothing);
    expect(find.text('reply'), findsNothing);
    expect(flight.isFinished, isTrue);
    expect(_host(tester).closes, 1);
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
    expect(find.text('reply'), findsOneWidget);
    final MorphFlight first = _host(tester).flight!;
    final BuildContext door = tester.element(find.text('more').first);
    final MorphFlight again = MorphContextMenuRegion.open(door);
    await settle(tester);
    expect(identical(again, first), isTrue);
    expect(_host(tester).opens, 1);
    MorphContextMenuRegion.close(door);
    await settle(tester);
    expect(first.isFinished, isTrue);
    expect(find.text('reply'), findsNothing);
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
    expect(find.text('reply'), findsNothing);
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
    expect(find.text('reply'), findsOneWidget);
    expect(_host(tester).taps, 1, reason: 'a committed release is no tap');
    flight.close();
    await settle(tester);
    expect(find.text('reply'), findsNothing);
  });

  testWidgets('the menu grows out of a blob at the hero\'s center and '
      'retracts into it', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    final Rect home = tester.getRect(find.byKey(_heroBox).first);
    final Rect rest = _menuShape(tester)!;
    flight.close();
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final Rect now = _menuShape(tester)!;
    expect(now.height, lessThan(rest.height));
    expect(now.width, lessThan(rest.width));
    expect(
      (now.center - home.center).distance,
      lessThan((rest.center - home.center).distance),
    );
    await settle(tester);
    expect(find.text('reply'), findsNothing);
  });

  testWidgets('the preview and the menu build nothing per flight frame', (
    WidgetTester tester,
  ) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    flight.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    var built = 0;
    final names = <String>[];
    debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
      built++;
      names.add(element.widget.runtimeType.toString());
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(flight.controller.value, inExclusiveRange(0.05, 0.95));
    expect(built, 0, reason: 'the close builds $names');
    debugOnRebuildDirtyWidget = null;
    await settle(tester);
  });

  testWidgets('the row semantics stand where they paint, open and '
      'unfolding', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await settle(tester);
    Rect global(SemanticsNode node) {
      Rect rect = node.rect;
      for (SemanticsNode? n = node; n != null; n = n.parent) {
        final Matrix4? transform = n.transform;
        if (transform != null) {
          rect = MatrixUtils.transformRect(transform, rect);
        }
      }
      return rect;
    }

    void follows(String when) {
      for (final String row in <String>['reply', 'delete']) {
        final Offset painted = tester.getCenter(find.text(row));
        final Rect read = global(tester.getSemantics(find.text(row)));
        expect(
          (read.center.dy - painted.dy).abs(),
          lessThan(1),
          reason: '$row $when: $read vs $painted',
        );
        expect(read.contains(painted), isTrue, reason: '$row $when');
      }
    }

    follows('open');
    _host(tester).flight!.close();
    await settle(tester);
    await tester.tap(find.text('more'));
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_host(tester).flight!.controller.value, lessThan(0.95));
    follows('opening');
    _host(tester).flight!.close();
    await settle(tester);
    semantics.dispose();
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
    expect(find.text('reply'), findsNothing);
    expect(
      tester.getRect(find.byKey(_heroBox)).width,
      moreOrLessEquals(_heroSize.width, epsilon: 0.1),
    );
  });

  testWidgets('a finger resting after a scroll took it schedules no frames', (
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
    await settle(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await gesture.up();
    await settle(tester);
    expect(_host(tester).holds, 0);
  });

  testWidgets('a secondary click opens; a hero near the bottom gets its menu '
      'above it, reversed', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host(heroTop: 500));
    final Rect home = tester.getRect(find.byKey(_heroBox));
    expect(home.top, 500);
    await tester.tap(find.text('hero'), buttons: kSecondaryButton);
    await settle(tester);
    expect(_host(tester).holds, 0);
    expect(find.text('reply'), findsOneWidget);
    final Rect open = tester.getRect(find.byKey(_heroBox).last);
    expect((open.center - home.center).distance, lessThan(1e-6));
    final Rect menu = _menuFrame(tester);
    // Above the preview and its accessory, the entries reversed.
    expect(menu.bottom, _near(open.top - _accessoryHeight - _gap - _gap));
    expect(
      tester.getCenter(find.text('delete')).dy,
      lessThan(tester.getCenter(find.text('reply')).dy),
    );
    _host(tester).flight!.close();
    await settle(tester);
    final Rect back = tester.getRect(find.byKey(_heroBox));
    expect((back.center - home.center).distance, lessThan(0.1));
    expect(back.width, moreOrLessEquals(home.width, epsilon: 0.1));
  });

  testWidgets('a menu that fits on neither side moves the preview with it', (
    WidgetTester tester,
  ) async {
    frame(tester);
    await tester.pumpWidget(const _Host(heroTop: 500, rows: 10));
    final Rect home = tester.getRect(find.byKey(_heroBox));
    await tester.tap(find.text('more'));
    await settle(tester);
    final Rect open = tester.getRect(find.byKey(_heroBox).last);
    final Rect menu = _menuFrame(tester);
    expect(menu.height, _rowsHeight(10));
    expect(menu.bottom, _near(600 - 12));
    expect(menu.top, _near(open.bottom + _gap));
    expect(open.center.dy, lessThan(home.center.dy - 100));
    expect(open.center.dx, _near(home.center.dx));
    _host(tester).flight!.close();
    await settle(tester);
    final Rect back = tester.getRect(find.byKey(_heroBox));
    expect((back.center - home.center).distance, lessThan(0.1));
  });

  testWidgets('the preview is one copy in the overlay over the hidden held '
      'view', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(_heroBox), findsNWidgets(2));
    await settle(tester);
    _host(tester).flight!.close();
    await settle(tester);
    expect(find.byKey(_heroBox), findsOneWidget);
  });

  testWidgets('deleting the hero from its own menu: the source unmounts '
      'mid-close and the flight dissolves', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('more'));
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    await tester.tap(find.text('delete'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_host(tester).picked, 'delete');
    // The live hero is gone from the page; the overlay's copy keeps the
    // preview flying home.
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byKey(_heroBox),
      ),
      findsNothing,
    );
    expect(flight.isSourceLost, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(find.text('reply'), findsNothing);
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
    expect(find.text('reply'), findsNothing);
    expect(_host(tester).taps, 1, reason: 'the tap reached the child');
    await tester.tap(find.text('more'));
    await settle(tester);
    expect(find.text('reply'), findsOneWidget);
    _host(tester).flight!.close();
    await settle(tester);
  });

  group('accessory', accessory);

  group('preview', previews);

  group('menu rows', menuRows);
}

/// A held 160 x 48 hero with three menu rows, recording what was chosen
/// and the haptics played.
class _RowsHost extends StatelessWidget {
  const _RowsHost({required this.picked, this.onOpen});

  final List<String> picked;
  final ValueChanged<MorphFlight>? onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: Center(
          child: MorphContextMenuRegion(
            onOpen: onOpen,
            menu: <MorphMenuEntry>[
              for (final String title in <String>['Reply', 'Copy', 'Delete'])
                MorphMenuItem(
                  title: title,
                  destructive: title == 'Delete',
                  onSelected: () => picked.add(title),
                ),
            ],
            child: Builder(
              builder: (BuildContext context) => GestureDetector(
                onTap: () => MorphContextMenuRegion.open(context),
                child: Container(
                  key: _heroBox,
                  width: _heroSize.width,
                  height: _heroSize.height,
                  color: const Color(0xFF334455),
                  child: const Text('rows-hero'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void menuRows() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> haptics;
  setUp(() {
    haptics = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String? ?? 'vibrate');
        }
        return null;
      },
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('the held finger slides onto a row and chooses it on release, '
      'with a selection haptic per row', (WidgetTester tester) async {
    frame(tester);
    final picked = <String>[];
    MorphFlight? flight;
    await tester.pumpWidget(
      _RowsHost(picked: picked, onOpen: (MorphFlight f) => flight = f),
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_heroBox)),
    );
    await frames(tester, const Duration(milliseconds: 1000));
    expect(haptics, <String>['HapticFeedbackType.heavyImpact']);
    expect(find.text('Copy'), findsOneWidget);
    final Offset reply = tester.getCenter(find.text('Reply'));
    final Offset copy = tester.getCenter(find.text('Copy'));
    await gesture.moveTo(reply);
    await frames(tester, const Duration(milliseconds: 50));
    await gesture.moveTo(copy);
    await frames(tester, const Duration(milliseconds: 50));
    expect(haptics, <String>[
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
    ]);
    await gesture.up();
    await settle(tester);
    expect(picked, <String>['Copy']);
    expect(flight!.isFinished, isTrue);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a release on the preview keeps the menu open; a tap on a row '
      'chooses it and both fly home', (WidgetTester tester) async {
    frame(tester);
    final picked = <String>[];
    MorphFlight? flight;
    await tester.pumpWidget(
      _RowsHost(picked: picked, onOpen: (MorphFlight f) => flight = f),
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_heroBox)),
    );
    await frames(tester, const Duration(milliseconds: 1000));
    await gesture.up();
    await settle(tester);
    expect(find.text('Reply'), findsOneWidget);
    expect(picked, isEmpty);
    await tester.tap(find.text('Reply'));
    await settle(tester);
    expect(picked, <String>['Reply']);
    expect(flight!.isFinished, isTrue);
  });

  testWidgets('a tap outside closes the menu and the preview', (
    WidgetTester tester,
  ) async {
    frame(tester);
    final picked = <String>[];
    MorphFlight? flight;
    await tester.pumpWidget(
      _RowsHost(picked: picked, onOpen: (MorphFlight f) => flight = f),
    );
    await tester.tap(find.text('rows-hero'));
    await settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(find.text('Copy'), findsNothing);
    expect(flight!.isFinished, isTrue);
    expect(picked, isEmpty);
  });

  testWidgets('arrow keys move the highlight and Enter chooses', (
    WidgetTester tester,
  ) async {
    frame(tester);
    final picked = <String>[];
    await tester.pumpWidget(_RowsHost(picked: picked));
    await tester.tap(find.text('rows-hero'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(picked, <String>['Copy']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('closing the flight closes the menu with it', (
    WidgetTester tester,
  ) async {
    frame(tester);
    MorphFlight? flight;
    await tester.pumpWidget(
      _RowsHost(picked: <String>[], onOpen: (MorphFlight f) => flight = f),
    );
    await tester.tap(find.text('rows-hero'));
    await settle(tester);
    flight!.close();
    await settle(tester);
    expect(find.text('Copy'), findsNothing);
  });
}

const Key _liveHero = ValueKey<String>('live-hero');
const Key _aboveBox = ValueKey<String>('above-box');

/// A held hero with a content-sized accessory whose note row is toggled
/// by a notifier INSIDE the built content: the size changes without any
/// region rebuild, as an app's state usually does.
class _LiveHost extends StatefulWidget {
  const _LiveHost({
    required this.expanded,
    this.replica,
    this.opensOnSecondaryTap = true,
    this.onOuterSecondaryTap,
  });

  final ValueNotifier<bool> expanded;
  final Widget? replica;
  final bool opensOnSecondaryTap;
  final VoidCallback? onOuterSecondaryTap;

  @override
  State<_LiveHost> createState() => _LiveHostState();
}

class _LiveHostState extends State<_LiveHost> {
  MorphFlight? flight;
  int reactions = 0;

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
                  accessory: MorphSatellite(
                    builder: (BuildContext context, MorphFlight flight) =>
                        ValueListenableBuilder<bool>(
                          valueListenable: widget.expanded,
                          builder: (BuildContext context, bool on, Widget? _) =>
                              GestureDetector(
                                onTap: () {
                                  reactions++;
                                  MorphContextMenuRegion.close(context);
                                },
                                child: SizedBox(
                                  key: _aboveBox,
                                  width: 200,
                                  height: on ? 100 : _accessoryHeight,
                                  child: const Text('above'),
                                ),
                              ),
                        ),
                  ),
                  menu: const <MorphMenuEntry>[MorphMenuItem(title: 'reply')],
                  child: Container(
                    key: _liveHero,
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

void accessory() {
  late ValueNotifier<bool> expanded;
  setUp(() => expanded = ValueNotifier<bool>(false));
  tearDown(() => expanded.dispose());

  testWidgets('a content-sized accessory stands above the preview, centered '
      'on it, and takes touches', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(_LiveHost(expanded: expanded));
    await tester.tap(find.text('more'));
    await settle(tester);
    final _LiveHostState host = tester.state<_LiveHostState>(
      find.byType(_LiveHost),
    );
    final Rect preview = tester.getRect(find.byKey(_liveHero).last);
    final Rect above = tester.getRect(find.byKey(_aboveBox));
    expect(above.bottom, _near(preview.top - _gap));
    expect(above.center.dx, _near(preview.center.dx));
    expect(above.size, const Size(200, _accessoryHeight));
    await tester.tap(find.text('above'));
    await settle(tester);
    expect(host.reactions, 1);
    expect(host.flight!.isFinished, isTrue);
    expect(find.text('above'), findsNothing);
  });

  testWidgets('an accessory growing while the menu is open grows upward; '
      'the preview stays put', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(_LiveHost(expanded: expanded));
    await tester.tap(find.text('more'));
    await settle(tester);
    final Rect preview = tester.getRect(find.byKey(_liveHero).last);
    final Rect before = tester.getRect(find.text('above'));
    expanded.value = true;
    await tester.pump();
    final Rect after = tester.getRect(find.text('above'));
    expect(after.top, _near(before.top - 60));
    expect(tester.getRect(find.byKey(_liveHero).last), preview);
    tester.state<_LiveHostState>(find.byType(_LiveHost)).flight!.close();
    await settle(tester);
  });

  testWidgets('the accessory unfolds out of the preview\'s top edge', (
    WidgetTester tester,
  ) async {
    frame(tester);
    await tester.pumpWidget(_LiveHost(expanded: expanded));
    await tester.tap(find.text('more'));
    await settle(tester);
    final Rect rest = tester.getRect(find.text('above'));
    final MorphFlight flight = tester
        .state<_LiveHostState>(find.byType(_LiveHost))
        .flight!;
    flight.close();
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final Rect now = tester.getRect(find.text('above'));
    expect(now.width, lessThan(rest.width));
    expect(now.bottom, greaterThan(rest.bottom - 1e-6));
    await settle(tester);
  });

  testWidgets('a replica supplies the overlay copy and leaves the live '
      'child only at its source', (WidgetTester tester) async {
    frame(tester);
    await tester.pumpWidget(
      _LiveHost(
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
    expect(find.text('ghost-copy'), findsOneWidget);
    expect(find.text('hero'), findsOneWidget);
    await settle(tester);
    expect(find.text('ghost-copy'), findsOneWidget);
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
              menu: const <MorphMenuEntry>[MorphMenuItem(title: 'action')],
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

  testWidgets('a rebuilt region updates its rows and accessory in place', (
    WidgetTester tester,
  ) async {
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
                  accessory: MorphSatellite(
                    builder: (BuildContext context, MorphFlight flight) =>
                        Text(changed ? 'new-above' : 'old-above'),
                  ),
                  menu: <MorphMenuEntry>[
                    MorphMenuItem(title: changed ? 'new-row' : 'old-row'),
                    if (!changed) const MorphMenuItem(title: 'gone-row'),
                  ],
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
    expect(_menuFrame(tester).height, _rowsHeight(2));
    rebuild(() => changed = true);
    await tester.pump();
    await settle(tester);
    expect(find.text('old-above'), findsNothing);
    expect(find.text('new-above'), findsOneWidget);
    expect(find.text('old-row'), findsNothing);
    expect(find.text('gone-row'), findsNothing);
    expect(find.text('new-row'), findsOneWidget);
    expect(
      _menuShape(tester)!.height,
      moreOrLessEquals(_rowsHeight(1), epsilon: 0.01),
    );
    flight!.close();
    await settle(tester);
  });

  testWidgets('opensOnSecondaryTap off leaves the right click to whoever '
      'else wants it', (WidgetTester tester) async {
    frame(tester);
    int outer = 0;
    await tester.pumpWidget(
      _LiveHost(expanded: expanded, onOuterSecondaryTap: () => outer++),
    );
    await tester.tap(find.text('hero'), buttons: kSecondaryButton);
    await settle(tester);
    expect(find.text('above'), findsOneWidget);
    expect(outer, 0);
    tester.state<_LiveHostState>(find.byType(_LiveHost)).flight!.close();
    await settle(tester);

    await tester.pumpWidget(
      _LiveHost(
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
                  onOpen: (MorphFlight f) => flight = f,
                  menu: _deviceRows(menu[3]),
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
      // What is on screen: the preview in the overlay while the flight
      // carries it, the page's own hero otherwise.
      Rect visible() => _shown(tester, flight);

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
      final Rect actions = _menuFrame(tester);
      expect(actions.width, closeTo(menu[2].toDouble(), 0.01));
      expect(actions.height, closeTo(menu[3].toDouble(), 0.01));
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
              onOpen: (MorphFlight f) => flight = f,
              menu: _deviceRows(menu[3]),
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
    final Iterable<Color> boxes = paintedBoxColors(tester, anyColoredBox).where(
      (Color color) =>
          color.r == 0 && color.g == 0 && color.b == 0 && color.a > 0,
    );
    return boxes.isEmpty ? 0 : boxes.last.a;
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
              onOpen: (MorphFlight f) => flight = f,
              menu: _deviceRows(menu[3]),
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
  Rect hero() => _shown(tester, flight);

  Rect? menuRect() => _menuShape(tester);

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
      debugPrint(
        '$name replay: menu open ${_replayError(deviceMenuOpen, ourMenuOpen)}, '
        'menu close ${_replayError(deviceMenuClose, ourMenuClose)}, '
        'hero close ${_replayError(deviceHeroClose, ourHeroClose)}',
      );
      for (final int axis in <int>[3, 4]) {
        final double extent = menu[axis - 1].toDouble();
        final double blob = frames(parts['open'])!.first[axis];
        final deviceSize = <(double, double)>[
          for (final f in frames(parts['open'])!)
            (f[0], (f[axis] - blob) / (extent - blob)),
        ];
        final ourSize = <(double, double)>[
          for (final (t, _, rect) in run.open)
            if (rect != null)
              (
                t,
                ((axis == 3 ? rect.width : rect.height) - blob) /
                    (extent - blob),
              ),
        ];
        final double sizeError = _replayError(deviceSize, ourSize);
        final double peak = ourSize
            .map(((double, double) f) => f.$2)
            .reduce(math.max);
        debugPrint(
          '$name menu axis $axis: rms $sizeError, '
          'device peak ${deviceSize.map(((double, double) f) => f.$2).reduce(math.max)}, '
          'replay peak $peak',
        );
        expect(
          sizeError,
          // The menu card grows out of the measured blob on the context
          // spring (m / l: width 0.73 / 0.36, height 0.80 / 0.39 percent;
          // the engine column measured 0.66 / 1.07 and 0.73 / 0.58).
          lessThan(name == 'ctxd-l-1' ? 0.005 : 0.0085),
          reason: '$name menu size axis $axis',
        );
        expect(peak, inInclusiveRange(1.01, 1.02));
      }
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

/// A held 120 x 80 thumbnail previewing a 300 x 200 picture.
Widget _previewHost({
  VoidCallback? onPreviewTap,
  ValueChanged<MorphFlight>? onOpen,
  List<String>? picked,
}) => MaterialApp(
  builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
  home: Scaffold(
    body: Center(
      child: MorphContextMenuRegion(
        onOpen: onOpen,
        onPreviewTap: onPreviewTap,
        preview: (BuildContext context) => const ColoredBox(
          color: Color(0xFF00AA00),
          child: Center(child: Text('big-preview')),
        ),
        previewSize: const Size(300, 200),
        menu: <MorphMenuEntry>[
          MorphMenuItem(title: 'Save', onSelected: () => picked?.add('Save')),
        ],
        child: Builder(
          builder: (BuildContext context) => GestureDetector(
            onTap: () => MorphContextMenuRegion.open(context),
            child: Container(
              key: _heroBox,
              width: 120,
              height: 80,
              color: const Color(0xFF334455),
              child: const Text('thumb'),
            ),
          ),
        ),
      ),
    ),
  ),
);

void previews() {
  testWidgets('a preview builder shows its own view at its size, grown out '
      'of the held view about its center, and home again', (
    WidgetTester tester,
  ) async {
    frame(tester);
    MorphFlight? flight;
    await tester.pumpWidget(
      _previewHost(onOpen: (MorphFlight f) => flight = f),
    );
    final Rect home = tester.getRect(find.byKey(_heroBox));
    expect(find.text('big-preview'), findsNothing);
    await tester.tap(find.text('thumb'));
    await settle(tester);
    final Rect shown = tester.getRect(find.text('big-preview').first);
    expect((shown.center - home.center).distance, lessThan(1e-6));
    final Rect box = tester.getRect(
      find.ancestor(
        of: find.text('big-preview'),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(box.size, const Size(300, 200));
    expect(_menuFrame(tester).top, _near(box.bottom + _gap));
    flight!.close();
    await settle(tester);
    expect(find.text('big-preview'), findsNothing);
    expect(tester.getRect(find.byKey(_heroBox)), home);
  });

  testWidgets('a tap on the preview runs onPreviewTap and closes the menu', (
    WidgetTester tester,
  ) async {
    frame(tester);
    var taps = 0;
    MorphFlight? flight;
    final picked = <String>[];
    await tester.pumpWidget(
      _previewHost(
        onPreviewTap: () => taps++,
        onOpen: (MorphFlight f) => flight = f,
        picked: picked,
      ),
    );
    await tester.tap(find.text('thumb'));
    await settle(tester);
    await tester.tap(find.text('big-preview'));
    await settle(tester);
    expect(taps, 1);
    expect(picked, isEmpty);
    expect(flight!.isFinished, isTrue);
  });

  testWidgets('without onPreviewTap a tap on the preview closes the menu', (
    WidgetTester tester,
  ) async {
    frame(tester);
    MorphFlight? flight;
    await tester.pumpWidget(
      _previewHost(onOpen: (MorphFlight f) => flight = f),
    );
    await tester.tap(find.text('thumb'));
    await settle(tester);
    await tester.tap(find.text('big-preview'), warnIfMissed: false);
    await settle(tester);
    expect(flight!.isFinished, isTrue);
  });
}
