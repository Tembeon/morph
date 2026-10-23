import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/theme/glass.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/control_state.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/press.dart';

/// One input owner for arbitrary app content, with the measured button press.
///
/// Wrap the painted child in [MorphTouchFeedback] to show the response.
/// This widget owns tap, optional hold, keyboard, focus and semantics;
/// the decorator owns no recognizer and plays no haptic. The child is
/// visual content, not another independently tappable control.
///
/// A scroll can cancel before ownership; a platform cancel or disabling
/// the target never activates it. Releasing within the glass button's
/// measured 70-point slop activates, including after exit and re-entry.
/// [minSize] enlarges only the hit box, not the painted child. A held
/// action uses Flutter's standard long-press threshold from the original
/// contact, including when a scrollable delays the visual response, and
/// suppresses tap.
class MorphTouchTarget extends StatefulWidget {
  /// Creates an input owner; both callbacks null disables it.
  const MorphTouchTarget({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.minSize = const Size(48, 48),
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticValue,
    this.semanticButton = true,
    this.builder,
    super.key,
  });

  /// The visual child, optionally wrapped in [MorphTouchFeedback].
  final Widget child;

  /// The committed pointer, keyboard or accessibility activation.
  final VoidCallback? onTap;

  /// The hold action; when present, a completed hold suppresses [onTap].
  final VoidCallback? onLongPress;

  /// Whether input is available.
  final bool enabled;

  /// The minimum hit box, independent of the painted child's size.
  final Size minSize;

  /// A caller-owned focus node, retained across presentations.
  final FocusNode? focusNode;

  /// Whether to request initial keyboard focus.
  final bool autofocus;

  /// The accessibility name; when supplied, child semantics are excluded.
  final String? semanticLabel;

  /// Additional localized accessibility information.
  final String? semanticValue;

  /// Whether the semantic node has the button role.
  final bool semanticButton;

  /// Builds at input edges and retains [child], never on motion frames.
  final MorphControlBuilder? builder;

  @override
  State<MorphTouchTarget> createState() => _MorphTouchTargetState();
}

class _MorphTouchTargetState extends MorphControlHost<MorphTouchTarget> {
  final MorphGlassButtonMotion motion = MorphGlassButtonMotion(size: Size.zero);
  final GlobalKey visual = GlobalKey();
  bool hovered = false;
  bool held = false;
  bool _inside = false;
  double? holdAt;
  bool _deliverHold = false;

  @override
  bool get controlEnabled =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  @override
  double get pressSlop => MorphGlassButtonMotion.highlightSlop;

  @override
  void advanceMotion(double t) {
    motion.advance(t);
    final due = holdAt;
    if (due != null && t >= due) {
      holdAt = null;
      if (press.inside) {
        held = true;
        _deliverHold = true;
      }
    }
  }

  @override
  void deliverMotionEvents() {
    super.deliverMotionEvents();
    if (!_deliverHold) return;
    _deliverHold = false;
    widget.onLongPress?.call();
  }

  @override
  double? get motionWakeTime => motion.isSettled ? holdAt : null;

  @override
  bool get motionSettled => motion.isSettled && holdAt == null;

  @override
  void settleMotion() => motion.settle();

  RenderBox? get _visualBox =>
      visual.currentContext?.findRenderObject() as RenderBox?;

  // The transform box measures coordinates before its own flex.
  Offset _position(PointerEvent event) {
    final box = _visualBox;
    return box == null
        ? event.localPosition
        : box.globalToLocal(event.position);
  }

  @override
  void onControlDown(double t, PointerDownEvent event) {
    final box = _visualBox;
    motion.size = box?.size ?? (context.findRenderObject()! as RenderBox).size;
    held = false;
    _inside = true;
    // A scrollable delays the visual response, not the hold's deadline.
    holdAt = widget.onLongPress == null
        ? null
        : t +
              (kLongPressTimeout.inMicroseconds -
                      pressDelay.inMicroseconds / timeDilation) /
                  Duration.microsecondsPerSecond;
    motion.pointerDown(t, _position(event));
    setState(() {});
  }

  @override
  void onControlMove(double t, PointerMoveEvent event) {
    final before = _inside;
    _inside = press.inside;
    motion.pointerMove(t, _position(event));
    if (!press.inside) holdAt = null;
    if (before != _inside) setState(() {});
  }

  @override
  void onControlUp(double t, PointerUpEvent event) {
    holdAt = null;
    motion.pointerUp(t, _position(event));
    setState(() {});
    if (!held) widget.onTap?.call();
  }

  @override
  void onControlUpOutside(double t, PointerUpEvent event) => onControlCancel(t);

  @override
  void onControlCancel(double t) {
    holdAt = null;
    _deliverHold = false;
    motion.pointerCancel(t);
    setState(() {});
  }

  void _activate() {
    if (!controlEnabled) return;
    final box = _visualBox;
    motion.size = box?.size ?? (context.findRenderObject()! as RenderBox).size;
    final center = motion.size.center(Offset.zero);
    motion.pointerDown(clock, center);
    motion.pointerUp(clock, center);
    wake();
    widget.onTap?.call();
  }

