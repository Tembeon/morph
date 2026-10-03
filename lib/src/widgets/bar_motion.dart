import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
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
  });

  /// The spring a capsule's frame moves on: `transition.springDuration`
  /// 0.416 s, bounce 0.25.
  final MorphSpring frameSpring;

  /// The time from the change to the start of the frame motion, in
  /// seconds (fitted jointly to the device and simulator recordings of
  /// `setToolbarItems(_:animated:)`, measured from the call).
  final double frameDelay;

  /// The time from the change to the start of the frame motion of a
  /// capsule that changes while a neighbour is born, in seconds: the
  /// survivor waits for the newborn (fitted 0.1 s; the tuning's
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

  /// iOS 27's values.
  static const standard = MorphBarTransitionSpec();

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
  const MorphBarCapsuleLayout(this.id, this.rect, this.items);

  /// The identity of the capsule across layouts.
  final Object id;

  /// The capsule's box in the bar's coordinates.
  final Rect rect;

  /// The items in the capsule.
  final List<MorphBarItemLayout> items;
}

/// A capsule of a bar in one frame.
@immutable
class MorphBarCapsuleFrame {
  /// Creates a frame.
  const MorphBarCapsuleFrame(this.id, this.rect, {required this.leaving});

  /// The identity of the capsule.
  final Object id;

  /// The capsule's box, swell included.
  final Rect rect;

  /// Whether the capsule is on its way out.
  final bool leaving;
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

class _Capsule {
  _Capsule(this.id, Rect rect, MorphSpring spring)
    : cx = MorphSpringState(spring, rect.center.dx),
      cy = MorphSpringState(spring, rect.center.dy),
      w = MorphSpringState(spring, rect.width),
      h = MorphSpringState(spring, rect.height);

  final Object id;
  final MorphSpringState cx;
  final MorphSpringState cy;
  final MorphSpringState w;
  final MorphSpringState h;
  final MorphSpringState pulseW = MorphSpringState(
    MorphBarTransitionSpec.standard.pulseUpSpring,
    1,
  );
  final MorphSpringState pulseH = MorphSpringState(
    MorphBarTransitionSpec.standard.pulseUpSpring,
    1,
  );
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
  Object capsule;
  Size size;
  final MorphSpringState cx;
  final MorphSpringState cy;
  final MorphSpringState presence;
  bool leaving = false;
}

/// The motion of a glass bar whose items change: iOS 27's toolbar and
/// navigation bar item transition.
///
/// Feed it layouts with [setLayout]. A capsule that keeps its identity
/// moves and resizes to its new box on [MorphBarTransitionSpec.frameSpring]
/// and, when its items changed, swells by up to 16 points (20 percent at
/// most) and settles back - the height first, then the width. A new
/// capsule is born at a fifth of its size on the facing edge of its
/// nearest neighbour and grows out of it; a capsule that goes shrinks back
/// into its neighbour. Items that stay travel to their new place; new
/// items appear at the old center of their capsule, at a fifth of their
/// size, blurred and transparent, and grow into place; leaving items
/// shrink, blur and fade into the new center of their capsule. Every
/// value retargets from its current state, so a change in the middle of
/// another change is continuous.
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

  /// Whether the platform asks for reduced motion: changes then snap.
  bool reducedMotion = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Advances the motion to time [t].
  void advance(double t) {
    _timeline.runDue(t);
    if (t > _now) _now = t;
    _capsules.removeWhere(
      (c) =>
          c.leaving &&
          c.w.target <= c.target.width * spec.appearScale + 1e-9 &&
          c.w.isAtRest(_now, 0.05) &&
          c.h.isAtRest(_now, 0.05),
    );
    _items.removeWhere(
      (i) =>
          i.leaving &&
          i.presence.target == 0 &&
          i.presence.isAtRest(_now, 0.002),
    );
  }

