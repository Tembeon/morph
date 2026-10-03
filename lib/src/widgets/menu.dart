import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/show.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/menu_motion.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// One row of a [MorphMenuButton]'s menu.
class MorphMenuItem {
  /// Creates a menu row.
  const MorphMenuItem({
    required this.title,
    this.icon,
    this.destructive = false,
    this.onSelected,
  });

  /// The row's title.
  final String title;

  /// The leading glyph, if any.
  final IconData? icon;

  /// Whether the row is drawn in the destructive color.
  final bool destructive;

  /// Called when the row is selected, before the menu starts closing.
  final VoidCallback? onSelected;
}

/// The look of a [MorphMenuButton] and its menu.
class MorphMenuStyle {
  /// Creates a style; the defaults are the iOS 27 light appearance.
  const MorphMenuStyle({
    this.buttonSize = 48,
    this.glassColor = const Color(0xF2FFFFFF),
    this.shadowColor = const Color(0x33000000),
    this.shadowElevation = 12,
    this.textStyle = const TextStyle(fontSize: 17, color: Color(0xFF000000)),
    this.iconColor = const Color(0xFF000000),
    this.iconSize = 20,
    this.destructiveColor = const Color(0xFFFF3B30),
    this.highlightColor = const Color(0x1F000000),
    this.glowColor = const Color(0xFFFFFFFF),
    this.rowPadding = 20,
  });

  /// The diameter of the button.
  final double buttonSize;

  /// The fill of the button and of the menu.
  final Color glassColor;

  /// The color of the shadow under the button and the menu.
  final Color shadowColor;

  /// The elevation of the shadow under the button and the menu.
  final double shadowElevation;

  /// The style of row titles.
  ///
  /// The menu shows in an overlay, outside the text style of the screen
  /// the button sits on, so this is the whole style of its titles: it
  /// replaces the overlay's ambient text style instead of merging into it.
  final TextStyle textStyle;

  /// The color of the button's default glyph and of row glyphs.
  final Color iconColor;

  /// The size of row glyphs.
  final double iconSize;

  /// The color of destructive rows.
  final Color destructiveColor;

  /// The fill of the pill under the highlighted row.
  final Color highlightColor;

  /// The color of the glow under a finger on the menu.
  final Color glowColor;

  /// The horizontal padding of row content.
  ///
  /// When any row has a glyph, every row reserves a leading slot twice
  /// as wide, with the glyph centered in it, and its title starts after
  /// the slot.
  final double rowPadding;

  /// The light appearance.
  static const light = MorphMenuStyle();

