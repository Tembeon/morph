import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/src/widgets/menu_morph_spec.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// The tuning of a glass button's menu, as measured on iOS 27.
///
/// The springs, delays and metrics are fitted to frame-by-frame
/// recordings of a `UIButton` with a glass configuration whose menu is its
/// primary action. Lengths are logical pixels, times seconds.
class MorphMenuTuning {
  /// Creates a tuning from explicit values.
  const MorphMenuTuning({
    this.morph = MorphMenuMorphSpec.standard,
    this.menuWidth = 250,
    this.rowHeight = 42,
    this.verticalPadding = 10,
    this.cornerRadius = 32,
    this.openingRadius = 195.4,
    this.radiusDelay = 0.098,
    this.sourceEndScale = 0.25,
    this.sourceTravel = 0.25,
    this.crossfadeBlur = 4,
    this.fadeLead = 0.015,
    this.lookFadeStart = 0.07,
    this.lookFadeEnd = 0.42,
    this.lookStretch = 2.5,
    this.contentFadeStart = 0,
    this.contentFadeEnd = 1,
    this.contentCloseFadeEnd = 0.53,
    this.contentKickScale = 1.45,
    this.contentBlur = 8,
    this.contentKickBlur = 6,
    this.tapOpenDelay = 0.05,
    this.holdDuration = 0.22,
    this.dismissDelay = 0.04,
    this.earlyCloseDelay = 0.016,
    this.actionDelay = 0.016,
    this.pressDelay = 0.015,
    this.sourceRelax = 0.05,
    this.openKickSpring = const MorphSpring(0.2048, 0.651),
    this.openKickGain = 4.229,
    this.closeKickSpring = const MorphSpring(0.3396, 0.8425),
    this.closeKickImpulse = 1450,
    this.closeKickDelay = 0.012,
    this.closeKickReach = 31.7,
    this.sourceKickSpring = const MorphSpring(0.3102, 0.6335),
    this.sourceKickGain = 2.02,
    this.edgeMargin = 8,
    this.glowDiameter = 160,
    this.glowOpacity = 0.5,
    this.glowFade = 0.07,
    this.highlightInset = 10,
    this.flexGain = 0.033,
    this.flexLimit = 2,
    this.flexSpring = const MorphSpring(0.15, 0.5),
    this.fusionRadius = 20,
    this.fusionCloseAmplitude = 20.95,
    this.fusionOpenRise = 0.0161,
    this.fusionCloseRise = 0.0213,
    this.fusionOpenHold = 0.199,
    this.fusionCloseHold = 0.057,
    this.fusionSpring = const MorphSpring(0.4286, 1),
    this.fusionCutoff = 0.2,
  });

  /// The morph tuning the menu's open and close springs come from.
  final MorphMenuMorphSpec morph;

  /// The spring that opens the menu: the morph's eject spring at its
  /// speed.
  MorphSpring get openSpring => morph.atSpeed(morph.eject);

  /// The spring that closes the menu: the morph's absorb spring at its
  /// speed.
  MorphSpring get closeSpring => morph.atSpeed(morph.absorb);

  /// The width of the open menu.
  final double menuWidth;

  /// The height of one row.
  final double rowHeight;

  /// The padding above the first and below the last row.
  final double verticalPadding;

  /// The corner radius of the open menu.
  final double cornerRadius;

  /// The corner radius the opening shape starts from before it eases to
  /// [cornerRadius]; the shape stays a capsule while it is smaller than
  /// this.
  final double openingRadius;

  /// Seconds the corner radius lags behind the opening.
  final double radiusDelay;

  /// The scale the button shrinks to inside the open menu.
  final double sourceEndScale;

  /// How far the shrinking button travels toward the menu center, as a
  /// fraction of the distance.
  final double sourceTravel;

  /// The blur radius of the button's look per unit of progress.
  final double crossfadeBlur;

  /// Seconds ahead at which the fades of the button's look and of the
  /// content read the progress spring.
  ///
  /// The fades lead the shapes by this much, so they run a little ahead of
  /// the geometry in both directions: the look leaves and the content
  /// arrives early while the menu opens, and the content leaves and the
  /// look returns early while it closes.
  final double fadeLead;

  /// The progress up to which the button's look stays fully opaque.
  final double lookFadeStart;

  /// The progress at which the button's look has faded out.
  ///
  /// The look leaves early: it is gone while the menu shape is still
  /// small, and it comes back only once the closing shape is nearly the
  /// button again.
  final double lookFadeEnd;

  /// How much wider the button's look grows per unit of progress, on top
  /// of the button shape's scale; its height follows the shape alone.
  final double lookStretch;

  /// The progress at which the menu content starts to appear.
  ///
  /// The content is in the drop from the start: its opacity follows the
  /// progress, so it is half there when the drop is half grown.
  final double contentFadeStart;

  /// The progress at which the menu content is fully opaque.
  final double contentFadeEnd;

  /// The progress at which the content of a closing menu has faded out.
  ///
  /// The content leaves faster than it came: a close fades it linearly
  /// from the opacity it had to nothing at this progress, so it is gone
  /// while the shape is still more than half grown. A re-open fades it
  /// back in from where it was to full at [contentFadeEnd].
  final double contentCloseFadeEnd;

  /// How much the content swells past the menu shape's scale with the
  /// shape's kick, per unit of kick relative to the menu height.
  ///
  /// The content rides the menu shape: it is scaled with it, plus this
  /// swell, so it unfolds out of the drop instead of being revealed at
  /// its final size.
  final double contentKickScale;