  /// Whether nothing is moving.
  bool get isSettled {
    if (!_timeline.isEmpty) return false;
    for (final c in _capsules) {
      if (c.leaving) return false;
      for (final s in [c.cx, c.cy, c.w, c.h]) {
        if (!s.isAtRest(_now, 0.01)) return false;
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

  _Capsule? _capsule(Object id) {
    for (final c in _capsules) {
      if (c.id == id && !c.leaving) return c;
    }
    return null;
  }

  _Item? _item(Object id) {
    for (final i in _items) {
      if (i.id == id && !i.leaving) return i;
    }
    return null;
  }

  Rect _visible(_Capsule c, double t) => Rect.fromCenter(
    center: Offset(c.cx.value(t), c.cy.value(t)),
    width: c.w.value(t),
    height: c.h.value(t),
  );

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
    final spring = spec.frameSpring;
    final content = spec.contentSpring;
    final targets = {for (final c in layout) c.id: c};
    final oldCenters = <Object, Offset>{
      for (final c in _capsules)
        if (!c.leaving) c.id: _visible(c, t).center,
    };
    final oldTargets = <Object, Rect>{
      for (final c in _capsules)
        if (!c.leaving) c.id: c.target,
    };
    final births = <Object, Offset>{};
    for (final c in layout) {
      final existing = _capsule(c.id);
      if (existing != null) continue;
      final birth = _birthPoint(c, layout);
      births[c.id] = birth;
      final born = _Capsule(
        c.id,
        Rect.fromCenter(
          center: birth,
          width: c.rect.width * spec.appearScale,
          height: c.rect.height * spec.appearScale,
        ),
        spring,
      );
      _capsules.add(born);
    }
    for (final c in _capsules) {
      if (c.leaving) continue;
      final target = targets[c.id];
      if (target == null) {
        c.leaving = true;
        final end = _deathPoint(c, oldTargets);
        final generation = ++c.generation;
        _timeline.at(t + spec.frameDelay, (double at) {
          if (c.generation != generation) return;
          c.cx.retarget(at, end.dx, spring: spring);
          c.cy.retarget(at, end.dy, spring: spring);
          c.w.retarget(at, c.target.width * spec.appearScale, spring: spring);
          c.h.retarget(at, c.target.height * spec.appearScale, spring: spring);
        });
        continue;
      }
      final born = births.containsKey(c.id);
      final changed = born || _itemsChanged(c.id, target.items);
      final moves = c.target != target.rect;
      c.target = target.rect;
      final generation = ++c.generation;
      final delay = !born && births.isNotEmpty && moves
          ? spec.birthStaggerDelay
          : spec.frameDelay;
      _timeline.at(t + delay, (double at) {
        if (c.generation != generation) return;
        c.cx.retarget(at, target.rect.center.dx, spring: spring);
        c.cy.retarget(at, target.rect.center.dy, spring: spring);
        c.w.retarget(at, target.rect.width, spring: spring);
        c.h.retarget(at, target.rect.height, spring: spring);
      });
      if (changed) _schedulePulse(c, t, generation, target.rect.size);
    }
    final newCenters = {for (final c in layout) c.id: c.rect.center};
    for (final i in _items) {
      if (i.leaving) continue;
      if (_findItem(layout, i.id) != null) continue;
      i.leaving = true;
      final end = newCenters[i.capsule] ?? Offset(i.cx.value(t), i.cy.value(t));
      _timeline.at(t + spec.contentDelay, (double at) {
        i.cx.retarget(at, end.dx, spring: content);
        i.cy.retarget(at, end.dy, spring: content);
        i.presence.retarget(at, 0, spring: content);
      });
    }
    for (final c in layout) {
      for (final item in c.items) {
        final existing = _item(item.id);
        if (existing != null) {
          existing.capsule = c.id;
          existing.size = item.rect.size;
          _timeline.at(t + spec.contentDelay, (double at) {
            existing.cx.retarget(at, item.rect.center.dx, spring: content);
            existing.cy.retarget(at, item.rect.center.dy, spring: content);
            existing.presence.retarget(at, 1, spring: content);
          });
          continue;
        }
        final start = oldCenters[c.id] ?? births[c.id] ?? item.rect.center;
        final born = _Item(item.id, c.id, start, item.rect.size, content);
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

  bool _itemsChanged(Object capsule, List<MorphBarItemLayout> items) {
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

  Offset _birthPoint(
    MorphBarCapsuleLayout born,
    List<MorphBarCapsuleLayout> layout,
  ) {
    MorphBarCapsuleLayout? nearest;
    var best = double.infinity;
    for (final c in layout) {
      if (c.id == born.id || _capsule(c.id) == null) continue;
      final d = (c.rect.center - born.rect.center).distance;
      if (d < best) {
        best = d;
        nearest = c;
      }
    }
    if (nearest == null) return born.rect.center;
    final x = nearest.rect.center.dx < born.rect.center.dx
        ? nearest.rect.right
        : nearest.rect.left;
    return Offset(x, born.rect.center.dy);
  }

  Offset _deathPoint(_Capsule leaving, Map<Object, Rect> oldTargets) {
    final here = leaving.target.center;
    Rect? nearest;
    var best = double.infinity;
    for (final entry in oldTargets.entries) {
      if (entry.key == leaving.id || _capsule(entry.key) == null) continue;
      final d = (entry.value.center - here).distance;
      if (d < best) {
        best = d;
        nearest = entry.value;
      }
    }
    if (nearest == null) return here;
    final x = nearest.center.dx < here.dx ? nearest.right : nearest.left;
    return Offset(x, nearest.center.dy);
  }

  void _snap(double t, List<MorphBarCapsuleLayout> layout) {
    _timeline.clear();
    _capsules.clear();
    _items.clear();
    for (final c in layout) {
      final capsule = _Capsule(c.id, c.rect, spec.frameSpring);
      capsule.target = c.rect;
      _capsules.add(capsule);
      for (final i in c.items) {
        _items.add(
          _Item(i.id, c.id, i.rect.center, i.rect.size, spec.contentSpring),
        );
      }
    }
  }

  /// The capsules at the current time, leaving ones included.
  List<MorphBarCapsuleFrame> get capsules => [
    for (final c in _capsules)
      MorphBarCapsuleFrame(c.id, _pulsed(c), leaving: c.leaving),
  ];

  Rect _pulsed(_Capsule c) {
    final base = _visible(c, _now);
    return Rect.fromCenter(
      center: base.center,
      width: math.max(
        0,
        base.width + (c.pulseW.value(_now) - 1) * c.target.width,
      ),
      height: math.max(
        0,
        base.height + (c.pulseH.value(_now) - 1) * c.target.height,
      ),
    );
  }

  /// The items at the current time, leaving ones included.
  List<MorphBarItemFrame> get items {
    final pulse = {
      for (final c in _capsules)
        if (!c.leaving) c.id: c.pulseH.value(_now),
    };
    return [
      for (final i in _items)
        () {
          final p = i.presence.value(_now);
          final s = lerpDouble(spec.appearScale, 1, p)!;
          return MorphBarItemFrame(
            i.id,
            center: Offset(i.cx.value(_now), i.cy.value(_now)),
            size: i.size,
            scale: math.max(0, s * (pulse[i.capsule] ?? 1)),
            presence: p.clamp(0.0, 1.0),
            blur: math.max(0, spec.appearBlur * (1 - p)),
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