  /// The dark appearance, sampled from the iOS 27 dark menu.
  static const dark = MorphMenuStyle(
    glassColor: Color(0xF2222222),
    shadowColor: Color(0x66000000),
    textStyle: TextStyle(fontSize: 17, color: Color(0xFFFFFFFF)),
    iconColor: Color(0xFFFFFFFF),
    destructiveColor: Color(0xFFFF5659),
    highlightColor: Color(0x29FFFFFF),
    glowColor: Color(0xFFFFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphMenuStyle resolve(
    BuildContext context,
    MorphMenuStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.menu ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };

  /// A copy of this style with the given fields replaced.
  MorphMenuStyle copyWith({
    double? buttonSize,
    Color? glassColor,
    Color? shadowColor,
    double? shadowElevation,
    TextStyle? textStyle,
    Color? iconColor,
    double? iconSize,
    Color? destructiveColor,
    Color? highlightColor,
    Color? glowColor,
    double? rowPadding,
  }) => MorphMenuStyle(
    buttonSize: buttonSize ?? this.buttonSize,
    glassColor: glassColor ?? this.glassColor,
    shadowColor: shadowColor ?? this.shadowColor,
    shadowElevation: shadowElevation ?? this.shadowElevation,
    textStyle: textStyle ?? this.textStyle,
    iconColor: iconColor ?? this.iconColor,
    iconSize: iconSize ?? this.iconSize,
    destructiveColor: destructiveColor ?? this.destructiveColor,
    highlightColor: highlightColor ?? this.highlightColor,
    glowColor: glowColor ?? this.glowColor,
    rowPadding: rowPadding ?? this.rowPadding,
  );
}

/// A round glass button that turns into its menu exactly like an iOS 27
/// `UIButton` whose menu is its primary action.
///
/// A tap opens the menu on release; holding opens it after
/// [MorphMenuTuning.holdDuration] and lets the finger slide onto a
/// row and select it on release. A release outside the menu, Esc or the
/// system back gesture closes it. The menu shows in the nearest [Overlay]
/// unless [overlay] names another one, below the button when the button
/// sits in the upper half of the safe area and above it, with its rows
/// reversed, otherwise; the keyboard counts as an obstructed edge.
///
/// The menu is a morph flight: the button is its source and the flight
/// runs UIKit's measured progress spring. The menu evaluates the same
/// spring on the clock its kicks run on and draws both shapes of
/// [MorphMenuMotion] inside a vessel target ([MorphTargetSpec.vessel]);
/// once the closing flight hands the source back, the button draws the
/// rest of the close itself until the kicks have rung out, as UIKit
/// keeps its morph on screen until then. The flight
/// provides the overlay, the pop layering, the modal barrier (without
/// dimming), the focus trap and [MorphFlight.events]; a button removed
/// while its menu is up lets the menu dissolve. A [MorphScope] above the
/// button is used when there is one; otherwise the button brings its
/// own.
class MorphMenuButton extends StatefulWidget {
  /// Creates a menu button.
  const MorphMenuButton({
    required this.items,
    this.child,
    this.style,
    this.tuning = MorphMenuTuning.standard,
    this.overlay,
    this.semanticLabel = 'More',
    this.onOpen,
    super.key,
  });

  /// The rows of the menu, top to bottom when it opens downward.
  final List<MorphMenuItem> items;

  /// The button's glyph; an ellipsis when null.
  final Widget? child;

  /// The look of the button and the menu; null resolves it through
  /// [MorphMenuStyle.resolve].
  final MorphMenuStyle? style;

  /// The measured motion.
  final MorphMenuTuning tuning;

  /// The overlay the menu shows in, or null for the nearest one.
  ///
  /// It must be an ancestor of this button.
  final OverlayState? overlay;

  /// The accessibility label of the button.
  final String semanticLabel;

  /// Called with the flight of the menu each time a new one launches;
  /// its [MorphFlight.events] are the seam for haptics.
  final ValueChanged<MorphFlight>? onOpen;

  @override
  State<MorphMenuButton> createState() => _MorphMenuButtonState();
}

/// The progress of the menu: the measured spring in motion time, the
/// clock the kicks run on, with the flight that carries the menu sent the
/// same way.
class _FlightProgress extends MorphMenuProgress {
  _FlightProgress(this._state, MorphMenuTuning tuning)
    : _spring = MorphMenuProgress.spring(tuning);

  final _MorphMenuButtonState _state;
  final MorphMenuProgress _spring;

  @override
  double valueAt(double t) => _spring.valueAt(t);

  @override
  bool isAtRestAt(double t) => _spring.isAtRestAt(t);

  @override
  void open(double t) {
    _spring.open(t);
    _state._launch();
  }

  @override
  void close(double t) {
    _spring.close(t);
    final flight = _state._flight;
    if (flight != null && !flight.isFinished) flight.close();
  }
}

class _MorphMenuButtonState extends State<MorphMenuButton>
    with
        SingleTickerProviderStateMixin<MorphMenuButton>,
        MorphClock<MorphMenuButton> {
  final Object _tagId = Object();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  MorphMenuMotion? _motion;
  MorphFlight? _flight;
  BuildContext? _scopeContext;
  OverlayState? _overlay;
  int? _pointer;
  bool _disposed = false;
  bool _repaintDisposed = false;
  MorphMenuStyle _style = MorphMenuStyle.light;

  @override
  void dispose() {
    _disposed = true;
    final flight = _flight;
    if (flight == null || flight.isFinished) {
      _disposeRepaint();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        flight.close();
      });
    }
    super.dispose();
  }

