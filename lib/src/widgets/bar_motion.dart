import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// UIKit's tuning for glass bar items that change: the
/// `GlassContainerToolbarPTSettings` iOS 27 runs when a toolbar's items
/// are replaced and when a navigation bar's buttons change on a push or
/// a pop.
///
/// Read live from the tuning (springs in SwiftUI's duration / bounce
/// terms, here as response / damping ratio = 1 - bounce) and placed in
/// time by the frame-by-frame recordings of `setToolbarItems(_:animated:)`
/// and of pushes.
@immutable
class MorphBarTransitionSpec {
  /// Creates a spec from explicit values.
  const MorphBarTransitionSpec({
    this.frameSpring = const MorphSpring(0.416, 0.75),
    this.frameDelay = 0.05,
    this.birthStaggerDelay = 0.1,
    this.contentSpring = const MorphSpring(0.416, 0.75),
    this.contentDelay = 0.05,
    this.appearScale = 0.2,
    this.appearBlur = 10,
    this.pulseDelay = 0.065,
    this.pulseUpSpring = const MorphSpring(0.292, 0.5),
    this.pulseMaxScale = 1.2,
    this.pulseMaxPoints = 16,
    this.pulseHeightDownDelay = 0.113,
    this.pulseHeightDownSpring = const MorphSpring(0.416, 0.584),
    this.pulseWidthDownDelay = 0.142,
    this.pulseWidthDownSpring = const MorphSpring(0.416, 0.5),
    this.segmentDelay = 0.030,
    this.oversizedInPlace = true,
  });

  /// The spring a capsule's frame moves on: `transition.springDuration`
  /// 0.416 s, bounce 0.25.
  final MorphSpring frameSpring;

  /// The time from the change to the start of the frame motion, in
  /// seconds (fitted jointly to the device and simulator recordings of
  /// `setToolbarItems(_:animated:)`, measured from the call).
  final double frameDelay;

  /// The time from the change to the start of the frame motion of a
  /// capsule that moves while a capsule of its side grows out of a
  /// survivor, in seconds: the survivor waits for the newborn (fitted 0.1 s; the tuning's
  /// `transition.minDelay` / `maxDelay` are 0.083 / 0.166).
  final double birthStaggerDelay;

  /// The spring items appear, leave and travel on (fitted 0.40 / 0.80 on
  /// the recordings, the transition spring within that spread).
  final MorphSpring contentSpring;

  /// The time from the change to the start of the item motion, in
  /// seconds (fitted).
  final double contentDelay;

  /// The scale an item or a capsule is born at and leaves at:
  /// `appearance.scale`.
  final double appearScale;

  /// The blur of an item that is born or leaves, at its smallest:
  /// `appearance.blurRadius`.
  final double appearBlur;

  /// The time from the change to the start of the size pulse, in seconds
  /// (fitted 0.065 s from the call; a frame or two before the tuning's
  /// `transition.minDelay` 0.083, which counts from the commit).
  final double pulseDelay;

  /// The spring a changed capsule swells on: `scalePulse.scaleUp` 0.292 s,
  /// bounce 0.5.
  final MorphSpring pulseUpSpring;

  /// The largest relative swell: `scalePulse.maxScaleWidth/Height`.
  final double pulseMaxScale;

  /// The largest swell in points: `scalePulse.maxPointScaleWidth/Height`.
  final double pulseMaxPoints;

  /// The time from the start of the swell to the return of the height:
  /// `scalePulse.scaleDownHeightDelay`.
  final double pulseHeightDownDelay;

  /// The spring the height returns on: 0.416 s, bounce 0.416.
  final MorphSpring pulseHeightDownSpring;

  /// The time from the start of the swell to the return of the width:
  /// `scalePulse.scaleDownWidthDelay`.
  final double pulseWidthDownDelay;

  /// The spring the width returns on: 0.416 s, bounce 0.5.
  final MorphSpring pulseWidthDownSpring;

  /// The time from the change to the start of a group that appears or
  /// leaves in place, in seconds: on a side of the bar that had no group
  /// or keeps none, or too large for its survivor (see [oversizedInPlace]).
  ///
  /// Such a group does not grow out of a neighbour: it stands at its own
  /// place, scaled by [pulseScaleFor] its length per axis, blurred by
  /// [appearBlur] and transparent, and comes in (or goes) on
  /// [frameSpring], scale, opacity and blur on one progress (free fits
  /// 0.39 - 0.41 s / 0.75 - 0.77 over 16 groups). Fitted to
  /// `setToolbarItems(_:animated:)` filling and emptying a toolbar side:
  /// 0.020 - 0.044 s from the call, replay optimum 0.026 - 0.030 (iPhone
  /// 16 Pro, iOS 27.0.1).
  final double segmentDelay;

