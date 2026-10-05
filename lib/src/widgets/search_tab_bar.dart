import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/chrome_group.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/search_field.dart';
import 'package:morph/src/widgets/search_motion.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/tab_bar.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// A floating [MorphTabBar] with a search tab that turns into a search
/// field, as iOS 27 shows a UITabBarController whose UISearchTab activates
/// search.
///
/// At rest the tab bar floats 21 points from the leading side and the
/// bottom, and the search tab is a separate glass circle at the trailing
/// side. Tapping the circle asks to start searching through
/// [onSearchingChanged]; with [searching] true, on
/// [MorphSearchTuning.tabSpring], the tab bar shrinks into a circle that
/// keeps the selected tab's glyph while the other tabs fade, and the search
/// circle stretches into a search field whose placeholder fades in; the
/// field takes the focus [MorphSearchTuning.tabActivationDelay] after the
/// tap, while the morph still runs, and, once the keyboard starts to rise,
/// rises above it on [MorphSearchTuning.tabFocusSpring] with a close
/// button, like [MorphSearchToolbar], while the tab circle (which the
/// keyboard covers in UIKit) fades. The close button (or Escape) ends the
/// focus and clears the text, and the field falls straight back to its
/// place above the tab circle as the keyboard leaves; tapping the tab
/// circle asks to stop searching, and the field turns back into the
/// circle. The tab circle takes the tap while the morph into the field
/// still runs (the morph turns around with its velocity, as UIKit's does)
/// until the keyboard covers it; the search circle ignores taps until the
/// morph back to the bar has settled, as UIKit's does.
///
/// This is UIKit's search tab with `automaticallyActivatesSearch`: only
/// then does iOS 27 set the search tab apart as a circle. A search tab
/// that waits for a tap on its field is an ordinary tab inside the bar
/// (a [MorphTabItem] of [MorphTabBar]).
///
/// The edges were measured at both ends and their timing fitted to video
/// of the real morph; the path between is a straight interpolation of the
/// glass on one spring.
///
/// Place it in a [Stack] that fills the screen, with [Positioned.fill]:
/// it takes hits only on its own glass.
class MorphSearchTabBar extends StatefulWidget {
  /// Creates the bar.
  const MorphSearchTabBar({
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.searching,
    required this.onSearchingChanged,
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    this.onQueryChanged,
    this.onSubmitted,
    this.searchLabel = 'Search',
    this.closeLabel = 'Close',
    this.style,
    this.searchStyle,
    super.key,
  });

  /// The tabs, two to four, besides the search tab.
  final List<MorphTabItem> items;

  /// The index of the selected tab.
  final int selected;

  /// Called with the new index when the user selects a tab.
  final ValueChanged<int>? onChanged;

  /// Whether the search tab is active: the field shows instead of the
  /// tabs.
  final bool searching;

  /// Called when the user asks to start (true) or stop (false) searching.
  final ValueChanged<bool> onSearchingChanged;

  /// The controller of the query; null keeps one inside.
  final TextEditingController? controller;

  /// The focus node of the query; null keeps one inside.
  final FocusNode? focusNode;

  /// The text shown while the field is empty.
  final String placeholder;

  /// Called whenever the query changes.
  final ValueChanged<String>? onQueryChanged;

  /// Called when the keyboard's search key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// The label screen readers announce for the search tab.
  final String searchLabel;

  /// The label screen readers announce for the close button.
  final String closeLabel;

  /// The look of the tab bar; null resolves it from the theme.
  final MorphTabBarStyle? style;

  /// The look of the search field; null resolves it from the theme.
  final MorphSearchFieldStyle? searchStyle;

  @override
  State<MorphSearchTabBar> createState() => _MorphSearchTabBarState();
}

