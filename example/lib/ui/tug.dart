import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/morph.dart';
import 'package:motor/motor.dart';

/// The pull a [Tug] reports in data mode: the tether offset plus the
/// glass deformation, ready to apply to real geometry such as a
/// [MorphPiece] rect.
typedef TugPull = ({Offset offset, double scaleX, double scaleY});

/// A glass surface on a short tether - a weight on a rubber leash, not
/// a soap bubble.
///
/// The model, all lengths as ratios of the surface's shorter side so
/// the gesture feels identical at any size:
///
/// - The pull is measured from the surface's own CENTER, not from
///   where the finger landed - grabbing an edge and sliding inward is
///   still a pull, and re-grabbing a returning surface needs no
///   bookkeeping. The offset FOLLOWS the finger on a critically damped
///   chase spring, integrated frame by frame on the widget's own
///   ticker (the comet pattern): pointer events only move the TARGET.
///   Retargeting a controller per event starves the simulation - a
///   high-frequency mouse restarts it before it ever ticks and the
///   surface freezes; and without any follow spring a grab near the
///   edge would teleport straight to full extension.
/// - Inside a dead zone ([dead], 0.24 of the side) nothing moves: a
///   press that is only a press cannot shiver, and breaking free gives
///   the pull a beginning.
/// - Past it the offset is `cap * tanh((d - dead) / cap)` along the
///   same vector, with [cap] only 0.16 of the side. Asymptotic - near
///   1:1 while small, never a wall. Travel and stretch trade against
///   each other, and the balance here leans hard toward shape: the
///   surface is being stretched, not relocated.
/// - The deformation locks to the SCREEN axes - no ellipse rotated
///   into the drag. Each axis grows on its own displacement, squared
///   (`1 + stretch * e^2`), and neither axis ever squashes: the
///   surface moves as a whole and stretches a little, it does not get
///   pressed into a lens. The growth extends TOWARD the pull: the
///   reported offset carries half of each axis's growth (continuous -
///   `e * |e|`, no sign flip at zero), so the trailing edge stays
///   planted while the leading edge reaches for the finger. The offset
///   is clamped as a VECTOR before it splits into axes - per-axis
///   clamping makes the area breathe on a circular sweep. A small
///   [lean] rides inside the scale.
/// - The finger COMPRESSES glass: pointer-down sinks the surface to
///   [press] on an overshoot-free spring (popping back out past rest
///   is the single most bubble-like thing a button can do).
/// - Release hands the chase velocity to the return springs, so a
///   flick lands with its momentum. Grabbing mid-return seeds the
///   chase from the return's own velocity - continuity in both
///   directions.
///
/// Two ways to consume it:
///
/// - Default: the pull paints as a render transform above [child]. A
///   [MorphTag] inside rides along, so a flight launches from wherever
///   the surface stands.
/// - Data mode ([onPull] set): nothing paints; the pull is reported so
///   the owner moves REAL geometry - a [MorphPiece] rect inside a
///   [MorphSkin]. The mass itself then carries the tether: pull one
///   piece toward another and the skin necks them into one body,
///   which no paint transform can do. The content inside rides the
///   rigid body, sinks with the press in full, and follows [follow] of
///   the surface stretch - glass deforms what is printed on it, a
///   little.
class Tug extends StatefulWidget {
  /// Creates a glass tether around [child].
  const Tug({
    super.key,
    required this.child,
    this.dead = 0.24,
    this.cap = 0.16,
    this.stretch = 0.14,
    this.lean = 3,
    this.press = 0.97,
    this.follow = 0.6,
    this.motion,
    this.onPull,
  });

  /// The tuggable surface.
  final Widget child;

  /// Dead-zone radius as a ratio of the shorter side.
  final double dead;

  /// Tether cap as a ratio of the shorter side - the asymptote the
  /// travel approaches past the dead zone.
  final double cap;

  /// Growth at a full pull as a ratio of the SHORTER side, eased in
  /// quadratically. Both axes gain the same absolute amount, so a wide
  /// pill stretches no further than a tall one. A sideways pull widens
  /// only; a diagonal grows both by half.
  final double stretch;

  /// Peak lean in degrees, signed by the horizontal pull.
  final double lean;

  /// Scale while the pointer is down: glass compresses, never pops.
  final double press;