  /// Whether a group too large for the group it would grow out of (or
  /// shrink into) appears (or leaves) in place instead.
  ///
  /// A group born beside a group of its side that stays grows out of that
  /// survivor: its own box fitted inside the survivor's box before the
  /// change (the size of each axis at most the survivor's, the place as
  /// near its own as fits), at [appearScale]; a group that goes shrinks
  /// into the survivor's box after the change the same way. When the group
  /// is wider or taller than the survivor, a toolbar shows it in place
  /// (`setToolbarItems(_:animated:)`: `[reply share folder]` beside `[compose]`
  /// or `[heart]` in place, `[heart]` out of `[Show Preferences]` and out of
  /// `[compose]`), while a navigation bar still grows it out of the
  /// survivor's own box (`[plus more]` out of `[1x]` on a push, back into it on
  /// a pop; iPhone 16 Pro, iOS 27.0.1, probe scene navseg set b).
  final bool oversizedInPlace;

  /// iOS 27's values for a toolbar whose items are replaced.
  static const standard = MorphBarTransitionSpec();

  /// iOS 27's values for a navigation bar on a push or a pop, which starts
  /// later than a toolbar's item replacement: the capsules' frames after
  /// 0.062 s (center replay optimum 0.060 - 0.062 over four pushes and
  /// four pops), groups coming or going in place after 0.058 s (0.050 -
  /// 0.063 over eight groups, replay optimum 0.058), measured from the
  /// `pushViewController` / `popViewController` call.
  static const navigation = MorphBarTransitionSpec(
    frameDelay: 0.062,
    segmentDelay: 0.058,
    oversizedInPlace: false,
  );

  /// The swell of a capsule [length] long, as a factor.
  double pulseScaleFor(double length) =>
      length <= 0 ? 1 : math.min(pulseMaxScale, 1 + pulseMaxPoints / length);
}

/// Where one item of a bar sits in a layout handed to [MorphBarMotion].
@immutable
class MorphBarItemLayout {
  /// Creates an item layout.
  const MorphBarItemLayout(this.id, this.rect);

  /// The identity of the item across layouts.
  final Object id;

  /// The item's box in the bar's coordinates.
  final Rect rect;
}

/// One glass capsule of a bar layout handed to [MorphBarMotion]: a group
/// of items that share one piece of glass.
@immutable
class MorphBarCapsuleLayout {
  /// Creates a capsule layout.
  const MorphBarCapsuleLayout(
    this.id,
    this.rect,
    this.items, {
    this.segment,
    this.anonymous = false,
  });

  /// The identity of the capsule across layouts.
  final Object id;

  /// Whether the capsule has no identity of its own, as a group without an
  /// id: it then continues the capsule without one of its segment whose
  /// center lies nearest (UIKit's bar groups carry no identity across a
  /// push: `[plus more]` `[1x]` -> `[Show Preferences]` keeps the inner group's
  /// glass, the nearer one).
  final bool anonymous;

  /// The side of the bar the capsule belongs to, such as its leading or
  /// trailing groups; null puts every such capsule on one side.
  ///
  /// A capsule changes only into a capsule of its own segment: an [id]
  /// found in another segment is a new capsule, and a newborn grows out of
  /// a capsule of its segment that stays only. When a segment keeps no
  /// capsule through the change, its capsules appear and leave in place
  /// (see [MorphBarTransitionSpec.segmentDelay]).
  final Object? segment;

  /// The capsule's box in the bar's coordinates.
  final Rect rect;

  /// The items in the capsule.
  final List<MorphBarItemLayout> items;
}

/// A capsule of a bar in one frame.
@immutable
class MorphBarCapsuleFrame {
  /// Creates a frame.
  const MorphBarCapsuleFrame(
    this.id,
    this.rect, {
    required this.leaving,
    this.segment,
    this.opacity = 1,
    this.apart = false,
  });

  /// The identity of the capsule.
  final Object id;

  /// The capsule's box, swell included.
  final Rect rect;

  /// Whether the capsule is on its way out.
  final bool leaving;

  /// The segment of the capsule's layout.
  final Object? segment;