  /// The blur radius of the content, in logical pixels on screen, at
  /// progress 0; it falls linearly to nothing at progress 1.
  final double contentBlur;

  /// The extra blur radius of the content per unit of the menu shape's
  /// kick relative to the menu height.
  final double contentKickBlur;

  /// Seconds between the release of a tap and the start of the opening.
  final double tapOpenDelay;

  /// Seconds a held finger needs to open the menu without a release.
  final double holdDuration;

  /// Seconds between a release that dismisses and the start of the
  /// closing.
  final double dismissDelay;

  /// Seconds between the opening and the start of the closing when the
  /// touch that closes the menu was released before the menu appeared.
  ///
  /// Measured on the device for releases from 0 to 100 ms after the tap
  /// that opened the menu: the close starts 16 ms after the opening
  /// whenever the release came, so the menu always reaches about 0.17 of
  /// its progress.
  final double earlyCloseDelay;

  /// Seconds between the release on a row and its action.
  final double actionDelay;

  /// Seconds between a touch and the start of the button's press growth.
  final double pressDelay;

  /// The time constant, in seconds, over which the closing button lets go
  /// of the scale it had when the menu opened.
  final double sourceRelax;

  /// The spring of the menu shape's kick while the menu opens.
  ///
  /// The kick is a second degree of freedom driven by the progress
  /// spring: while opening, it chases [openKickGain] times the velocity
  /// of the opening spring on this spring.
  final MorphSpring openKickSpring;

  /// The gain of the opening kick, in pixels per unit of progress
  /// velocity, for a menu 146 pixels tall; other heights scale it by
  /// [MorphMenuMotion.kickAmplitude].
  final double openKickGain;

  /// The spring the menu shape's closing kick rings on.
  final MorphSpring closeKickSpring;

  /// The velocity, in pixels per second, a close strikes the menu
  /// shape's kick with, for a menu 146 pixels tall; other heights scale
  /// it by their measured closing amplitude.
  ///
  /// The close kicks the menu shape away from the button, the same way
  /// the opening does; the kick it still carries from the opening rings
  /// out on [closeKickSpring] together with the strike.
  final double closeKickImpulse;

  /// Seconds between the start of a close and its strike on the menu
  /// shape.
  final double closeKickDelay;

  /// The kick, in pixels for a menu 146 pixels tall, past which a close
  /// no longer strikes: the strike shrinks linearly with the kick the
  /// menu shape still carries, so a close during the opening only tops
  /// it up.
  final double closeKickReach;

  /// The spring of the button shape's kick.
  final MorphSpring sourceKickSpring;

  /// The gain of the button shape's kick while the menu closes, in
  /// pixels per unit of progress velocity, for a menu 146 pixels tall
  /// (other heights scale it by their measured amplitude);
  /// the closing progress runs backward, so the button shape is kicked
  /// toward the button's side. The button shape has no kick while the
  /// menu opens.
  final double sourceKickGain;

  /// The smallest gap a centered menu keeps from the safe area's sides;
  /// a menu that would come closer aligns with the button's edge instead.
  final double edgeMargin;

  /// The diameter of the glow under a finger on the menu.
  final double glowDiameter;

  /// The opacity of the glow under a finger on the menu.
  final double glowOpacity;

  /// Seconds the glow takes to appear and to fade.
  final double glowFade;

  /// The horizontal inset of the highlight pill from the menu's sides.
  final double highlightInset;

  /// How far the menu leans toward a finger on it, per pixel of distance
  /// from its center.
  final double flexGain;

  /// The largest lean toward a finger, in pixels per axis.
  final double flexLimit;

  /// The spring of the lean toward a finger.
  final MorphSpring flexSpring;

  /// The largest fusion radius: the standard deviation, in pixels, of
  /// the Gaussian that blurs the distance field of the two shapes.
  ///
  /// Read from the morph container's `gaussianRadius` on the device
  /// (iOS 27.0.1, iPhone 16 Pro): the container is one SDF layer with
  /// smoothness 0, so the shapes are joined only by this blur, which
  /// rises to 20 at every open and close and falls back to 0. A blur of
  /// this standard deviation reproduces the filmed silhouettes, neck
  /// included, of a ten-row menu closing into a bottom button (fit 0.9
  /// to 1.2 times the logged radius; 1.1 pt rms in row width).
  final double fusionRadius;

  /// The amplitude of the closing fusion envelope, in pixels; the
  /// envelope peaks at 19.7 because its fall starts before its rise
  /// ends. Fitted to the logged `gaussianRadius` of two closes (0.13 pt
  /// rms).
  final double fusionCloseAmplitude;

  /// The time constant, in seconds, of the fusion's rise when the menu
  /// opens. Fitted to two logged opens (0.4 pt rms, the fit's spread
  /// 0.016 to 0.017).
  final double fusionOpenRise;

  /// The time constant, in seconds, of the fusion's rise when the menu
  /// closes. Fitted to two logged closes.
  final double fusionCloseRise;

  /// Seconds after an open at which the fusion starts to fall.
  final double fusionOpenHold;

  /// Seconds after a close at which the fusion starts to fall.
  final double fusionCloseHold;

  /// The spring the fusion falls on, critically damped: fitted free to
  /// 0.424 to 0.433 s in both directions, the `liquidMorph` blur-in
  /// spring 0.3 at its speed of 0.7.
  final MorphSpring fusionSpring;

  /// The fusion radius under which the container drops its blur: the
  /// device's logged radius jumps from 0.18 to 0.
  final double fusionCutoff;