  /// How much of the surface stretch the content rides in data mode
  /// (the press sink always applies in full). Zero keeps the content
  /// rigid; one glues it to the glass.
  final double follow;

  /// Profile whose closeMotion plays the return; defaults to
  /// [MorphMotion.normal].
  final MorphMotion? motion;

  /// When set, [Tug] paints nothing and reports the pull instead -
  /// for owners that move real geometry (a [MorphPiece] rect). Fixed
  /// for the widget's lifetime: toggling it swaps the tree shape.
  final ValueChanged<TugPull>? onPull;

  @override
  State<Tug> createState() => _TugState();
}

class _TugState extends State<Tug> with TickerProviderStateMixin {
  late final SingleMotionController _x = _spring(0);
  late final SingleMotionController _y = _spring(0);
  late final SingleMotionController _press = _spring(1);
  late final Listenable _frame = Listenable.merge(<Listenable>[_x, _y, _press]);

  Offset _homeCenter = .zero;
  Size _size = Size.zero;
  double _side = 0;
  double _capPx = 1;
  double _deadPx = 0;

  // The chase: pointer events move the target, the ticker integrates.
  late final Ticker _chase = createTicker(_chaseTick);
  Duration _chaseLast = .zero;
  Offset _target = .zero;
  Offset _chaseVelocity = .zero;
  static const double _chaseStiffness = 900;

  SingleMotionController _spring(double initial) => SingleMotionController(
    motion: (widget.motion ?? MorphMotion.normal).closeMotion,
    vsync: this,
    initialValue: initial,
  );

  @override
  void initState() {
    super.initState();
    _frame.addListener(_report);
  }

  @override
  void dispose() {
    _frame.removeListener(_report);
    _chase.dispose();
    _x.dispose();
    _y.dispose();
    _press.dispose();
    super.dispose();
  }

  ({Offset tether, Offset growth, double deformX, double deformY, double sink})
  _model() {
    final Offset pull = Offset(_x.value, _y.value);
    // Vector clamp BEFORE the axis split: the return spring overshoots
    // its own cap chasing a moving target, and per-axis clamping would
    // square off the tether's circle.
    final Offset e0 = pull / _capPx;
    final double m = e0.distance;
    final Offset e = m > 1 ? e0 / m : e0;
    final double sink = _press.value;
    // The growth is an ABSOLUTE amount scaled by the shorter side (a
    // wide pill must not stretch further than a tall one). Half of
    // each axis's growth rides the offset, signed by the pull (e * |e|
    // keeps it continuous through zero): the trailing edge stays
    // planted and all visible growth reaches toward the finger.
    final double grow = _side * widget.stretch;
    final Offset growth = Offset(
      grow * e.dx * e.dx.abs() / 2,
      grow * e.dy * e.dy.abs() / 2,
    );
    return (
      tether: pull,
      growth: growth,
      deformX: 1 + grow * e.dx * e.dx / math.max(_size.width, 1),
      deformY: 1 + grow * e.dy * e.dy / math.max(_size.height, 1),
      sink: sink,
    );
  }

  TugPull _compute() {
    final ({
      Offset tether,
      Offset growth,
      double deformX,
      double deformY,
      double sink,
    })
    m = _model();
    return (
      offset: m.tether + m.growth,
      scaleX: m.deformX * m.sink,
      scaleY: m.deformY * m.sink,
    );
  }

  void _report() {
    widget.onPull?.call(_compute());
  }

  void _down(DragDownDetails details) {
    _press.motion = MorphMotion.fast.openMotion;
    _press.animateTo(widget.press);
  }