  @override
  Widget buildControl(BuildContext context) {
    motion.reducedMotion = morphReducedMotionOf(context);
    final state = MorphControlState(
      pressed: motion.isPressed && press.inside,
      active: motion.isPressed,
      hovered: controlEnabled && hovered,
      focused: controlEnabled && controlFocused,
      enabled: controlEnabled,
    );
    return MorphPress(
      target: this,
      enabled: controlEnabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onHighlight: highlightControlFocus,
      onActivate: widget.onTap == null ? null : _activate,
      behavior: HitTestBehavior.opaque,
      delaysInScrollable: true,
      semantics: SemanticsProperties(
        button: widget.semanticButton,
        enabled: controlEnabled,
        label: widget.semanticLabel,
        value: widget.semanticValue,
        onTap: controlEnabled && widget.onTap != null ? _activate : null,
        onLongPress: controlEnabled ? widget.onLongPress : null,
      ),
      child: MouseRegion(
        cursor: controlEnabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: widget.minSize.width,
            minHeight: widget.minSize.height,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: _TouchScope(
              host: this,
              state: state,
              child: ExcludeSemantics(
                excluding: widget.semanticLabel != null,
                child:
                    widget.builder?.call(context, state, widget.child) ??
                    widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TouchScope extends InheritedWidget {
  const _TouchScope({
    required this.host,
    required this.state,
    required super.child,
  });
  final _MorphTouchTargetState host;
  final MorphControlState state;

  @override
  bool updateShouldNotify(_TouchScope oldWidget) => true;
}

/// A passive, shaped press response for the nearest [MorphTouchTarget].
///
/// The child retains its own size and state. Flex and glow use the measured
/// glass-button motion; this decorator adds no glass or backdrop group.
/// In liquid glass it approximates the native color-matrix glow with a
/// clipped white wash and Gaussian spot over the child's paint. Flat glass
/// uses only a uniform highlight: the built-in flat renderer has no glow.
/// Hover and keyboard focus add a subtle highlight; focus also outlines
/// [shape]. These app-surface colors are approximations, not measured
/// UIKit appearance tables. Use [highlightColor] for the app's palette.
///
/// Install one decorator per target. For an existing Morph control, use
/// that control directly: wrapping it would create a second input owner.
class MorphTouchFeedback extends StatelessWidget {
  /// Decorates a target's visual content without owning input.
  const MorphTouchFeedback({
    required this.child,
    this.shape = const StadiumBorder(),
    this.flex = true,
    this.highlightColor,
    super.key,
  });

  /// The painted content, retained across motion frames.
  final Widget child;

  /// Any Flutter shape, independent of the target's rectangular hit box.
  final ShapeBorder shape;

  /// Whether the measured lift and flex deform the child.
  final bool flex;

  /// The flat, hover and focus highlight; null uses a brightness-aware fill.
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TouchScope>();
    assert(
      scope != null,
      'MorphTouchFeedback needs a MorphTouchTarget above it.',
    );
    if (scope == null) return child;
    final host = scope.host;
    final brightness = morphBrightnessOf(context);
    final painter = MorphGlassScope.maybeOf(context);
    final liquid =
        painter is GlassBuiltInPainter &&
        painter.effectiveTier == MorphGlassTier.liquid;
    final color =
        highlightColor ??
        (brightness == Brightness.dark
            ? const Color(0x1FFFFFFF)
            : const Color(0x14000000));
    return RepaintBoundary(
      child: MorphLiveTransform(
        key: host.visual,
        live: host.frames,
        writeInto: (Matrix4 into) {
          if (!flex) return;
          final lean = host.motion.lean;
          into.translateByDouble(lean.dx, lean.dy, 0, 1);
          into.scaleByDouble(host.motion.scaleX, host.motion.scaleY, 1, 1);
        },
        child: CustomPaint(
          foregroundPainter: _FeedbackPainter(
            host,
            scope.state,
            shape,
            color,
            liquid: liquid,
            brightness: brightness,
            direction: Directionality.maybeOf(context),
          ),
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

class _FeedbackPainter extends CustomPainter {
  _FeedbackPainter(
    this.host,
    this.state,
    this.shape,
    this.color, {
    required this.liquid,
    required this.brightness,
    required this.direction,
  }) : super(repaint: host.frames);
  final _MorphTouchTargetState host;
  final MorphControlState state;
  final ShapeBorder shape;
  final Color color;
  final bool liquid;
  final Brightness brightness;
  final TextDirection? direction;

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.getOuterPath(
      Offset.zero & size,
      textDirection: direction,
    );
    final motion = host.motion;
    canvas.save();
    canvas.clipPath(path);
    final paint = Paint();
    final strength = state.enabled
        ? (state.hovered || state.focused ? 1.0 : motion.glow.clamp(0.0, 1.0))
        : 0.0;
    paint.color = color.withValues(alpha: color.a * strength);
    canvas.drawPath(path, paint);
    final glow = liquid && state.enabled ? motion.glowAt(brightness) : null;
    if (glow != null && glow.radius > 0) {
      paint.shader =
          RadialGradient(
            colors: [
              for (var i = 0; i <= 6; i++)
                Color.fromRGBO(
                  255,
                  255,
                  255,
                  (glow.gain /
                          (1 + glow.gain) *
                          math.exp(-0.5 * math.pow(i / 2, 2)))
                      .clamp(0.0, 1.0),
                ),
            ],
          ).createShader(
            Rect.fromCircle(center: glow.center, radius: glow.radius * 3),
          );
      canvas.drawPath(path, paint);
    }
    canvas.restore();
    if (state.focused) {
      final ring = Paint();
      ring.style = PaintingStyle.stroke;
      ring.strokeWidth = 2;
      ring.color = const Color(0xFF0088FF);
      canvas.drawPath(path, ring);
    }
  }

  @override
  bool shouldRepaint(_FeedbackPainter oldDelegate) => true;
}
