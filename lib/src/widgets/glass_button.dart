import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/motion/flex_interaction.dart';
import 'package:morph/src/motion/flex_spec.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_glow.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/motion/timeline.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/theme/theme.dart';

/// The motion of an iOS 27 glass button: the lift, the stretch and shift
/// toward a finger that drags, and the touch glow.
///
/// It is UIKit's flex interaction for a surface of the button's size
/// ([MorphFlexSpec.forSize]). A touch scales the whole button by
/// [MorphFlexSpec.liftScaleFor], the lift over its long side; the press
/// rides the tracking spring, the release the scale spring, so a small
/// button rings below its size while a wide one barely does. The button
/// stays lifted for the whole touch, even far outside. A finger that
/// drags stretches it along the drag, narrows it across and shifts it
/// toward the finger: a quarter as much per pixel inside the button as
/// beyond its edge, over the spec's stretch threshold. A glow fades in
/// under the finger and fades out on release while the little glow at
/// the touch point grows.
///
/// The flex takes up every touch [touchDelay] after the touch's own time
/// stamp, as UIKit's does; whether the button is pressed and whether a
/// release activates it follow the touch at once.
///
/// Times are seconds and positions pixels in the button's own space.
///
/// The button settles once every part's remaining swing is below
/// `MorphRest` (0.1 pt, 0.3 device px at 3x; an opacity half an 8-bit
/// step) and snaps onto its targets: invisible, NEAR.
/// A finger held still counts: a held button stops ticking once its lift
/// and glow are in place and wakes on the finger's next move or its lift.
class MorphGlassButtonMotion {
  /// Creates the motion of a button of [size].
  MorphGlassButtonMotion({required Size size})
    : _flex = MorphFlexInteraction(size: size, glows: true);

  /// The time constant of the glow fading in, in seconds.
  static const double glowTime = MorphFlexInteraction.glowTime;

  /// The spring the glow fades out and the little glow grows on.
  static const glowSpring = MorphFlexInteraction.glowSpring;

  /// How far outside the button the touch still counts as inside.
  static const double highlightSlop = 70;

  /// Seconds between a touch's own time stamp and the flex taking it up:
  /// the touch-down, every move and the release.
  ///
  /// UIKit's glass button starts its lift 22.5 - 29.2 ms after the touch's
  /// stamp (median 26.1, iPhone 16 Pro: the last three taps of
  /// `button-glass-44x44-taps` and the five touches on the button in a
  /// scroll view of `tracking/scroll-delay`) and its return 22.1 - 28.3 ms
  /// after the release's (median 26.0, the seven `*-hold800` captures):
  /// delivery 10 - 25 ms, then the frame the flex begins on. Fed this late,
  /// the drag-off and alert lean replays halve their error. The first
  /// touch after the button appears starts 38 - 47 ms after its stamp, the
  /// next display frame coming ~21 ms after the one before instead of 8.3;
  /// that one-time setup is not reproduced.
  static const double touchDelay = 0.026;

  /// The diameter of the little glow at the touch point.
  static const double littleGlowSize = MorphFlexInteraction.littleGlowSize;

  /// How much the little glow grows while it fades out.
  static const double littleGlowGrowth = MorphFlexInteraction.littleGlowGrowth;

  /// Whether the button moves for Reduce Motion: it glows under the touch
  /// but never lifts or leans. This approximates the platform's behavior;
  /// it is not measured.
  bool get reducedMotion => _flex.reducedMotion;

  set reducedMotion(bool value) => _flex.reducedMotion = value;

  final MorphFlexInteraction _flex;
  final MorphTimeline _input = MorphTimeline();
  double _now = 0;
  bool _pressed = false;
  bool _inside = false;

  /// The size of the button at rest.
  Size get size => _flex.size;

  set size(Size value) => _flex.size = value;

  /// The deformation tuning UIKit derives for [size].
  MorphFlexSpec get spec => _flex.spec;

  /// The scale of the fully lifted button.
  double get liftedScale => _flex.liftedScale;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether a finger is down on the button.
  bool get isPressed => _pressed;

  /// Whether the finger is close enough that a release activates.
  bool get isHighlighted => _pressed && _inside;

  /// The lift: the mean of [scaleX] and [scaleY], which the stretch
  /// leaves alone.
  double get scale => _flex.scale(_now);

  /// The horizontal scale, lift and drag stretch combined.
  double get scaleX => _flex.scaleX(_now);

  /// The vertical scale, lift and drag stretch combined.
  double get scaleY => _flex.scaleY(_now);