  /// How present the capsule's glass is, 0 to 1.
  final double opacity;

  /// Whether the capsule appears or leaves in place: UIKit draws it in a
  /// glass container of its own, so it never fuses with the other
  /// capsules of the bar.
  final bool apart;
}

/// An item of a bar in one frame.
@immutable
class MorphBarItemFrame {
  /// Creates a frame.
  const MorphBarItemFrame(
    this.id, {
    required this.center,
    required this.size,
    required this.scale,
    required this.presence,
    required this.blur,
    required this.leaving,
  });

  /// The identity of the item.
  final Object id;

  /// The center of the item.
  final Offset center;

  /// The item's laid-out size; [scale] applies on top.
  final Size size;

  /// The scale the item is drawn at.
  final double scale;

  /// How present the item is, 0 gone and 1 fully there; UIKit draws it at
  /// this opacity.
  final double presence;

  /// The blur the item is drawn with, in logical pixels.
  final double blur;

  /// Whether the item is on its way out.
  final bool leaving;
}

/// The identity a capsule on its way out takes when a capsule of the new
/// layout carries the id it had.
@internal
class MorphBarDepartedId {
  /// Wraps the [id] a leaving capsule had.
  MorphBarDepartedId(this.id);

  /// The id the capsule had.
  final Object id;

  @override
  String toString() => 'MorphBarDepartedId($id)';
}

class _Capsule {
  _Capsule(
    this.id,
    this.segment,
    Rect rect,
    MorphBarTransitionSpec spec, {
    required this.anonymous,
  }) : cx = MorphSpringState(spec.frameSpring, rect.center.dx),
       cy = MorphSpringState(spec.frameSpring, rect.center.dy),
       w = MorphSpringState(spec.frameSpring, rect.width),
       h = MorphSpringState(spec.frameSpring, rect.height),
       pulseW = MorphSpringState(spec.pulseUpSpring, 1),
       pulseH = MorphSpringState(spec.pulseUpSpring, 1);

  Object id;
  final Object? segment;
  final bool anonymous;
  final MorphSpringState cx;
  final MorphSpringState cy;
  final MorphSpringState w;
  final MorphSpringState h;
  final MorphSpringState pulseW;
  final MorphSpringState pulseH;
  MorphSpringState? presence;
  bool leaving = false;
  int generation = 0;
  Rect target = Rect.zero;
}

class _Item {
  _Item(this.id, this.capsule, Offset center, this.size, MorphSpring spring)
    : cx = MorphSpringState(spring, center.dx),
      cy = MorphSpringState(spring, center.dy),
      presence = MorphSpringState(spring, 1);

  final Object id;
  _Capsule capsule;
  Size size;
  final MorphSpringState cx;
  final MorphSpringState cy;
  final MorphSpringState presence;
  bool leaving = false;
  int generation = 0;
}

/// The motion of a glass bar whose items change: iOS 27's toolbar and
/// navigation bar item transition.
///
/// Feed it layouts with [setLayout]. A capsule that keeps its identity
/// moves and resizes to its new box on [MorphBarTransitionSpec.frameSpring]
/// and, when its items changed, swells by up to 16 points (20 percent at
/// most) and settles back - the height first, then the width. Items that
/// stay travel to their new place; new items appear at the old center of
/// their capsule, at a fifth of their size, blurred and transparent, and
/// grow into place; leaving items shrink, blur and fade into the new
/// center of their capsule. Every value retargets from its current state,
/// so a change in the middle of another change is continuous.
///
/// Capsules change only within their [MorphBarCapsuleLayout.segment]: the
/// leading groups of a bar into leading groups, the trailing ones into
/// trailing ones. A capsule with an id continues the capsule of its
/// segment with that id; an [MorphBarCapsuleLayout.anonymous] one the
/// nearest anonymous capsule of its segment.
///
/// One law places every capsule that comes or goes. A new capsule grows
/// out of the nearest capsule of its segment that stays: its own box
/// fitted inside that survivor's box before the change, at a fifth of the
/// fitted size; a capsule that goes shrinks into the survivor's box after
/// the change the same way, so it vanishes inside it. The survivor swells
/// as if its items changed. A capsule with no survivor on its side - and,
/// with [MorphBarTransitionSpec.oversizedInPlace], one too large for its
/// survivor - appears in place, swollen, blurred and transparent, settling
/// in, or swells and fades where it stands (see
/// [MorphBarTransitionSpec.segmentDelay]). Such capsules are
/// [MorphBarCapsuleFrame.apart]: they never fuse with the others.
///
/// [setDrift] leans the capsules part of the way toward another layout
/// without changing the layout itself, as a navigation bar does during an
/// interactive pop; the next [setLayout] starts from where the drift put
/// them.
///
/// Times are seconds, positions logical pixels in the bar's own space.
class MorphBarMotion {
  /// Creates the motion with [spec].
  MorphBarMotion({this.spec = MorphBarTransitionSpec.standard});

