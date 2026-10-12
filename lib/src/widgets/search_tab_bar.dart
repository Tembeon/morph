import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/chrome_group.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
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
/// circle; the query clears at the end of that frame. The tab circle takes the tap while the morph into the field
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

  /// Called whenever the query changes, including the empty query when
  /// the close button or the end of the search clears it.
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
    _ticks.follow(frames);
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
        _focus.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _controller.text.isEmpty) return;
          _controller.clear();
          widget.onQueryChanged?.call('');
        });
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
    _ticks.dispose();
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

  MorphSearchTabGeometry? _geometry;
  _TabFrame _frame = _TabFrame.zero;
  // A keyboard frame rebuilds and reads again with the new geometry.
  late final MorphFrameSync<_TabStructure?> _ticks =
      MorphFrameSync<_TabStructure?>(
        structure: () => _geometry == null ? null : _readFrame(),
        rebuild: (_TabStructure? _) => setState(() {}),
      );

  _TabStructure _readFrame() {
    final geometry = _geometry!;
    final q = _morph.value(_now);
    final p = _focusMotion.progress(_now);
    final focused = _focusMotion.isFocused;
    final settled = (q - 1).abs() < 0.001 && widget.searching;
    final fieldRect = Rect.lerp(geometry.field, geometry.focusedField, p)!;
    _frame = _TabFrame(
      q: q,
      p: p,
      bar: Rect.lerp(geometry.bar, geometry.tab, q)!,
      field: fieldRect,
      search: Rect.lerp(geometry.search, fieldRect, q)!,
      close: Rect.lerp(
        Rect.fromLTWH(
          geometry.field.right - MorphSearchTuning.height,
          geometry.field.top,
          MorphSearchTuning.height,
          MorphSearchTuning.height,
        ),
        geometry.close,
        p,
      )!,
    );
    final shown = q.clamp(0.0, 1.0);
    return (
      resting: q.abs() < 0.001 && !widget.searching,
      settled: settled,
      tabIgnoring: !widget.searching || p >= 0.5,
      tabLabel: (1 - shown * 2).clamp(0.0, 1.0) > 0.01,
      placeholder: shown > 0.01,
      closeShown: settled && (p > 0.001 || focused),
      focused: focused,
    );
  }

  double _fallbackBarWidth() {
    final count = widget.items.length;
    return MorphTabBarMetrics.geometry(count, 0).width;
  }

  MorphSearchTabBar? _partsFor;
  late MorphTabBar _tabBar;
  late MorphSearchField _field;

  @override
  void reassemble() {
    super.reassemble();
    _partsFor = null;
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
    // The keyboard's inset rebuilds this on every frame of its rise and
    // fall; the bar and the field depend only on the widget, so those
    // rebuilds reuse them and Flutter skips their subtrees.
    if (!identical(_partsFor, widget)) {
      _partsFor = widget;
      _tabBar = MorphTabBar(
        key: _bar,
        items: widget.items,
        selected: selected,
        onChanged: widget.onChanged,
        style: widget.style,
      );
      _field = MorphSearchField(
        controller: _controller,
        focusNode: _focus,
        placeholder: widget.placeholder,
        onChanged: widget.onQueryChanged,
        onSubmitted: widget.onSubmitted,
        style: widget.searchStyle,
      );
    }
    final bar = _tabBar;
    final field = _field;
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
          _geometry = geometry;
          final structure = _ticks.read()!;
          final settled = structure.settled;
          final children = <Widget>[];
          if (structure.resting) {
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
              MorphLivePositionedTemplate(
                key: const ValueKey<String>('tab'),
                live: _ticks,
                template: () =>
                    Positioned.fromRect(rect: _frame.bar, child: morphLiveSlot),
                child: IgnorePointer(
                  ignoring: structure.tabIgnoring,
                  child: MorphLiveOpacity(
                    live: _ticks,
                    opacityOf: () => (1 - _frame.p).clamp(0.0, 1.0),
                    child: _MorphingTabs(
                      live: _ticks,
                      items: widget.items,
                      selected: selected,
                      progress: () => _frame.q,
                      restRect: geometry.bar,
                      rect: () => _frame.bar,
                      labelShown: structure.tabLabel,
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
              MorphLivePositionedTemplate(
                key: const ValueKey<String>('search'),
                live: _ticks,
                template: () => Positioned.fromRect(
                  rect: _frame.search,
                  child: morphLiveSlot,
                ),
                child: IgnorePointer(
                  ignoring: !structure.resting,
                  child: _SearchCircle(
                    live: _ticks,
                    progress: () => _frame.q,
                    rect: () => _frame.search,
                    restRect: geometry.search,
                    placeholderShown: structure.placeholder,
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
              MorphLivePositionedTemplate(
                key: const ValueKey<String>('field'),
                live: _ticks,
                // Hidden, the field only holds the focus; parking it at
                // its settled rect spares a relayout per morph frame.
                template: () => Positioned.fromRect(
                  rect: settled ? _frame.search : _frame.field,
                  child: morphLiveSlot,
                ),
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
          if (structure.closeShown) {
            children.add(
              MorphLivePositionedTemplate(
                key: const ValueKey<String>('close'),
                live: _ticks,
                template: () => Positioned.fromRect(
                  rect: _frame.close,
                  child: morphLiveSlot,
                ),
                child: IgnorePointer(
                  ignoring: !structure.focused,
                  child: MorphLiveOpacity(
                    live: _ticks,
                    opacityOf: () => _frame.p.clamp(0.0, 1.0),
                    child: MorphLiveTransform(
                      live: _ticks,
                      writeInto: (Matrix4 into) {
                        final scale = MorphSearchMotion.appearScaleFor(
                          _frame.p,
                        );
                        into.scaleByDouble(scale, scale, 1, 1);
                      },
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
      ),
    );
    return MorphChromeBackdrop(child: shortcuts);
  }
}

class _TabFrame {
  const _TabFrame({
    required this.q,
    required this.p,
    required this.bar,
    required this.field,
    required this.search,
    required this.close,
  });

  static const zero = _TabFrame(
    q: 0,
    p: 0,
    bar: Rect.zero,
    field: Rect.zero,
    search: Rect.zero,
    close: Rect.zero,
  );

  final double q;
  final double p;
  final Rect bar;
  final Rect field;
  final Rect search;
  final Rect close;
}

typedef _TabStructure = ({
  bool resting,
  bool settled,
  bool tabIgnoring,
  bool tabLabel,
  bool placeholder,
  bool closeShown,
  bool focused,
});

RRect _capsuleIn(Rect rect) => RRect.fromRectAndRadius(
  Offset.zero & rect.size,
  Radius.circular(math.min(rect.width, rect.height) / 2),
);

class _MorphingTabs extends StatelessWidget {
  const _MorphingTabs({
    required this.live,
    required this.items,
    required this.selected,
    required this.progress,
    required this.restRect,
    required this.rect,
    required this.labelShown,
    required this.style,
    required this.glass,
    required this.brightness,
    required this.rtl,
    required this.label,
    required this.onTap,
  });

  final Listenable live;
  final List<MorphTabItem> items;
  final int selected;
  final double Function() progress;
  final Rect restRect;
  final Rect Function() rect;
  final bool labelShown;
  final MorphTabBarStyle style;
  final MorphGlassPainter? glass;
  final Brightness brightness;
  final bool rtl;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    double q() => progress().clamp(0.0, 1.0);
    double fade() => (1 - q() * 2).clamp(0.0, 1.0);
    final pitch =
        (restRect.width - 2 * MorphTabBarMetrics.sideInset) / items.length;
    final selectedCenter = Offset(
      MorphTabBarMetrics.sideInset +
          pitch * (rtl ? items.length - 1 - selected + 0.5 : selected + 0.5),
      restRect.height / 2,
    );
    final glass = this.glass;
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
                        live: live,
                        shape: () => _capsuleIn(rect()),
                        color: () => style.barColor,
                        shadow: style.shadowColor,
                      ),
                    )
                  : MorphGlassHost(
                      painter: glass,
                      mode: MorphGlassMode.surface,
                      frames: live,
                      frame: () => MorphGlassFrame([
                        MorphGlassSurface(
                          kind: MorphGlassKind.bar,
                          shape: _capsuleIn(rect()),
                          color: style.barColor,
                          brightness: brightness,
                        ),
                      ]),
                    ),
            ),
            Positioned.fill(
              child: MorphLiveClipRRect(
                live: live,
                borderRadiusOf: () =>
                    BorderRadius.circular(_capsuleIn(rect()).tlRadiusX),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      if (i != selected)
                        MorphLivePositionedTemplate(
                          live: live,
                          template: () {
                            final now = rect();
                            return Positioned(
                              left:
                                  restRect.left -
                                  now.left +
                                  MorphTabBarMetrics.sideInset +
                                  pitch * (rtl ? items.length - 1 - i : i),
                              top: restRect.top - now.top,
                              width: pitch,
                              height: restRect.height,
                              child: morphLiveSlot,
                            );
                          },
                          child: MorphLiveOpacity(
                            live: live,
                            opacityOf: fade,
                            child: _TabGlyph(
                              item: items[i],
                              color: style.color,
                              showLabel: true,
                            ),
                          ),
                        ),
                    MorphLivePositionedTemplate(
                      live: live,
                      template: () {
                        final now = rect();
                        final center = Offset.lerp(
                          selectedCenter - (now.topLeft - restRect.topLeft),
                          now.size.center(Offset.zero),
                          q(),
                        )!;
                        return Positioned(
                          left: center.dx - pitch / 2,
                          top: center.dy - restRect.height / 2,
                          width: pitch,
                          height: restRect.height,
                          child: morphLiveSlot,
                        );
                      },
                      child: _SelectedGlyph(
                        live: live,
                        item: items[selected],
                        color: () =>
                            Color.lerp(style.selectedColor, style.color, q())!,
                        fade: fade,
                        labelShown: labelShown,
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

/// The selected tab's glyph while the bar shrinks into the tab circle: its
/// color turns from the selected tint to the plain one and its label
/// shrinks and fades, each frame without a build.
class _SelectedGlyph extends StatelessWidget {
  const _SelectedGlyph({
    required this.live,
    required this.item,
    required this.color,
    required this.fade,
    required this.labelShown,
  });

  final Listenable live;
  final MorphTabItem item;
  final Color Function() color;
  final double Function() fade;
  final bool labelShown;

  TextStyle get _labelStyle => MorphTypography.resolve(
    MorphTypography.tabLabelSelected,
  ).copyWith(fontSize: 10 * fade(), color: color());

  @override
  Widget build(BuildContext context) {
    final icon = (IconTheme.of(context).opacity ?? 1) == 1
        ? _liveParagraph(
            Icon(
              item.icon,
              size: MorphTabBarMetrics.iconSize,
              color: color(),
            ).build(context),
            live,
            (TextStyle style) => style.copyWith(color: color()),
          )
        : null;
    final text = labelShown
        ? _liveParagraph(
            Text(
              item.label,
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: _labelStyle,
            ).build(context),
            live,
            (TextStyle style) =>
                style.copyWith(fontSize: 10 * fade(), color: color()),
          )
        : null;
    if (icon == null || (labelShown && text == null)) {
      return ListenableBuilder(
        listenable: live,
        builder: (BuildContext context, Widget? _) => _TabGlyph(
          item: item,
          color: color(),
          showLabel: false,
          labelOpacity: fade(),
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        MorphLiveTemplate(
          live: live,
          template: () =>
              SizedBox(height: MorphTabBarMetrics.labelGap * fade()),
        ),
        if (text != null)
          MorphLiveOpacity(live: live, opacityOf: fade, child: text),
      ],
    );
  }
}

/// [built], the tree a [Text] or an [Icon] builds, with its one paragraph's
/// style following [live] through [restyle], or null when [built] is not a
/// plain paragraph under single-child layout wrappers.
///
/// Semantics wrappers are dropped: the glyphs here sit under a node that
/// excludes its children's semantics, and they neither lay out nor paint.
Widget? _liveParagraph(
  Widget built,
  Listenable live,
  TextStyle Function(TextStyle style) restyle,
) {
  Widget? inner(Widget? child) =>
      child == null ? null : _liveParagraph(child, live, restyle);
  switch (built) {
    case RichText(text: final TextSpan span)
        when span.runtimeType == TextSpan &&
            span.children == null &&
            span.recognizer == null &&
            span.semanticsLabel == null &&
            span.style?.foreground == null &&
            span.style?.background == null:
      final style = span.style;
      if (style == null) return null;
      return MorphLiveTemplate(
        live: live,
        template: () => RichText(
          textAlign: built.textAlign,
          textDirection: built.textDirection,
          softWrap: built.softWrap,
          overflow: built.overflow,
          textScaler: built.textScaler,
          maxLines: built.maxLines,
          locale: built.locale,
          strutStyle: built.strutStyle,
          textWidthBasis: built.textWidthBasis,
          textHeightBehavior: built.textHeightBehavior,
          selectionRegistrar: built.selectionRegistrar,
          selectionColor: built.selectionColor,
          text: TextSpan(
            text: span.text,
            style: restyle(style),
            locale: span.locale,
            spellOut: span.spellOut,
          ),
        ),
      );
    case Semantics(:final child) || ExcludeSemantics(:final child):
      return inner(child);
    case SizedBox(:final width, :final height, :final child):
      final live = inner(child);
      return live == null
          ? null
          : SizedBox(width: width, height: height, child: live);
    case Align(:final alignment, :final widthFactor, :final heightFactor):
      final live = inner(built.child);
      return live == null
          ? null
          : Align(
              alignment: alignment,
              widthFactor: widthFactor,
              heightFactor: heightFactor,
              child: live,
            );
    case Transform(:final child):
      final live = inner(child);
      return live == null
          ? null
          : Transform(
              transform: built.transform,
              origin: built.origin,
              alignment: built.alignment,
              transformHitTests: built.transformHitTests,
              filterQuality: built.filterQuality,
              child: live,
            );
    default:
      return null;
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
    required this.live,
    required this.progress,
    required this.rect,
    required this.restRect,
    required this.placeholderShown,
    required this.placeholder,
    required this.label,
    required this.style,
    required this.tabStyle,
    required this.glass,
    required this.brightness,
    required this.rtl,
    required this.onTap,
  });

  final Listenable live;
  final double Function() progress;
  final Rect Function() rect;
  final Rect restRect;
  final bool placeholderShown;
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
    double q() => progress().clamp(0.0, 1.0);
    Color body() => Color.lerp(tabStyle.barColor, style.capsuleColor, q())!;
    const glyph = MorphSearchTuning.glyphSize;
    final glass = this.glass;
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
                        live: live,
                        shape: () => _capsuleIn(rect()),
                        color: body,
                        shadow: style.shadowColor,
                      ),
                    )
                  : MorphGlassHost(
                      painter: glass,
                      mode: MorphGlassMode.surface,
                      frames: live,
                      frame: () => MorphGlassFrame([
                        MorphGlassSurface(
                          kind: MorphGlassKind.button,
                          shape: _capsuleIn(rect()),
                          color: body(),
                          brightness: brightness,
                        ),
                      ]),
                    ),
            ),
            MorphLivePositionedTemplate(
              live: live,
              template: () {
                final now = rect();
                final start = Offset(
                  rtl
                      ? now.width -
                            MorphSearchTuning.glyphInset -
                            glyph.width / 2
                      : MorphSearchTuning.glyphInset + glyph.width / 2,
                  now.height / 2,
                );
                final t = q();
                final center = Offset.lerp(
                  now.size.center(Offset.zero),
                  start,
                  t,
                )!;
                return Positioned(
                  left: center.dx - glyph.width / 2 * (1 + 0.15 * (1 - t)),
                  top: center.dy - glyph.height / 2 * (1 + 0.15 * (1 - t)),
                  width: glyph.width * (1 + 0.15 * (1 - t)),
                  height: glyph.height * (1 + 0.15 * (1 - t)),
                  child: morphLiveSlot,
                );
              },
              child: CustomPaint(
                painter: _MagnifierGlyph(
                  live: live,
                  color: () =>
                      Color.lerp(tabStyle.color, style.glyphColor, q())!,
                ),
              ),
            ),
            if (placeholderShown)
              PositionedDirectional(
                start: MorphSearchTuning.textInset,
                end: 8,
                top: 0,
                bottom: 0,
                child: ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MorphLiveOpacity(
                      live: live,
                      opacityOf: () => ((q() - 0.4) / 0.6).clamp(0.0, 1.0),
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
  _MagnifierGlyph({required Listenable live, required this.color})
    : super(repaint: live);

  final Color Function() color;

  @override
  void paint(Canvas canvas, Size size) =>
      morphPaintMagnifier(canvas, size, color());

  @override
  bool shouldRepaint(_MagnifierGlyph oldDelegate) => true;
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required Listenable live,
    required this.shape,
    required this.color,
    required this.shadow,
  }) : super(repaint: live);

  final RRect Function() shape;
  final Color Function() color;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = this.shape();
    final shadowPaint = Paint();
    shadowPaint.color = shadow;
    shadowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(shape.shift(const Offset(0, 4)), shadowPaint);
    final fill = Paint();
    fill.color = color();
    canvas.drawRRect(shape, fill);
  }

  @override
  bool shouldRepaint(_BodyPainter oldDelegate) => true;
}
