import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/src/widgets/search_motion.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// The look of a [MorphSearchField] and a [MorphSearchToolbar].
@immutable
class MorphSearchFieldStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphSearchFieldStyle({
    this.capsuleColor = const Color(0xD9FFFFFF),
    this.rimColor = const Color(0x1F000000),
    this.shadowColor = const Color(0x1A000000),
    this.textColor = const Color(0xFF000000),
    this.placeholderColor = const Color(0x993C3C43),
    this.restingPlaceholderColor = const Color(0x69000000),
    this.glyphColor = const Color(0xFF000000),
    this.clearColor = const Color(0xFF000000),
    this.clearGlyphColor = const Color(0xFFFFFFFF),
    this.cursorColor = const Color(0xFF426AF3),
    this.disabledFillColor = const Color(0x0F767680),
  });

  /// The flat stand-in for the field's glass when no [MorphGlassPainter]
  /// is installed; a painter receives it as the tint.
  final Color capsuleColor;

  /// The outline of the flat capsule.
  final Color rimColor;

  /// The shadow of the flat capsule.
  final Color shadowColor;

  /// The color of the typed text: label.
  final Color textColor;

  /// The color of the placeholder while the field has the focus:
  /// secondaryLabel.
  final Color placeholderColor;

  /// The color of the placeholder while the field does not have the
  /// focus: lighter than [placeholderColor] on the glass (an iPhone 16
  /// Pro's screen: 149 on 252 light, 110 on 32 dark, where the focused
  /// placeholder reads 133 and 142).
  final Color restingPlaceholderColor;

  /// The color of the magnifier and of the close button's cross.
  final Color glyphColor;

  /// The fill of the clear button.
  final Color clearColor;

  /// The cross of the clear button.
  final Color clearGlyphColor;

  /// The color of the text cursor (an iPhone 16 Pro's screen: 66, 106,
  /// 243 light and 64, 107, 248 dark, bluer than the accent).
  final Color cursorColor;

  /// The flat fill that replaces the glass of a disabled field: UIKit's
  /// disabled UISearchTextField drops its glass, rim and lift for a plain
  /// 0x767680 fill at 6 percent in light and 12 percent in dark (iPhone 16
  /// Pro, iOS 27.0.1); the magnifier and the placeholder keep their
  /// colors.
  final Color disabledFillColor;

  /// The light appearance.
  static const light = MorphSearchFieldStyle();

  /// The dark appearance.
  static const dark = MorphSearchFieldStyle(
    capsuleColor: Color(0xB82C2C2E),
    rimColor: Color(0x33FFFFFF),
    shadowColor: Color(0x40000000),
    textColor: Color(0xFFFFFFFF),
    placeholderColor: Color(0x8AEBEBF5),
    restingPlaceholderColor: Color(0x59FFFFFF),
    glyphColor: Color(0xFFFFFFFF),
    clearColor: Color(0xFFFFFFFF),
    clearGlyphColor: Color(0xFF000000),
    cursorColor: Color(0xFF406BF8),
    disabledFillColor: Color(0x1F767680),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphSearchFieldStyle resolve(
    BuildContext context,
    MorphSearchFieldStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.searchField,
    light: light,
    dark: dark,
  );
}

/// The iOS 27 search field: a glass capsule with a magnifier, the text
/// and a clear button.
///
/// The capsule is 48 points tall. A touch lifts it like a glass button of
/// its size, [MorphSearchTuning.pressDelay] after the contact, and a tap
/// focuses it; the clear button shows while there is text and empties
/// the field. Place it wherever a search field belongs; for the bottom
/// placement UIKit uses on an iPhone, with the focus transition, use
/// [MorphSearchToolbar].
///
/// Labels follow the text scale up to [maxTextScale]. Screen readers see
/// a text field labelled [semanticLabel] (the placeholder by default).
///
/// A disabled field ([enabled] false) is a flat fill without glass
/// ([MorphSearchFieldStyle.disabledFillColor]); it neither lifts nor takes
/// the focus. The change shows in one frame.
class MorphSearchField extends StatefulWidget {
  /// Creates a search field.
  const MorphSearchField({
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.style,
    this.semanticLabel,
    this.clearLabel = 'Clear text',
    super.key,
  });

