import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// A QA walk through every gallery page on a device: realistic gestures,
/// screenshots between the steps, every framework error and per-page
/// frame timings, reported through the binding's report data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('gallery QA walk', (WidgetTester tester) async {
    final qa = _Qa(binding, tester);
    final previousOnError = FlutterError.onError;
    FlutterError.onError = qa.recordError;
    SchedulerBinding.instance.addTimingsCallback(qa.recordTimings);
    try {
      await qa.run();
    } on Object catch (error, stack) {
      qa.errors.add('[${qa.page}] ABORTED: $error\n$stack');
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(qa.recordTimings);
      FlutterError.onError = previousOnError;
      timeDilation = 1;
    }
    binding.reportData = <String, Object?>{
      ...?binding.reportData,
      'qa': qa.report(),
    };
    File('${_Qa.outDir.path}/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(qa.report()),
    );
    debugPrint('QA REPORT ${qa.summary()}');
    expect(qa.errors, isEmpty, reason: qa.errors.join('\n\n'));
  });
}

class _Qa {
  _Qa(this.binding, this.tester);

  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  final List<String> errors = [];
  final List<(String, int, int)> _pages = [];
  final List<ui.FrameTiming> _timings = [];
  final Map<String, List<String>> _checks = {};
  final Stopwatch _clock = Stopwatch();
  String _page = 'boot';

  String get page => _page;
  int _pageStart = 0;
  int _shot = 0;
  int _pointer = 100;

  void recordError(FlutterErrorDetails details) {
    errors.add('[$_page] ${details.exceptionAsString()}\n${details.stack}');
  }

  void recordTimings(List<ui.FrameTiming> timings) => _timings.addAll(timings);

  void check(String what, {required bool ok}) {
    (_checks[_page] ??= []).add('${ok ? 'ok' : 'FAIL'} $what');
    if (!ok) errors.add('[$_page] check failed: $what');
  }

  void _enter(String page) {
    _leave();
    _page = page;
    _pageStart = developer.Timeline.now;
  }

  void _leave() {
    if (_page == 'boot') return;
    _pages.add((_page, _pageStart, developer.Timeline.now));
  }

  Future<void> shot(String name) async {
    await tester.pump();
    _shot++;
    final label = '${_shot.toString().padLeft(2, '0')}-$name';
    final data = await binding.callbackManager.takeScreenshot(label);
    final bytes = (data['bytes']! as List<Object?>).cast<int>();
    final file = File('${outDir.path}/$label.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  Future<void> settle([int ms = 900]) async {
    await tester.pump(Duration(milliseconds: ms));
  }

  Duration get _now => _clock.elapsed;

  /// A finger: down, a path of moves at [step] spacing, optional holds
  /// before and after the moves, up.
  Future<void> finger(
    Offset from,
    List<Offset> path, {
    Duration holdBefore = Duration.zero,
    Duration holdAfter = Duration.zero,
    Duration step = const Duration(milliseconds: 8),
    Future<void> Function()? whileHeld,
    bool release = true,
  }) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    await gesture.down(from, timeStamp: _now);
    await tester.pump(holdBefore == Duration.zero ? step : holdBefore);
    for (final p in path) {
      await gesture.moveTo(p, timeStamp: _now);
      await tester.pump(step);
    }
    if (holdAfter > Duration.zero) await tester.pump(holdAfter);
    if (whileHeld != null) await whileHeld();
    if (release) {
      await gesture.up(timeStamp: _now);
    }
    await tester.pump();
  }

  static List<Offset> line(Offset a, Offset b, int n) => [
    for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!,
  ];

  Future<void> tap(Offset at, {int holdMs = 60}) =>
      finger(at, const [], holdBefore: Duration(milliseconds: holdMs));

  Future<void> open(String title) async {
    await tester.tap(find.text(title));
    await settle(700);
  }

  Future<void> back() async {
    await tester.pageBack();
    await settle(700);
  }

  Offset textIn(Finder scope, String text) => tester.getCenter(
    find.descendant(of: scope, matching: find.text(text)).first,
  );

