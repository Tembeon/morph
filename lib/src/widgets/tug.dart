import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/foundation.dart';
import 'package:morph/src/widgets/chase_spring.dart';
import 'package:motor/motor.dart';

/// The full internal model of a pull, before it is packed for a
/// consumer: the tether, the axis deformations without the press, and
/// the press sink.
typedef _TugModel = ({
  Offset tether,
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
/// - The offset is `d / (1 + d / cap)` along the pull vector, with
///   [cap] (0.16 of the side) the asymptote it approaches but never
///   reaches. Hyperbolic rather than tanh: near 1:1 while small and
///   then endlessly soft, where tanh arrives at its wall and sits
///   there. Clamped as a VECTOR before any axis split - per-axis
///   clamping makes the area breathe on a circular sweep. [dead] still
///   exists but rests at 0: the press scale, not a dead zone, is what
///   keeps a press from shivering.
/// - The deformation locks to the SCREEN axes - no ellipse rotated
///   into the drag. Both axes first grow by their own share of the
///   pull (`1 + |stretch| / side`), and then a VOLUME CORRECTION pulls
///   the product back onto `1 + magnitude * volume`: the surface may
///   gain area as it is drawn out, but far less than growing both axes
///   would give it. The cross axis therefore thins while the pulled
///   one swells - mass being drawn out of a body, not a box being
///   scaled. The tether rides INSIDE the scale, which is what makes
///   the leading edge arrive before the trailing edge leaves. A small
///   [lean] rides inside it too.
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
    this.dead = 0,
    this.cap = 0.16,
    this.stretch = 0.5,
    this.volume = 0.5,
    this.lean = 0,
    this.press = 0.97,
    this.follow = 0.6,
    this.motion,
    this.channel,
    this.filterQuality,
  });

  /// The tuggable surface.
  final Widget child;

  /// Dead-zone radius as a ratio of the shorter side.
  final double dead;

  /// Tether cap as a ratio of the shorter side - the asymptote the
  /// travel approaches past the dead zone.
  final double cap;

  /// How much of the resisted pull the SHAPE reads, before the volume
  /// correction. Higher swells more for the same travel.
  final double stretch;

  /// How much total area the surface may gain at full pull, as a
  /// fraction of the pull magnitude. 0 holds the area constant (the
  /// pulled axis swells only as far as the cross axis thins); the
  /// default 0.5 lets it swell half as fast as it is drawn out.
  final double volume;

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

  /// Sampling for the content's scale in PAINT mode, or null to
  /// transform the canvas.
  ///
  /// Null (the default) keeps the child on
  /// [PaintingContext.pushTransform]: it is drawn straight at the final
  /// resolution, so text and icons stay vector-crisp at any swell. A
  /// non-null value moves the subtree onto an [ImageFilterLayer]
  /// instead - rasterized at its own size and then resampled - which is
  /// what a raster child being scaled DOWN wants, and what softens
  /// glyphs being scaled up. Channel mode has its own answer:
  /// [MorphSkin.contentFilterQuality], because there the skin owns the
  /// transform.
  final FilterQuality? filterQuality;

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
    // Vector clamp BEFORE the axis split: the chase spring overshoots
    // its own cap following a fast circle, and per-axis clamping would
    // square off the tether's circle.
    final Offset pull = _xy.value;
    final double len = pull.distance;
    final Offset clamped = len > _capPx ? pull * (_capPx / len) : pull;
    final Offset stretchPixels = clamped * widget.stretch;
    final (double deformX, double deformY) = _liquidScale(
      stretchPixels,
      _size,
      widget.volume,
    );
    return (
      tether: stretchPixels,
      deformX: deformX,
      deformY: deformY,
      sink: _press.value,
    );
  }

  /// Both axes grow by their own share of the pull, then a volume
  /// correction pulls the product onto a target that grows far slower -
  /// so the cross axis thins as the pulled one swells.
  static (double, double) _liquidScale(
    Offset stretchPixels,
    Size size,
    double volume,
  ) {
    if (size.isEmpty) {
      return (1, 1);
    }
    final double relX = stretchPixels.dx.abs() / size.width;
    final double relY = stretchPixels.dy.abs() / size.height;
    final double baseX = 1 + relX;
    final double baseY = 1 + relY;
    final double magnitude = math.sqrt(relX * relX + relY * relY);
    final double correction = math.sqrt(
      (1 + magnitude * volume) / (baseX * baseY),
    );
    return (baseX * correction, baseY * correction);
  }

  void _report() {
    final MorphPieceChannel? channel = widget.channel;
    if (channel == null) {
      return;
    }
    final _TugModel m = _model();
    final double scaleX = m.deformX * m.sink;
    final double scaleY = m.deformY * m.sink;
    // The content correction goes through the CHANNEL rather than a
    // Transform around the child. A widget transform here would be a
    // SECOND animated matrix under the skin's, and the skin can only
    // freeze its own: glyphs inside would keep re-snapping to a new
    // subpixel bucket every frame - letters visibly shuffling against
    // each other - no matter what the skin samples with.
    channel.update(
      offset: Offset(m.tether.dx * scaleX, m.tether.dy * scaleY),
      scaleX: scaleX,
      scaleY: scaleY,
      contentScaleX: (1 + widget.follow * (m.deformX - 1)) / m.deformX,
      contentScaleY: (1 + widget.follow * (m.deformY - 1)) / m.deformY,
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
    final double free = math.max(len - _deadPx, 0);
    final double applied = free / (1 + free / _capPx);
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
    // The chase's velocity carries into the return springs: a flick
    // lands with its momentum. Only THIS gesture's velocity though: a
    // drop without a grab (a cancelled tap) must not replay the
    // previous flick into a resting surface.
    final Offset carried = _chase.isActive ? _spring.velocity : Offset.zero;
    _chase.stop();
    _xy.motion = (widget.motion ?? MorphMotion.normal).closeMotion;
    _xy.animateTo(.zero, withVelocity: carried);
  }

  void _restorePress() {
    // The open motion is overshoot-free by contract: the release never
    // pops outward past resting size.
    _press.motion = MorphMotion.fast.openMotion;
    _press.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: _down,
      onPanStart: _grab,
      onPanUpdate: _pull,
      onPanEnd: (DragEndDetails details) => _drop(),
      onPanCancel: _drop,
      // Channel mode owns no widget of its own: the pull, the press and
      // the content correction are all written into the channel and
      // applied by the skin. Nothing rebuilds per frame, and the
      // content sits under exactly ONE animated matrix - the skin's,
      // which is the one that can be frozen for sampling.
      child: widget.channel != null
          ? widget.child
          : ListenableBuilder(
              listenable: _frame,
              child: widget.child,
              builder: (BuildContext context, Widget? child) {
                final _TugModel m = _model();
                // Paint mode. The wrapper chain is structurally
                // IDENTICAL for every pull, including rest (all
                // transforms degrade to identity): swapping to a bare
                // child at zero would remount the subtree, and a
                // MorphTag inside would lose its state and desync from
                // a live flight.
                return Transform.scale(
                  scaleX: m.deformX * m.sink,
                  scaleY: m.deformY * m.sink,
                  filterQuality: widget.filterQuality,
                  child: Transform.translate(
                    offset: m.tether,
                    child: Transform.rotate(
                      angle:
                          widget.lean *
                          math.pi /
                          180 *
                          (m.tether.dx / _capPx).clamp(-1, 1),
                      child: child,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
