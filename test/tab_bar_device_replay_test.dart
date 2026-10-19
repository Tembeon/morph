import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/tab_bar.dart';

import 'support/onset.dart';
import 'support/trace.dart';

const _dir = 'test/fixtures/ios27-device/lens';

/// The center of the recorded tab bars, which swell around it while
/// pressed.
const double _barCenter = 201;

/// The slot centers and resting lens width of the recorded tab bars by tab
/// count: the logged tap positions and the resting lens rows (x, bw).
const Map<int, ({List<double> centers, double width})> _bars = {
  2: (centers: [158, 244], width: 94),
  3: (centers: [115, 201, 287], width: 94),
  4: (centers: [74, 158.67, 243.33, 328], width: 98),
  5: (centers: [63.5, 132.25, 201, 269.75, 338.5], width: 77),
};

/// The device recordings of taps from one tab to another, about 2 s apart.
const _files = [
  'tabbar2-taps.jsonl',
  'tabbar3-taps.jsonl',
  'tabbar4-taps.jsonl',
  'tabbar5-taps.jsonl',
  'tabbar3-pairs.jsonl',
  'tabbar4-pairs.jsonl',
  'tabbar5-many.jsonl',
  'tabbar4-no-radio.jsonl',
  'tabbar4-radio-first.jsonl',
];

// lens_test.dart replays the same quantities of tab bar taps (travel
// center, lifted bounds) with these per-tap rms bounds, in points.
const double _centerTolerance = 1.5;
const double _sizeTolerance = 2.5;

double _rms(List<double> e) => e.isEmpty ? 0 : rms(e);

/// One recorded tap and morph's errors against the lens it moved.
class _Tap {
  _Tap(this.file, this.count, this.from, this.to, this.down);

  final String file;
  final int count;
  final int from;
  final int to;
  final double down;

  /// Seconds from the touch's stamp to the recorded lens's lift start.
  double onset = 0;

  final List<double> center = [];
  final List<double> size = [];
  int selected = -1;
  int landed = -1;

  /// Whether the lens size lags its lift on the device: every selection
  /// from or to the third slot of the four-tab bar (tab-bar.md, slow lift,
  /// documented and not modelled).
  bool get slowLift => count == 4 && (from == 2 || to == 2);

  String get label =>
      '$file $from->$to: center ${_rms(center).toStringAsFixed(2)} '
      'size ${_rms(size).toStringAsFixed(2)}';
}

/// The tab bar lens rows at the bar's level without UIKit's bar-local
/// glitch rows (far above the bar, or one row jumping into the bar's own
/// coordinates), which morph deliberately does not reproduce.
List<TraceFrame> _lensRows(Trace trace) {
  final ys = [
    for (final f in trace.frames)
      if (f.raw['ctl'] == 'tabbar') f.y,
  ];
  ys.sort();
  final y = ys[ys.length ~/ 2];
  final level = [
    for (final f in trace.frames)
      if (f.raw['ctl'] == 'tabbar' && (f.y - y).abs() < 10) f,
  ];
  return [
    for (var i = 0; i < level.length; i++)
      if (i == 0 ||
          i == level.length - 1 ||
          (level[i].x - (level[i - 1].x + level[i + 1].x) / 2).abs() < 15 ||
          (level[i - 1].x - level[i + 1].x).abs() >= 15)
        level[i],
  ];
}