  Future<void> run() async {
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);
    _clock.start();
    await MorphGlassRenderer.precache();
    runApp(const GalleryApp());
    await settle(1200);
    _enter('home');
    await shot('home');
    await _segmented();
    await _tabBar();
    await _controls();
    await _menu();
    await _glass();
    await _inspector();
    await _slowMotion();
    await _dark();
    _leave();
  }

  Future<void> _segmented() async {
    await open('Segmented control');
    _enter('segmented');
    await shot('segmented-resting');
    final controls = find.byType(MorphSegmentedControl);
    final two = controls.at(0);
    await tap(textIn(two, 'Night'));
    await settle();
    check('Two selects Night', ok: _selectedOf(two) == 1);

    final three = controls.at(1);
    await tap(textIn(three, 'C'));
    await settle();
    final c = textIn(three, 'C');
    final a = textIn(three, 'A');
    await finger(
      c,
      line(c, a, 30),
      holdBefore: const Duration(milliseconds: 120),
      whileHeld: () => shot('segmented-drag-held-at-A'),
    );
    await settle();
    check('Three dragged C to A', ok: _selectedOf(three) == 0);

    final narrow = controls.at(6);
    final x = textIn(narrow, 'X');
    final rect = tester.getRect(narrow);
    await finger(
      x,
      line(x, Offset(rect.left - 120, x.dy), 25),
      holdBefore: const Duration(milliseconds: 120),
      holdAfter: const Duration(milliseconds: 300),
      whileHeld: () => shot('segmented-rubber-band-left'),
    );
    await settle();
    check(
      'Narrow stays on X after a left overdrag',
      ok: _selectedOf(narrow) == 0,
    );
    await finger(
      x,
      line(x, Offset(rect.right + 160, x.dy), 40),
      holdBefore: const Duration(milliseconds: 120),
      holdAfter: const Duration(milliseconds: 300),
      whileHeld: () => shot('segmented-rubber-band-right'),
    );
    await settle();
    check('Narrow lands on Z past the right end', ok: _selectedOf(narrow) == 2);

    final five = controls.at(3);
    for (final label in ['5', '1', '4', '2']) {
      await tap(textIn(five, label), holdMs: 30);
      await tester.pump(const Duration(milliseconds: 70));
    }
    await shot('segmented-five-interrupted');
    await settle();
    check('Five ends on 2', ok: _selectedOf(five) == 1);

    final content = controls.at(4);
    await tap(textIn(content, 'Unread messages'));
    await settle();
    final uneven = controls.at(5);
    final ua = textIn(uneven, 'A');
    await finger(
      ua,
      line(ua, textIn(uneven, 'Mid size'), 40),
      holdBefore: const Duration(milliseconds: 120),
    );
    await settle();
    check('Uneven dragged A to Mid size', ok: _selectedOf(uneven) == 3);

    await finger(
      textIn(two, 'Night'),
      const [],
      holdBefore: const Duration(milliseconds: 400),
      whileHeld: () => shot('segmented-held-selected'),
    );
    await settle();
    await shot('segmented-after');
    await back();
  }

  int _selectedOf(Finder control) =>
      tester.widget<MorphSegmentedControl>(control).selected;

  Future<void> _tabBar() async {
    await open('Tab bar');
    _enter('tab-bar');
    await shot('tabbar4-resting');
    final count = find.byType(MorphSegmentedControl).first;
    await tap(textIn(count, '3'));
    await settle();
    await shot('tabbar3-resting');
    final bar = find.byType(MorphTabBar);
    final home = textIn(bar, 'Home');
    final radio = textIn(bar, 'Radio');
    await finger(
      radio,
      const [],
      holdBefore: const Duration(milliseconds: 400),
      whileHeld: () => shot('tabbar3-held-other'),
    );
    await settle();
    check('Radio selected by press', ok: _tabOf(bar) == 2);
    await finger(
      radio,
      const [],
      holdBefore: const Duration(milliseconds: 400),
      whileHeld: () => shot('tabbar3-held-selected'),
    );
    await settle();
    await finger(
      radio,
      line(radio, home, 40),
      holdBefore: const Duration(milliseconds: 150),
      whileHeld: () => shot('tabbar3-scrub-at-home'),
    );
    await settle();
    check('scrub lands on Home', ok: _tabOf(bar) == 0);
    final barRect = tester.getRect(bar);
    await finger(
      home,
      line(home, Offset(barRect.right + 80, home.dy), 50),
      holdBefore: const Duration(milliseconds: 150),
      holdAfter: const Duration(milliseconds: 250),
      whileHeld: () => shot('tabbar3-scrub-past-end'),
    );
    await settle();
    check('scrub past the end lands on Radio', ok: _tabOf(bar) == 2);

    final list = find.byType(ListView);
    await tester.fling(list, const Offset(0, -500), 1500);
    await settle(1200);
    await shot('tabbar3-over-scrolled-content');
    await tester.fling(list, const Offset(0, 2000), 3000);
    await settle(1200);
    for (final (label, n) in [('5', 5), ('2', 2)]) {
      await tap(textIn(find.byType(MorphSegmentedControl).first, label));
      await settle();
      final bars = find.byType(MorphTabBar);
      check(
        'bar has $n tabs',
        ok: tester.widget<MorphTabBar>(bars).items.length == n,
      );
      await shot('tabbar$n-resting');
    }
    await tap(textIn(find.byType(MorphSegmentedControl).first, '4'));
    await settle();
    await back();
  }

  int _tabOf(Finder bar) => tester.widget<MorphTabBar>(bar).selected;

  Future<void> _controls() async {
    await open('Controls');
    _enter('controls');
    await shot('controls-resting');
    final switches = find.byType(MorphSwitch);
    final off = switches.at(0);
    await tap(tester.getCenter(off));
    await settle();
    check('switch tap turns on', ok: tester.widget<MorphSwitch>(off).value);
    final offRect = tester.getRect(off);
    final knob = Offset(offRect.right - 20, offRect.center.dy);
    await finger(knob, [
      ...line(knob, Offset(offRect.left + 10, knob.dy), 12),
      ...line(
        Offset(offRect.left + 10, knob.dy),
        knob + const Offset(15, 0),
        12,
      ),
    ], holdBefore: const Duration(milliseconds: 100));
    await settle();
    check(
      'switch dragged there and back stays on',
      ok: tester.widget<MorphSwitch>(off).value,
    );
    await finger(
      knob,
      line(knob, Offset(offRect.left - 20, knob.dy), 14),
      holdBefore: const Duration(milliseconds: 100),
    );
    await settle();
    check('switch dragged off', ok: !tester.widget<MorphSwitch>(off).value);
    final offKnob = Offset(offRect.left + 20, offRect.center.dy);
    await finger(
      offKnob,
      const [],
      holdBefore: const Duration(milliseconds: 400),
      whileHeld: () => shot('switch-off-knob-held'),
    );
    await settle();
    check(
      'a held tap on the off switch turns it on',
      ok: tester.widget<MorphSwitch>(off).value,
    );
    await tap(tester.getCenter(off));
    await settle();

    final sliders = find.byType(MorphSlider);
    final wide = sliders.at(0);
    Offset thumb(Finder slider) {
      final r = tester.getRect(slider);
      final v = tester.widget<MorphSlider>(slider).value;
      return Offset(r.left + 18.5 + v * (r.width - 37), r.center.dy);
    }

    final t0 = thumb(wide);
    await finger(
      t0,
      line(t0, t0 + const Offset(90, 0), 30),
      step: const Duration(milliseconds: 16),
      holdAfter: const Duration(milliseconds: 200),
      whileHeld: () => shot('slider-thumb-held'),
    );
    await settle();
    final afterDrag = tester.widget<MorphSlider>(wide).value;
    check('slider drag moved it right ($afterDrag)', ok: afterDrag > 0.5);
    final t1 = thumb(wide);
    await finger(t1, line(t1, t1 - const Offset(70, 0), 4));
    await settle(1500);
    final afterFling = tester.widget<MorphSlider>(wide).value;
    check(
      'slider fling glided left ($afterFling)',
      ok: afterFling < afterDrag - 0.2,
    );
    final r = tester.getRect(wide);
    await tap(Offset(r.right - 10, r.center.dy));
    await settle();
    check(
      'a tap on the track away from the thumb does nothing',
      ok: tester.widget<MorphSlider>(wide).value == afterFling,
    );
    final narrow = sliders.at(1);
    final n0 = thumb(narrow);
    await finger(n0, line(n0, n0 + const Offset(400, 0), 6));
    await settle(1500);
    check(
      'narrow slider flung to its end',
      ok: tester.widget<MorphSlider>(narrow).value == 1,
    );
    await shot('sliders-after');

    final big = find.widgetWithText(MorphGlassButton, '120 x 44');
    final bigCenter = tester.getCenter(big);
    final tapsBefore = _taps();
    await finger(
      bigCenter,
      const [],
      holdBefore: const Duration(milliseconds: 400),
      whileHeld: () => shot('glass-120x44-pressed'),
    );
    await settle();
    check('button tap counts', ok: _taps() == tapsBefore + 1);
    await finger(
      bigCenter,
      line(bigCenter, bigCenter + const Offset(0, 160), 30),
      holdBefore: const Duration(milliseconds: 100),
      whileHeld: () => shot('glass-dragged-off'),
    );
    await settle();
    check('drag-off release does not tap', ok: _taps() == tapsBefore + 1);
    final small = find.byType(MorphGlassButton).first;
    await finger(
      tester.getCenter(small),
      const [],
      holdBefore: const Duration(milliseconds: 400),
      whileHeld: () => shot('glass-44x44-pressed'),
    );
    await settle();
    await tap(
      tester.getCenter(find.widgetWithText(MorphGlassButton, 'Prominent')),
    );
    await settle();
    check('prominent tap counts', ok: _taps() == tapsBefore + 3);

    await tester.scrollUntilVisible(
      find.byType(MorphStepper),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(400);
    final stepper = find.byType(MorphStepper);
    final sr = tester.getRect(stepper);
    final plus = Offset(sr.right - sr.width / 4, sr.center.dy);
    final minus = Offset(sr.left + sr.width / 4, sr.center.dy);
    await tap(plus);
    await settle(300);
    check('stepper + tap', ok: _stepper() == 6);
    await finger(
      plus,
      const [],
      holdBefore: const Duration(milliseconds: 2000),
      whileHeld: () => shot('stepper-held-plus'),
    );
    await settle(300);
    check('stepper hold repeats to max (${_stepper()})', ok: _stepper() == 10);
    await finger(
      minus,
      const [],
      holdBefore: const Duration(milliseconds: 3500),
    );
    await settle(300);
    check(
      'stepper hold repeats down at 2 per second (${_stepper()})',
      ok: _stepper() == 3,
    );
    final held = _stepper();
    await finger(
      minus,
      line(minus, minus + const Offset(0, 120), 20),
      holdBefore: const Duration(milliseconds: 80),
    );
    await settle(300);
    check('stepper drag-off does not step', ok: _stepper() == held);
    await shot('controls-after');
    await back();
  }

  int _taps() {
    final caption = find.textContaining('Glass buttons, tapped');
    final text = tester.widget<Text>(caption).data!;
    return int.parse(text.split(' ')[3]);
  }

  double _stepper() =>
      tester.widget<MorphStepper>(find.byType(MorphStepper)).value;

  Future<void> _menu() async {
    await open('Menu');
    _enter('menu');
    await shot('menu-resting');
    final barButton = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(MorphMenuButton),
    );
    final appBar = tester.getCenter(barButton);
    final all = find.byType(MorphMenuButton);
    final rects = [
      for (var i = 0; i < all.evaluate().length; i++)
        if (tester.getCenter(all.at(i)) != appBar) tester.getRect(all.at(i)),
    ];
    final size = tester.getSize(find.byType(Scaffold));
    Offset nearest(Offset p) => rects
        .map((r) => r.center)
        .reduce((a, b) => (a - p).distance < (b - p).distance ? a : b);
    final center = nearest(Offset(size.width / 2, size.height / 2));
    final topRight = nearest(Offset(size.width, 150));
    final bottomLeft = nearest(Offset(0, size.height));
    final bottomRight = nearest(Offset(size.width, size.height));
    final ten = nearest(Offset(size.width / 2, size.height * 0.85));

    await tap(center);
    await settle();
    await shot('menu-open-center');
    await tap(tester.getCenter(find.text('Share').last));
    await settle();
    check(
      'menu gone after select',
      ok: find.text('Duplicate').evaluate().isEmpty,
    );
    check('last shows Share', ok: _menuLast() == 'Share');

    await tap(center);
    await settle();
    await tap(Offset(size.width / 2, size.height - 60));
    await tester.pump(const Duration(milliseconds: 60));
    await shot('menu-closing');
    await tap(center);
    await settle();
    await shot('menu-reopened-during-close');
    await tap(Offset(20, size.height / 2));
    await settle();

    await _slideHeld(ten, 'Rename');
    await settle();
    check(
      'drag-to-select picked Rename (${_menuLast()})',
      ok: _menuLast() == 'Rename',
    );

    for (final (name, at) in [
      ('top-right', topRight),
      ('bottom-left', bottomLeft),
      ('bottom-right', bottomRight),
      ('app-bar', appBar),
    ]) {
      await tap(at);
      await settle();
      await shot('menu-open-$name');
      final copy = find.text('Copy');
      check('menu $name shows rows on screen', ok: copy.evaluate().isNotEmpty);
      if (copy.evaluate().isNotEmpty) {
        final rowRect = tester.getRect(copy.last);
        check(
          'menu $name rows inside the screen ($rowRect)',
          ok:
              rowRect.left >= 0 &&
              rowRect.right <= size.width &&
              rowRect.top >= 0 &&
              rowRect.bottom <= size.height,
        );
      }
      await tap(Offset(size.width / 2, size.height / 2 + 40));
      await settle();
    }
    await back();
  }

  Future<void> _slideHeld(Offset from, String row) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    await gesture.down(from, timeStamp: _now);
    await tester.pump(const Duration(milliseconds: 1200));
    await shot('menu-ten-held-open');
    final to = tester.getCenter(find.text(row).last);
    for (final p in line(from, to, 30)) {
      await gesture.moveTo(p, timeStamp: _now);
      await tester.pump(const Duration(milliseconds: 12));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await shot('menu-drag-to-select-on-row');
    await gesture.up(timeStamp: _now);
    await tester.pump();
  }

  String _menuLast() {
    final last = find.byWidgetPredicate(
      (Widget w) => w is Text && w.style?.color == const Color(0xFF8E8E93),
    );
    return tester.widget<Text>(last.first).data ?? '?';
  }

  Finder _switchNamed(String label) => find.byWidgetPredicate(
    (Widget w) => w is MorphSwitch && w.semanticLabel == label,
  );

  Future<void> _setting(Finder target) async {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(300);
    await tap(tester.getCenter(target));
    await settle();
  }

  Future<void> _sceneTop() async {
    await tester.scrollUntilVisible(
      find.byType(MorphTabBar),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await settle(600);
  }

  Future<void> _glass() async {
    await open('Glass renderer');
    _enter('glass');
    await shot('glass-light');
    final segmented = find.byType(MorphSegmentedControl).first;
    final albums = textIn(segmented, 'Albums');
    await finger(
      textIn(segmented, 'Photos'),
      line(textIn(segmented, 'Photos'), albums, 25),
      holdBefore: const Duration(milliseconds: 150),
      whileHeld: () => shot('glass-lens-lifted'),
    );
    await settle();
    final tab = find.byType(MorphTabBar);
    await finger(
      textIn(tab, 'Search'),
      const [],
      holdBefore: const Duration(milliseconds: 400),
      whileHeld: () => shot('glass-tab-held'),
    );
    await settle();
    for (final material in ['Toolbar', 'Clear', 'Regular']) {
      await _setting(find.text(material));
      await _sceneTop();
      await shot('glass-${material.toLowerCase()}');
    }
    await _setting(find.text('Dark'));
    await _sceneTop();
    await shot('glass-dark');
    await _setting(_switchNamed('Right to left'));
    await _sceneTop();
    await shot('glass-dark-rtl');
    final rtlSeg = find.byType(MorphSegmentedControl).first;
    await tap(textIn(rtlSeg, 'Search'));
    await settle();
    check(
      'RTL tap on Search selects it',
      ok: tester.widget<MorphSegmentedControl>(rtlSeg).selected == 2,
    );
    final slider = find.byType(MorphSlider).first;
    final sr = tester.getRect(slider);
    final v = tester.widget<MorphSlider>(slider).value;
    final thumb = Offset(sr.right - 18.5 - v * (sr.width - 37), sr.center.dy);
    await finger(thumb, line(thumb, thumb - const Offset(60, 0), 20));
    await settle();
    check(
      'RTL slider drag left grows it',
      ok: tester.widget<MorphSlider>(slider).value > v,
    );
    await shot('glass-dark-rtl-after');
    await _setting(_switchNamed('Disabled'));
    await _sceneTop();
    await shot('glass-dark-rtl-disabled');
    final before = tester.widget<MorphSegmentedControl>(rtlSeg).selected;
    await tap(textIn(rtlSeg, 'Photos'));
    await settle();
    check(
      'disabled segmented ignores taps',
      ok: tester.widget<MorphSegmentedControl>(rtlSeg).selected == before,
    );
    await _setting(_switchNamed('Right to left'));
    await _setting(find.text('Light'));
    await _sceneTop();
    await shot('glass-light-disabled');
    await _setting(_switchNamed('Disabled'));
    await _setting(_switchNamed('Fallback glass'));
    await _sceneTop();
    await shot('glass-fallback');
    await _setting(_switchNamed('Fallback glass'));
    await _setting(find.text('Frosted'));
    await _sceneTop();
    await shot('glass-frosted');
    await _setting(find.text('Flat'));
    await _sceneTop();
    await shot('glass-off');
    await back();
    await open('Controls');
    check(
      'the flat renderer reaches other pages',
      ok: find.byType(MorphGlass).evaluate().isEmpty,
    );
    await back();
    await open('Glass renderer');
    await _setting(find.text('Liquid'));
    await _setting(find.text('System'));
    await back();
    await open('Controls');
    check(
      'the liquid renderer reaches other pages',
      ok: find.byType(MorphGlass).evaluate().isNotEmpty,
    );
    await back();
  }

  Future<void> _inspector() async {
    await open('Size to physics');
    _enter('inspector');
    await shot('inspector');
    final sliders = find.byType(MorphSlider);
    for (var i = 0; i < 2; i++) {
      final r = tester.getRect(sliders.at(i));
      final v = tester.widget<MorphSlider>(sliders.at(i)).value;
      final thumb = Offset(r.left + 18.5 + v * (r.width - 37), r.center.dy);
      await finger(
        thumb,
        line(thumb, thumb + Offset(i == 0 ? 90 : -40, 0), 20),
      );
    }
    await settle(600);
    await tap(tester.getCenter(find.byType(MorphSwitch)));
    await settle(400);
    await shot('inspector-loupe');
    await back();
  }

  Future<void> _slowMotion() async {
    _enter('slow-motion');
    await tester.tap(find.text('Slow-mo off').last);
    await settle(300);
    check('5x on', ok: timeDilation == 5);
    await open('Segmented control');
    final two = find.byType(MorphSegmentedControl).first;
    await tap(textIn(two, 'Day'));
    await tester.pump(const Duration(milliseconds: 600));
    await shot('slowmo-segmented-mid-travel');
    await settle(4000);
    await back();
    await settle(3000);
    await tester.tap(find.text('Slow-mo 5x').last);
    await tester.pump();
    await tester.tap(find.text('Slow-mo 10x').last);
    await settle(300);
    check('slow-mo back off', ok: timeDilation == 1);
    await shot('home-end');
  }

  /// The dark pass: the same scenes as the native dark references in
  /// tool/ios_reference/references/dark/, named after them.
  Future<void> _dark() async {
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await settle(600);
    _enter('dark');
    await shot('dark-home');
    await open('Segmented control');
    await shot('dark-segmented-resting');
    final two = find.byType(MorphSegmentedControl).first;
    await finger(
      textIn(two, 'Day'),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('dark-segmented-held-selected'),
    );
    await settle();
    await back();
    await open('Tab bar');
    await tap(textIn(find.byType(MorphSegmentedControl).first, '3'));
    await settle();
    await shot('dark-tabbar3-resting');
    final bar = find.byType(MorphTabBar);
    await finger(
      textIn(bar, 'Home'),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('dark-tabbar3-held-selected'),
    );
    await settle();
    await finger(
      textIn(bar, 'Library'),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('dark-tabbar3-held-other'),
    );
    await settle();
    await back();
    await open('Controls');
    await shot('dark-controls-resting');
    final off = find.byType(MorphSwitch).first;
    final offRect = tester.getRect(off);
    await finger(
      Offset(offRect.left + 20, offRect.center.dy),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('dark-switch-off-knob-held'),
    );
    await settle();
    final wide = find.byType(MorphSlider).first;
    final r = tester.getRect(wide);
    final v = tester.widget<MorphSlider>(wide).value;
    final thumb = Offset(r.left + 18.5 + v * (r.width - 37), r.center.dy);
    await finger(
      thumb,
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('dark-slider-thumb-held'),
    );
    await settle();
    final big = find.widgetWithText(MorphGlassButton, '120 x 44');
    await finger(
      tester.getCenter(big),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('dark-glass-120x44-pressed'),
    );
    await settle();
    await back();
    await open('Menu');
    await shot('dark-menu-button-resting');
    final all = find.byType(MorphMenuButton);
    final size = tester.getSize(find.byType(Scaffold));
    final mid = Offset(size.width / 2, size.height / 2);
    var center = tester.getCenter(all.first);
    for (var i = 0; i < all.evaluate().length; i++) {
      final c = tester.getCenter(all.at(i));
      if ((c - mid).distance < (center - mid).distance) center = c;
    }
    await tap(center);
    await settle();
    await shot('dark-menu-open');
    await tap(Offset(20, size.height / 2));
    await settle();
    await back();
    await open('Glass renderer');
    await shot('dark-glass-renderer');
    await back();
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    await settle(600);
  }

  Map<String, Object?> report() => {
    'errors': errors,
    'checks': _checks,
    'frames': _frameStats(),
  };

  Map<String, Object?> _frameStats() {
    final out = <String, Object?>{};
    for (final (page, start, end) in _pages) {
      final frames = [
        for (final t in _timings)
          if (t.timestampInMicroseconds(ui.FramePhase.vsyncStart) >= start &&
              t.timestampInMicroseconds(ui.FramePhase.vsyncStart) < end)
            t,
      ];
      if (frames.isEmpty) {
        out[page] = 'no frames';
        continue;
      }
      double ms(Duration d) => d.inMicroseconds / 1000;
      final build = [for (final f in frames) ms(f.buildDuration)];
      build.sort();
      final raster = [for (final f in frames) ms(f.rasterDuration)];
      raster.sort();
      final total = [for (final f in frames) ms(f.totalSpan)];
      total.sort();
      double p95(List<double> v) =>
          v[math.min(v.length - 1, (v.length * 0.95).floor())];
      out[page] = {
        'n': frames.length,
        'build_p95': p95(build),
        'build_worst': build.last,
        'raster_p95': p95(raster),
        'raster_worst': raster.last,
        'total_p95': p95(total),
        'over_8.3ms': [
          for (final f in frames)
            if (ms(f.buildDuration) > 8.3 || ms(f.rasterDuration) > 8.3) f,
        ].length,
      };
    }
    out['all_timings'] = _timings.length;
    return out;
  }

  String summary() => '${report()}';

  /// Where the screenshots and the report land: the app's temporary
  /// directory, pulled with `devicectl device copy from`.
  static final Directory outDir = Directory('${Directory.systemTemp.path}/qa');
}