  void _disposeRepaint() {
    if (_repaintDisposed) return;
    _repaintDisposed = true;
    _repaint.dispose();
  }

  MorphMenuMotion _prepare() {
    final current = _motion;
    if (current != null && current.isPresented) return current;
    final overlay = widget.overlay ?? Overlay.of(context);
    _overlay = overlay;
    final box = context.findRenderObject()! as RenderBox;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final button = origin & box.size;
    final padding = morphTargetPaddingOf(
      context,
      overlayBox.size,
      overlayBox: overlayBox,
    );
    if (current != null && identical(current.tuning, widget.tuning)) {
      current.relayout(
        button: button,
        bounds: overlayBox.size,
        padding: padding,
        itemCount: widget.items.length,
      );
      return current;
    }
    final motion = MorphMenuMotion(
      button: button,
      itemCount: widget.items.length,
      bounds: overlayBox.size,
      padding: padding,
      tuning: widget.tuning,
      progress: _FlightProgress(this, widget.tuning),
    );
    motion.advance(clock);
    motion.onSelected = _selected;
    _motion = motion;
    return motion;
  }

  void _launch() {
    final launchContext = _scopeContext;
    if (_disposed || launchContext == null || !launchContext.mounted) return;
    final tuning = widget.tuning;
    final flight = showMorph(
      launchContext,
      from: _tagId,
      target: MorphTargetSpec.vessel(
        rectFor: (Size size, EdgeInsets padding) =>
            _motion?.menuRect ?? Rect.zero,
      ),
      builder: (BuildContext context, MorphFlight flight) =>
          _MenuLayer(state: this, flight: flight),
      motion: MorphMotion.springs(
        name: 'menu',
        open: tuning.openSpring,
        close: tuning.closeSpring,
      ),
      maxScrimOpacity: 0,
      onDismissRequested: _dismissRequested,
      semanticLabel: widget.semanticLabel,
      overlay: _overlay,
    );
    if (identical(flight, _flight)) return;
    _flight = flight;
    flight.closed.whenComplete(() {
      if (identical(_flight, flight)) _flight = null;
      if (_disposed && _flight == null) _disposeRepaint();
    });
    widget.onOpen?.call(flight);
  }

  void _dismissRequested() {
    _motion?.close(clock);
    wake();
  }

  void _selected(int index) {
    if (index < widget.items.length) widget.items[index].onSelected?.call();
  }

  @override
  void advanceMotion(double t) {
    final motion = _motion;
    if (motion == null) return;
    motion.advance(t);
    _repaint.value++;
  }

  @override
  bool get motionSettled => _motion?.isSettled ?? true;