  /// The tuning.
  final MorphBarTransitionSpec spec;

  final MorphTimeline _timeline = MorphTimeline();
  final List<_Capsule> _capsules = [];
  final List<_Item> _items = [];
  double _now = 0;
  bool _hasLayout = false;
  Map<_Capsule, Rect> _driftTo = const {};
  double _drift = 0;

  /// Whether the platform asks for reduced motion: changes then snap.
  bool reducedMotion = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Advances the motion to time [t].
  void advance(double t) {
    _timeline.runDue(t);
    if (t > _now) _now = t;
    _capsules.removeWhere((c) => c.leaving && _gone(c));
    for (final c in _capsules) {
      final presence = c.presence;
      if (presence != null &&
          !c.leaving &&
          presence.target == 1 &&
          presence.isAtRest(_now, 0.002)) {
        c.presence = null;
      }
    }
    _items.removeWhere(
      (i) =>
          (i.capsule.presence != null && !_capsules.contains(i.capsule)) ||
          (i.leaving &&
              i.presence.target == 0 &&
              i.presence.isAtRest(_now, 0.002)),
    );
  }

  bool _gone(_Capsule c) {
    final presence = c.presence;
    if (presence != null) {
      return presence.target == 0 && presence.isAtRest(_now, 0.002);
    }
    return c.w.target <= c.target.width * spec.appearScale + 1e-9 &&
        c.w.isAtRest(_now, 0.05) &&
        c.h.isAtRest(_now, 0.05);
  }

  /// Whether nothing is moving.
  bool get isSettled {
    if (!_timeline.isEmpty) return false;
    for (final c in _capsules) {
      if (c.leaving || c.presence != null) return false;
      if (!c.cx.isAtRest(_now, 0.01) ||
          !c.cy.isAtRest(_now, 0.01) ||
          !c.w.isAtRest(_now, 0.01) ||
          !c.h.isAtRest(_now, 0.01)) {
        return false;
      }
      if (!c.pulseW.isAtRest(_now, 1e-4) || !c.pulseH.isAtRest(_now, 1e-4)) {
        return false;
      }
    }
    for (final i in _items) {
      if (i.leaving) return false;
      if (!i.cx.isAtRest(_now, 0.01) ||
          !i.cy.isAtRest(_now, 0.01) ||
          !i.presence.isAtRest(_now, 0.001)) {
        return false;
      }
    }
    return true;
  }

  _Item? _item(Object id) {
    for (final i in _items) {
      if (i.id == id && !i.leaving) return i;
    }
    return null;
  }

