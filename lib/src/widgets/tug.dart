import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/foundation.dart';
import 'package:morph/src/widgets/chase_spring.dart';
import 'package:motor/motor.dart';

/// The full internal model of a pull, before it is packed for a
/// consumer: the tether and the growth separately (channel mode
/// corrects content by the growth), the axis deformations without
/// the press, and the press sink.
typedef _TugModel = ({
  Offset tether,
  Offset growth,
  double deformX,
  double deformY,
  double sink,
});

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
///   edge would teleport straight to full extension. At rest under a
///   motionless finger the tick snaps to the target once and stops
///   writing - a held button costs nothing per frame.
/// - Inside a dead zone ([dead], 0.24 of the side) nothing moves: a
///   press that is only a press cannot shiver, and breaking free gives
///   the pull a beginning.
/// - Past it the offset is `cap * tanh((d - dead) / cap)` along the
///   same vector, with [cap] only 0.16 of the side. Asymptotic - near
///   1:1 while small, never a wall. (Deliberately tanh and not the
///   package's [morphRubberband]: tanh saturates noticeably faster,
///   and this exact hand feel is the one that was tuned by eye.)
///   Travel and stretch trade against each other, and the balance here
///   leans hard toward shape: the surface is being stretched, not
///   relocated.
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
/// - Channel mode ([channel] set): the pull is written straight into a
///   [MorphPieceChannel], so the skin moves REAL mass geometry - a
///   [MorphPiece] inside a [MorphSkin]. The mass itself then carries
///   the tether: pull one piece toward another and the skin necks them
///   into one body, which no paint transform can do. The skin paints
///   the content with the full channel transform (one rigid body);
///   [Tug] corrects it from inside so the content rides the tether,
///   sinks with the press in full, and follows only [follow] of the
///   surface stretch - glass deforms what is printed on it, a little.
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
    this.channel,
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

  /// How much of the surface stretch the content rides in channel mode
  /// (the press sink always applies in full). Zero keeps the content
  /// rigid; one glues it to the glass.
  final double follow;

  /// Profile whose closeMotion plays the return; defaults to
  /// [MorphMotion.normal].
  final MorphMotion? motion;

  /// When set, [Tug] writes the pull into this channel and the skin
  /// moves the real mass geometry; the widget itself paints only the
  /// content correction. Fixed for the widget's lifetime: toggling it
  /// swaps the tree shape. The channel's value is not reset on
  /// unmount - the owner of the channel owns its value.
  final MorphPieceChannel? channel;

  @override
  State<Tug> createState() => _TugState();
}

class _TugState extends State<Tug> with TickerProviderStateMixin {
  late final MotionController<Offset> _xy = MotionController<Offset>(
    motion: (widget.motion ?? MorphMotion.normal).closeMotion,
    vsync: this,
    converter: MotionConverter.offset,
    initialValue: .zero,
  );
  late final SingleMotionController _press = SingleMotionController(
    motion: (widget.motion ?? MorphMotion.normal).closeMotion,
    vsync: this,
    initialValue: 1,
  );
  late final Listenable _frame = Listenable.merge(<Listenable>[_xy, _press]);

  Offset _homeCenter = .zero;
  Size _size = Size.zero;

  // The chase: pointer events move the target, the ticker integrates.
  late final Ticker _chase = createTicker(_chaseTick);
  final ChaseSpring _spring = ChaseSpring();
  Duration _chaseLast = .zero;

  double get _side => _size.shortestSide;
  double get _capPx => math.max(widget.cap * _side, 1);
  double get _deadPx => widget.dead * _side;

  @override
  void initState() {
    super.initState();
    _frame.addListener(_report);
  }

  @override
  void dispose() {
    _frame.removeListener(_report);
    _chase.dispose();
    _xy.dispose();
    _press.dispose();
    super.dispose();
  }

  _TugModel _model() {
    final Offset pull = _xy.value;
    // Vector clamp BEFORE the axis split: the chase spring overshoots
    // its own cap following a fast circle, and per-axis clamping would
    // square off the tether's circle.
    final Offset e0 = pull / _capPx;
    final double m = e0.distance;
    final Offset e = m > 1 ? e0 / m : e0;
    // The growth is an ABSOLUTE amount scaled by the shorter side (a
    // wide pill must not stretch further than a tall one). Half of
    // each axis's growth rides the offset, signed by the pull (e * |e|
    // keeps it continuous through zero): the trailing edge stays
    // planted and all visible growth reaches toward the finger.
    final double grow = _side * widget.stretch;
    return (
      tether: pull,
      growth: Offset(
        grow * e.dx * e.dx.abs() / 2,
        grow * e.dy * e.dy.abs() / 2,
      ),
      deformX: 1 + grow * e.dx * e.dx / math.max(_size.width, 1),
      deformY: 1 + grow * e.dy * e.dy / math.max(_size.height, 1),
      sink: _press.value,
    );
  }