  /// The fusion envelope [t] seconds after an open, or a close when
  /// [opening] is false, before it is limited to [fusionRadius].
  ///
  /// It rises as `1 - exp(-t / rise)` and, after the hold, falls as a
  /// critically damped spring released from rest.
  double fusionEnvelope(double t, {required bool opening}) {
    if (t <= 0) return 0;
    final rise = opening ? fusionOpenRise : fusionCloseRise;
    final hold = opening ? fusionOpenHold : fusionCloseHold;
    final amplitude = opening ? fusionRadius : fusionCloseAmplitude;
    final fall = math.max(t - hold, 0.0);
    final w = 2 * math.pi / fusionSpring.response;
    return amplitude *
        (1 - math.exp(-t / rise)) *
        (1 + w * fall) *
        math.exp(-w * fall);
  }

  /// Whether the fusion envelope started [t] seconds ago has fallen
  /// under [fusionCutoff] for good.
  bool fusionEnded(double t, {required bool opening}) =>
      t > (opening ? fusionOpenHold : fusionCloseHold) &&
      fusionEnvelope(t, opening: opening) < fusionCutoff;

  /// The height of a menu with [rows] rows.
  double menuHeight(int rows) => 2 * verticalPadding + rowHeight * rows;

  /// The measured iOS 27 menu.
  static const standard = MorphMenuTuning();
}

/// One of the two shapes a menu morph is drawn from.
///
/// [rect] is the visible frame, already scaled; [localSize] is the frame
/// before the uniform [scale], which is the size content is laid out in.
class MorphMenuBlob {
  /// Creates a blob.
  const MorphMenuBlob({
    required this.rect,
    required this.radius,
    required this.scale,
    required this.localSize,
  });

  /// The visible frame.
  final Rect rect;

  /// The visible corner radius.
  final double radius;

  /// The uniform scale from [localSize] to [rect].
  final double scale;

  /// The frame before scaling.
  final Size localSize;

  /// The visible shape as a rounded rectangle.
  RRect get rrect => RRect.fromRectAndRadius(rect, Radius.circular(radius));
}

/// The progress of a menu morph: 0 is the button, 1 the menu.
///
/// [MorphMenuMotion] reads it and asks it to open and to close; it never
/// integrates the progress itself. [MorphMenuProgress.spring] is the
/// measured spring evaluated at explicit times, which makes the motion a
/// pure function of time; a widget wraps it to send the engine flight
/// that carries the menu the same way.
abstract class MorphMenuProgress {
  /// Creates a progress.
  MorphMenuProgress();

  /// The measured progress spring of [tuning], evaluated in closed form:
  /// it opens on [MorphMenuTuning.openSpring] and closes on
  /// [MorphMenuTuning.closeSpring], and a reversal carries the velocity.
  factory MorphMenuProgress.spring(MorphMenuTuning tuning) = _SpringProgress;

  /// The progress at time [t].
  double valueAt(double t);

  /// Whether the progress rests at its target at time [t].
  bool isAtRestAt(double t);

  /// Sends the progress toward 1 from time [t].
  void open(double t);

  /// Sends the progress toward 0 from time [t].
  void close(double t);
}

class _SpringProgress extends MorphMenuProgress {
  _SpringProgress(this.tuning)
    : _spring = MorphSpringState(tuning.openSpring, 0);

  final MorphMenuTuning tuning;
  final MorphSpringState _spring;

  @override
  double valueAt(double t) => _spring.value(t);

  @override
  bool isAtRestAt(double t) =>
      _spring.isAtRest(t, _spring.target == 0 ? 1e-3 : 1e-4);

  @override
  void open(double t) => _spring.retarget(t, 1, spring: tuning.openSpring);

  @override
  void close(double t) => _spring.retarget(t, 0, spring: tuning.closeSpring);
}

enum _Phase { idle, opening, closing }

class _Pointer {
  _Pointer({
    required this.fromButton,
    required this.position,
    required this.startedInMenu,
  });

  final bool fromButton;
  final bool startedInMenu;
  Offset position;
  bool openedByHold = false;
}

/// A damped spring driven by an input, integrated from samples.
class _DrivenKick {
  double value = 0;
  double velocity = 0;

  bool get isAtRest => value.abs() < 0.01 && velocity.abs() < 0.1;

  void reset() {
    value = 0;
    velocity = 0;
  }

  /// Integrates from time [from] to [to] on [spring], chasing [input]
  /// (zero when null).
  void step(
    double from,
    double to,
    MorphSpring spring,
    double Function(double t)? input,
  ) {
    final steps = math.max(1, ((to - from) / 0.001).ceil());
    final h = (to - from) / steps;
    final k = spring.stiffness;
    final c = spring.damping;
    for (var i = 0; i < steps; i++) {
      final target = input == null ? 0.0 : input(from + (i + 0.5) * h);
      velocity += (k * (target - value) - c * velocity) * h;
      value += velocity * h;
    }
  }
}