  /// Pairs the capsules of [layout] (all but [skip]) with the [candidates]
  /// that continue into them: a capsule with an id continues the
  /// candidate of its segment with that id, an anonymous one the anonymous
  /// candidate of its segment whose place ([from]) lies nearest, nearest
  /// pairs first.
  Map<int, _Capsule> _pair(
    List<MorphBarCapsuleLayout> layout,
    List<_Capsule> candidates,
    Rect Function(_Capsule c) from, {
    Set<int> skip = const {},
  }) {
    final out = <int, _Capsule>{};
    final taken = <_Capsule>{};
    for (var k = 0; k < layout.length; k++) {
      final c = layout[k];
      if (c.anonymous || skip.contains(k)) continue;
      for (final candidate in candidates) {
        if (!candidate.anonymous &&
            candidate.id == c.id &&
            candidate.segment == c.segment &&
            !taken.contains(candidate)) {
          out[k] = candidate;
          taken.add(candidate);
          break;
        }
      }
    }
    final pairs = <(double, int, int)>[];
    for (var k = 0; k < layout.length; k++) {
      final c = layout[k];
      if (!c.anonymous || skip.contains(k)) continue;
      for (var n = 0; n < candidates.length; n++) {
        final candidate = candidates[n];
        if (!candidate.anonymous || candidate.segment != c.segment) continue;
        pairs.add(((from(candidate).center - c.rect.center).distance, k, n));
      }
    }
    pairs.sort(
      (a, b) => switch (a.$1.compareTo(b.$1)) {
        0 => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3),
        final order => order,
      },
    );
    for (final (_, k, n) in pairs) {
      final candidate = candidates[n];
      if (out.containsKey(k) || taken.contains(candidate)) continue;
      out[k] = candidate;
      taken.add(candidate);
    }
    return out;
  }

  /// Brings back the items of [layout] that are still on their way out:
  /// an id has one entry, and the one that leaves turns around from where
  /// it is.
  void _reviveItems(List<MorphBarCapsuleLayout> layout) {
    for (final c in layout) {
      for (final item in c.items) {
        for (final i in _items) {
          if (i.id == item.id && i.leaving) {
            i.leaving = false;
            i.generation++;
          }
        }
      }
    }
  }

  /// The box of [size] at [center] moved and cut to lie inside [into]:
  /// each axis at most as long as [into]'s, as near [center] as it fits.
  static Rect _inside(Size size, Offset center, Rect into) {
    final w = math.min(size.width, into.width);
    final h = math.min(size.height, into.height);
    double fit(double v, double lo, double hi) =>
        math.min(math.max(v, lo), math.max(lo, hi));
    return Rect.fromCenter(
      center: Offset(
        fit(center.dx, into.left + w / 2, into.right - w / 2),
        fit(center.dy, into.top + h / 2, into.bottom - h / 2),
      ),
      width: w,
      height: h,
    );
  }

  /// Whether a capsule of [size] grows out of (or shrinks into) a survivor
  /// whose box is [into] rather than appearing (or leaving) in place.
  bool _fits(Size size, Rect into) =>
      !spec.oversizedInPlace ||
      (size.width <= into.width + 1e-6 && size.height <= into.height + 1e-6);

  Rect _visible(_Capsule c, double t) => Rect.fromCenter(
    center: Offset(c.cx.value(t), c.cy.value(t)),
    width: c.w.value(t),
    height: c.h.value(t),
  );

  /// Leans every capsule that [toward] also has (paired as [setLayout]
  /// pairs them) [amount] of the way from where it is toward its box there,
  /// its items riding along; null or 0 removes the lean at once.
  ///
  /// The lean is drawn on top of the motion, a pure function of [amount];
  /// a [setLayout] while leaning starts from the leaning capsules.
  void setDrift(List<MorphBarCapsuleLayout>? toward, double amount) {
    if (toward == null || amount == 0) {
      _driftTo = const {};
      _drift = 0;
      return;
    }
    final live = [
      for (final c in _capsules)
        if (!c.leaving) c,
    ];
    _driftTo = {
      for (final MapEntry(key: k, value: c) in _pair(
        toward,
        live,
        (c) => c.target,
      ).entries)
        c: toward[k].rect,
    };
    _drift = amount;
  }

  /// Whether capsules lean toward a [setDrift] layout.
  bool get isDrifting => _drift != 0 && _driftTo.isNotEmpty;

  /// Ends a [setDrift] lean at time [t] without a jump: the capsules spring
  /// home on [MorphBarTransitionSpec.frameSpring] from where they lean.
  void endDrift(double t) {
    advance(t);
    _keepDrift(t, rest: false);
  }

  void _keepDrift(double t, {required bool rest}) {
    if (!isDrifting) return;
    void put(MorphSpringState s, double v) {
      if (rest) {
        s.snap(t, v);
      } else {
        s.setState(t, v, s.velocity(t));
      }
    }

    final shift = <_Capsule, Offset>{};
    for (final c in _capsules) {
      if (c.leaving || !_driftTo.containsKey(c)) continue;
      final base = _visible(c, t);
      final r = _drifted(c, t);
      shift[c] = r.center - base.center;
      put(c.cx, r.center.dx);
      put(c.cy, r.center.dy);
      put(c.w, r.width);
      put(c.h, r.height);
    }
    for (final i in _items) {
      final d = i.leaving ? null : shift[i.capsule];
      if (d == null) continue;
      put(i.cx, i.cx.value(t) + d.dx);
      put(i.cy, i.cy.value(t) + d.dy);
    }
    _driftTo = const {};
    _drift = 0;
  }

  Rect _drifted(_Capsule c, double t) {
    final base = _visible(c, t);
    final to = c.leaving || _drift == 0 ? null : _driftTo[c];
    if (to == null) return base;
    return Rect.lerp(base, to, _drift)!;
  }

  /// Shows [layout] from time [t]; with [animated] false (and on the
  /// first layout) everything snaps.
  void setLayout(
    double t,
    List<MorphBarCapsuleLayout> layout, {
    bool animated = true,
  }) {
    advance(t);
    if (!_hasLayout || !animated || reducedMotion) {
      _hasLayout = true;
      _snap(t, layout);
      return;
    }
    _keepDrift(t, rest: true);
    _reviveItems(layout);
    final spring = spec.frameSpring;
    final content = spec.contentSpring;
    final live = [
      for (final c in _capsules)
        if (!c.leaving) c,
    ];
    final oldCenters = <_Capsule, Offset>{
      for (final c in live) c: _visible(c, t).center,
    };
    final paired = _pair(layout, live, (c) => c.target);
    final leaving = [
      for (final c in _capsules)
        if (c.leaving) c,
    ];
    for (final MapEntry(key: k, value: c) in _pair(
      layout,
      leaving,
      (c) => _visible(c, t),
      skip: paired.keys.toSet(),
    ).entries) {
      c.leaving = false;
      c.generation++;
      paired[k] = c;
    }
    final survivors = {
      for (final MapEntry(key: k, value: c) in paired.entries)
        if (live.contains(c)) k: c,
    };
    (_Capsule, Rect)? nearestSurvivor(
      Object? segment,
      Offset from, {
      required bool after,
    }) {
      (_Capsule, Rect)? best;
      var distance = double.infinity;
      for (final MapEntry(key: k, value: c) in survivors.entries) {
        if (c.segment != segment) continue;
        final d = (layout[k].rect.center - from).distance;
        if (d < distance) {
          distance = d;
          best = (c, after ? layout[k].rect : _visible(c, t));
        }
      }
      return best;
    }

    final resolved = <_Capsule>[];
    final births = <_Capsule, Offset>{};
    final inPlace = <_Capsule>{};
    final hosts = <_Capsule>{};
    final birthSegments = <Object?>{};
    for (var k = 0; k < layout.length; k++) {
      final c = layout[k];
      final existing = paired[k];
      if (existing != null) {
        if (existing.anonymous) existing.id = c.id;
        resolved.add(existing);
        continue;
      }
      final (host, source) =
          nearestSurvivor(c.segment, c.rect.center, after: false) ??
          (null, Rect.zero);
      final _Capsule born;
      if (host != null && _fits(c.rect.size, source)) {
        final box = _inside(c.rect.size, c.rect.center, source);
        born = _Capsule(
          c.id,
          c.segment,
          Rect.fromCenter(
            center: box.center,
            width: box.width * spec.appearScale,
            height: box.height * spec.appearScale,
          ),
          spec,
          anonymous: c.anonymous,
        );
        births[born] = box.center;
        hosts.add(host);
        birthSegments.add(c.segment);
      } else {
        born = _Capsule(c.id, c.segment, c.rect, spec, anonymous: c.anonymous);
        born.presence = MorphSpringState(spring, 0);
        inPlace.add(born);
      }
      _capsules.add(born);
      resolved.add(born);
    }
    final layoutOf = <_Capsule, MorphBarCapsuleLayout>{
      for (var k = 0; k < layout.length; k++) resolved[k]: layout[k],
    };
    final deaths = <_Capsule, Offset>{};
    for (final c in List.of(_capsules)) {
      if (c.leaving || layoutOf.containsKey(c)) continue;
      c.leaving = true;
      final generation = ++c.generation;
      final here = _visible(c, t).center;
      final (host, sink) =
          nearestSurvivor(c.segment, here, after: true) ?? (null, Rect.zero);
      if (host == null || !_fits(c.target.size, sink)) {
        final presence = c.presence ??= MorphSpringState(spring, 1);
        _timeline.at(t + spec.segmentDelay, (double at) {
          if (c.generation != generation) return;
          presence.retarget(at, 0, spring: spring);
        });
        continue;
      }
      final box = _inside(c.target.size, here, sink);
      deaths[c] = box.center;
      hosts.add(host);
      _timeline.at(t + spec.frameDelay, (double at) {
        if (c.generation != generation) return;
        c.cx.retarget(at, box.center.dx, spring: spring);
        c.cy.retarget(at, box.center.dy, spring: spring);
        c.w.retarget(at, box.width * spec.appearScale, spring: spring);
        c.h.retarget(at, box.height * spec.appearScale, spring: spring);
      });
    }
    final liveIds = {
      for (final c in _capsules)
        if (!c.leaving) c.id,
    };
    for (final c in _capsules) {
      if (c.leaving && liveIds.contains(c.id)) c.id = MorphBarDepartedId(c.id);
    }
    for (final c in resolved) {
      final target = layoutOf[c]!;
      final born = births.containsKey(c);
      final appearing = inPlace.contains(c);
      final changed =
          born ||
          (!appearing && (hosts.contains(c) || _itemsChanged(c, target.items)));
      final moves = c.target != target.rect;
      c.target = target.rect;
      final generation = ++c.generation;
      final delay = !born && birthSegments.contains(c.segment) && moves
          ? spec.birthStaggerDelay
          : spec.frameDelay;
      _timeline.at(t + delay, (double at) {
        if (c.generation != generation) return;
        c.cx.retarget(at, target.rect.center.dx, spring: spring);
        c.cy.retarget(at, target.rect.center.dy, spring: spring);
        c.w.retarget(at, target.rect.width, spring: spring);
        c.h.retarget(at, target.rect.height, spring: spring);
      });
      final presence = c.presence;
      if (presence != null) {
        _timeline.at(t + spec.segmentDelay, (double at) {
          if (c.generation != generation) return;
          presence.retarget(at, 1, spring: spring);
        });
      }
      if (changed) _schedulePulse(c, t, generation, target.rect.size);
    }
    final newCenters = {
      for (var k = 0; k < layout.length; k++)
        resolved[k]: layout[k].rect.center,
      ...deaths,
    };
    for (final i in _items) {
      if (i.leaving) continue;
      if (_findItem(layout, i.id) != null) continue;
      i.leaving = true;
      final generation = ++i.generation;
      final end = newCenters[i.capsule] ?? Offset(i.cx.value(t), i.cy.value(t));
      _timeline.at(t + spec.contentDelay, (double at) {
        if (i.generation != generation) return;
        i.cx.retarget(at, end.dx, spring: content);
        i.cy.retarget(at, end.dy, spring: content);
        i.presence.retarget(at, 0, spring: content);
      });
    }
    for (var k = 0; k < layout.length; k++) {
      final c = layout[k];
      final capsule = resolved[k];
      for (final item in c.items) {
        final existing = _item(item.id);
        if (existing != null) {
          existing.capsule = capsule;
          existing.size = item.rect.size;
          _timeline.at(t + spec.contentDelay, (double at) {
            existing.cx.retarget(at, item.rect.center.dx, spring: content);
            existing.cy.retarget(at, item.rect.center.dy, spring: content);
            existing.presence.retarget(at, 1, spring: content);
          });
          continue;
        }
        if (inPlace.contains(capsule)) {
          _items.add(
            _Item(item.id, capsule, item.rect.center, item.rect.size, content),
          );
          continue;
        }
        final start =
            oldCenters[capsule] ?? births[capsule] ?? item.rect.center;
        final born = _Item(item.id, capsule, start, item.rect.size, content);
        born.presence.snap(t, 0);
        _items.add(born);
        _timeline.at(t + spec.contentDelay, (double at) {
          born.cx.retarget(at, item.rect.center.dx, spring: content);
          born.cy.retarget(at, item.rect.center.dy, spring: content);
          born.presence.retarget(at, 1, spring: content);
        });
      }
    }
  }

  void _schedulePulse(_Capsule c, double t, int generation, Size size) {
    final start = t + spec.pulseDelay;
    _timeline.at(start, (double at) {
      if (c.generation != generation) return;
      c.pulseW.retarget(
        at,
        spec.pulseScaleFor(size.width),
        spring: spec.pulseUpSpring,
      );
      c.pulseH.retarget(
        at,
        spec.pulseScaleFor(size.height),
        spring: spec.pulseUpSpring,
      );
    });
    _timeline.at(start + spec.pulseHeightDownDelay, (double at) {
      if (c.generation != generation) return;
      c.pulseH.retarget(at, 1, spring: spec.pulseHeightDownSpring);
    });
    _timeline.at(start + spec.pulseWidthDownDelay, (double at) {
      if (c.generation != generation) return;
      c.pulseW.retarget(at, 1, spring: spec.pulseWidthDownSpring);
    });
  }

  bool _itemsChanged(_Capsule capsule, List<MorphBarItemLayout> items) {
    final before = [
      for (final i in _items)
        if (!i.leaving && i.capsule == capsule) i.id,
    ];
    if (before.length != items.length) return true;
    for (var k = 0; k < items.length; k++) {
      if (before[k] != items[k].id) return true;
    }
    return false;
  }

  MorphBarItemLayout? _findItem(List<MorphBarCapsuleLayout> layout, Object id) {
    for (final c in layout) {
      for (final i in c.items) {
        if (i.id == id) return i;
      }
    }
    return null;
  }

  void _snap(double t, List<MorphBarCapsuleLayout> layout) {
    _driftTo = const {};
    _drift = 0;
    _timeline.clear();
    _capsules.clear();
    _items.clear();
    for (final c in layout) {
      final capsule = _Capsule(
        c.id,
        c.segment,
        c.rect,
        spec,
        anonymous: c.anonymous,
      );
      capsule.target = c.rect;
      _capsules.add(capsule);
      for (final i in c.items) {
        _items.add(
          _Item(i.id, capsule, i.rect.center, i.rect.size, spec.contentSpring),
        );
      }
    }
  }

  /// The capsules at the current time, leaving ones included.
  List<MorphBarCapsuleFrame> get capsules => [
    for (final c in _capsules)
      MorphBarCapsuleFrame(
        c.id,
        _pulsed(c),
        leaving: c.leaving,
        segment: c.segment,
        opacity: (c.presence?.value(_now) ?? 1).clamp(0.0, 1.0),
        apart: c.presence != null,
      ),
  ];

  /// The swell of a capsule that appears or leaves in place, per axis.
  Offset _apartScale(_Capsule c) {
    final presence = c.presence;
    if (presence == null) return const Offset(1, 1);
    final rest = 1 - presence.value(_now);
    return Offset(
      1 + (spec.pulseScaleFor(c.target.width) - 1) * rest,
      1 + (spec.pulseScaleFor(c.target.height) - 1) * rest,
    );
  }

  Rect _pulsed(_Capsule c) {
    final base = _drifted(c, _now);
    final apart = _apartScale(c);
    return Rect.fromCenter(
      center: base.center,
      width: math.max(
        0,
        (base.width + (c.pulseW.value(_now) - 1) * c.target.width) * apart.dx,
      ),
      height: math.max(
        0,
        (base.height + (c.pulseH.value(_now) - 1) * c.target.height) * apart.dy,
      ),
    );
  }

  /// The items at the current time, leaving ones included.
  List<MorphBarItemFrame> get items {
    final pulse = {
      for (final c in _capsules)
        if (!c.leaving) c: c.pulseH.value(_now),
    };
    final shift = <_Capsule, Offset>{
      if (isDrifting)
        for (final c in _capsules)
          if (!c.leaving && _driftTo.containsKey(c))
            c: _drifted(c, _now).center - _visible(c, _now).center,
    };
    return [
      for (final i in _items)
        () {
          final p = i.presence.value(_now);
          final s = lerpDouble(spec.appearScale, 1, p)!;
          var center =
              Offset(i.cx.value(_now), i.cy.value(_now)) +
              (i.leaving ? Offset.zero : shift[i.capsule] ?? Offset.zero);
          var scale = s * (pulse[i.capsule] ?? 1);
          var presence = p.clamp(0.0, 1.0);
          var blur = math.max(0.0, spec.appearBlur * (1 - p));
          final capsule = i.capsule;
          final apart = capsule.presence;
          if (apart != null) {
            final q = apart.value(_now);
            final f = _apartScale(capsule);
            final origin = _drifted(capsule, _now).center;
            center =
                origin +
                Offset(
                  (center.dx - origin.dx) * f.dx,
                  (center.dy - origin.dy) * f.dy,
                );
            scale *= f.dy;
            presence *= q.clamp(0.0, 1.0);
            blur = math.max(blur, spec.appearBlur * (1 - q));
          }
          return MorphBarItemFrame(
            i.id,
            center: center,
            size: i.size,
            scale: math.max(0, scale),
            presence: presence,
            blur: blur,
            leaving: i.leaving,
          );
        }(),
    ];
  }

  /// The frame of the item [id], or null when it is not in the bar.
  MorphBarItemFrame? itemFrame(Object id) {
    for (final f in items) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// The frame of the capsule [id], or null when it is not in the bar.
  MorphBarCapsuleFrame? capsuleFrame(Object id) {
    for (final f in capsules) {
      if (f.id == id) return f;
    }
    return null;
  }
}