  /// How far the button shows shifted toward the finger: the flex's
  /// drift at the button's scale.
  Offset get lean => _flex.translation(_now);

  /// The glow strength, 0 to 1.
  double get glow => _flex.glow(_now);

  /// The opacity of the glow over the whole button.
  double get bigGlowOpacity => _flex.bigGlowOpacity(_now);

  /// The opacity of the little glow at the touch point.
  double get littleGlowOpacity => _flex.littleGlowOpacity(_now);

  /// The scale of the little glow.
  double get littleGlowScale => _flex.littleGlowScale(_now);

  /// The center of the little glow.
  Offset get littleGlowCenter => _flex.littleGlowCenter(_now);

  /// The measured touch's glow through the shared glass color model.
  ///
  /// Its timing and growth follow this button's flex interaction; the
  /// wash and spot color matrices use the glass glow seam. A [tint]ed or
  /// [clear] surface lights with its own spot gain
  /// ([MorphTouchGlowMotion.spotGainFor]); the press itself is the same for
  /// every glass (UIKit gives the clear configurations no press of their
  /// own, read from UIKit, notes private).
  MorphGlassGlow? glowAt(
    Brightness brightness, {
    Color? tint,
    bool clear = false,
  }) {
    final big = bigGlowOpacity;
    final little = littleGlowOpacity;
    if (big <= 0.001 && little <= 0.001) return null;
    return MorphGlassGlow(
      wash: MorphTouchGlowMotion.washOffset * big,
      center: littleGlowCenter,
      radius:
          MorphTouchGlowMotion.spotSpread * littleGlowSize * littleGlowScale,
      gain:
          MorphTouchGlowMotion.spotGainFor(
            brightness,
            tint: tint,
            clear: clear,
          ) *
          MorphTouchGlowMotion.spotCore *
          little,
    );
  }

  /// Whether what remains of the button's motion is invisible
  /// (`MorphRest`, NEAR); a button held still under a finger settles too
  /// and wakes on the finger's next move or its lift.
  bool get isSettled => _input.isEmpty && _flex.isSettled(_now);

  /// Whether the button rests undeformed: settled with no finger on it.
  bool get isAtRest => !_pressed && isSettled;

  /// Puts a settled button onto its targets.
  void settle() => _flex.settle(_now);

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
    _input.runDue(t);
  }

  /// A finger touched the button at [position].
  void pointerDown(double t, Offset position) {
    advance(t);
    _pressed = true;
    _inside = true;
    _later(t, (s) => _flex.pointerDown(s, position));
  }

  /// The finger moved to [position].
  void pointerMove(double t, Offset position) {
    advance(t);
    if (!_pressed) return;
    _later(t, (s) => _flex.pointerMove(s, position));
    _inside = (Offset.zero & size).inflate(highlightSlop).contains(position);
  }

  /// The finger left the button at [position]; returns whether the
  /// release activates the button.
  bool pointerUp(double t, Offset position) {
    advance(t);
    if (!_pressed) return false;
    pointerMove(t, position);
    final activated = _inside;
    _release(t);
    return activated;
  }

  /// The touch was cancelled; the button returns without activating.
  void pointerCancel(double t) {
    advance(t);
    if (!_pressed) return;
    _release(t);
  }

  void _release(double t) {
    _pressed = false;
    _inside = false;
    _later(t, _flex.release);
  }

  void _later(double t, void Function(double t) action) {
    _input.insert(t + touchDelay, action);
    _input.runDue(_now);
  }
}

/// The look of a [MorphGlassButton].
@immutable
class MorphGlassButtonAppearance implements MorphAppearance {
  /// Creates an appearance; the defaults are the iOS light appearance.
  const MorphGlassButtonAppearance({
    this.fillColor = const Color(0xD9FFFFFF),
    this.clearFillColor = const Color(0x40FFFFFF),
    this.rimColor = const Color(0x1F000000),
    this.prominentColor = const Color(0xFF0088FF),
    this.prominentRimColor = const Color(0x33FFFFFF),
    this.foregroundColor = const Color(0xFF000000),
    this.prominentForegroundColor = const Color(0xFFFFFFFF),
    this.shadowColor = const Color(0x1A000000),
    this.disabledForegroundColor = const Color(0x4C3C3C43),
    this.disabledTintColor = const Color(0xFFD1D1D6),
  });

  /// The fill of the regular glass.
  final Color fillColor;

  /// The flat stand-in for clear glass without a painter or on the flat
  /// tier: an approximation, not measured.
  final Color clearFillColor;

