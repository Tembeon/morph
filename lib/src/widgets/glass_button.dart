import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_glow.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';

/// The motion of an iOS 27 glass button: one uniform lift, a lean toward
/// a finger that drags off, and the touch glow.
///
/// A touch scales the whole button by `1 + lift / width`, where the lift
/// in pixels and both springs come from [MorphFlexSpec.forSize]:
/// the press rides the tracking spring, the release the scale spring, so
/// a small button rings below its size while a wide one barely does. The
/// button stays lifted for the whole touch, even far outside; a finger
/// that drags away pulls it along by `d * |d| / 10000` pixels and
/// stretches it along the drag. A glow fades in under the finger and
/// fades out on release while the little glow at the touch point grows.
///
/// Times are seconds and positions pixels in the button's own space.
class MorphGlassButtonMotion {
  /// Creates the motion of a button of [size].
  MorphGlassButtonMotion({required Size size})
    : _size = size,
      _spec = MorphFlexSpec.forSize(size);

  /// The time constant of the glow fading in, in seconds.
  static const double glowTime = 0.023;

  /// The spring the glow fades out and the little glow grows on.
  static const glowSpring = MorphSpring(0.5, 1);

  /// The divisor of the lean: a drag of `d` pixels leans `d * |d|` over
  /// this many pixels.
  static const double leanDivisor = 10000;

  /// How much the button stretches along the drag per pixel of lean.
  static const double leanStretch = 0.0064;

  /// How far outside the button the touch still counts as inside.
  static const double highlightSlop = 70;

  /// The diameter of the little glow at the touch point.
  static const double littleGlowSize = 66;

  /// How much the little glow grows while it fades out.
  static const double littleGlowGrowth = 4;

  /// How strongly a dragging finger pulls this surface, relative to a
  /// button: the lean is `pull * d * |d| / leanDivisor`. A large surface
  /// that lifts like a button, such as an alert's platter, leans less.
  double pull = 1;

  /// How much this surface stretches along the drag per pixel of lean,
  /// relative to a button's [leanStretch].
  double stretch = 1;

  /// Whether the button moves for Reduce Motion: it glows under the touch
  /// but never lifts or leans. This approximates the platform's behavior;
  /// it is not measured.
  bool reducedMotion = false;

  Size _size;
  MorphFlexSpec _spec;
  final MorphSpringState _scale = MorphSpringState(
    MorphFlexSpec.ultraSmall.trackingSpring,
    1,
  );
  final MorphSpringState _leanX = MorphSpringState(
    MorphFlexSpec.ultraSmall.trackingSpring,
    0,
  );
  final MorphSpringState _leanY = MorphSpringState(
    MorphFlexSpec.ultraSmall.trackingSpring,
    0,
  );
  final MorphSpringState _glowOut = MorphSpringState(glowSpring, 0);
  final MorphSpringState _littleScale = MorphSpringState(glowSpring, 1);
  final MorphSpringState _glowX = MorphSpringState(
    MorphFlexSpec.ultraSmall.trackingSpring,
    0,
  );
  final MorphSpringState _glowY = MorphSpringState(
    MorphFlexSpec.ultraSmall.trackingSpring,
    0,
  );

  double _now = 0;
  Offset? _down;
  bool _inside = false;
  double _glowStart = 0;
  double _glowFrom = 0;

  /// The size of the button at rest.
  Size get size => _size;

  set size(Size value) {
    if (value == _size) return;
    _size = value;
    _spec = MorphFlexSpec.forSize(value);
  }

  /// The deformation tuning UIKit derives for [size].
  MorphFlexSpec get spec => _spec;

  /// The scale of the fully lifted button.
  double get liftedScale =>
      _size.width > 0 ? 1 + _spec.liftScalePoints / _size.width : 1;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether a finger is down on the button.
  bool get isPressed => _down != null;

  /// Whether the finger is close enough that a release activates.
  bool get isHighlighted => _down != null && _inside;