  void _grab(DragStartDetails details) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    _size = box.size;
    _side = math.min(box.size.width, box.size.height);
    _capPx = math.max(widget.cap * _side, 1);
    _deadPx = widget.dead * _side;
    // Home center: the box's current global center minus whatever pull
    // already applies. In paint mode the transform hangs BELOW this
    // box, so the box never moves; in data mode the geometry carries
    // the pull and must be subtracted.
    final Offset center = box.localToGlobal(box.size.center(.zero));
    _homeCenter = widget.onPull == null ? center : center - _compute().offset;
    // Seed the chase from wherever the surface is, carrying a
    // mid-return spring's velocity into the grab.
    _target = Offset(_x.value, _y.value);
    _chaseVelocity = Offset(_x.velocity, _y.velocity);
    _chaseLast = .zero;
    if (!_chase.isActive) {
      _chase.start();
    }
  }

  void _pull(DragUpdateDetails details) {
    final Offset raw = details.globalPosition - _homeCenter;
    final double len = raw.distance;
    final double applied = len <= _deadPx
        ? 0
        : _capPx * _tanh((len - _deadPx) / _capPx);
    _target = len == 0 ? .zero : raw * (applied / len);
  }

  void _chaseTick(Duration elapsed) {
    // Ticker.elapsed restarts from zero on every start() - the clock
    // must reset at grab or the first dt goes negative.
    final double dt = math.min(
      (elapsed - _chaseLast).inMicroseconds / Duration.microsecondsPerSecond,
      1 / 30,
    );
    _chaseLast = elapsed;
    if (dt <= 0) {
      return;
    }
    // Critically damped (damping = 2*sqrt(k)): tight under the finger,
    // no oscillation of its own - character belongs to the return.
    final double damping = 2 * math.sqrt(_chaseStiffness);
    final Offset pos = Offset(_x.value, _y.value);
    final Offset delta = _target - pos;
    _chaseVelocity += (delta * _chaseStiffness - _chaseVelocity * damping) * dt;
    final Offset next = pos + _chaseVelocity * dt;
    _x.value = next.dx;
    _y.value = next.dy;
  }

  void _release(DragEndDetails details) {
    _restorePress();
    _home();
  }

  void _drop() {
    _restorePress();
    _home();
  }

  void _home() {
    if (_chase.isActive) {
      _chase.stop();
    }
    // The chase's velocity carries into the return springs: a flick
    // lands with its momentum.
    final Motion close = (widget.motion ?? MorphMotion.normal).closeMotion;
    _x.motion = close;
    _y.motion = close;
    _x.animateTo(0, withVelocity: _chaseVelocity.dx);
    _y.animateTo(0, withVelocity: _chaseVelocity.dy);
    _chaseVelocity = .zero;
  }

  void _restorePress() {
    // The open motion is overshoot-free by contract: the release never
    // pops outward past resting size.
    _press.motion = MorphMotion.fast.openMotion;
    _press.animateTo(1);
  }

  static double _tanh(double x) {
    final double e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = widget.onPull != null
        // Data mode: the owner grows the real geometry, and the child
        // box grows with it - so the content inside would re-center
        // and read as the glass growing BOTH ways. Compensate: the
        // content rides the rigid body (tether only) while the mass
        // alone reaches for the finger; the press sinks it in full and
        // [follow] of the stretch deforms it.
        ? ListenableBuilder(
            listenable: _frame,
            child: widget.child,
            builder: (BuildContext context, Widget? child) {
              final ({
                Offset tether,
                Offset growth,
                double deformX,
                double deformY,
                double sink,
              })
              m = _model();
              return Transform.translate(
                offset: -m.growth,
                child: Transform.scale(
                  scaleX: m.sink * (1 + widget.follow * (m.deformX - 1)),
                  scaleY: m.sink * (1 + widget.follow * (m.deformY - 1)),
                  child: child,
                ),
              );
            },
          )
        : ListenableBuilder(
            listenable: _frame,
            child: widget.child,
            builder: (BuildContext context, Widget? child) {
              // The wrapper chain is structurally IDENTICAL for every
              // pull, including rest (all transforms degrade to
              // identity): swapping to a bare child at zero would
              // remount the subtree, and a MorphTag inside would lose
              // its state and desync from a live flight.
              final TugPull p = _compute();
              return Transform.translate(
                offset: p.offset,
                child: Transform.scale(
                  scaleX: p.scaleX,
                  scaleY: p.scaleY,
                  child: Transform.rotate(
                    angle:
                        widget.lean *
                        math.pi /
                        180 *
                        (_capPx == 1 ? 0 : (p.offset.dx / _capPx).clamp(-1, 1)),
                    child: child,
                  ),
                ),
              );
            },
          );
    return GestureDetector(
      onPanDown: _down,
      onPanStart: _grab,
      onPanUpdate: _pull,
      onPanEnd: _release,
      onPanCancel: _drop,
      child: body,
    );
  }
}