/// The motion of a glass button turning into its menu and back: a pure
/// function of the touches it is fed, the progress it reads and the time
/// it is advanced to.
///
/// One progress drives two shapes. The menu shape grows out of the
/// button: a square of the menu's width scaled down to half the button's
/// height that stretches to the menu's height while it scales up, rides
/// from the button's center to the menu's center and dips past it on a
/// vertical kick. The button shape shrinks to a quarter and slides a
/// quarter of the way toward the menu. The two are drawn as one union
/// without a neck. The button's glyph rides the button shape, widening as
/// it blurs out early; the menu content rides the menu shape at the
/// shape's scale, swelling a little with its kick, and fades in with the
/// progress, so the menu unfolds out of the drop.
///
/// The kicks are a second degree of freedom per shape, driven by the
/// progress spring: while the menu opens, the menu shape's kick chases
/// the velocity of the opening spring, played from the moment the menu
/// started opening, on [MorphMenuTuning.openKickSpring]; a close strikes
/// it away from the button ([MorphMenuTuning.closeKickImpulse]) and it
/// rings out on [MorphMenuTuning.closeKickSpring], and the button
/// shape's kick chases the velocity of the closing spring. Each kick is
/// integrated over every [advance], so it carries through every
/// reversal.
///
/// Feed pointer events in the coordinate space of [bounds] with their
/// timestamps, call [advance] with the frame time, then read [menuBlob],
/// [buttonBlob] and the crossfade values. A tap opens on release, a hold
/// opens after [MorphMenuTuning.holdDuration]; a release outside the
/// menu closes it and a release on a row selects that row.
class MorphMenuMotion {
  /// Creates the motion of the button at [button] whose menu has
  /// [itemCount] rows, inside [bounds] minus the safe-area [padding].
  ///
  /// [sourceHeight] is the height of the view the menu shape starts from;
  /// it defaults to the button's height and differs for bar buttons,
  /// whose glass platter is larger than the button. [progress] defaults
  /// to [MorphMenuProgress.spring] of [tuning].
  MorphMenuMotion({
    required Rect button,
    required this._itemCount,
    required this._bounds,
    this._padding = EdgeInsets.zero,
    double? sourceHeight,
    this.tuning = MorphMenuTuning.standard,
    MorphMenuProgress? progress,
  }) : _button = button,
       _sourceHeight = sourceHeight ?? button.height,
       _flex = MorphFlexSpec.forSize(button.size),
       _progress = progress ?? MorphMenuProgress.spring(tuning) {
    _radius = MorphSpringState(tuning.openSpring, 0);
    _press = MorphSpringState(_flex.trackingSpring, 1);
    _leanX = MorphSpringState(tuning.flexSpring, 0);
    _leanY = MorphSpringState(tuning.flexSpring, 0);
    _place(1);
  }

  /// The measured behavior this motion reproduces.
  final MorphMenuTuning tuning;

  final MorphMenuProgress _progress;

  Rect _button;
  int _itemCount;
  Size _bounds;
  EdgeInsets _padding;
  double _sourceHeight;
  MorphFlexSpec _flex;

  late final MorphSpringState _radius;
  late final MorphSpringState _press;
  late final MorphSpringState _leanX;
  late final MorphSpringState _leanY;

  final _DrivenKick _menuKick = _DrivenKick();
  final _DrivenKick _buttonKick = _DrivenKick();
  MorphSpringState? _openReference;
  MorphSpringState? _closeReference;
  final List<({double start, bool opening})> _fusions = [];
  final MorphMenuFusion _fusion = MorphMenuFusion();
  double _sampleTime = double.negativeInfinity;

  _Phase _phase = _Phase.idle;
  double _sourceScale = 1;
  Rect _pressed = Rect.zero;
  Rect _menu = Rect.zero;
  bool _down = true;
  double _amplitude = 1;
  double _closeAmplitude = 1;
  double _sourceAmplitude = 1;
  double _radiusFrom = 0;
  double _closeRadius = 0;
  double _closeProgress = 1;
  double _closeStart = 0;
  double _closeSource = 1;
  double _closeLive = 1;
  double _fadeFrom = 0;
  double _fadeTo = 1;
  double _fadeAnchor = 0;
  double _fadeEnd = 1;
  int _openGeneration = 0;
  int _pressGeneration = 0;
  bool _openPending = false;
  ({double t, Offset position})? _earlyRelease;
  _Pointer? _pointer;
  int? _highlighted;
  Offset? _glowAt;
  double _glowFrom = 0;
  double _glowStart = 0;
  double _glowTarget = 0;

  final MorphTimeline _timeline = MorphTimeline(now: 0);

  /// Called with the row index when a row is selected, at the moment its
  /// action runs, which is before the menu starts closing.
  void Function(int index)? onSelected;

  double get _now => _timeline.now;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// The layout frame of the button.
  Rect get button => _button;

  /// The number of rows of the menu.
  int get itemCount => _itemCount;

  /// The bounds the menu is placed in.
  Size get bounds => _bounds;

  /// Updates the geometry; ignored while the menu is shown.
  void relayout({
    required Rect button,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    int? itemCount,
    double? sourceHeight,
  }) {
    if (_phase != _Phase.idle) return;
    _button = button;
    _bounds = bounds;
    _padding = padding;
    _itemCount = itemCount ?? _itemCount;
    _sourceHeight = sourceHeight ?? button.height;
    _flex = MorphFlexSpec.forSize(button.size);
    _place(_press.value(_now));
  }

  /// The progress of the morph at the time the motion was last advanced
  /// to, read from its [MorphMenuProgress]: 0 is the button, 1 the menu.
  ///
  /// The opening spring overshoots, so the value briefly exceeds 1, and
  /// the closing one briefly dips below 0.
  double get progress => _progress.valueAt(_now);

  /// Whether the menu is on screen, opening, open or closing.
  bool get isPresented => _phase != _Phase.idle;

  /// Whether the menu is opening or open.
  bool get isOpen => _phase == _Phase.opening;

  /// Whether the menu is closing.
  bool get isClosing => _phase == _Phase.closing;