  /// The uniform lift scale.
  double get scale => _scale.value(_now);

  /// The horizontal scale, lift and drag stretch combined.
  double get scaleX {
    final e =
        leanStretch *
        stretch *
        (_leanX.value(_now).abs() - _leanY.value(_now).abs());
    return scale * (1 + e);
  }

  /// The vertical scale, lift and drag stretch combined.
  double get scaleY {
    final e =
        leanStretch *
        stretch *
        (_leanY.value(_now).abs() - _leanX.value(_now).abs());
    return scale * (1 + e);
  }

  /// The lean toward the finger.
  Offset get lean => Offset(_leanX.value(_now), _leanY.value(_now));

  /// The glow strength, 0 to 1.
  double get glow {
    if (_down != null) {
      return 1 - (1 - _glowFrom) * math.exp(-(_now - _glowStart) / glowTime);
    }
    return _glowOut.value(_now).clamp(0.0, 1.0);
  }

  /// The opacity of the glow over the whole button.
  double get bigGlowOpacity => glow * _spec.bigGlowOpacity;

  /// The opacity of the little glow at the touch point.
  double get littleGlowOpacity => glow * _spec.littleGlowOpacity;

  /// The scale of the little glow.
  double get littleGlowScale => _littleScale.value(_now);

  /// The center of the little glow.
  Offset get littleGlowCenter => Offset(_glowX.value(_now), _glowY.value(_now));

  /// The measured touch's glow through the shared glass color model.
  ///
  /// Its timing and growth follow this button's flex interaction; the
  /// wash and spot color matrices use the glass glow seam.
  MorphGlassGlow? glowAt(Brightness brightness) {
    final big = bigGlowOpacity;
    final little = littleGlowOpacity;
    if (big <= 0.001 && little <= 0.001) return null;
    return MorphGlassGlow(
      wash: MorphTouchGlowMotion.washOffset * big,
      center: littleGlowCenter,
      radius:
          MorphTouchGlowMotion.spotSpread * littleGlowSize * littleGlowScale,
      gain:
          MorphTouchGlowMotion.spotGain(brightness) *
          MorphTouchGlowMotion.spotCore *
          little,
    );
  }

  /// Whether every part of the button is at rest.
  bool get isSettled =>
      _down == null &&
      _scale.isAtRest(_now, 1e-4) &&
      _leanX.isAtRest(_now, 0.01) &&
      _leanY.isAtRest(_now, 0.01) &&
      _glowOut.isAtRest(_now, 0.002) &&
      _littleScale.isAtRest(_now, 0.002);

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
  }

  /// A finger touched the button at [position].
  void pointerDown(double t, Offset position) {
    advance(t);
    _glowFrom = glow;
    _glowStart = t;
    _down = position;
    _inside = true;
    _scale.retarget(
      t,
      reducedMotion ? 1 : liftedScale,
      spring: _spec.trackingSpring,
    );
    _littleScale.snap(t, 1);
    final glowAt = _clampToButton(position);
    _glowX.snap(t, glowAt.dx);
    _glowY.snap(t, glowAt.dy);
  }

  /// The finger moved to [position].
  void pointerMove(double t, Offset position) {
    advance(t);
    final down = _down;
    if (down == null) return;
    final d = position - down;
    final lean = reducedMotion
        ? Offset.zero
        : d * d.distance * pull / leanDivisor;
    final tracking = _spec.trackingSpring;
    _leanX.retarget(t, lean.dx, spring: tracking);
    _leanY.retarget(t, lean.dy, spring: tracking);
    final glowAt = _clampToButton(position);
    _glowX.retarget(t, glowAt.dx, spring: tracking);
    _glowY.retarget(t, glowAt.dy, spring: tracking);
    _inside = (Offset.zero & _size).inflate(highlightSlop).contains(position);
  }

  /// The finger left the button at [position]; returns whether the
  /// release activates the button.
  bool pointerUp(double t, Offset position) {
    advance(t);
    if (_down == null) return false;
    pointerMove(t, position);
    final activated = _inside;
    _release(t);
    return activated;
  }

  /// The touch was cancelled; the button returns without activating.
  void pointerCancel(double t) {
    advance(t);
    if (_down == null) return;
    _release(t);
  }

  void _release(double t) {
    final strength = glow;
    _down = null;
    _inside = false;
    final spring = _spec.scaleSpring;
    _scale.retarget(t, 1, spring: spring);
    _leanX.retarget(t, 0, spring: spring);
    _leanY.retarget(t, 0, spring: spring);
    _glowOut.snap(t, strength);
    _glowOut.retarget(t, 0);
    _littleScale.retarget(t, littleGlowGrowth);
  }

  Offset _clampToButton(Offset p) =>
      Offset(p.dx.clamp(0.0, _size.width), p.dy.clamp(0.0, _size.height));
}

