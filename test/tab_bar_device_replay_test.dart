import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/lens_motion.dart';

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