  /// The outline of the regular glass.
  final Color rimColor;

  /// The fill of a [MorphGlassButton.prominent] button without its own
  /// tint: the accent, iOS 27's systemBlue as rendered (UIKit
  /// `baseBackgroundColor`, which defaults to `tintColor`).
  final Color prominentColor;

  /// The outline of a prominent button.
  final Color prominentRimColor;

  /// The label color of the regular glass.
  final Color foregroundColor;

  /// The label color of a prominent button.
  final Color prominentForegroundColor;

  /// The shadow under the button.
  final Color shadowColor;

  /// The label color of a disabled button, regular or prominent:
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
  static const light = MorphGlassButtonAppearance();

  /// The dark appearance.
  static const dark = MorphGlassButtonAppearance(
    fillColor: Color(0xB82C2C2E),
    clearFillColor: Color(0x402C2C2E),
    rimColor: Color(0x33FFFFFF),
    prominentColor: Color(0xFF0091FF),
    foregroundColor: Color(0xFFFFFFFF),
    shadowColor: Color(0x40000000),
    disabledForegroundColor: Color(0x4CEBEBF5),
    disabledTintColor: Color(0xFF3A3A3C),
  );

  /// Copies this appearance with the given fields replaced.
  MorphGlassButtonAppearance copyWith({
    Color? fillColor,
    Color? clearFillColor,
    Color? rimColor,
    Color? prominentColor,
    Color? prominentRimColor,
    Color? foregroundColor,
    Color? prominentForegroundColor,
    Color? shadowColor,
    Color? disabledForegroundColor,
    Color? disabledTintColor,
  }) => MorphGlassButtonAppearance(
    fillColor: fillColor ?? this.fillColor,
    clearFillColor: clearFillColor ?? this.clearFillColor,
    rimColor: rimColor ?? this.rimColor,
    prominentColor: prominentColor ?? this.prominentColor,
    prominentRimColor: prominentRimColor ?? this.prominentRimColor,
    foregroundColor: foregroundColor ?? this.foregroundColor,
    prominentForegroundColor:
        prominentForegroundColor ?? this.prominentForegroundColor,
    shadowColor: shadowColor ?? this.shadowColor,
    disabledForegroundColor:
        disabledForegroundColor ?? this.disabledForegroundColor,
    disabledTintColor: disabledTintColor ?? this.disabledTintColor,
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness with [MorphThemeData.tint] as its
  /// [prominentColor].
  static MorphGlassButtonAppearance resolve(
    BuildContext context,
    MorphGlassButtonAppearance? explicit,
  ) => morphResolveAppearance(
    context,
    explicit,
    light: light,
    dark: dark,
    tinted: (table, tint) => table.copyWith(prominentColor: tint),
  );

  @override
  bool operator ==(Object other) =>
      other is MorphGlassButtonAppearance &&
      other.fillColor == fillColor &&
      other.clearFillColor == clearFillColor &&
      other.rimColor == rimColor &&
      other.prominentColor == prominentColor &&
      other.prominentRimColor == prominentRimColor &&
      other.foregroundColor == foregroundColor &&
      other.prominentForegroundColor == prominentForegroundColor &&
      other.shadowColor == shadowColor &&
      other.disabledForegroundColor == disabledForegroundColor &&
      other.disabledTintColor == disabledTintColor;

  @override
  int get hashCode => Object.hash(
    fillColor,
    clearFillColor,
    rimColor,
    prominentColor,
    prominentRimColor,
    foregroundColor,
    prominentForegroundColor,
    shadowColor,
    disabledForegroundColor,
    disabledTintColor,
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
/// A disabled button keeps its glass and draws its label in the appearance's
/// [MorphGlassButtonAppearance.disabledForegroundColor]; a prominent one swaps
/// its tint for [MorphGlassButtonAppearance.disabledTintColor]. It ignores
/// touches: no lift, no glow, no lean. The change shows in one frame.
///
/// With a [menu] the button is a [MorphMenuSource]: it turns into its
/// menu with the measured motion of [MorphMenuButton], as a glass
/// `UIButton` with a menu. The shape the menu grows out of and lands back
/// into starts and ends in the button's own fill or tint.
class MorphGlassButton extends StatefulWidget {
  /// Creates a regular glass button (`UIButton.Configuration.glass()`).
  const MorphGlassButton({
    required this.child,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    this.minSize = const Size(44, 44),
    this.appearance,
    this.menu,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  }) : tint = null,
       prominent = false,
       style = MorphGlassStyle.regular;

  /// Creates a prominent glass button filled with [tint]
  /// (`UIButton.Configuration.prominentGlass()`, its
  /// `baseBackgroundColor`); without one it is filled with the ambient
  /// accent, [MorphGlassButtonAppearance.prominentColor].
  const MorphGlassButton.prominent({
    required this.child,
    required this.onPressed,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    this.minSize = const Size(44, 44),
    this.appearance,
    this.menu,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  }) : prominent = true,
       style = MorphGlassStyle.regular;

  /// Creates a clear glass button (`UIButton.Configuration.clearGlass()`),
  /// for buttons over rich media: the clear material, without the regular
  /// glass's wash. Its label needs contrast of its own over a bright
  /// backdrop. The press is the regular button's; the touch glow uses
  /// clear glass's white level (read from UIKit, notes private).
  const MorphGlassButton.clear({
    required this.child,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    this.minSize = const Size(44, 44),
    this.appearance,
    this.menu,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  }) : tint = null,
       prominent = false,
       style = MorphGlassStyle.clear;

  /// Creates a prominent clear glass button filled with [tint], or the
  /// ambient accent without one
  /// (`UIButton.Configuration.prominentClearGlass()`). The press is the
  /// regular button's; the touch glow follows the tint's luminance as on
  /// any tinted glass (read from UIKit, notes private).
  const MorphGlassButton.prominentClear({
    required this.child,
    required this.onPressed,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    this.minSize = const Size(44, 44),
    this.appearance,
    this.menu,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  }) : prominent = true,
       style = MorphGlassStyle.clear;

  /// The label of the button.
  final Widget child;

  /// The label screen readers announce (`accessibilityLabel`); give one to
  /// a button whose [child] is only an icon. Null lets the [child]'s text
  /// speak.
  final String? semanticLabel;

  /// Called when the button is tapped; null disables a button without a
  /// [menu].
  final VoidCallback? onPressed;

  /// Whether the button accepts input.
  ///
  /// False disables the button as a null [onPressed] does, and also one
  /// with a [menu]: it keeps its tree, closes an open menu and draws
  /// disabled.
  final bool enabled;

  /// The entries of the button's menu (`UIButton.menu`), or null for a
  /// button without one.
  ///
  /// Without [onPressed] the menu is the button's primary action
  /// (`showsMenuAsPrimaryAction`): a tap opens it on release, a held
  /// finger opens it after the measured hold and may slide
  /// onto a row and choose it on release ([MorphMenuTrigger.tap]). With
  /// [onPressed] a tap presses the button and only a hold opens the menu
  /// ([MorphMenuTrigger.hold]). The button then lifts by the menu's
  /// measured press instead of its own, without the touch glow or the
  /// lean. It stays focusable: Space and Enter open the menu that is the
  /// primary action, or press a button with [onPressed].
  final List<MorphMenuEntry>? menu;

  /// The fill of a [MorphGlassButton.prominent] button, or null for the
  /// appearance's [MorphGlassButtonAppearance.prominentColor]; a regular
  /// button has none.
  final Color? tint;

  /// Whether the glass is filled with a tint
  /// (`UIButton.Configuration.prominentGlass()` or
  /// `prominentClearGlass()`).
  final bool prominent;

  /// The glass material: regular, or clear for [MorphGlassButton.clear]
  /// and [MorphGlassButton.prominentClear].
  final MorphGlassStyle style;

  /// The space around [child].
  final EdgeInsetsGeometry padding;

  /// The smallest size of the button.
  final Size minSize;

  /// The look of the button; null resolves it from the theme.
  final MorphGlassButtonAppearance? appearance;

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

  @override
  void settleMotion() => _motion.settle();

  bool get _enabled =>
      widget.enabled && (widget.onPressed != null || widget.menu != null);

  @override
  bool get controlEnabled => _enabled;

  @override
  double get pressSlop => MorphGlassButtonMotion.highlightSlop;

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
      oldWidget.enabled == widget.enabled &&
      oldWidget.tint == widget.tint &&
      oldWidget.prominent == widget.prominent &&
      oldWidget.style == widget.style &&
      oldWidget.padding == widget.padding &&
      oldWidget.minSize == widget.minSize &&
      oldWidget.appearance == widget.appearance &&
      identical(oldWidget.menu, widget.menu);

  void _press() => widget.onPressed?.call();

  @override
  Widget buildControl(BuildContext context) {
    final style = MorphGlassButtonAppearance.resolve(
      context,
      widget.appearance,
    );
    final brightness = morphBrightnessOf(context);
    final glass = MorphGlassScope.maybeOf(context);
    _motion.reducedMotion = morphReducedMotionOf(context);
    final enabled = _enabled;
    final tint = !widget.prominent
        ? null
        : enabled
        ? widget.tint ?? style.prominentColor
        : style.disabledTintColor;
    final clear = widget.style == MorphGlassStyle.clear;
    final fill = clear ? style.clearFillColor : style.fillColor;
    final glassTint = clear && tint == null ? const Color(0x00000000) : null;
    final foreground = !enabled
        ? style.disabledForegroundColor
        : tint == null
        ? style.foregroundColor
        : style.prominentForegroundColor;
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
    final menu = widget.menu;
    if (menu != null) {
      final hold = widget.onPressed != null;
      final color = tint ?? fill;
      final rim = tint == null ? style.rimColor : style.prominentRimColor;
      return RepaintBoundary(
        child: MorphMenuSource(
          menu: menu,
          trigger: hold ? .hold : .tap,
          onTap: _press,
          enabled: enabled,
          semanticLabel: widget.semanticLabel,
          color: color,
          rimColor: rim,
          look: content,
          child: MorphControlCapsule(
            painter: glass,
            frames: frames,
            color: color,
            tint: glassTint,
            style: clear ? MorphGlassStyle.clear : null,
            rim: rim,
            shadow: style.shadowColor,
            brightness: brightness,
            enabled: enabled,
            child: content,
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: MorphPress(
        target: this,
        enabled: _enabled,
        onHighlight: highlightControlFocus,
        onActivate: _enabled ? _press : null,
        semantics: SemanticsProperties(
          button: true,
          enabled: _enabled,
          label: widget.semanticLabel,
          onTap: _enabled ? _press : null,
        ),
        behavior: HitTestBehavior.opaque,
        child: MorphLiveTransform(
          live: frames,
          writeInto: (Matrix4 into) {
            if (_motion.isAtRest) return;
            final lean = _motion.lean;
            into.translateByDouble(lean.dx, lean.dy, 0, 1);
            into.scaleByDouble(_motion.scaleX, _motion.scaleY, 1, 1);
          },
          child: MorphFocusRing(
            visible: controlFocused,
            child: MorphControlCapsule(
              painter: glass,
              frames: frames,
              color: tint ?? fill,
              tint: glassTint,
              style: clear ? MorphGlassStyle.clear : null,
              rim: tint == null ? style.rimColor : style.prominentRimColor,
              shadow: style.shadowColor,
              brightness: brightness,
              enabled: enabled,
              lift: () => _lift,
              glow: () => _motion.glowAt(brightness, tint: tint, clear: clear),
              still: () => _motion.isSettled,
              child: content,
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
    this.shape = morphCapsuleShape,
    this.style,
    this.tint,
    super.key,
  });

  /// The outline of the surface in a box of the given size: a capsule by
  /// default.
  final RRect Function(Size size) shape;

  /// The material the glass asks its painter for, or null for the
  /// painter's default.
  final MorphGlassStyle? style;

  /// The glass tint handed to the painter apart from the flat [color], or
  /// null to tint with [color].
  final Color? tint;

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

  /// The content above the surface, drawn through [MorphGlyphs]: the
  /// control's press and lift scale it.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = painter;
    final child = MorphGlyphs(child: this.child);
    if (glass == null) {
      return CustomPaint(
        painter: _CapsulePainter(
          shape: shape,
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
              final shape = this.shape(constraints.biggest);
              return MorphGlassLayer(
                painter: glass,
                frames: frames,
                still: still,
                surfaces: () => [
                  MorphGlassSurface(
                    kind: MorphGlassKind.button,
                    shape: shape,
                    color: color,
                    tint: tint,
                    style: style,
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

/// A capsule filling a box of [size].
@internal
RRect morphCapsuleShape(Size size) => RRect.fromRectAndRadius(
  Offset.zero & size,
  Radius.circular(math.min(size.width, size.height) / 2),
);

class _CapsulePainter extends CustomPainter {
  _CapsulePainter({
    required this.shape,
    required Listenable frames,
    required this.color,
    required this.rim,
    required this.shadow,
    required this.glow,
  }) : super(repaint: frames);

  final RRect Function(Size size) shape;
  final Color color;
  final Color rim;
  final Color shadow;
  final MorphGlassGlow? Function()? glow;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = this.shape(size);
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
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.rim != rim ||
      oldDelegate.shadow != shadow ||
      oldDelegate.glow != glow;
}