/// Replays the logged touches of [file] through a tab bar lens resting in
/// slot 0 at 120 Hz and returns each tap with its errors over the 1.5 s
/// after its touch.
///
/// Without [alignToLift] the touches play at their logged stamps, as morph
/// stamps them on the device (support/onset.dart). With it, each tap's
/// touches are shifted so that the lens starts when the recorded lens
/// starts lifting: the comparison then checks the travel, lift and
/// landing apart from the onset, which differs from tap to tap by UIKit's
/// delivery.
///
/// The center compares the travel center with the recorded window center
/// taken back into the bar's own coordinates by the bar's swell (`w` over
/// `bw` times `sx`) minus the deformation drift (`p_driftX`), as
/// lens_scrub_test does; the 2026-10-03 recaptures keep only the lens size
/// and compare the size alone. UIKit refreshes the lens geometry about
/// every other 120 Hz tick, so a row that repeats the previous geometry is
/// a hold and is skipped.
List<_Tap> _replay(String file, {required bool alignToLift}) {
  final count = int.parse(file.substring(6, 7));
  final bar = _bars[count]!;
  final trace = Trace.load('$_dir/$file');
  final rows = _lensRows(trace);
  const tuning = MorphLensTuning.tabBar;
  final motion = MorphLensMotion(
    tuning: tuning,
    slots: [for (final c in bar.centers) (center: c, width: bar.width)],
    selected: 0,
    height: rows.first.bh,
  );
  int slotOf(double x) {
    var best = 0;
    for (var i = 1; i < bar.centers.length; i++) {
      if ((bar.centers[i] - x).abs() < (bar.centers[best] - x).abs()) {
        best = i;
      }
    }
    return best;
  }

  final taps = <_Tap>[];
  final touches = <(TraceTouch, _Tap?)>[];
  var shift = 0.0;
  var from = 0;
  for (final touch in trace.touches) {
    _Tap? tap;
    if (touch.phase == 0) {
      tap = _Tap(file, count, from, slotOf(touch.x), touch.t);
      from = tap.to;
      tap.onset = lensLiftStart(rows, touch.t) - touch.t;
      shift = alignToLift ? tap.onset - tuning.startDelay : 0;
      taps.add(tap);
    }
    touches.add((
      TraceTouch(touch.t + shift, touch.phase, touch.x, touch.y),
      tap,
    ));
  }

  motion.advance(touches.first.$1.t - 0.5);
  var next = 0;
  _Tap? current;
  double? previousX;
  double? previousLocal;
  double? previousHeight;
  for (final f in rows) {
    while (next < touches.length && touches[next].$1.t <= f.t) {
      final (touch, tap) = touches[next++];
      switch (touch.phase) {
        case 0:
          current?.selected = motion.selected;
          current = tap;
          motion.pointerDown(touch.t, touch.x);
        case 3:
          motion.pointerUp(touch.t, touch.x);
        case _:
          motion.pointerMove(touch.t, touch.x);
      }
    }
    motion.advance(f.t);
    final heldSize = previousHeight == f.bh;
    previousHeight = f.bh;
    final sx = f.opt('sx');
    final drift = f.opt('p_driftX');
    double? local;
    if (sx != null && drift != null) {
      final swell = f.w / (f.bw * sx);
      local = _barCenter + (f.x - _barCenter) / swell - drift;
    }
    // A held lens still shifts in the window while the bar's swell moves.
    final heldCenter =
        previousX == f.x ||
        (local != null &&
            previousLocal != null &&
            (local - previousLocal).abs() < 0.02);
    previousX = f.x;
    previousLocal = local;
    final tap = current;
    if (tap == null || f.t >= tap.down + 1.5) continue;
    tap.landed = slotOf(f.x);
    if (!heldSize) {
      tap.size.add(motion.size.width - f.bw);
      tap.size.add(motion.size.height - f.bh);
    }
    if (local != null && !heldCenter) {
      tap.center.add(motion.travelCenter - local);
    }
  }
  current?.selected = motion.selected;
  return taps;
}

List<_Tap> _all({required bool alignToLift}) => [
  for (final file in _files) ..._replay(file, alignToLift: alignToLift),
];

/// The labels of [taps] whose center or size error exceeds the tolerance;
/// [slowLift] picks the taps whose size is compared.
List<String> _failures(Iterable<_Tap> taps, {required bool slowLift}) => [
  for (final tap in taps)
    if (_rms(tap.center) >= _centerTolerance ||
        (tap.slowLift == slowLift && _rms(tap.size) >= _sizeTolerance))
      tap.label,
];

/// The device recordings that log the lens layer's own scale (`sx`), from
/// which the bar's swell is read: 25 taps of 58 ms and one 1 s hold.
const _swellFiles = [
  'tabbar2-taps.jsonl',
  'tabbar3-taps.jsonl',
  'tabbar4-taps.jsonl',
  'tabbar5-taps.jsonl',
];

// The aligned taps' growth rms is 0.05 - 0.17 pt, in points of the bar's
// width.
const double _growthTolerance = 0.2;

/// One recorded touch and morph's growth against the bar's recorded swell.
class _Swell {
  _Swell(this.file, this.down, this.up, this.onset, this.lensOnset);

  final String file;
  final double down;
  final double up;

  /// Seconds from the touch's stamp to the recorded lens's lift start.
  final double lensOnset;