  void _report() {
    final MorphPieceChannel? channel = widget.channel;
    if (channel == null) {
      return;
    }
    final _TugModel m = _model();
    channel.update(
      offset: m.tether + m.growth,
      scaleX: m.deformX * m.sink,
      scaleY: m.deformY * m.sink,
    );
  }

  void _down(DragDownDetails details) {
    _press.motion = MorphMotion.fast.openMotion;
    _press.animateTo(widget.press);
  }

  void _grab(DragStartDetails details) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    _size = box.size;
    // Home center: the box's current global center minus whatever pull
    // already applies. In paint mode the transform hangs BELOW this
    // box, so the box never moves; in channel mode the skin's paint
    // transform carries the pull (localToGlobal sees it) and it must
    // be subtracted.
    final Offset center = box.localToGlobal(box.size.center(.zero));
    final MorphPieceChannel? channel = widget.channel;
    _homeCenter = channel == null ? center : center - channel.offset;
    // Seed the chase from wherever the surface is, carrying a
    // mid-return spring's velocity into the grab.
    _spring.grab(_xy.value, velocity: _xy.velocity);
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
    _spring.target = len == 0 ? .zero : raw * (applied / len);
  }

  void _chaseTick(Duration elapsed) {
    // Ticker.elapsed restarts from zero on every start() - the clock
    // must reset at grab or the first dt goes negative.
    final double dt = math.min(
      (elapsed - _chaseLast).inMicroseconds / Duration.microsecondsPerSecond,
      1 / 30,
    );
    _chaseLast = elapsed;
    // The chase's own rest guard keeps a motionless finger free: once
    // it snaps onto the target, tick reports no change and the
    // controller is not written - in channel mode that is what stops
    // the skin from re-tracing epsilon motion at full frame rate.
    if (_spring.tick(dt)) {
      _xy.value = _spring.value;
    }
  }

  void _drop() {
    _restorePress();
    _chase.stop();
    // The chase's velocity carries into the return springs: a flick
    // lands with its momentum.
    _xy.motion = (widget.motion ?? MorphMotion.normal).closeMotion;
    _xy.animateTo(.zero, withVelocity: _spring.velocity);
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
    return GestureDetector(
      onPanDown: _down,
      onPanStart: _grab,
      onPanUpdate: _pull,
      onPanEnd: (DragEndDetails details) => _drop(),
      onPanCancel: _drop,
      child: ListenableBuilder(
        listenable: _frame,
        child: widget.child,
        builder: (BuildContext context, Widget? child) {
          final _TugModel m = _model();
          // Channel mode: the skin paints this subtree with the FULL
          // channel transform (mass and content as one rigid body), so
          // the raw stretch would deform the content 1:1 and the
          // growth would read as the glass growing both ways. Correct
          // from inside by desired/applied: the content rides the
          // tether alone while the mass reaches for the finger, the
          // press sinks it in full (sink cancels out of the ratio),
          // and [follow] of the stretch deforms it.
          if (widget.channel != null) {
            final double appliedX = m.deformX * m.sink;
            final double appliedY = m.deformY * m.sink;
            return Transform.translate(
              offset: Offset(-m.growth.dx / appliedX, -m.growth.dy / appliedY),
              child: Transform.scale(
                scaleX: (1 + widget.follow * (m.deformX - 1)) / m.deformX,
                scaleY: (1 + widget.follow * (m.deformY - 1)) / m.deformY,
                child: child,
              ),
            );
          }
          // Paint mode. The wrapper chain is structurally IDENTICAL
          // for every pull, including rest (all transforms degrade to
          // identity): swapping to a bare child at zero would remount
          // the subtree, and a MorphTag inside would lose its state
          // and desync from a live flight.
          final Offset offset = m.tether + m.growth;
          return Transform.translate(
            offset: offset,
            child: Transform.scale(
              scaleX: m.deformX * m.sink,
              scaleY: m.deformY * m.sink,
              child: Transform.rotate(
                angle:
                    widget.lean *
                    math.pi /
                    180 *
                    (offset.dx / _capPx).clamp(-1, 1),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
