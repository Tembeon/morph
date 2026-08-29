import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/foundation.dart';
import 'package:morph/src/widgets/chase_spring.dart';
import 'package:motor/motor.dart';

/// The full internal model of a pull: the tether travel and the final
/// axis scales (deformation, press and the vertical gate composed).
typedef _TugModel = ({Offset travel, double scaleX, double scaleY});

/// A glass surface under a finger - heavy from the first pixel, alive
/// forever.
///
/// The model is the iOS 26 liquid-glass button, all lengths normalized
/// by the surface's shorter side `M` so the gesture feels identical at
/// any size:
///
/// - The pull is measured from the surface's own CENTER, not from where
///   the finger landed - grabbing an edge and sliding inward is still a
///   pull, and re-grabbing a returning surface needs no bookkeeping.
///   The RAW pull follows the finger on a critically damped chase
///   spring, integrated frame by frame on the widget's own ticker:
///   pointer events only move the target. Retargeting a controller per
///   event starves the simulation - a high-frequency mouse restarts it
///   before it ever ticks and the surface freezes. At rest under a
///   motionless finger the tick snaps to the target once and stops
///   writing - a held button costs nothing per frame.
/// - TRAVEL is `capM * tanh(give * d / capM)` along the pull vector,
///   with `capM = cap * M`. The initial transmission is [give] - a few
///   percent of the finger's motion, so the surface reads as heavy -
///   and the asymptote is [cap] of the whole side, so it responds to
///   the 300th pixel of a drag as it did to the 30th: there is no wall.
/// - The SHAPE reads the raw pull at gain [stretch] plus the pull's own
///   velocity times [jiggle] - the pixels the silhouette has not caught
///   up with - saturated together on one shared ceiling. Both axes only
///   grow by their own share, and then a volume correction pulls the
///   product back onto `1 + magnitude * volume`: the cross axis thins
///   as the pulled one swells - mass being drawn out of a body, not a
///   box being scaled. Because the shape reads the RAW pull, it answers
///   far more than the position does: the finger pulls the flesh while
///   the body barely moves. The velocity term is the derivative of the
///   same spring, not a second driver - the readout is a pure function
///   of the one spring's (value, velocity), which stays continuous
///   through any interruption.
/// - The finger LIFTS glass: pointer-down grows each side of the
///   surface by [pressGrow] px on a spring with a little bounce
///   (negative sinks instead - an ink material's taste).
/// - Release hands the chase velocity to the return spring - a flick
///   lands with its momentum - and the shape follows the bouncing
///   return offset, so the landing wobbles for free. Grabbing
///   mid-return seeds the chase from the return's own velocity:
///   continuity in both directions.
/// - The gesture layer is a raw [Listener], not a detector: it never
///   enters the arena, so a selector or scrollable inside wins its
///   drag normally while the body reads the same finger in parallel;
///   a non-primary button does nothing.
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
///   into one body, which no paint transform can do. Content rides the
///   mass 1:1 - ink lies on the body and cannot slide; for glyph
///   crispness under the moving transform see
///   [MorphSkin.contentFilterQuality].
class Tug extends StatefulWidget {
  /// Creates a glass tether around [child].
  const Tug({
    super.key,
    required this.child,
    this.dead = 0,
    this.cap = 1,
    this.give = 0.05,
    this.stretch = 0.08,
    this.volume = 0.5,
    this.jiggle = 0.003,
    this.pressGrow = 4,
    this.vertical = 1,
    this.chaseStiffness = 900,
    this.motion,
    this.channel,
    this.filterQuality,
  });

  /// The tuggable surface.
  final Widget child;

  /// Dead-zone radius in px around home; the pull starts past it.
  /// Rests at 0: the press growth, not a dead zone, is what keeps a
  /// press from shivering.
  final double dead;

  /// Travel asymptote as a ratio of the shorter side. The default 1
  /// means the whole side - unreachable in practice, which is the
  /// point: the tether never visibly hits a wall.
  final double cap;