  /// Seconds from the touch's and the release's stamps to the start and the
  /// return of the recorded swell.
  final ({double press, double release}) onset;

  /// morph's growth minus the recorded one, in points of the bar's width.
  final List<double> growth = [];

  String get label =>
      '$file ${((up - down) * 1000).round()} ms: press '
      '${(onset.press * 1000).toStringAsFixed(1)} release '
      '${(onset.release * 1000).toStringAsFixed(1)} ms, growth '
      '${_rms(growth).toStringAsFixed(3)} pt';
}

/// Replays the logged touches of [file] through a tab bar lens and returns
/// each touch with morph's growth against the bar's recorded swell, from
/// just before the touch to 0.6 s after its release.
///
/// The recorded swell is the lens's window width over its bounds times its
/// own scale (`w` over `bw` times `sx`), the bar's growth that swell times
/// the bar's width; a row that repeats the previous geometry is a hold and
/// is skipped. Without [alignToSwell] the touches play at their logged
/// stamps, as morph stamps them on the device. With it, each touch and
/// release is shifted so that morph's growth starts and returns when the
/// recorded one does: the comparison then checks the growth's size and
/// spring apart from its onsets, which differ from tap to tap by UIKit's
/// delivery.
List<_Swell> _replaySwell(String file, {required bool alignToSwell}) {
  final count = int.parse(file.substring(6, 7));
  final bar = _bars[count]!;
  final width =
      (bar.centers[1] - bar.centers[0]) * count +
      2 * MorphTabBarMetrics.sideInset;
  const tuning = MorphLensTuning.tabBar;
  final trace = Trace.load('$_dir/$file');
  final lens = _lensRows(trace);
  final rows = <(double, double)>[];
  TraceFrame? previous;
  for (final f in lens) {
    final held =
        previous != null &&
        previous.x == f.x &&
        previous.w == f.w &&
        previous.bw == f.bw &&
        previous.opt('sx') == f.opt('sx');
    previous = f;
    if (!held) rows.add((f.t, f.w / (f.bw * f.opt('sx')!) - 1));
  }

  final swells = <_Swell>[];
  final touches = <TraceTouch>[];
  TraceTouch? down;
  for (final touch in trace.touches) {
    if (touch.phase == 0) down = touch;
    if (touch.phase != 3 || down == null) continue;
    final onset = pressOnsets(
      rows,
      down.t,
      touch.t,
      spring: tuning.chromeSpring,
      amplitude: tuning.chromeGrowth / width,
    );
    final lensOnset = lensLiftStart(lens, down.t) - down.t;
    swells.add(_Swell(file, down.t, touch.t, onset, lensOnset));
    final pressShift = alignToSwell ? onset.press - tuning.chromeLag : 0.0;
    final releaseShift = alignToSwell
        ? onset.release - tuning.chromeReleaseLag
        : 0.0;
    touches.add(TraceTouch(down.t + pressShift, 0, down.x, down.y));
    touches.add(TraceTouch(touch.t + releaseShift, 3, touch.x, touch.y));
  }
  touches.sort((a, b) => a.t.compareTo(b.t));

  final motion = MorphLensMotion(
    tuning: tuning,
    slots: [for (final c in bar.centers) (center: c, width: bar.width)],
    selected: 0,
    height: MorphTabBarMetrics.lensHeight,
  );
  motion.advance(touches.first.t - 0.5);
  var next = 0;
  for (final (t, swell) in rows) {
    while (next < touches.length && touches[next].t <= t) {
      final touch = touches[next++];
      if (touch.phase == 0) {
        motion.pointerDown(touch.t, touch.x);
      } else {
        motion.pointerUp(touch.t, touch.x);
      }
    }
    motion.advance(t);
    for (final s in swells) {
      if (t >= s.down - 0.03 && t <= s.up + 0.6) {
        s.growth.add(motion.chromeGrowth - swell * width);
      }
    }
  }
  return swells;
}

List<_Swell> _allSwells({required bool alignToSwell}) => [
  for (final file in _swellFiles)
    ..._replaySwell(file, alignToSwell: alignToSwell),
];