  /// Whether a tap's release has scheduled the opening and the menu is
  /// not on its way yet.
  ///
  /// A touch that lands anywhere in this window belongs to the menu, as
  /// on iOS: it is held until the menu opens, and a release that came
  /// before then is applied at the opening - on a row it selects the row,
  /// outside the menu it closes the menu again
  /// [MorphMenuTuning.earlyCloseDelay] after the opening.
  bool get isOpenPending => _openPending;

  /// The final frame of the open menu.
  Rect get menuRect => _menu;

  /// Whether the menu opens below the button; otherwise it opens above it
  /// and its rows are reversed.
  bool get opensDown => _down;

  /// The button's frame at the scale it had when the menu opened, which
  /// the menu is aligned to.
  Rect get pressedButtonRect => _pressed;

  /// The scale of the button's press growth.
  double get pressScale => _press.value(_now);

  /// The row under the finger, or the selected row while the menu closes.
  int? get highlighted => _highlighted;

  /// The center of the glow under a finger on the menu.
  Offset? get glowCenter => _glowAt;

  /// The opacity of the glow under a finger on the menu.
  double get glowOpacity {
    final span = tuning.glowFade;
    final t = ((_now - _glowStart) / span).clamp(0.0, 1.0);
    return _glowFrom + (_glowTarget - _glowFrom) * t;
  }

  /// The opacity of the menu content.
  double get contentOpacity => _contentOpacityAt(_now);

  double _contentOpacityAt(double t) {
    if (_phase == _Phase.idle) {
      return _ramp(
        _progress.valueAt(t),
        tuning.contentFadeStart,
        tuning.contentFadeEnd,
      );
    }
    final span = _fadeAnchor - _fadeEnd;
    if (span.abs() < 1e-6) return _fadeTo;
    final p = _progress.valueAt(t + tuning.fadeLead);
    final f = ((p - _fadeEnd) / span).clamp(0.0, 1.0);
    return _fadeTo + (_fadeFrom - _fadeTo) * f;
  }

  void _fade(
    double t, {
    required double from,
    required bool opening,
    bool fresh = false,
  }) {
    final p = _progress.valueAt(t + tuning.fadeLead);
    _fadeFrom = from;
    _fadeTo = opening ? 1 : 0;
    if (opening) {
      _fadeAnchor = fresh ? tuning.contentFadeStart : p;
      _fadeEnd = tuning.contentFadeEnd;
    } else {
      _fadeAnchor = p;
      _fadeEnd = p > tuning.contentCloseFadeEnd + 0.05
          ? tuning.contentCloseFadeEnd
          : 0;
    }
  }

  /// The blur radius of the menu content, in logical pixels on screen.
  double get contentBlur => math.max(
    0,
    tuning.contentBlur * (1 - progress) +
        tuning.contentKickBlur * _relativeKick,
  );

  /// The scale of the menu content relative to its final size: the menu
  /// shape's scale plus a swell with its kick.
  ///
  /// The content is placed by [contentRect] at this scale and clipped by
  /// [menuBlob].
  double get contentScale => _contentScale(menuBlob);

  double _contentScale(MorphMenuBlob menu) =>
      menu.scale + tuning.contentKickScale * _relativeKick;

  /// The frame of the menu content: [menuRect]'s size at [contentScale],
  /// riding [menuBlob].
  ///
  /// A menu taller than it is wide keeps its first row on the shape's top
  /// edge, like a list scrolled to its start, and grows below it; a menu
  /// as wide as it is tall or wider is centered on the shape.
  Rect get contentRect {
    final menu = menuBlob;
    final scale = _contentScale(menu);
    final width = _menu.width * scale;
    final height = _menu.height * scale;
    final shape = menu.rect;
    if (_menu.height > _menu.width) {
      return Rect.fromLTWH(
        shape.center.dx - width / 2,
        shape.top,
        width,
        height,
      );
    }
    return Rect.fromCenter(center: shape.center, width: width, height: height);
  }

  /// The opacity of the button's look inside the button shape.
  double get buttonLookOpacity =>
      1 - _ramp(_leadingProgress, tuning.lookFadeStart, tuning.lookFadeEnd);

  /// The blur radius of the button's look.
  double get buttonLookBlur => tuning.crossfadeBlur * progress.clamp(0.0, 1.0);

  /// The horizontal stretch of the button's look relative to the button
  /// shape's scale.
  double get buttonLookStretch =>
      1 + tuning.lookStretch * progress.clamp(0.0, 1.0);

  double get _leadingProgress => _phase == _Phase.idle
      ? progress
      : _progress.valueAt(_now + tuning.fadeLead);

  double get _relativeKick => _menu.height > 0 ? menuKick / _menu.height : 0;

  static double _ramp(double value, double from, double to) =>
      ((value - from) / (to - from)).clamp(0.0, 1.0);

  /// The fusion radius: the standard deviation, in pixels, of the
  /// Gaussian blur UIKit applies to the distance field of [menuBlob] and
  /// [buttonBlob] to fuse them into one silhouette; 0 when they are
  /// drawn as their plain union.
  ///
  /// Every open and every close starts its own envelope
  /// ([MorphMenuTuning.fusionEnvelope]); the radius is the largest of the
  /// envelopes still running, limited to
  /// [MorphMenuTuning.fusionRadius], so a reversal never makes it jump.
  double get fusionRadius => _fusionAt(_now);

  /// The silhouette of [menuBlob] and [buttonBlob] fused at
  /// [fusionRadius], in the motion's coordinates, or null while the
  /// radius is under 1 pixel and the silhouette
  /// is the plain union of the two shapes.
  Path? get silhouette {
    if (_phase == _Phase.idle) return null;
    final radius = fusionRadius;
    if (radius < MorphMenuFusion.minimumRadius) return null;
    return _fusion.outline(menuBlob.rrect, buttonBlob.rrect, radius);
  }