/// The look of a [MorphGlassButton].
@immutable
class MorphGlassButtonStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphGlassButtonStyle({
    this.fillColor = const Color(0xD9FFFFFF),
    this.rimColor = const Color(0x1F000000),
    this.tintedRimColor = const Color(0x33FFFFFF),
    this.foregroundColor = const Color(0xFF000000),
    this.tintedForegroundColor = const Color(0xFFFFFFFF),
    this.shadowColor = const Color(0x1A000000),
    this.disabledForegroundColor = const Color(0x4C3C3C43),
    this.disabledTintColor = const Color(0xFFD1D1D6),
  });

  /// The fill of the clear glass.
  final Color fillColor;

  /// The outline of the clear glass.
  final Color rimColor;

  /// The outline of a tinted button.
  final Color tintedRimColor;

  /// The label color of the clear glass.
  final Color foregroundColor;

  /// The label color of a tinted button.
  final Color tintedForegroundColor;

  /// The shadow under the button.
  final Color shadowColor;

  /// The label color of a disabled button, clear or tinted:
  /// tertiaryLabel.
  ///
  /// UIKit leaves the glass of a disabled `.glass()` button untouched and
  /// draws its title and image in tertiaryLabel (iPhone 16 Pro, iOS
  /// 27.0.1, light and dark).
  final Color disabledForegroundColor;

  /// The fill that replaces the tint of a disabled prominent button:
  /// systemGray4, as UIKit draws a disabled `.prominentGlass()` button.
  final Color disabledTintColor;

  /// The light appearance.
  static const light = MorphGlassButtonStyle();

  /// The dark appearance.
  static const dark = MorphGlassButtonStyle(
    fillColor: Color(0xB82C2C2E),
    rimColor: Color(0x33FFFFFF),
    foregroundColor: Color(0xFFFFFFFF),
    shadowColor: Color(0x40000000),
    disabledForegroundColor: Color(0x4CEBEBF5),
    disabledTintColor: Color(0xFF3A3A3C),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphGlassButtonStyle resolve(
    BuildContext context,
    MorphGlassButtonStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.glassButton,
    light: light,
    dark: dark,
  );
}

/// A glass button that responds to touch exactly like iOS 27's
/// `UIButton.Configuration.glass()`.
///
/// The whole button, label included, lifts by a uniform scale that
/// depends on its size, leans after a finger that drags off and glows
/// under the touch; see [MorphGlassButtonMotion]. [onPressed] fires
/// when the finger lifts within 70 pixels of the button.
///
/// The button is focusable; Space and Enter press it. With the
/// platform's reduced motion on, it glows but never lifts or leans.
///
/// A disabled button keeps its glass and draws its label in the style's
/// [MorphGlassButtonStyle.disabledForegroundColor]; a prominent one swaps
/// its tint for [MorphGlassButtonStyle.disabledTintColor]. It ignores
/// touches: no lift, no glow, no lean. The change shows in one frame.
class MorphGlassButton extends StatefulWidget {
  /// Creates a glass button.
  const MorphGlassButton({
    required this.child,
    required this.onPressed,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    this.minSize = const Size(44, 44),
    this.style,
    super.key,
  });