  /// Initial transmission of the tether: how much of the finger's first
  /// pixels the surface travels. The Apple feel is heavy - 0.05.
  ///
  /// Surfaces wider than 2:1 calm down on their own: the effective
  /// transmission scales by `min(1, 2 * shortSide / longSide)`, so an
  /// ordinary pill keeps the reference feel while a screen-wide bar
  /// answers the same finger with a whisper.
  final double give;

  /// Gain of the shape on the raw pull: how many px of silhouette
  /// stretch one px of finger travel buys before saturation.
  final double stretch;

  /// How much total area the surface may gain at full deformation, as a
  /// fraction of the deformation magnitude. 0 holds the area constant
  /// (the pulled axis swells only as far as the cross axis thins); the
  /// default 0.5 is glass - ink is less inflatable and wants less.
  final double volume;

  /// Lag of the silhouette behind the motion, in SECONDS: the pull's
  /// velocity times this many seconds is added to the shape input, so a
  /// fast return stretches along the motion and the landing wobble
  /// deforms the body. 0.002 whispers, 0.006 is loud.
  final double jiggle;

  /// Pointer-down growth in px, gained by EACH side (a wide bar lifts
  /// by the same few physical pixels as a small pill). Positive lifts
  /// (glass), negative sinks (ink), 0 disables the press response.
  final double pressGrow;

  /// Share of the vertical axis that responds, 0..1. At 0 the surface
  /// neither travels nor deforms vertically - its height is pinned -
  /// which is what a bar hugging a screen edge wants.
  final double vertical;

  /// Stiffness of the chase spring following the finger; higher chases
  /// tighter. The chase stays critically damped.
  final double chaseStiffness;

  /// Profile whose closeMotion plays the return; null uses the built-in
  /// glass return spring (~360 ms, half-bounce - the liquid-glass
  /// reference release).
  final MorphMotion? motion;

  /// When set, [Tug] writes the pull into this channel and the skin
  /// moves the real mass geometry; the widget itself paints nothing.
  /// Fixed for the widget's lifetime: toggling it swaps the tree shape.
  /// The channel's value is not reset on unmount - the owner of the
  /// channel owns its value.
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
  /// The liquid-glass reference spring (stiffness ~300, damping ratio
  /// 0.5): the press and the built-in return both ride it. This is the
  /// BUTTON-scale member of the glass family - [MorphMotion.glass]
  /// carries the flight-scale calibration of the same character (the
  /// 0.5 ratio's ~16% undershoot is a few px here and was slapstick
  /// over a flight's hundreds).
  static const Motion _glassSpring = CupertinoMotion(
    duration: Duration(milliseconds: 363),
    bounce: 0.5,
  );

  /// Ceiling of the shape input as a ratio of the shorter side - one
  /// shared saturation for the pull and the velocity lag.
  static const double _shapeCeiling = 0.35;

  late final MotionController<Offset> _xy = MotionController<Offset>(
    motion: _returnMotion,
    vsync: this,
    converter: MotionConverter.offset,
    initialValue: .zero,
  );
  late final SingleMotionController _press = SingleMotionController(
    motion: _glassSpring,
    vsync: this,
    initialValue: 0,
  );
  late final Listenable _frame = Listenable.merge(<Listenable>[_xy, _press]);

  Offset _homeCenter = .zero;
  Size _size = Size.zero;
  int? _pointer;

  // The chase: pointer events move the target, the ticker integrates.
  late final Ticker _chase = createTicker(_chaseTick);
  late final ChaseSpring _spring = ChaseSpring(
    stiffness: widget.chaseStiffness,
  );
  Duration _chaseLast = .zero;

  Motion get _returnMotion => widget.motion?.closeMotion ?? _glassSpring;

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
    if (_size.isEmpty) {
      return (travel: .zero, scaleX: 1, scaleY: 1);
    }
    final double m = _size.shortestSide;
    final Offset pull = _xy.value;
    final Offset velocity = _chase.isActive ? _spring.velocity : _xy.velocity;

    // Travel: tiny transmission, asymptote a whole side away. Vector
    // form - a per-axis tanh squares off a circular sweep. Beyond a
    // 2:1 aspect the transmission fades with the aspect: chrome-wide
    // bodies read as heavier, which is what their mass says.
    final double capPx = math.max(widget.cap * m, 1);
    final double give = widget.give * math.min(1, 2 * m / _size.longestSide);
    final double len = pull.distance;
    final Offset travel = len == 0
        ? .zero
        : pull * (capPx * _tanh(give * len / capPx) / len);