  double _fusionAt(double t) {
    var radius = 0.0;
    for (final fusion in _fusions) {
      radius = math.max(
        radius,
        tuning.fusionEnvelope(t - fusion.start, opening: fusion.opening),
      );
    }
    if (radius < tuning.fusionCutoff) return 0;
    return math.min(radius, tuning.fusionRadius);
  }

  bool _fusionAtRest(double t) {
    _fusions.removeWhere(
      (({double start, bool opening}) fusion) =>
          tuning.fusionEnded(t - fusion.start, opening: fusion.opening),
    );
    return _fusions.isEmpty;
  }

  /// The vertical kick of the menu shape, positive toward the side the
  /// menu opens to.
  double get menuKick => _menuKick.value;

  /// The vertical kick of the button shape, positive toward the side the
  /// menu opens to.
  double get buttonKick => _buttonKick.value;

  /// The menu shape: grows out of the button into the menu.
  MorphMenuBlob get menuBlob {
    final p = progress;
    final w = tuning.menuWidth;
    final h = _menu.height;
    final s0 = 0.5 * _sourceHeight / math.max(w, h);
    final scale = s0 + (1 - s0) * p;
    final localHeight = w + (h - w) * p;
    final from = _button.center;
    final to = _menu.center;
    final sign = _down ? 1.0 : -1.0;
    final center = Offset(
      from.dx + (to.dx - from.dx) * p + _leanX.value(_now),
      from.dy + (to.dy - from.dy) * p + sign * menuKick + _leanY.value(_now),
    );
    return MorphMenuBlob(
      rect: Rect.fromCenter(
        center: center,
        width: w * scale,
        height: localHeight * scale,
      ),
      radius: _localRadius(p, localHeight) * scale,
      scale: scale,
      localSize: Size(w, localHeight),
    );
  }