  /// The label of the button.
  final Widget child;

  /// Called when the button is tapped; null disables the button.
  final VoidCallback? onPressed;

  /// The fill of a prominent glass button; null for the clear glass.
  final Color? tint;

  /// The space around [child].
  final EdgeInsetsGeometry padding;

  /// The smallest size of the button.
  final Size minSize;

  /// The look of the button; null resolves it from the theme.
  final MorphGlassButtonStyle? style;

  @override
  State<MorphGlassButton> createState() => _MorphGlassButtonState();
}

class _MorphGlassButtonState extends MorphControlHost<MorphGlassButton> {
  final MorphGlassButtonMotion _motion = MorphGlassButtonMotion(
    size: Size.zero,
  );

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  bool get _enabled => widget.onPressed != null;

  @override
  bool get controlEnabled => _enabled;

  @override
  bool acceptsControlPointer(PointerDownEvent event) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    _motion.size = box.size;
    return true;
  }

  @override
  void onControlDown(double t, PointerDownEvent event) =>
      _motion.pointerDown(t, event.localPosition);

  @override
  void onControlMove(double t, PointerMoveEvent event) =>
      _motion.pointerMove(t, event.localPosition);

  @override
  void onControlUp(double t, PointerUpEvent event) {
    final activated = _motion.pointerUp(t, event.localPosition);
    if (activated) widget.onPressed?.call();
  }

  @override
  void onControlCancel(double t) => _motion.pointerCancel(t);

  double get _lift {
    final lifted = _motion.liftedScale - 1;
    if (lifted <= 0) return 0;
    return ((_motion.scale - 1) / lifted).clamp(0.0, 1.0);
  }

  @override
  bool buildsLike(MorphGlassButton oldWidget) =>
      identical(oldWidget.child, widget.child) &&
      (oldWidget.onPressed == null) == (widget.onPressed == null) &&
      oldWidget.tint == widget.tint &&
      oldWidget.padding == widget.padding &&
      oldWidget.minSize == widget.minSize &&
      oldWidget.style == widget.style;

  void _press() => widget.onPressed?.call();

  @override
  Widget buildControl(BuildContext context) {
    final style = MorphGlassButtonStyle.resolve(context, widget.style);
    final brightness = morphBrightnessOf(context);
    final glass = MorphGlass.maybeOf(context);
    _motion.reducedMotion = morphReducedMotionOf(context);
    final enabled = _enabled;
    final tint = widget.tint == null
        ? null
        : enabled
        ? widget.tint
        : style.disabledTintColor;
    final foreground = !enabled
        ? style.disabledForegroundColor
        : tint == null
        ? style.foregroundColor
        : style.tintedForegroundColor;
    final Widget content = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.minSize.width,
        minHeight: widget.minSize.height,
      ),
      child: Padding(
        padding: widget.padding,
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: IconTheme.merge(
            data: IconThemeData(color: foreground, size: 22),
            child: DefaultTextStyle.merge(
              style: MorphTypography.resolve(
                MorphTypography.button,
              ).copyWith(color: foreground),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: MorphControlFocus(
        enabled: _enabled,
        onHighlight: highlightControlFocus,
        onActivate: _enabled ? _press : null,
        child: Semantics(
          button: true,
          enabled: _enabled,
          onTap: _enabled ? _press : null,
          child: MorphTouchListener(
            enabled: _enabled,
            behavior: HitTestBehavior.opaque,
            onPointerDown: handleDown,
            onPointerMove: handleMove,
            onPointerUp: handleUp,
            onPointerCancel: handleCancel,
            child: ListenableBuilder(
              listenable: frames,
              builder: (BuildContext context, Widget? child) {
                final lean = _motion.lean;
                final transform = Matrix4.identity();
                if (!_motion.isSettled) {
                  transform.translateByDouble(lean.dx, lean.dy, 0, 1);
                  transform.multiply(
                    Matrix4.diagonal3Values(_motion.scaleX, _motion.scaleY, 1),
                  );
                }
                return Transform(
                  transform: transform,
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: MorphFocusRing(
                visible: controlFocused,
                child: MorphControlCapsule(
                  painter: glass,
                  frames: frames,
                  color: tint ?? style.fillColor,
                  rim: tint == null ? style.rimColor : style.tintedRimColor,
                  shadow: style.shadowColor,
                  brightness: brightness,
                  enabled: enabled,
                  lift: () => _lift,
                  glow: () => _motion.glowAt(brightness),
                  still: () => _motion.isSettled,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A capsule surface shared by glass buttons and search fields.
@internal
class MorphControlCapsule extends StatelessWidget {
  /// Creates a capsule with optional frame-driven lift and glow.
  const MorphControlCapsule({
    required this.painter,
    required this.frames,
    required this.color,
    required this.rim,
    required this.shadow,
    required this.brightness,
    required this.enabled,
    required this.child,
    this.lift,
    this.glow,
    this.still,
    super.key,
  });

  /// Whether the capsule and every transform the control applies above it
  /// are at rest now, or null when the control does not tell.
  final bool Function()? still;

  /// The installed glass painter, or null for the flat appearance.
  final MorphGlassPainter? painter;

  /// Notifications for the surface's motion.
  final Listenable frames;

  /// The fill or glass tint.
  final Color color;

  /// The flat appearance's rim.
  final Color rim;

  /// The flat appearance's shadow.
  final Color shadow;

  /// The surface's resolved brightness.
  final Brightness brightness;

  /// Whether the surface accepts input.
  final bool enabled;

  /// The current lift, or null for a resting surface.
  final double Function()? lift;

  /// The current glow, or null for an unlit surface.
  final MorphGlassGlow? Function()? glow;

  /// The content above the surface.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = painter;
    if (glass == null) {
      return CustomPaint(
        painter: _CapsulePainter(
          frames: frames,
          color: color,
          rim: rim,
          shadow: shadow,
          glow: glow,
        ),
        child: child,
      );
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shape = _capsule(constraints.biggest);
              return MorphGlassLayer(
                painter: glass,
                frames: frames,
                still: still,
                surfaces: () => [
                  MorphGlassSurface(
                    kind: MorphGlassKind.button,
                    shape: shape,
                    color: color,
                    brightness: brightness,
                    enabled: enabled,
                    lift: lift?.call() ?? 0,
                    glow: glow?.call(),
                  ),
                ],
              );
            },
          ),
        ),
        child,
      ],
    );
  }
}

RRect _capsule(Size size) => RRect.fromRectAndRadius(
  Offset.zero & size,
  Radius.circular(math.min(size.width, size.height) / 2),
);

class _CapsulePainter extends CustomPainter {
  _CapsulePainter({
    required Listenable frames,
    required this.color,
    required this.rim,
    required this.shadow,
    required this.glow,
  }) : super(repaint: frames);

  final Color color;
  final Color rim;
  final Color shadow;
  final MorphGlassGlow? Function()? glow;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _capsule(size);
    final shadowPaint = Paint();
    shadowPaint.color = shadow;
    shadowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(shape.shift(const Offset(0, 2)), shadowPaint);
    final fill = Paint();
    fill.color = color;
    canvas.drawRRect(shape, fill);
    final stroke = Paint();
    stroke.style = PaintingStyle.stroke;
    stroke.strokeWidth = 0.5;
    stroke.color = rim;
    canvas.drawRRect(shape.deflate(0.25), stroke);
    final light = glow?.call();
    if (light != null) morphPaintGlassGlow(canvas, shape, light);
  }

  @override
  bool shouldRepaint(_CapsulePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.rim != rim ||
      oldDelegate.shadow != shadow ||
      oldDelegate.glow != glow;
}