  /// The controller of the text; null keeps one inside.
  final TextEditingController? controller;

  /// The focus node of the text; null keeps one inside.
  final FocusNode? focusNode;

  /// The text shown while the field is empty.
  final String placeholder;

  /// Called whenever the text changes.
  final ValueChanged<String>? onChanged;

  /// Called when the keyboard's search key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the field takes the focus when it first shows.
  final bool autofocus;

  /// The look; null resolves it from the theme.
  final MorphSearchFieldStyle? style;

  /// The label screen readers announce; defaults to [placeholder].
  final String? semanticLabel;

  /// The label screen readers announce for the clear button.
  final String clearLabel;

  /// The largest text scale the text follows.
  static const double maxTextScale = 1.5;

  @override
  State<MorphSearchField> createState() => _MorphSearchFieldState();
}

class _MorphSearchFieldState extends State<MorphSearchField>
    with
        SingleTickerProviderStateMixin<MorphSearchField>,
        MorphClock<MorphSearchField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  final MorphSearchMotion _motion = MorphSearchMotion();
  final ValueNotifier<bool> _settled = ValueNotifier<bool>(true);
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);
  final GlobalKey<EditableTextState> _editable = GlobalKey<EditableTextState>();
  Offset? _downAt;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _focus =>
      widget.focusNode ??
      (_ownFocus ??= FocusNode(debugLabel: 'MorphSearchField'));

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editable;

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => widget.enabled && _focus.hasFocus;

  @override
  void advanceMotion(double t) {
    _motion.advance(t);
    _settled.value = _motion.isSettled;
  }

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void didUpdateWidget(MorphSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      if (_focus.hasFocus) _focus.unfocus();
      _downAt = null;
      _motion.pointerCancel(clock);
      wake();
    }
  }

  @override
  void dispose() {
    _settled.dispose();
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || event.buttons != kPrimaryButton) return;
    _downAt = event.position;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) _motion.size = box.size;
    _motion.reducedMotion = morphReducedMotionOf(context);
    _motion.pointerDown(stamp(event));
  }

  void _up(PointerEvent event) {
    final from = _downAt;
    _downAt = null;
    if (event is PointerUpEvent &&
        from != null &&
        widget.enabled &&
        !_focus.hasFocus &&
        (event.position - from).distance < kTouchSlop) {
      _focus.requestFocus();
    }
    if (!_motion.isPressed) return;
    _motion.pointerUp(stamp(event));
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphSearchFieldStyle.resolve(context, widget.style);
    final glass = MorphGlass.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: MorphSearchField.maxTextScale);
    final text = MorphTypography.resolve(
      MorphTypography.searchField.copyWith(height: 1.2, color: style.textColor),
    );
    final editable = EditableText(
      key: _editable,
      controller: _controller,
      focusNode: _focus,
      readOnly: !widget.enabled,
      autofocus: widget.autofocus,
      style: text,
      textScaler: scaler,
      cursorColor: style.cursorColor,
      backgroundCursorColor: style.placeholderColor,
      selectionColor: style.cursorColor.withValues(alpha: 0.25),
      maxLines: 1,
      textInputAction: TextInputAction.search,
      keyboardAppearance: brightness,
      textCapitalization: TextCapitalization.sentences,
      rendererIgnoresPointer: true,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
    final content = Padding(
      padding: const EdgeInsetsDirectional.only(
        start: MorphSearchTuning.glyphInset,
      ),
      child: Row(
        children: [
          SizedBox.fromSize(
            size: MorphSearchTuning.glyphSize,
            child: CustomPaint(
              painter: _MagnifierPainter(color: style.glyphColor),
            ),
          ),
          SizedBox(
            width:
                MorphSearchTuning.textInset -
                MorphSearchTuning.glyphInset -
                MorphSearchTuning.glyphSize.width,
          ),
          Expanded(
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                ListenableBuilder(
                  listenable: Listenable.merge([_controller, _focus]),
                  builder: (BuildContext context, Widget? _) =>
                      _controller.text.isEmpty
                      ? ExcludeSemantics(
                          child: Text(
                            widget.placeholder,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            textScaler: scaler,
                            style: text.copyWith(
                              color: _focus.hasFocus
                                  ? style.placeholderColor
                                  : style.restingPlaceholderColor,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Semantics(
                  label: widget.semanticLabel ?? widget.placeholder,
                  child: widget.enabled
                      ? _gestures.buildGestureDetector(
                          behavior: HitTestBehavior.translucent,
                          child: editable,
                        )
                      : IgnorePointer(child: ExcludeFocus(child: editable)),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (BuildContext context, Widget? child) =>
                _controller.text.isEmpty
                ? const SizedBox(width: MorphSearchTuning.clearInset)
                : child!,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 8,
                end: MorphSearchTuning.clearInset,
              ),
              child: Semantics(
                button: true,
                label: widget.clearLabel,
                onTap: widget.enabled ? _clear : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.enabled ? _clear : null,
                  child: SizedBox.square(
                    dimension: MorphSearchTuning.clearSize,
                    child: CustomPaint(
                      painter: _ClearPainter(
                        fill: style.clearColor,
                        cross: style.clearGlyphColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return DefaultTextStyle(
      style: text,
      child: MorphTouchListener(
        enabled: widget.enabled && !_focus.hasFocus,
        delaysInScrollable: true,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? _focus.requestFocus : null,
          child: ListenableBuilder(
            listenable: frames,
            builder: (BuildContext context, Widget? child) => Transform.scale(
              scale: widget.enabled ? _motion.pressScale(_motion.time) : 1,
              child: child,
            ),
            child: SizedBox(
              height: MorphSearchTuning.height,
              child: widget.enabled
                  ? MorphControlCapsule(
                      painter: glass,
                      frames: _settled,
                      still: () => _settled.value,
                      color: style.capsuleColor,
                      rim: style.rimColor,
                      shadow: style.shadowColor,
                      brightness: brightness,
                      enabled: widget.enabled,
                      child: content,
                    )
                  : CustomPaint(
                      painter: _FlatPainter(style.disabledFillColor),
                      child: content,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

RRect _capsule(Size size) => RRect.fromRectAndRadius(
  Offset.zero & size,
  Radius.circular(math.min(size.width, size.height) / 2),
);

class _FlatPainter extends CustomPainter {
  const _FlatPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    fill.color = color;
    canvas.drawRRect(_capsule(size), fill);
  }

  @override
  bool shouldRepaint(_FlatPainter oldDelegate) => oldDelegate.color != color;
}

class _MagnifierPainter extends CustomPainter {
  const _MagnifierPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      morphPaintMagnifier(canvas, size, color);

  @override
  bool shouldRepaint(_MagnifierPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Paints the search field's magnifier into a box of [size], as SF
/// Symbols' `magnifyingglass` reads on an iPhone 16 Pro's screen in a
/// [MorphSearchTuning.glyphSize] box: a ring 13.33 points across drawn
/// 1.75 thick, its center 8.67 and 7.67 points in from the box's top
/// left, and a handle out to 17.4 and 16.7; all of it scales with the box.
@internal
void morphPaintMagnifier(Canvas canvas, Size size, Color color) {
  const box = MorphSearchTuning.glyphSize;
  final k = math.min(size.width / box.width, size.height / box.height);
  final origin = Offset(
    (size.width - box.width * k) / 2,
    (size.height - box.height * k) / 2,
  );
  final paint = Paint();
  paint.color = color;
  paint.style = PaintingStyle.stroke;
  paint.strokeWidth = 1.75 * k;
  paint.strokeCap = StrokeCap.round;
  final c = origin + const Offset(8.67, 7.67) * k;
  final r = (13.33 - 1.75) / 2 * k;
  canvas.drawCircle(c, r, paint);
  final d = r * 0.7071;
  canvas.drawLine(
    c + Offset(d, d),
    origin + const Offset(17.4, 16.7) * k,
    paint,
  );
}

class _ClearPainter extends CustomPainter {
  const _ClearPainter({required this.fill, required this.cross});

  final Color fill;
  final Color cross;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r =
        math.min(size.width, size.height) /
        2 *
        MorphSearchTuning.clearInk /
        MorphSearchTuning.clearSize;
    final paint = Paint();
    paint.color = fill;
    canvas.drawCircle(c, r, paint);
    final x = Paint();
    x.color = cross;
    x.style = PaintingStyle.stroke;
    x.strokeWidth = r * 0.2;
    x.strokeCap = StrokeCap.round;
    final d = r * 0.36;
    canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), x);
    canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), x);
  }

  @override
  bool shouldRepaint(_ClearPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.cross != cross;
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => morphPaintCross(canvas, size, color);

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.color != color;
}

/// Paints the close button's cross centered in a box of [size]: two
/// strokes [MorphSearchTuning.closeStroke] thick whose ink, round caps
/// included, fills a square [MorphSearchTuning.closeInk] points across.
@internal
void morphPaintCross(Canvas canvas, Size size, Color color) {
  const ink = MorphSearchTuning.closeInk;
  const stroke = MorphSearchTuning.closeStroke;
  final paint = Paint();
  paint.color = color;
  paint.style = PaintingStyle.stroke;
  paint.strokeWidth = stroke;
  paint.strokeCap = StrokeCap.round;
  final c = size.center(Offset.zero);
  const h = (ink - stroke) / 2;
  canvas.drawLine(c + const Offset(-h, -h), c + const Offset(h, h), paint);
  canvas.drawLine(c + const Offset(h, -h), c + const Offset(-h, h), paint);
}

/// The bottom-placed search bar of iOS 27: a search field in the toolbar
/// that expands above the keyboard when it is focused.
///
/// At rest the field fills the room between the [leading] and [trailing]
/// toolbar buttons, each in its own 48 point glass circle, 28 points from
/// the screen's sides and bottom. Focusing the field starts the search:
/// once the keyboard starts to rise (as UIKit waits for it, at most
/// [MorphSearchTuning.keyboardWaitLimit]), on one spring
/// ([MorphSearchMotion]) the field widens to 8 points from
/// the sides and rises to 10 points above the keyboard, the other buttons
/// swell to 1.2 and fade where they stand, and a close button arrives
/// next to the field. The close button (or Escape) ends the search: the
/// text clears, the keyboard leaves, the close button fades where it
/// stands and the buttons come back from where the focused layout puts
/// them without a keyboard. Tapping elsewhere leaves the search active,
/// as in UIKit.
///
/// Place it in a [Stack] that fills the screen, with [Positioned.fill]:
/// it takes hits only on its own glass.
class MorphSearchToolbar extends StatefulWidget {
  /// Creates the bar.
  const MorphSearchToolbar({
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    this.leading = const [],
    this.trailing = const [],
    this.onChanged,
    this.onSubmitted,
    this.onActiveChanged,
    this.style,
    this.buttonStyle,
    this.closeLabel = 'Close',
    super.key,
  });

  /// The controller of the text; null keeps one inside.
  final TextEditingController? controller;

  /// The focus node of the text; null keeps one inside.
  final FocusNode? focusNode;

  /// The text shown while the field is empty.
  final String placeholder;

  /// The toolbar buttons before the field, shown at rest.
  final List<MorphBarButton> leading;

  /// The toolbar buttons after the field, shown at rest.
  final List<MorphBarButton> trailing;

  /// Called whenever the text changes.
  final ValueChanged<String>? onChanged;

  /// Called when the keyboard's search key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Called when the search starts (true) or ends (false).
  final ValueChanged<bool>? onActiveChanged;

  /// The look of the field; null resolves it from the theme.
  final MorphSearchFieldStyle? style;

  /// The look of the toolbar buttons and the close button; null resolves
  /// it from the theme.
  final MorphGlassButtonStyle? buttonStyle;

  /// The label screen readers announce for the close button.
  final String closeLabel;

  @override
  State<MorphSearchToolbar> createState() => _MorphSearchToolbarState();
}

class _MorphSearchToolbarState extends State<MorphSearchToolbar>
    with
        SingleTickerProviderStateMixin<MorphSearchToolbar>,
        MorphClock<MorphSearchToolbar> {
  final MorphSearchMotion _motion = MorphSearchMotion();
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  FocusNode? _listening;
  Rect? _frozenClose;
  double? _frozenKeyboard;
  Rect _lastClose = Rect.zero;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _focus =>
      widget.focusNode ??
      (_ownFocus ??= FocusNode(debugLabel: 'MorphSearchToolbar'));

  double? _keyboardWait;

  @override
  void advanceMotion(double t) {
    final wait = _keyboardWait;
    if (wait != null && t - wait >= MorphSearchTuning.keyboardWaitLimit) {
      _keyboardWait = null;
      _motion.focus(t, delay: 0);
    }
    _motion.advance(t);
  }

  @override
  bool get motionSettled => _motion.isSettled && _keyboardWait == null;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(MorphSearchToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
  }

  void _listen() {
    final node = _focus;
    if (identical(node, _listening)) return;
    _listening?.removeListener(_focusChanged);
    _listening = node;
    node.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _listening?.removeListener(_focusChanged);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (_focus.hasFocus && !_motion.isFocused && _keyboardWait == null) {
      _frozenClose = null;
      _frozenKeyboard = null;
      final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
      if (keyboard > 0) {
        _motion.focus(clock);
      } else {
        _keyboardWait = clock;
      }
      wake();
      setState(() {});
      widget.onActiveChanged?.call(true);
    }
  }

  void _end() {
    if (!_motion.isFocused && _keyboardWait == null) return;
    _keyboardWait = null;
    _frozenClose = _lastClose;
    _frozenKeyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    _motion.unfocus(clock);
    _controller.clear();
    widget.onChanged?.call('');
    _focus.unfocus();
    wake();
    setState(() {});
    widget.onActiveChanged?.call(false);
  }

  double _buttonWidth(MorphBarButton button, TextDirection direction) =>
      math.max(
        MorphSearchTuning.height,
        morphBarContentWidth(
          button,
          MorphBarMetrics.toolbar,
          MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25),
          direction,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final rtl = direction == TextDirection.rtl;
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    if (_keyboardWait != null && keyboard > 0) {
      _keyboardWait = null;
      _motion.focus(clock, delay: MorphSearchTuning.keyboardLag);
      wake();
    }
    final leadWidths = [
      for (final b in widget.leading) _buttonWidth(b, direction),
    ];
    final trailWidths = [
      for (final b in widget.trailing) _buttonWidth(b, direction),
    ];
    final field = MorphSearchField(
      controller: _controller,
      focusNode: _focus,
      placeholder: widget.placeholder,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: widget.style,
    );
    final close = _GlassItem(
      button: MorphBarButton(
        id: 'morph.search.close',
        icon: SizedBox.fromSize(
          size: MorphSearchTuning.closeGlyphSize,
          child: CustomPaint(
            painter: _CrossPainter(
              color: MorphSearchFieldStyle.resolve(
                context,
                widget.style,
              ).glyphColor,
            ),
          ),
        ),
        onPressed: _end,
        semanticLabel: widget.closeLabel,
      ),
      style: widget.buttonStyle,
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _end,
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final size = constraints.biggest;
          final rest = morphSearchBarLayout(
            width: size.width,
            bottom: size.height - MorphSearchTuning.restInset,
            focused: false,
            leading: leadWidths,
            trailing: trailWidths,
            rtl: rtl,
          );
          final focused = morphSearchBarLayout(
            width: size.width,
            bottom:
                size.height -
                (_motion.isFocused ? keyboard : _frozenKeyboard ?? keyboard) -
                MorphSearchTuning.keyboardGap,
            focused: true,
            leading: leadWidths,
            trailing: trailWidths,
            rtl: rtl,
          );
          final virtual = morphSearchBarLayout(
            width: size.width,
            bottom: size.height - MorphSearchTuning.keyboardGap,
            focused: true,
            leading: leadWidths,
            trailing: trailWidths,
            rtl: rtl,
          );
          return ListenableBuilder(
            listenable: frames,
            builder: (BuildContext context, Widget? _) {
              final p = _motion.progress(_motion.time);
              final focusing = _motion.isFocused;
              final fieldRect = Rect.lerp(rest.field, focused.field, p)!;
              final closeRect =
                  _frozenClose ?? Rect.lerp(rest.close, focused.close, p)!;
              _lastClose = closeRect;
              Rect side(Rect atRest, Rect atFocus) =>
                  focusing ? atRest : Rect.lerp(atFocus, atRest, 1 - p)!;
              final items = <Widget>[
                for (var i = 0; i < widget.leading.length; i++)
                  _placed(
                    side(rest.leading[i], virtual.leading[i]),
                    1 - p,
                    _GlassItem(
                      button: widget.leading[i],
                      style: widget.buttonStyle,
                    ),
                    key: ValueKey<Object>(('lead', widget.leading[i].id)),
                    interactive: !focusing,
                  ),
                for (var i = 0; i < widget.trailing.length; i++)
                  _placed(
                    side(rest.trailing[i], virtual.trailing[i]),
                    1 - p,
                    _GlassItem(
                      button: widget.trailing[i],
                      style: widget.buttonStyle,
                    ),
                    key: ValueKey<Object>(('trail', widget.trailing[i].id)),
                    interactive: !focusing,
                  ),
                if (p > 0.001 || focusing)
                  _placed(
                    closeRect,
                    p,
                    close,
                    key: const ValueKey<String>('close'),
                    interactive: focusing,
                  ),
              ];
              return MorphGlassStage(
                open: p <= 0 && !focusing,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fromRect(
                      key: const ValueKey<String>('field'),
                      rect: fieldRect,
                      child: field,
                    ),
                    ...items,
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _placed(
    Rect rect,
    double presence,
    Widget child, {
    required Key key,
    required bool interactive,
  }) {
    final p = presence.clamp(0.0, 1.0);
    Widget out = Transform.scale(
      scale: MorphSearchMotion.appearScaleFor(p),
      child: child,
    );
    final blur = MorphSearchMotion.appearBlurFor(p);
    if (blur > 0.05) {
      out = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: blur / 2,
          sigmaY: blur / 2,
          tileMode: TileMode.decal,
        ),
        child: out,
      );
    }
    out = MorphGlassStageFade(opacity: p, child: out);
    if (!interactive || p < 0.01) {
      out = IgnorePointer(child: ExcludeSemantics(child: out));
    }
    return Positioned.fromRect(key: key, rect: rect, child: out);
  }
}

class _GlassItem extends StatelessWidget {
  const _GlassItem({required this.button, required this.style});

  final MorphBarButton button;
  final MorphGlassButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = button.label;
    return Semantics(
      label: button.semanticLabel ?? label,
      excludeSemantics: true,
      button: true,
      enabled: button.enabled && button.onPressed != null,
      onTap: button.enabled ? button.onPressed : null,
      child: MorphGlassButton(
        onPressed: button.enabled ? button.onPressed : null,
        padding: EdgeInsets.zero,
        minSize: const Size.square(MorphSearchTuning.height),
        style: style,
        child: label == null
            ? button.icon!
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Text(label, maxLines: 1),
              ),
      ),
    );
  }
}