  Offset _local(Offset global) {
    final box = _overlay?.context.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  void _buttonDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton || _pointer != null) return;
    final current = _motion;
    if (current != null && current.isOpen) return;
    final motion = _prepare();
    _pointer = event.pointer;
    motion.pointerDown(stamp(event), _local(event.position));
  }

  void _menuDown(PointerDownEvent event) {
    final motion = _motion;
    if (motion == null || _pointer != null) return;
    if (event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    motion.pointerDown(stamp(event), _local(event.position));
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _motion?.pointerMove(stamp(event), _local(event.position));
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _motion?.pointerUp(stamp(event), _local(event.position));
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _motion?.pointerCancel(stamp(event));
  }

  void _openFromSemantics() {
    final motion = _prepare();
    motion.open(clock);
    wake();
  }

  void _selectFromSemantics(int index) {
    _motion?.select(clock, index);
    wake();
  }

  /// Whether the motion is up while no vessel shows it: after the latch
  /// the rest of the close plays on the button itself.
  bool get _landing {
    final motion = _motion;
    if (motion == null || !motion.isPresented) return false;
    final flight = _flight;
    return flight == null || !flight.isAirborne;
  }

  Widget _face(BuildContext context, MorphMenuStyle style, Widget glyph) {
    final motion = _motion;
    if (motion == null || !_landing) {
      final box = Offset.zero & Size.square(style.buttonSize);
      return _MenuShapes(
        style: style,
        glyph: glyph,
        source: RRect.fromRectAndRadius(box, Radius.circular(box.width / 2)),
        sourceRect: box,
      );
    }
    final origin = -motion.button.topLeft;
    final source = motion.buttonBlob;
    return _MenuShapes(
      style: style,
      glyph: glyph,
      menu: motion.menuBlob.rrect.shift(origin),
      source: source.rrect.shift(origin),
      sourceRect: source.rect.shift(origin),
      sourceScale: source.scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphMenuStyle.resolve(context, widget.style);
    _style = style;
    final flight = _flight;
    if (flight != null && !flight.isFinished) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!flight.isFinished) flight.markNeedsBuild();
      });
    }
    final glyph = widget.child ?? _Ellipsis(color: style.iconColor);
    final Widget button = Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: _openFromSemantics,
      child: MorphTouchListener(
        behavior: .opaque,
        onPointerDown: _buttonDown,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: SizedBox.square(
          dimension: style.buttonSize,
          child: ListenableBuilder(
            listenable: frames,
            builder: (BuildContext context, Widget? child) => Transform.scale(
              scale: _landing ? 1 : _motion?.pressScale ?? 1,
              child: child,
            ),
            child: Builder(
              builder: (BuildContext context) {
                _scopeContext = context;
                return MorphTag(
                  id: _tagId,
                  shape: const CircleBorder(),
                  surfaceColor: style.glassColor,
                  child: ListenableBuilder(
                    listenable: frames,
                    builder: (BuildContext context, Widget? _) =>
                        _face(context, style, glyph),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    if (MorphScope.maybeOf(context) != null) return button;
    return MorphScope(child: button);
  }
}

/// Both shapes of the morph and the button's look inside the shrinking
/// one, in the coordinates of the box this is laid out in; with no [menu]
/// it is the resting button.
///
/// The look fades only with a [look]: on the button (resting, or after
/// the latch, where the progress is at or under zero) it is drawn
/// without a layer, which keeps the glass of every resting button in its
/// backdrop group.
class _MenuShapes extends StatelessWidget {
  const _MenuShapes({
    required this.style,
    required this.glyph,
    required this.source,
    required this.sourceRect,
    this.menu,
    this.sourceScale = 1,
    this.lookStretch = 1,
    this.look,
    this.content,
  });

  final MorphMenuStyle style;
  final Widget glyph;
  final RRect? menu;
  final RRect source;
  final Rect sourceRect;
  final double sourceScale;
  final double lookStretch;
  final ({double opacity, double blur})? look;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final glass = MorphGlass.maybeOf(context);
    final menu = this.menu;
    final content = this.content;
    final look = this.look;
    final Widget glyph = Center(
      child: Transform.scale(
        scaleX: sourceScale * lookStretch,
        scaleY: sourceScale,
        child: this.glyph,
      ),
    );
    final Widget surfaces;
    if (glass == null) {
      surfaces = CustomPaint(
        painter: _GlassPainter(style: style, menu: menu, source: source),
      );
    } else {
      final brightness = morphBrightnessOf(context);
      surfaces = glass.buildLayer(context, [
        MorphGlassSurface(
          kind: MorphGlassKind.button,
          shape: source,
          color: style.glassColor,
          brightness: brightness,
        ),
        if (menu != null)
          MorphGlassSurface(
            kind: MorphGlassKind.menu,
            shape: menu,
            color: style.glassColor,
            brightness: brightness,
          ),
      ]);
    }
    return Stack(
      clipBehavior: .none,
      children: [
        Positioned.fill(child: surfaces),
        ?content,
        Positioned.fromRect(
          rect: sourceRect,
          child: IgnorePointer(
            child: look == null
                ? glyph
                : _Faded(opacity: look.opacity, blur: look.blur, child: glyph),
          ),
        ),
      ],
    );
  }
}

/// [child] at [opacity] and blurred by [blur], drawn through one layer.
class _Faded extends StatelessWidget {
  const _Faded({
    required this.opacity,
    required this.blur,
    required this.child,
  });

  final double opacity;
  final double blur;
  final Widget child;

  static final ui.ImageFilter _none = ui.ImageFilter.blur(
    tileMode: TileMode.decal,
  );

  @override
  Widget build(BuildContext context) {
    final blurred = blur > 0.05 && opacity > 0;
    return Opacity(
      opacity: blurred ? 1 : opacity,
      child: ImageFiltered(
        enabled: blurred,
        imageFilter: blurred
            ? ui.ImageFilter.compose(
                outer: ui.ColorFilter.matrix(<double>[
                  1, 0, 0, 0, 0, //
                  0, 1, 0, 0, 0, //
                  0, 0, 1, 0, 0, //
                  0, 0, 0, opacity, 0,
                ]),
                inner: ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.decal,
                ),
              )
            : _none,
        child: child,
      ),
    );
  }
}

/// The menu inside the vessel: both shapes, the content and the button's
/// look, laid out over the whole overlay and drawn from the motion. The
/// rows are built once per build of the vessel; every frame moves only
/// the wrappers around them.
class _MenuLayer extends StatelessWidget {
  const _MenuLayer({required this.state, required this.flight});

  final _MorphMenuButtonState state;
  final MorphFlight flight;

  @override
  Widget build(BuildContext context) {
    final style = state._style;
    final glyph = state.widget.child ?? _Ellipsis(color: style.iconColor);
    final Widget rows = RepaintBoundary(
      key: const ValueKey<String>('rows'),
      child: DefaultTextStyle(
        style: MorphTypography.resolve(style.textStyle),
        child: _MenuRows(state: state),
      ),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([state._repaint, flight.frameTicks]),
      child: rows,
      builder: (BuildContext context, Widget? rows) {
        final motion = state._motion;
        if (motion == null) return const SizedBox.shrink();
        final menu = motion.menuBlob;
        final source = motion.buttonBlob;
        final size = motion.menuRect.size;
        final scale = motion.contentScale;
        return IgnorePointer(
          ignoring: !motion.isOpen,
          child: Listener(
            behavior: .opaque,
            onPointerDown: state._menuDown,
            onPointerMove: state._move,
            onPointerUp: state._up,
            onPointerCancel: state._cancel,
            child: _MenuShapes(
              style: style,
              glyph: glyph,
              menu: menu.rrect,
              source: source.rrect,
              sourceRect: source.rect,
              sourceScale: source.scale,
              lookStretch: motion.buttonLookStretch,
              look: (
                opacity: motion.buttonLookOpacity,
                blur: motion.buttonLookBlur,
              ),
              content: Positioned.fromRect(
                rect: menu.rect,
                child: ClipRRect(
                  borderRadius: .circular(menu.radius),
                  child: OverflowBox(
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: Transform.scale(
                      scale: scale,
                      child: _Faded(
                        opacity: motion.contentOpacity,
                        blur: motion.contentBlur / scale,
                        child: SizedBox.fromSize(
                          size: size,
                          child: Stack(
                            children: [..._feedback(motion, style), rows!],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _feedback(MorphMenuMotion motion, MorphMenuStyle style) {
    final tuning = motion.tuning;
    final count = math.min(state.widget.items.length, motion.itemCount);
    final highlighted = motion.highlighted;
    final glow = motion.glowCenter;
    final glowOpacity = motion.glowOpacity;
    return [
      if (highlighted != null && highlighted < count)
        Positioned(
          left: tuning.highlightInset,
          right: tuning.highlightInset,
          top:
              tuning.verticalPadding +
              tuning.rowHeight * motion.slotOf(highlighted),
          height: tuning.rowHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: style.highlightColor,
              borderRadius: .circular(tuning.rowHeight / 2),
            ),
          ),
        ),
      if (glow != null && glowOpacity > 0)
        Positioned.fromRect(
          rect: Rect.fromCenter(
            center: _contentLocal(motion, glow),
            width: tuning.glowDiameter,
            height: tuning.glowDiameter,
          ),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: .circle,
                gradient: RadialGradient(
                  colors: [
                    style.glowColor.withValues(alpha: glowOpacity),
                    style.glowColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

/// [position] in the coordinates of the content laid out at its final
/// size, which [MorphMenuMotion.contentRect] shows scaled.
Offset _contentLocal(MorphMenuMotion motion, Offset position) {
  final frame = motion.contentRect;
  return (position - frame.topLeft) / motion.contentScale;
}

/// The rows of the menu, laid out in the open menu's frame.
class _MenuRows extends StatelessWidget {
  const _MenuRows({required this.state});

  final _MorphMenuButtonState state;

  @override
  Widget build(BuildContext context) {
    final motion = state._motion;
    if (motion == null) return const SizedBox.shrink();
    final items = state.widget.items;
    final tuning = motion.tuning;
    final count = math.min(items.length, motion.itemCount);
    final leading = items.any((MorphMenuItem item) => item.icon != null);
    return Padding(
      padding: .symmetric(vertical: tuning.verticalPadding),
      child: Column(
        children: [
          for (var slot = 0; slot < count; slot++)
            _row(motion.slotOf(slot), tuning.rowHeight, leading: leading),
        ],
      ),
    );
  }

  Widget _row(int index, double height, {required bool leading}) {
    final style = state._style;
    final item = state.widget.items[index];
    final color = item.destructive
        ? style.destructiveColor
        : style.textStyle.color ?? style.iconColor;
    final icon = item.icon;
    return Semantics(
      button: true,
      label: item.title,
      onTap: () => state._selectFromSemantics(index),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: .symmetric(horizontal: style.rowPadding),
          child: Row(
            children: [
              if (leading) ...[
                SizedBox(
                  width: 2 * style.rowPadding,
                  child: icon == null
                      ? null
                      : Center(
                          child: Icon(icon, size: style.iconSize, color: color),
                        ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MorphTypography.resolve(
                    style.textStyle,
                  ).copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glass of both shapes as one union, or the resting button when
/// there is no [menu].
class _GlassPainter extends CustomPainter {
  const _GlassPainter({required this.style, required this.source, this.menu});

  final MorphMenuStyle style;
  final RRect source;
  final RRect? menu;

  @override
  void paint(Canvas canvas, Size size) {
    final menu = this.menu;
    final shape = Path();
    shape.addRRect(source);
    if (menu != null) shape.addRRect(menu);
    canvas.drawShadow(shape, style.shadowColor, style.shadowElevation, true);
    final fill = Paint();
    fill.color = style.glassColor;
    canvas.drawPath(shape, fill);
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) =>
      oldDelegate.menu != menu ||
      oldDelegate.source != source ||
      oldDelegate.style != style;
}

class _Ellipsis extends StatelessWidget {
  const _Ellipsis({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: CustomPaint(painter: _EllipsisPainter(color)),
    );
  }
}

class _EllipsisPainter extends CustomPainter {
  const _EllipsisPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    final center = size.center(Offset.zero);
    for (final dx in const [-7.0, 0.0, 7.0]) {
      canvas.drawCircle(center + Offset(dx, 0), 2.2, paint);
    }
  }

  @override
  bool shouldRepaint(_EllipsisPainter oldDelegate) =>
      oldDelegate.color != color;
}