  /// The button shape: shrinks into the menu.
  MorphMenuBlob get buttonBlob {
    final p = progress;
    final from = _sourceScaleAt(_now);
    final scale = from + (tuning.sourceEndScale - from) * p;
    final start = _button.center;
    final travel = (_menu.center - start) * (tuning.sourceTravel * p);
    final sign = _down ? 1.0 : -1.0;
    final center = start + travel + Offset(0, sign * buttonKick);
    final size = _button.size * scale;
    return MorphMenuBlob(
      rect: Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      ),
      radius: math.min(size.width, size.height) / 2,
      scale: scale,
      localSize: _button.size,
    );
  }

  /// Whether nothing moves and nothing is pending.
  bool get isSettled {
    final t = _now;
    if (_pointer != null || !_timeline.isEmpty) return false;
    if (_phase == _Phase.closing) return false;
    if (!_press.isAtRest(t, 1e-3) ||
        !_leanX.isAtRest(t) ||
        !_leanY.isAtRest(t) ||
        glowOpacity > 0) {
      return false;
    }
    if (_phase == _Phase.opening) {
      return _progress.isAtRestAt(t) &&
          _radius.isAtRest(t, 1e-3) &&
          _menuKick.isAtRest &&
          _buttonKick.isAtRest &&
          _fusionAtRest(t);
    }
    return true;
  }

  /// The row at [position], in item order, or null.
  int? rowAt(Offset position) {
    if (_phase == _Phase.idle || !_menu.contains(position)) return null;
    final slot =
        ((position.dy - _menu.top - tuning.verticalPadding) / tuning.rowHeight)
            .floor();
    if (slot < 0 || slot >= _itemCount) return null;
    return slotOf(slot);
  }

  /// The visual slot, from the top of the menu, of row [index]; rows are
  /// reversed when the menu opens upward.
  int slotOf(int index) => _down ? index : _itemCount - 1 - index;

  /// Opens the menu at time [t].
  ///
  /// [sourceScale] is the button's scale at that moment, which sizes the
  /// frame the menu aligns to; it defaults to the current press scale.
  void open(double t, {double? sourceScale}) {
    advance(t);
    _open(t, sourceScale: sourceScale);
  }

  /// Closes the menu at time [t].
  void close(double t) {
    advance(t);
    _close(t);
  }

  /// Selects row [index] at time [t] as a release on it would.
  void select(double t, int index) {
    advance(t);
    if (_phase != _Phase.opening) return;
    _select(t, index);
  }

  /// A finger touched down at [position].
  void pointerDown(double t, Offset position) {
    advance(t);
    if (_pointer != null) return;
    if (_phase == _Phase.opening) {
      _pointer = _Pointer(
        fromButton: false,
        position: position,
        startedInMenu: _menu.contains(position),
      );
      _highlighted = rowAt(position);
      _glow(t, position, on: true);
      return;
    }
    if (_openPending) {
      _pointer = _Pointer(
        fromButton: false,
        position: position,
        startedInMenu: false,
      );
      return;
    }
    if (!_button.contains(position)) return;
    final pointer = _Pointer(
      fromButton: true,
      position: position,
      startedInMenu: false,
    );
    _pointer = pointer;
    final generation = ++_pressGeneration;
    final lifted = 1 + _flex.liftScalePoints / _button.height;
    _timeline.at(t + tuning.pressDelay, (double s) {
      if (generation != _pressGeneration) return;
      _press.retarget(s, lifted, spring: _flex.trackingSpring);
    });
    _timeline.at(t + tuning.holdDuration, (double s) {
      if (!identical(_pointer, pointer) || _phase == _Phase.opening) return;
      pointer.openedByHold = true;
      _open(s);
      _glow(s, pointer.position, on: true);
    });
  }

  /// The finger moved to [position].
  void pointerMove(double t, Offset position) {
    advance(t);
    final pointer = _pointer;
    if (pointer == null) return;
    pointer.position = position;
    if (_phase != _Phase.opening) return;
    _highlighted = rowAt(position);
    _glowAt = position;
    final lean = (position - _menu.center) * tuning.flexGain;
    final limit = tuning.flexLimit;
    _leanX.retarget(t, lean.dx.clamp(-limit, limit));
    _leanY.retarget(t, lean.dy.clamp(-limit, limit));
  }

  /// The finger lifted at [position].
  void pointerUp(double t, Offset position) {
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    pointer.position = position;
    _relax(t);
    if (pointer.fromButton) {
      _release(t);
      if (!pointer.openedByHold) {
        if (_phase != _Phase.opening) {
          _openPending = true;
          _timeline.at(t + tuning.tapOpenDelay, _open);
        }
        return;
      }
    }
    if (_phase != _Phase.opening) {
      if (_openPending) _earlyRelease = (t: t, position: position);
      return;
    }
    final row = rowAt(position);
    if (row != null) {
      _select(t, row);
    } else {
      _highlighted = null;
      if (!pointer.fromButton && !_menu.contains(position)) {
        _timeline.at(t + tuning.dismissDelay, _close);
      }
    }
  }

  /// The touch was cancelled.
  void pointerCancel(double t) {
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    _relax(t);
    if (_phase == _Phase.opening) _highlighted = null;
    if (pointer.fromButton) _release(t);
  }

  /// Advances the motion to time [t]: runs every event due by then and
  /// samples the progress, integrating the kicks over the interval.
  void advance(double t) {
    if (t < _now) return;
    _timeline.runDue(t);
    _sample(t);
    if (_phase == _Phase.closing &&
        _progress.isAtRestAt(t) &&
        _menuKick.isAtRest &&
        _buttonKick.isAtRest &&
        _fusionAtRest(t)) {
      _phase = _Phase.idle;
      _highlighted = null;
      _menuKick.reset();
      _buttonKick.reset();
      _openReference = null;
      _closeReference = null;
    }
  }

  /// The final frame of a menu of [size] opened from a button whose frame
  /// at its current scale is [button], inside [bounds] minus [padding].
  ///
  /// The menu opens downward with its top on the button's top when the
  /// button's center is in the upper half of the safe area, and upward with its
  /// bottom on the button's bottom otherwise. It is centered on the button
  /// when that keeps [edgeMargin] from the safe area's sides, and aligns
  /// with the button's nearer edge otherwise; the result is then clamped
  /// into the safe area.
  static ({Rect rect, bool down}) place({
    required Rect button,
    required Size size,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    double edgeMargin = 8,
  }) {
    final down =
        button.center.dy <= (padding.top + bounds.height - padding.bottom) / 2;
    final minLeft = padding.left;
    final maxRight = bounds.width - padding.right;
    var left = button.center.dx - size.width / 2;
    if (left < minLeft + edgeMargin ||
        left + size.width > maxRight - edgeMargin) {
      left = button.center.dx < bounds.width / 2
          ? button.left
          : button.right - size.width;
    }
    left = math.max(minLeft, math.min(left, maxRight - size.width));
    var top = down ? button.top : button.bottom - size.height;
    final maxBottom = bounds.height - padding.bottom;
    top = math.max(padding.top, math.min(top, maxBottom - size.height));
    return (
      rect: Rect.fromLTWH(left, top, size.width, size.height),
      down: down,
    );
  }

  /// The opening kick's amplitude relative to a 146-pixel menu, for a
  /// menu [height] pixels tall; it scales [MorphMenuTuning.openKickGain].
  static double kickAmplitude(double height) =>
      _interpolate(_kickAmplitude, height);

  static double _interpolate(List<(double, double)> table, double height) {
    if (height <= table.first.$1) return table.first.$2;
    for (var i = 1; i < table.length; i++) {
      final (h1, a1) = table[i];
      if (height <= h1) {
        final (h0, a0) = table[i - 1];
        return a0 + (a1 - a0) * (height - h0) / (h1 - h0);
      }
    }
    return table.last.$2;
  }

  void _sample(double t) {
    final from = _sampleTime;
    if (t > from && from.isFinite && _phase != _Phase.idle) {
      final a = _amplitude;
      final open = _openReference;
      final close = _closeReference;
      final opening = _phase == _Phase.opening;
      _menuKick.step(
        from,
        t,
        opening ? tuning.openKickSpring : tuning.closeKickSpring,
        open == null || !opening
            ? null
            : (double s) => tuning.openKickGain * a * open.velocity(s),
      );
      _buttonKick.step(
        from,
        t,
        tuning.sourceKickSpring,
        close == null
            ? null
            : (double s) =>
                  tuning.sourceKickGain * _sourceAmplitude * close.velocity(s),
      );
    }
    if (t >= from) _sampleTime = t;
  }

  void _place(double sourceScale) {
    _sourceScale = sourceScale;
    _pressed = Rect.fromCenter(
      center: _button.center,
      width: _button.width * sourceScale,
      height: _button.height * sourceScale,
    );
    final size = Size(tuning.menuWidth, tuning.menuHeight(_itemCount));
    final placed = place(
      button: _pressed,
      size: size,
      bounds: _bounds,
      padding: _padding,
      edgeMargin: tuning.edgeMargin,
    );
    _menu = placed.rect;
    _down = placed.down;
    _amplitude = kickAmplitude(size.height);
    _closeAmplitude = _interpolate(_closeKickAmplitude, size.height);
    _sourceAmplitude = _interpolate(_sourceKickAmplitude, size.height);
  }

  void _open(double t, {double? sourceScale}) {
    _openPending = false;
    if (_phase == _Phase.opening) return;
    _sample(t);
    final fresh = _phase == _Phase.idle;
    final opacity = fresh ? 0.0 : _contentOpacityAt(t);
    if (_phase == _Phase.idle) {
      _place(sourceScale ?? _press.value(t));
      _radiusFrom = tuning.openingRadius;
    } else {
      _sourceScale = sourceScale ?? _sourceScaleAt(t);
      _radiusFrom = _closingRadius(_progress.valueAt(t));
    }
    _phase = _Phase.opening;
    _fusions.add((start: t, opening: true));
    final reference = MorphSpringState(tuning.openSpring, 0);
    reference.retarget(t, 1);
    _openReference = reference;
    _progress.open(t);
    _fade(t, from: opacity, opening: true, fresh: fresh);
    _radius.snap(t, 0);
    final generation = ++_openGeneration;
    _timeline.at(t + tuning.radiusDelay, (double s) {
      if (generation != _openGeneration) return;
      _radius.retarget(s, 1, spring: tuning.openSpring);
    });
    _takeEarlyTouch(t);
  }

  void _takeEarlyTouch(double t) {
    final pointer = _pointer;
    if (pointer != null && !pointer.fromButton) {
      _highlighted = rowAt(pointer.position);
      _glow(t, pointer.position, on: true);
    }
    final release = _earlyRelease;
    _earlyRelease = null;
    if (release == null) return;
    final row = rowAt(release.position);
    if (row != null) {
      _highlighted = row;
      _timeline.at(t + tuning.actionDelay, (double s) => onSelected?.call(row));
      _timeline.at(t + tuning.earlyCloseDelay, _close);
    } else if (!_menu.contains(release.position)) {
      _timeline.at(t + tuning.earlyCloseDelay, _close);
    }
  }

  void _close(double t) {
    if (_phase != _Phase.opening) return;
    _sample(t);
    final opacity = _contentOpacityAt(t);
    _closeRadius = _openingRadius(t);
    _closeProgress = _progress.valueAt(t);
    _closeStart = t;
    _closeSource = _sourceScale;
    _closeLive = _press.value(t);
    _openGeneration++;
    _phase = _Phase.closing;
    _fusions.add((start: t, opening: false));
    _relax(t);
    final reference = MorphSpringState(tuning.closeSpring, 1);
    reference.retarget(t, 0);
    _closeReference = reference;
    _progress.close(t);
    _fade(t, from: opacity, opening: false);
    final generation = _openGeneration;
    _timeline.at(t + tuning.closeKickDelay, (double s) {
      if (generation != _openGeneration || _phase != _Phase.closing) return;
      _sample(s);
      final reach = tuning.closeKickReach * _closeAmplitude;
      final room = (1 - _menuKick.value / reach).clamp(0.0, 1.0);
      _menuKick.velocity += tuning.closeKickImpulse * _closeAmplitude * room;
    });
  }

  void _select(double t, int index) {
    _highlighted = index;
    _timeline.at(t + tuning.actionDelay, (double s) => onSelected?.call(index));
    _timeline.at(t + tuning.dismissDelay, _close);
  }

  void _release(double t) {
    _pressGeneration++;
    _press.retarget(t, 1, spring: _flex.scaleSpring);
  }

  void _relax(double t) {
    _leanX.retarget(t, 0);
    _leanY.retarget(t, 0);
    _glow(t, _glowAt, on: false);
  }

  void _glow(double t, Offset? position, {required bool on}) {
    final current = glowOpacity;
    _glowAt = position;
    _glowFrom = current;
    _glowStart = t;
    _glowTarget = on ? tuning.glowOpacity : 0;
  }

  double _sourceScaleAt(double t) {
    if (_phase != _Phase.closing) return _sourceScale;
    final live = _press.value(t);
    final decay = math.exp(-(t - _closeStart) / tuning.sourceRelax);
    return live + (_closeSource - _closeLive) * decay;
  }

  double _openingRadius(double t) {
    final target = math.min(tuning.cornerRadius, _menu.height / 2);
    return _radiusFrom + (target - _radiusFrom) * _radius.value(t);
  }

  double _closingRadius(double p) {
    final half = tuning.menuWidth / 2;
    if (_closeProgress.abs() < 1e-3) return half;
    return half + (_closeRadius - half) * p / _closeProgress;
  }

  double _localRadius(double p, double localHeight) {
    final raw = _phase == _Phase.closing
        ? _closingRadius(p)
        : _openingRadius(_now);
    final capped = math.min(
      raw,
      math.min(tuning.menuWidth / 2, localHeight / 2),
    );
    return math.max(0, capped);
  }
}

const List<(double, double)> _kickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (188, 1.488),
  (230, 1.628),
  (272, 1.61),
  (356, 1.563),
  (440, 1.481),
];

// The closing amplitudes were captured at 146, 230 and 440 pixels;
// below 146 the opening's amplitude stands in.
const List<(double, double)> _closeKickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (230, 1.644),
  (440, 1.61),
];

const List<(double, double)> _sourceKickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (230, 1.488),
  (440, 1.777),
];