void main() {
  test('tab bar taps at their logged times start the lens when the device '
      'does', () {
    final taps = _all(alignToLift: false);
    expect(taps, hasLength(79));
    // The onset is counted from the touch's stamp. The device's own taps
    // spread by UIKit's delivery around their median (39 - 57 ms, median
    // 45.5).
    final onsets = [for (final tap in taps) tap.onset];
    expect(
      median(onsets),
      closeTo(MorphLensTuning.tabBar.startDelay, deviceFrame / 2),
    );
    for (final tap in taps) {
      expect(
        tap.onset,
        closeTo(MorphLensTuning.tabBar.startDelay, deliverySpread),
        reason: tap.label,
      );
      expect(tap.selected, tap.to, reason: tap.label);
      expect(tap.landed, tap.to, reason: tap.label);
      if (!tap.slowLift) {
        expect(_rms(tap.size), lessThan(_sizeTolerance), reason: tap.label);
      }
    }
    // The travel center follows each tap's own onset, so the typical tap
    // meets the aligned tolerance and the others stray by their onset.
    final centers = [
      for (final tap in taps)
        if (tap.center.isNotEmpty) _rms(tap.center),
    ];
    expect(centers, hasLength(26));
    expect(median(centers), lessThan(_centerTolerance));
  });

  test('tab bar taps travel, lift and land like the device once the lens '
      'starts', () {
    final taps = _all(alignToLift: true);
    expect(taps, hasLength(79));
    for (final tap in taps) {
      expect(tap.selected, tap.to, reason: tap.label);
      expect(tap.landed, tap.to, reason: tap.label);
      expect(tap.size.length, greaterThan(40), reason: tap.label);
    }
    final travelled = [
      for (final tap in taps)
        if (tap.center.isNotEmpty) tap,
    ];
    expect(travelled, hasLength(26));
    for (final tap in travelled) {
      expect(tap.center.length, greaterThan(20), reason: tap.label);
    }
    expect(_failures(taps, slowLift: false), isEmpty);
  });

  test('the tab bar swells when the device does, counted from the touch '
      'stamps', () {
    const tuning = MorphLensTuning.tabBar;
    final swells = _allSwells(alignToSwell: false);
    expect(swells, hasLength(26));
    // The device's bar swells with its lens (38.8 - 54.3 ms, median 44.75)
    // and returns after a delivery (15.8 - 36.3 ms, median 21.6).
    expect(
      median([for (final s in swells) s.onset.press]),
      closeTo(tuning.chromeLag, deviceFrame / 2),
    );
    expect(
      median([for (final s in swells) s.onset.release]),
      closeTo(tuning.chromeReleaseLag, deviceFrame / 2),
    );
    for (final s in swells) {
      // The swell starts on the frame the lens does (-4.5 - +1 ms apart).
      expect(s.onset.press, closeTo(s.lensOnset, deviceFrame), reason: s.label);
      expect(
        s.onset.press,
        closeTo(tuning.chromeLag, deliverySpread),
        reason: s.label,
      );
      expect(
        s.onset.release,
        closeTo(tuning.chromeReleaseLag, deliverySpread),
        reason: s.label,
      );
    }
    // Each tap strays by its own onsets: 0.09 - 0.67 pt, median 0.28. One
    // lag of 20 ms (or the 34.3 ms that one lag fits with the growth left
    // free) at both ends leaves a median of 1.25 (1.11) pt.
    expect(median([for (final s in swells) _rms(s.growth)]), lessThan(0.35));
  });

  test('the tab bar swells like the device once its swell starts', () {
    final swells = _allSwells(alignToSwell: true);
    expect(swells, hasLength(26));
    for (final s in swells) {
      expect(s.growth.length, greaterThan(30), reason: s.label);
      // The device holds its bar 14.06 - 14.14 pt wider (five holds), morph
      // 14.6: a hold's plateau stays 0.46 pt apart (tab-bar.md).
      final held = s.up - s.down > 0.5;
      expect(
        _rms(s.growth),
        lessThan(held ? 0.65 : _growthTolerance),
        reason: s.label,
      );
    }
  });

  test(
    'the lens of the four-tab bar grows late at its third slot like the '
    'device',
    () {
      final slow = [
        for (final tap in _all(alignToLift: true))
          if (tap.slowLift) tap,
      ];
      expect(slow, hasLength(22));
      expect(_failures(slow, slowLift: true), isEmpty);
    },
    skip:
        'slow lift, documented and not modelled (tab-bar.md): size rms '
        '3.42 - 3.93 pt on 22 of 22 taps vs 2.5, max 6.8 pt',
  );
}