    // Shape: the raw pull at [stretch] gain plus the velocity lag,
    // saturated together - the ceiling is one per body, whatever
    // deforms it.
    Offset shape = pull * widget.stretch + velocity * widget.jiggle;
    final double ceiling = _shapeCeiling * m;
    final double shapeLen = shape.distance;
    if (shapeLen > 0) {
      shape = shape * (ceiling * _tanh(shapeLen / ceiling) / shapeLen);
    }
    final (double deformX, double deformY) = _liquidScale(
      shape,
      _size,
      widget.volume,
    );

    // Press: absolute growth PER AXIS - each side gains [pressGrow] px,
    // so a wide bar lifts by the same few physical pixels as a small
    // pill instead of scaling its whole width (the reference presses
    // wide chrome by absolute pixels too).
    final double p = _press.value * widget.pressGrow;
    final double scaleX = deformX * (1 + p / _size.width);
    final double scaleY = deformY * (1 + p / _size.height);
    return (
      travel: travel,
      scaleX: scaleX,
      // The vertical gate closes over EVERYTHING that would change the
      // height - deformation, volume thinning and press alike - so a
      // bar with vertical: 0 is truly height-pinned.
      scaleY: 1 + (scaleY - 1) * widget.vertical,
    );
  }

  /// Both axes grow by their own share of the deformation, then a
  /// volume correction pulls the product onto a target that grows far
  /// slower - so the cross axis thins as the pulled one swells.
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
    // The travel rides INSIDE the scale, which is what makes the
    // leading edge arrive before the trailing edge leaves.
    channel.update(
      offset: Offset(m.travel.dx * m.scaleX, m.travel.dy * m.scaleY),
      scaleX: m.scaleX,
      scaleY: m.scaleY,
    );
  }

  void _grab(PointerDownEvent event) {
    // The pull and the press belong to the primary button only: a
    // right click on desktop opens a menu, the body has nothing to
    // answer.
    if (_pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    _press.animateTo(1);

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

  void _pull(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final Offset full = event.position - _homeCenter;
    // The vertical gate applies at the INPUT, so a killed axis also
    // shrinks the effective pull length instead of leaking into the
    // shape through the magnitude.
    final Offset raw = Offset(full.dx, full.dy * widget.vertical);
    final double len = raw.distance;
    final double free = math.max(len - widget.dead, 0);
    // The chase target is the RAW pull; all resistance lives in the
    // readout, so the shape can answer the finger while the body
    // stands nearly still.
    _spring.target = len == 0 ? .zero : raw * (free / len);
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

  void _drop(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _press.animateTo(0);
    // The chase's velocity carries into the return spring: a flick
    // lands with its momentum. Only THIS gesture's velocity though: a
    // drop without a grab (a cancelled tap) must not replay the
    // previous flick into a resting surface.
    final Offset carried = _chase.isActive ? _spring.velocity : Offset.zero;
    _chase.stop();
    _xy.motion = _returnMotion;
    _xy.animateTo(.zero, withVelocity: carried);
  }

  static double _tanh(double x) {
    // exp overflows to infinity near x = 355 and the ratio becomes
    // NaN - a NaN offset would poison the channel and the skin tracer.
    // tanh is 1.0 to machine precision long before that.
    if (x > 20) {
      return 1;
    }
    final double e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _grab,
      onPointerMove: _pull,
      onPointerUp: _drop,
      onPointerCancel: _drop,
      // Channel mode owns no widget of its own: the pull and the press
      // are written into the channel and applied by the skin. Nothing
      // rebuilds per frame, and the content sits under exactly ONE
      // animated matrix - the skin's, which is the one that can be
      // frozen for sampling.
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
                  scaleX: m.scaleX,
                  scaleY: m.scaleY,
                  filterQuality: widget.filterQuality,
                  child: Transform.translate(offset: m.travel, child: child),
                );
              },
            ),
    );
  }
}