class _MorphSearchTabBarState extends State<MorphSearchTabBar>
    with
        SingleTickerProviderStateMixin<MorphSearchTabBar>,
        MorphClock<MorphSearchTabBar> {
  final MorphSpringState _morph = MorphSpringState(
    MorphSearchTuning.tabSpring,
    0,
  );
  final MorphSearchMotion _focusMotion = MorphSearchMotion(
    spring: MorphSearchTuning.tabFocusSpring,
  );
  double? _keyboardWait;
  double? _frozenKeyboard;
  final GlobalKey _bar = GlobalKey();
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  FocusNode? _listening;
  double _now = 0;
  double? _barWidth;

  static const MorphSpring _spring = MorphSearchTuning.tabSpring;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _focus =>
      widget.focusNode ??
      (_ownFocus ??= FocusNode(debugLabel: 'MorphSearchTabBar'));

  @override
  void advanceMotion(double t) {
    if (t > _now) _now = t;
    final wait = _keyboardWait;
    if (wait != null && t - wait >= MorphSearchTuning.keyboardWaitLimit) {
      _keyboardWait = null;
      _focusMotion.focus(t, delay: 0);
    }
    _focusMotion.advance(t);
    final activate = _activateAt;
    if (activate != null && t >= activate) {
      _activateAt = null;
      if (widget.searching && !_focus.hasFocus) _focus.requestFocus();
    }
  }

  double? _activateAt;

  @override
  bool get motionSettled =>
      _morph.isAtRest(_now, 0.001) &&
      _focusMotion.isSettled &&
      _keyboardWait == null &&
      _activateAt == null;

  @override
  void initState() {
    super.initState();
    if (widget.searching) _morph.snap(0, 1);
    _listen();
  }

  @override
  void didUpdateWidget(MorphSearchTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
    if (oldWidget.searching != widget.searching) {
      _morph.retarget(clock, widget.searching ? 1 : 0, spring: _spring);
      _activateAt = widget.searching
          ? clock + MorphSearchTuning.tabActivationDelay
          : null;
      if (!widget.searching) {
        _controller.clear();
        _focus.unfocus();
      }
      wake();
    }
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
    if (_focus.hasFocus && !_focusMotion.isFocused && _keyboardWait == null) {
      _frozenKeyboard = null;
      final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
      if (keyboard > 0) {
        _focusMotion.focus(clock, delay: MorphSearchTuning.tabKeyboardLag);
      } else {
        _keyboardWait = clock;
      }
      wake();
      setState(() {});
    } else if (!_focus.hasFocus &&
        (_focusMotion.isFocused || _keyboardWait != null)) {
      _keyboardWait = null;
      _frozenKeyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
      _focusMotion.unfocus(clock, delay: MorphSearchTuning.tabUnfocusDelay);
      wake();
      setState(() {});
    }
  }

  void _close() {
    _controller.clear();
    widget.onQueryChanged?.call('');
    _focus.unfocus();
  }

  double _fallbackBarWidth() {
    final count = widget.items.length;
    return MorphTabBarMetrics.geometry(count, 0).width;
  }

  void _measureBar() {
    final box = _bar.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.size.width != _barWidth) {
      setState(() => _barWidth = box.size.width);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.isEmpty
        ? -1
        : widget.selected.clamp(0, widget.items.length - 1);
    final tabStyle = MorphTabBarStyle.resolve(context, widget.style);
    final searchStyle = MorphSearchFieldStyle.resolve(
      context,
      widget.searchStyle,
    );
    final glass = MorphGlass.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final rtl = direction == TextDirection.rtl;
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    if (_keyboardWait != null && keyboard > 0) {
      _keyboardWait = null;
      _focusMotion.focus(clock, delay: MorphSearchTuning.tabKeyboardLag);
      wake();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureBar();
    });
    final bar = MorphTabBar(
      key: _bar,
      items: widget.items,
      selected: selected,
      onChanged: widget.onChanged,
      style: widget.style,
    );
    final field = MorphSearchField(
      controller: _controller,
      focusNode: _focus,
      placeholder: widget.placeholder,
      onChanged: widget.onQueryChanged,
      onSubmitted: widget.onSubmitted,
      style: widget.searchStyle,
    );
    final shortcuts = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final geometry = morphSearchTabLayout(
            size: constraints.biggest,
            barWidth: _barWidth ?? _fallbackBarWidth(),
            keyboard: _focusMotion.isFocused
                ? keyboard
                : _frozenKeyboard ?? keyboard,
            rtl: rtl,
          );
          return ListenableBuilder(
            listenable: frames,
            builder: (BuildContext context, Widget? _) {
              final q = _morph.value(_now);
              final p = _focusMotion.progress(_now);
              final resting = q.abs() < 0.001 && !widget.searching;
              final settled = (q - 1).abs() < 0.001 && widget.searching;
              final barRect = Rect.lerp(geometry.bar, geometry.tab, q)!;
              final searchRect = Rect.lerp(
                geometry.search,
                Rect.lerp(geometry.field, geometry.focusedField, p),
                q,
              )!;
              final closeRect = Rect.lerp(
                Rect.fromLTWH(
                  geometry.field.right - MorphSearchTuning.height,
                  geometry.field.top,
                  MorphSearchTuning.height,
                  MorphSearchTuning.height,
                ),
                geometry.close,
                p,
              )!;
              final children = <Widget>[];
              if (resting) {
                children.add(
                  Positioned(
                    key: const ValueKey<String>('bar'),
                    left: geometry.bar.left,
                    top: geometry.bar.top,
                    child: bar,
                  ),
                );
              } else if (widget.items.isNotEmpty) {
                children.add(
                  Positioned.fromRect(
                    key: const ValueKey<String>('tab'),
                    rect: barRect,
                    child: IgnorePointer(
                      ignoring: !widget.searching || p >= 0.5,
                      child: Opacity(
                        opacity: (1 - p).clamp(0.0, 1.0),
                        child: _MorphingTabs(
                          items: widget.items,
                          selected: selected,
                          progress: q,
                          restRect: geometry.bar,
                          rect: barRect,
                          style: tabStyle,
                          glass: glass,
                          brightness: brightness,
                          rtl: rtl,
                          label: widget.items[selected].label,
                          onTap: () => widget.onSearchingChanged(false),
                        ),
                      ),
                    ),
                  ),
                );
              }
              if (!settled) {
                children.add(
                  Positioned.fromRect(
                    key: const ValueKey<String>('search'),
                    rect: searchRect,
                    child: IgnorePointer(
                      ignoring: !resting,
                      child: _SearchCircle(
                        progress: q,
                        rect: searchRect,
                        restRect: geometry.search,
                        placeholder: widget.placeholder,
                        label: widget.searchLabel,
                        style: searchStyle,
                        tabStyle: tabStyle,
                        glass: glass,
                        brightness: brightness,
                        rtl: rtl,
                        onTap: () => widget.onSearchingChanged(true),
                      ),
                    ),
                  ),
                );
              }
              if (widget.searching || settled) {
                children.add(
                  Positioned.fromRect(
                    key: const ValueKey<String>('field'),
                    rect: searchRect,
                    child: IgnorePointer(
                      ignoring: !settled,
                      child: Opacity(
                        opacity: settled ? 1 : 0,
                        alwaysIncludeSemantics: true,
                        child: field,
                      ),
                    ),
                  ),
                );
              }
              if (settled && (p > 0.001 || _focusMotion.isFocused)) {
                children.add(
                  Positioned.fromRect(
                    key: const ValueKey<String>('close'),
                    rect: closeRect,
                    child: IgnorePointer(
                      ignoring: !_focusMotion.isFocused,
                      child: Opacity(
                        opacity: p.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: MorphSearchMotion.appearScaleFor(p),
                          child: _RoundGlassButton(
                            label: widget.closeLabel,
                            onPressed: _close,
                            child: _CrossGlyph(color: searchStyle.glyphColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Stack(clipBehavior: Clip.none, children: children);
            },
          );
        },
      ),
    );
    return MorphChromeBackdrop(child: shortcuts);
  }
}

class _MorphingTabs extends StatelessWidget {
  const _MorphingTabs({
    required this.items,
    required this.selected,
    required this.progress,
    required this.restRect,
    required this.rect,
    required this.style,
    required this.glass,
    required this.brightness,
    required this.rtl,
    required this.label,
    required this.onTap,
  });

  final List<MorphTabItem> items;
  final int selected;
  final double progress;
  final Rect restRect;
  final Rect rect;
  final MorphTabBarStyle style;
  final MorphGlassPainter? glass;
  final Brightness brightness;
  final bool rtl;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = progress.clamp(0.0, 1.0);
    final pitch =
        (restRect.width - 2 * MorphTabBarMetrics.sideInset) / items.length;
    final shape = RRect.fromRectAndRadius(
      Offset.zero & rect.size,
      Radius.circular(math.min(rect.width, rect.height) / 2),
    );
    final fade = (1 - q * 2).clamp(0.0, 1.0);
    final selectedCenter = Offset(
      MorphTabBarMetrics.sideInset +
          pitch * (rtl ? items.length - 1 - selected + 0.5 : selected + 0.5),
      restRect.height / 2,
    );
    final iconCenter = Offset.lerp(
      selectedCenter - (rect.topLeft - restRect.topLeft),
      rect.size.center(Offset.zero),
      q,
    )!;
    final iconColor = Color.lerp(style.selectedColor, style.color, q)!;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: glass == null
                  ? CustomPaint(
                      painter: _BodyPainter(
                        shape: shape,
                        color: style.barColor,
                        shadow: style.shadowColor,
                      ),
                    )
                  : glass!.buildSurface(
                      context,
                      MorphGlassSurface(
                        kind: MorphGlassKind.bar,
                        shape: shape,
                        color: style.barColor,
                        brightness: brightness,
                      ),
                    ),
            ),
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(shape.tlRadiusX),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      if (i != selected)
                        Positioned(
                          left:
                              restRect.left -
                              rect.left +
                              MorphTabBarMetrics.sideInset +
                              pitch * (rtl ? items.length - 1 - i : i),
                          top: restRect.top - rect.top,
                          width: pitch,
                          height: restRect.height,
                          child: Opacity(
                            opacity: fade,
                            child: _TabGlyph(
                              item: items[i],
                              color: style.color,
                              showLabel: true,
                            ),
                          ),
                        ),
                    Positioned(
                      left: iconCenter.dx - pitch / 2,
                      top: iconCenter.dy - restRect.height / 2,
                      width: pitch,
                      height: restRect.height,
                      child: _TabGlyph(
                        item: items[selected],
                        color: iconColor,
                        showLabel: false,
                        labelOpacity: fade,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabGlyph extends StatelessWidget {
  const _TabGlyph({
    required this.item,
    required this.color,
    required this.showLabel,
    this.labelOpacity = 1,
  });

  final MorphTabItem item;
  final Color color;
  final bool showLabel;
  final double labelOpacity;

  @override
  Widget build(BuildContext context) {
    final labelVisible = showLabel ? 1.0 : labelOpacity;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(item.icon, size: MorphTabBarMetrics.iconSize, color: color),
        SizedBox(height: MorphTabBarMetrics.labelGap * labelVisible),
        if (labelVisible > 0.01)
          Opacity(
            opacity: labelVisible,
            child: Text(
              item.label,
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: MorphTypography.resolve(
                MorphTypography.tabLabelSelected,
              ).copyWith(fontSize: 10 * labelVisible, color: color),
            ),
          ),
      ],
    );
  }
}

class _SearchCircle extends StatelessWidget {
  const _SearchCircle({
    required this.progress,
    required this.rect,
    required this.restRect,
    required this.placeholder,
    required this.label,
    required this.style,
    required this.tabStyle,
    required this.glass,
    required this.brightness,
    required this.rtl,
    required this.onTap,
  });

  final double progress;
  final Rect rect;
  final Rect restRect;
  final String placeholder;
  final String label;
  final MorphSearchFieldStyle style;
  final MorphTabBarStyle tabStyle;
  final MorphGlassPainter? glass;
  final Brightness brightness;
  final bool rtl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = progress.clamp(0.0, 1.0);
    final shape = RRect.fromRectAndRadius(
      Offset.zero & rect.size,
      Radius.circular(math.min(rect.width, rect.height) / 2),
    );
    const glyph = MorphSearchTuning.glyphSize;
    final start = Offset(
      rtl
          ? rect.width - MorphSearchTuning.glyphInset - glyph.width / 2
          : MorphSearchTuning.glyphInset + glyph.width / 2,
      rect.height / 2,
    );
    final glyphCenter = Offset.lerp(rect.size.center(Offset.zero), start, q)!;
    final glyphColor = Color.lerp(tabStyle.color, style.glyphColor, q)!;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: glass == null
                  ? CustomPaint(
                      painter: _BodyPainter(
                        shape: shape,
                        color: Color.lerp(
                          tabStyle.barColor,
                          style.capsuleColor,
                          q,
                        )!,
                        shadow: style.shadowColor,
                      ),
                    )
                  : glass!.buildSurface(
                      context,
                      MorphGlassSurface(
                        kind: MorphGlassKind.button,
                        shape: shape,
                        color: Color.lerp(
                          tabStyle.barColor,
                          style.capsuleColor,
                          q,
                        )!,
                        brightness: brightness,
                      ),
                    ),
            ),
            Positioned(
              left: glyphCenter.dx - glyph.width / 2 * (1 + 0.15 * (1 - q)),
              top: glyphCenter.dy - glyph.height / 2 * (1 + 0.15 * (1 - q)),
              width: glyph.width * (1 + 0.15 * (1 - q)),
              height: glyph.height * (1 + 0.15 * (1 - q)),
              child: CustomPaint(painter: _MagnifierGlyph(color: glyphColor)),
            ),
            if (q > 0.01)
              PositionedDirectional(
                start: MorphSearchTuning.textInset,
                end: 8,
                top: 0,
                bottom: 0,
                child: ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Opacity(
                      opacity: ((q - 0.4) / 0.6).clamp(0.0, 1.0),
                      child: Text(
                        placeholder,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: MorphTypography.resolve(
                          MorphTypography.searchField.copyWith(
                            height: 1.2,
                            color: style.placeholderColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: MorphGlassButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        minSize: const Size.square(MorphSearchTuning.height),
        child: child,
      ),
    );
  }
}

class _CrossGlyph extends StatelessWidget {
  const _CrossGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: MorphSearchTuning.closeGlyphSize,
    child: CustomPaint(painter: _CrossLines(color: color)),
  );
}

class _CrossLines extends CustomPainter {
  const _CrossLines({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => morphPaintCross(canvas, size, color);

  @override
  bool shouldRepaint(_CrossLines oldDelegate) => oldDelegate.color != color;
}

class _MagnifierGlyph extends CustomPainter {
  const _MagnifierGlyph({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      morphPaintMagnifier(canvas, size, color);

  @override
  bool shouldRepaint(_MagnifierGlyph oldDelegate) => oldDelegate.color != color;
}

class _BodyPainter extends CustomPainter {
  const _BodyPainter({
    required this.shape,
    required this.color,
    required this.shadow,
  });

  final RRect shape;
  final Color color;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint();
    shadowPaint.color = shadow;
    shadowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(shape.shift(const Offset(0, 4)), shadowPaint);
    final fill = Paint();
    fill.color = color;
    canvas.drawRRect(shape, fill);
  }

  @override
  bool shouldRepaint(_BodyPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.shadow != shadow;
}
