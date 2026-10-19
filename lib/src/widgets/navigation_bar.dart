import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/bar_motion.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/navigation_motion.dart';
import 'package:morph/src/widgets/scroll_edge_effect.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/theme/theme.dart';

/// Whether the inline title paints in a layer of its own, so its fade
/// and rise repaint only the title and not the bar and the page around
/// it. On by default; `--dart-define=MORPH_TITLE_LAYER=false` paints it
/// with the bar, for an A/B.
bool debugMorphInlineTitleLayer = const bool.fromEnvironment(
  'MORPH_TITLE_LAYER',
  defaultValue: true,
);

/// The measured geometry of an iOS 27 navigation bar on a phone.
abstract final class MorphNavigationBarMetrics {
  /// The height of the bar below the status bar.
  static const double barHeight = 54;

  /// The space between the screen's sides and the outer capsules on a
  /// 402 point wide screen (20 on the 440 point Pro Max).
  static const double sideInset = 16;

  /// The height of the large title area below the bar.
  static const double largeTitleHeight = 52;

  /// The leading inset of the large title.
  static const double largeTitleInset = 16;

  /// The space between the top of the large title area and the top of
  /// its text.
  static const double largeTitleTop = 3.67;

  /// The size of the large title.
  static const double largeTitleSize = 34;

  /// The size of the inline title.
  static const double titleSize = 17;

  /// The size of the inline title when a subtitle sits under it: short
  /// emphasized subheadline, semibold (read from UIKit, notes private).
  static const double titleWithSubtitleSize = 15;

  /// The size of the inline subtitle under the inline title: short
  /// caption 1, regular, in secondaryLabel (read from UIKit, notes
  /// private). The gap between the two lines is not read: they stack
  /// line box on line box.
  static const double subtitleSize = 12;

  /// The size of a large title with a subtitle under it: emphasized
  /// title 2, bold (read from UIKit, notes private).
  static const double largeTitleWithSubtitleSize = 22;

  /// The size of the subtitle under a large title: caption 2, medium, in
  /// secondaryLabel (read from UIKit, notes private).
  static const double largeSubtitleSize = 11;

  /// How far above the bottom of the large title area a large subtitle's
  /// baseline sits, as the title's own baseline does without a subtitle
  /// (read from UIKit, notes private).
  static const double largeBaselineInset = 16;

  /// How far above the top of a large subtitle's line the large title's
  /// baseline sits (read from UIKit, notes private).
  static const double largeTitleSubtitleGap = 6;

  /// The height a large subtitle adds to the large title area. UIKit sizes
  /// the area by the title's and the subtitle's lines plus
  /// [largeTitleSubtitleGap]; with the 34 point title's line replaced by
  /// the 22 point one, the change is this (lines at
  /// [MorphBarMetrics.lineHeight] of their size; the formula is read from
  /// UIKit, the result needs a device check).
  static const double largeSubtitleHeight =
      (largeTitleWithSubtitleSize + largeSubtitleSize - largeTitleSize) *
          MorphBarMetrics.lineHeight +
      largeTitleSubtitleGap;

  /// The least space between the inline title and the bar's buttons
  /// (`titleControlPadding`); see [morphInlineTitleFrame] for where the
  /// title goes when it does not fit centered.
  static const double titlePadding = 12;
}

/// Where a navigation bar puts an inline title [textWidth] wide, or null
/// when there is no room for it.
///
/// [lo] and [hi] bound the room between the groups (see
/// [morphInlineTitleBounds]). UIKit centers the title on the bar when it
/// fits between the bounds so centered; otherwise it puts the title at the
/// leading bound (not just as far as needed) and truncates it with an
/// ellipsis at the other one; with no room left the title is not drawn.
/// Measured on the simulator (iPhone 17 Pro, iOS 27.0, 2026-10-14: five
/// title lengths with and without a subtitle under a back button and zero
/// to three trailing groups, 46 bars): every title within 1 point of this
/// rule. An iPhone 16 Pro's full matrix confirms 62 visible single-line
/// title frames within 0.5 points, including wide leading groups.
/// A title with a subtitle places its two lines as one block
/// [textWidth] wide, both lines leading-aligned when the block is not
/// centered (one bar of nine centers a fitting subtitle under a truncated
/// title: not reproduced). UIKit can drop a long title with 49 points of
/// room and collapse overflowing button groups before allocating the
/// title; those priority rules are not reproduced. Morph drops at no room.
@internal
({double left, double width, bool centered})? morphInlineTitleFrame({
  required double barWidth,
  required double textWidth,
  required double lo,
  required double hi,
  required bool rtl,
}) {
  final room = hi - lo;
  if (room <= 0 || textWidth <= 0) return null;
  final center = barWidth / 2;
  final half = textWidth / 2;
  if (center - half >= lo - 0.01 && center + half <= hi + 0.01) {
    return (left: center - half, width: textWidth, centered: true);
  }
  final width = math.min(textWidth, room);
  return (left: rtl ? hi - width : lo, width: width, centered: false);
}

/// The room a navigation bar leaves its inline title between its capsules,
/// for [morphInlineTitleFrame].
///
/// Each capsule is `(left, right, onLeft)`, `onLeft` true for the groups
/// on the left side of the bar (the leading groups in left-to-right
/// text). [lo] is the right edge of the left groups plus
/// [MorphNavigationBarMetrics.titlePadding], [sideInset] without them;
/// [hi] the left edge of the right groups minus the padding, the bar's
/// width less [sideInset] without them. A group bounds the side it belongs
/// to wherever it stands, also when it reaches past the bar's center.
@internal
({double lo, double hi}) morphInlineTitleBounds({
  required double barWidth,
  required double sideInset,
  required List<(double, double, bool)> capsules,
}) {
  const pad = MorphNavigationBarMetrics.titlePadding;
  var lo = sideInset;
  var hi = barWidth - sideInset;
  for (final (l, r, onLeft) in capsules) {
    if (onLeft) {
      lo = math.max(lo, r + pad);
    } else {
      hi = math.min(hi, l - pad);
    }
  }
  return (lo: lo, hi: hi);
}

/// The style of a navigation bar's large title: [MorphTypography.largeTitle].
TextStyle morphLargeTitleStyle(Color color) => MorphTypography.resolve(
  MorphTypography.largeTitle.copyWith(
    fontSize: MorphNavigationBarMetrics.largeTitleSize,
    height: MorphBarMetrics.lineHeight,
    color: color,
  ),
);

/// The style of a navigation bar's inline title: [MorphTypography.title].
TextStyle morphInlineTitleStyle(Color color) => MorphTypography.resolve(
  MorphTypography.title.copyWith(
    fontSize: MorphNavigationBarMetrics.titleSize,
    height: MorphBarMetrics.lineHeight,
    color: color,
  ),
);

/// The style of a navigation bar's inline title with a subtitle under it.
TextStyle morphInlineTitleWithSubtitleStyle(Color color) =>
    MorphTypography.resolve(
      TextStyle(
        fontSize: MorphNavigationBarMetrics.titleWithSubtitleSize,
        fontWeight: FontWeight.w600,
        height: MorphBarMetrics.lineHeight,
        color: color,
      ),
    );

/// The style of a navigation bar's inline subtitle, [color] usually the
/// appearance's [MorphBarAppearance.subtitleColor].
TextStyle morphInlineSubtitleStyle(Color color) => MorphTypography.resolve(
  MorphTypography.body.copyWith(
    fontSize: MorphNavigationBarMetrics.subtitleSize,
    height: MorphBarMetrics.lineHeight,
    color: color,
  ),
);

/// The style of a large title with a subtitle under it.
TextStyle morphLargeTitleWithSubtitleStyle(Color color) =>
    MorphTypography.resolve(
      MorphTypography.largeTitle.copyWith(
        fontSize: MorphNavigationBarMetrics.largeTitleWithSubtitleSize,
        height: MorphBarMetrics.lineHeight,
        color: color,
      ),
    );

/// The style of the subtitle under a large title.
TextStyle morphLargeSubtitleStyle(Color color) => MorphTypography.resolve(
  TextStyle(
    fontSize: MorphNavigationBarMetrics.largeSubtitleSize,
    fontWeight: FontWeight.w500,
    height: MorphBarMetrics.lineHeight,
    color: color,
  ),
);

/// The buttons a navigation bar leans toward while an interactive pop is
/// in progress: those of the screen the pop leads to.
///
/// While a finger drags a page off the screen, UIKit moves the bar's
/// capsules part of the way toward the places they take on the screen
/// below: each capsule that the destination bar also has (the same group
/// id, or the same place on its side) travels and resizes
/// [MorphNavigationTuning.barDrift] times the page's [progress] of the
/// way, a pure function of the page's position. A cancelled pop drifts
/// back with the returning page; a committed one hands the drifted
/// capsules to the bar's item transition.
@immutable
@internal
class MorphNavigationBarDrift {
  /// Creates a drift toward [leading] and [trailing].
  const MorphNavigationBarDrift({
    required this.progress,
    this.leading = const [],
    this.trailing = const [],
  });

  /// The groups at the leading edge of the destination bar.
  final List<MorphBarButtonGroup> leading;

  /// The groups at the trailing edge of the destination bar.
  final List<MorphBarButtonGroup> trailing;

  /// How far the page is out, 0 in place and 1 gone.
  final ValueListenable<double> progress;
}

/// An iOS 27 navigation bar: glass button capsules at the sides, a title
/// between them, no background of its own.
///
/// The bar is [MorphNavigationBarMetrics.barHeight] tall below the top
/// safe area. Its buttons are [MorphBarButtonGroup]s - adjacent buttons
/// share one capsule, separate groups float 12 points apart - and every
/// change of [leading] or [trailing] animates like UIKit's bar button
/// transition (see [MorphBarMotion]); a back button is a
/// [MorphBarButton.back] in [leading]. The inline [title] shows while
/// [titleVisible]: a screen with a large title hides it until the large
/// title has scrolled under the bar, then it rises in on the measured
/// [MorphNavigationTitleMotion]. Pass [animate] false for a change
/// that does not come from a finger.
///
/// The bar has no fill: while [scrolledUnder] it fades in the
/// [MorphScrollEdgeEffect] of [edgeEffect] beneath itself, over the
/// content it covers. A [MorphNavigationScaffold] wires both flags to its
/// scroll view.
class MorphNavigationBar extends StatefulWidget {
  /// Creates a navigation bar.
  const MorphNavigationBar({
    this.title,
    this.subtitle,
    this.leading = const [],
    this.trailing = const [],
    this.titleVisible = true,
    this.scrolledUnder = false,
    this.animate = true,
    this.edgeEffect = MorphScrollEdgeEffectStyle.hard,
    this.edgeEffectAppearance,
    @internal this.titleExitShift = -MorphNavigationTuning.parallax,
    @internal this.drift,
    this.appearance,
    this.menuAppearance,
    @internal this.menuTuning = MorphBarMenuTuning.standard,
    @internal this.menuOverlay,
    this.sideInset = MorphNavigationBarMetrics.sideInset,
    @internal this.hiding,
    @internal this.hidden,
    super.key,
  });

  /// The inline title.
  final String? title;

  /// The line under the inline title (UIKit `UINavigationItem.subtitle`,
  /// iOS 26), or null. It shows and hides with the title; its size and
  /// spacing are not yet measured on a device.
  final String? subtitle;

  /// The groups at the leading edge, in reading order, such as a back
  /// button (UIKit `leftBarButtonItems`).
  final List<MorphBarButtonGroup> leading;

  /// The groups at the trailing edge, in reading order.
  final List<MorphBarButtonGroup> trailing;

  /// Whether the inline title is shown.
  final bool titleVisible;

  /// Whether content has scrolled under the bar: the bar's
  /// [MorphScrollEdgeEffect] fades in.
  final bool scrolledUnder;

  /// Whether changes of [titleVisible] and [scrolledUnder] animate; pass
  /// false for a change no finger caused (UIKit switches at once then).
  ///
  /// A [titleVisible] change that comes with a new [title] always
  /// switches at once: the new screen's title arrives on the title swap,
  /// and a hidden one (under a large title) is never drawn.
  final bool animate;

  /// The scroll edge effect the bar draws under itself while
  /// [scrolledUnder]; null draws none. UIKit's automatic style under a
  /// navigation bar is the hard one ("thin film").
  final MorphScrollEdgeEffectStyle? edgeEffect;

  /// The look of the edge effect; null resolves it from the theme.
  final MorphScrollEdgeEffectAppearance? edgeEffectAppearance;

  /// How far a replaced title travels while it fades out, as a share of
  /// the bar's width: on a push the old title rides the page underneath
  /// (-0.3), on a pop the page that leaves (1). The new title fades in
  /// where it stands. Both ride [MorphNavigationTuning.pushSpring].
  @internal
  @internal
  final double titleExitShift;

  /// The bar the capsules lean toward during an interactive pop; null
  /// keeps them in place.
  @internal
  @internal
  final MorphNavigationBarDrift? drift;

  /// The look; null resolves it from the theme.
  final MorphBarAppearance? appearance;

  /// The look of the buttons' menus, such as the back button's; null
  /// resolves it from the theme.
  final MorphMenuAppearance? menuAppearance;

  /// The bar buttons' menu recognition, opening delay and menu motion.
  @internal
  final MorphBarMenuTuning menuTuning;

  /// The overlay the buttons' menus fly in; null uses
  /// [morphPresentationOverlayOf].
  @internal
  final OverlayState? menuOverlay;

  /// The space between the screen's sides and the outer capsules.
  final double sideInset;

  /// How far the bar is hidden, 0 shown and 1 slid up off the screen with
  /// its edge effect; null keeps it shown. A [MorphNavigationScaffold]
  /// drives it.
  @internal
  @internal
  final Animation<double>? hiding;

  /// Whether the bar is hidden or hiding: it takes no touches then.
  @internal
  @internal
  final ValueListenable<bool>? hidden;

  /// The height of a bar below a status bar [topInset] tall.
  static double heightFor(double topInset) =>
      topInset + MorphNavigationBarMetrics.barHeight;

  @override
  State<MorphNavigationBar> createState() => _MorphNavigationBarState();
}

class _MorphNavigationBarState extends State<MorphNavigationBar>
    with
        SingleTickerProviderStateMixin<MorphNavigationBar>,
        MorphClock<MorphNavigationBar> {
  late final MorphNavigationTitleMotion _motion = MorphNavigationTitleMotion(
    titleVisible: widget.titleVisible,
    scrolledUnder: widget.scrolledUnder,
  );
  List<(double, double, bool)> _capsuleEdges = const [];
  final MorphSpringState _swap = MorphSpringState(
    MorphNavigationTuning.pushSpring,
    1,
  );
  String? _outgoing;
  String? _outgoingSubtitle;
  double _exitShift = 0;
  final Map<(String, String?, TextScaler, TextDirection), Size> _titleSizes =
      {};

  Size _titleSize(
    String title,
    String? subtitle,
    TextScaler scaler,
    TextDirection direction,
  ) {
    if (_titleSizes.length > 8) _titleSizes.clear();
    return _titleSizes.putIfAbsent((title, subtitle, scaler, direction), () {
      Size measure(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        );
        painter.layout();
        final size = painter.size;
        painter.dispose();
        return size;
      }

      const black = Color(0xFF000000);
      final size = measure(
        title,
        subtitle == null
            ? morphInlineTitleStyle(black)
            : morphInlineTitleWithSubtitleStyle(black),
      );
      if (subtitle == null) return size;
      final below = measure(subtitle, morphInlineSubtitleStyle(black));
      return Size(
        math.max(size.width, below.width),
        size.height + below.height,
      );
    });
  }

  @override
  void advanceMotion(double t) {
    _motion.advance(t);
    if (_outgoing != null && _swap.isWithin(t, MorphRest.opacity)) {
      setState(() => _outgoing = null);
    }
  }

  @override
  bool get motionSettled =>
      _motion.isSettled &&
      (_outgoing == null || _swap.isWithin(clock, MorphRest.opacity));

  @override
  void settleMotion() => _motion.settle();

  double get _swapProgress {
    if (_outgoing == null) return 1;
    if (_swap.isWithin(clock, MorphRest.opacity)) return 1;
    return _swap.value(clock).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(MorphNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final animated = widget.animate && !morphReducedMotionOf(context);
    if (oldWidget.title != widget.title &&
        oldWidget.title != null &&
        !morphReducedMotionOf(context)) {
      _outgoing = oldWidget.titleVisible ? oldWidget.title : null;
      _outgoingSubtitle = oldWidget.subtitle;
      _exitShift = widget.titleExitShift;
      _swap.setState(clock, 0, MorphNavigationTuning.pushVelocity);
      _swap.retarget(clock, 1);
      wake();
    }
    if (oldWidget.titleVisible != widget.titleVisible) {
      _motion.setTitleVisible(
        clock,
        visible: widget.titleVisible,
        animated: animated && oldWidget.title == widget.title,
      );
      wake();
    }
    if (oldWidget.scrolledUnder != widget.scrolledUnder) {
      _motion.setScrolledUnder(
        clock,
        scrolledUnder: widget.scrolledUnder,
        animated: animated,
      );
      wake();
    }
  }

  void _onLayout(List<MorphBarCapsuleLayout> layout, bool rtl) {
    final edges = [
      for (final c in layout)
        (c.rect.left, c.rect.right, (c.segment == MorphBarSide.leading) != rtl),
    ];
    if (_edgesEqual(edges, _capsuleEdges)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _capsuleEdges = edges);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphBarAppearance.resolve(context, widget.appearance);
    final top = MediaQuery.maybePaddingOf(context)?.top ?? 0;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final leading = widget.leading;
    final drift = morphReducedMotionOf(context) ? null : widget.drift;
    _motion.reducedMotion = morphReducedMotionOf(context);
    final edge = widget.edgeEffect;
    final bar = Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: SizedBox(
          height: MorphNavigationBarMetrics.barHeight,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final width = constraints.maxWidth;
              final scaler =
                  MediaQuery.maybeTextScalerOf(
                    context,
                  )?.clamp(maxScaleFactor: MorphBarMetrics.maxTextScale) ??
                  TextScaler.noScaling;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: MorphBarItems(
                      metrics: MorphBarMetrics.navigation,
                      top: 0,
                      leadingInset: widget.sideInset,
                      trailingInset: widget.sideInset,
                      appearance: widget.appearance,
                      menuAppearance: widget.menuAppearance,
                      menuTuning: widget.menuTuning,
                      menuOverlay: widget.menuOverlay,
                      onLayout: (layout) =>
                          _onLayout(layout, direction == TextDirection.rtl),
                      groups: _placed(leading, widget.trailing),
                      driftGroups: drift == null
                          ? null
                          : _placed(drift.leading, drift.trailing),
                      driftProgress: drift?.progress,
                      driftFactor: MorphNavigationTuning.barDrift,
                      transition: MorphBarTransitionSpec.navigation,
                    ),
                  ),
                  if (_outgoing case final outgoing?)
                    _InlineTitle(
                      title: outgoing,
                      subtitle: _outgoingSubtitle,
                      subtitleColor: style.subtitleColor,
                      size: _titleSize(
                        outgoing,
                        _outgoingSubtitle,
                        scaler,
                        direction,
                      ),
                      scaler: scaler,
                      opacity: () => 1 - _swapProgress,
                      shift: () => _exitShift * width * _swapProgress,
                      motion: null,
                      frames: frames,
                      color: style.titleColor,
                      width: width,
                      edges: _capsuleEdges,
                      sideInset: widget.sideInset,
                      direction: direction,
                    ),
                  if (widget.title case final title?)
                    _InlineTitle(
                      title: title,
                      subtitle: widget.subtitle,
                      subtitleColor: style.subtitleColor,
                      size: _titleSize(
                        title,
                        widget.subtitle,
                        scaler,
                        direction,
                      ),
                      scaler: scaler,
                      opacity: () => _swapProgress,
                      shift: () => 0,
                      motion: _motion,
                      frames: frames,
                      color: style.titleColor,
                      width: width,
                      edges: _capsuleEdges,
                      sideInset: widget.sideInset,
                      direction: direction,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    final extent = MorphNavigationBar.heightFor(top);
    if (edge == null) return _hideable(bar, extent);
    final band = MorphScrollEdgeEffect.bandExtent(
      edge,
      extent,
      MorphScrollEdgeEffectAppearance.resolve(
        context,
        widget.edgeEffectAppearance,
      ),
    );
    return _hideable(
      Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: band,
            child: MorphScrollEdgeEffect.driven(
              extent: extent,
              style: edge,
              appearance: widget.edgeEffectAppearance,
              opacity: () => _motion.edgeOpacity,
              repaint: frames,
            ),
          ),
          bar,
        ],
      ),
      math.max(extent, band),
    );
  }

  // Slides the bar (and its edge effect, [travel] reaching past both) up
  // off the screen while it hides: a transform, so the glass keeps reading
  // its backdrop and the motion builds nothing.
  Widget _hideable(Widget bar, double travel) {
    final hiding = widget.hiding;
    if (hiding == null) return bar;
    Widget out = MorphLiveTransform.matrix(
      live: hiding,
      alignment: null,
      matrixOf: () =>
          Matrix4.translationValues(0, -travel * hiding.value.clamp(0, 1.2), 0),
      child: bar,
    );
    final hidden = widget.hidden;
    if (hidden != null) {
      out = MorphLiveIgnorePointer(
        live: hidden,
        ignoringOf: () => hidden.value,
        child: out,
      );
    }
    return out;
  }
}

List<MorphPlacedGroup> _placed(
  List<MorphBarButtonGroup> leading,
  List<MorphBarButtonGroup> trailing,
) => [
  for (final g in leading) MorphPlacedGroup(g, MorphBarSide.leading),
  for (final g in trailing) MorphPlacedGroup(g, MorphBarSide.trailing),
];

bool _edgesEqual(
  List<(double, double, bool)> a,
  List<(double, double, bool)> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final (al, ar, aSide) = a[i];
    final (bl, br, bSide) = b[i];
    if (aSide != bSide || (al - bl).abs() > 0.01 || (ar - br).abs() > 0.01) {
      return false;
    }
  }
  return true;
}

class _InlineTitle extends StatefulWidget {
  const _InlineTitle({
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.size,
    required this.scaler,
    required this.opacity,
    required this.shift,
    required this.motion,
    required this.frames,
    required this.color,
    required this.width,
    required this.edges,
    required this.sideInset,
    required this.direction,
  });

  final String title;
  final String? subtitle;
  final Color subtitleColor;
  final Size size;
  final TextScaler scaler;
  final double Function() opacity;
  final double Function() shift;
  final MorphNavigationTitleMotion? motion;
  final Listenable frames;
  final Color color;
  final double width;
  final List<(double, double, bool)> edges;
  final double sideInset;
  final TextDirection direction;

  @override
  State<_InlineTitle> createState() => _InlineTitleState();
}

class _InlineTitleState extends State<_InlineTitle> {
  bool? _shown;

  @override
  void initState() {
    super.initState();
    widget.frames.addListener(_sync);
  }

  @override
  void didUpdateWidget(_InlineTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frames, widget.frames)) {
      oldWidget.frames.removeListener(_sync);
      widget.frames.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.frames.removeListener(_sync);
    super.dispose();
  }

  double get _opacity => (widget.motion?.titleOpacity ?? 1) * widget.opacity();

  double get _blur => widget.motion?.titleBlur ?? 0;

  bool _shownNow() => _opacity > 0.001;

  void _sync() {
    if (_shownNow() != _shown) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown = _shownNow();
    final style = widget.subtitle == null
        ? morphInlineTitleStyle(widget.color)
        : morphInlineTitleWithSubtitleStyle(widget.color);
    final textHeight = widget.size.height;
    final width = widget.width;
    final rtl = widget.direction == TextDirection.rtl;
    final bounds = morphInlineTitleBounds(
      barWidth: width,
      sideInset: widget.sideInset,
      capsules: widget.edges,
    );
    final frame = morphInlineTitleFrame(
      barWidth: width,
      textWidth: widget.size.width,
      lo: bounds.lo,
      hi: bounds.hi,
      rtl: rtl,
    );
    final capsuleCenter = MorphBarMetrics.navigation.capsuleHeight / 2;
    if (frame == null) {
      return Positioned(
        left: 0,
        width: 0,
        top: capsuleCenter,
        height: 0,
        child: widget.motion == null || !shown
            ? const SizedBox.shrink()
            : Semantics(header: true, label: widget.title),
      );
    }
    final align = frame.centered ? TextAlign.center : TextAlign.start;
    Widget out;
    if (!shown) {
      out = const ExcludeSemantics(child: SizedBox.shrink());
    } else {
      final frames = widget.frames;
      out = Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        textScaler: widget.scaler,
        style: style,
      );
      if (widget.subtitle case final subtitle?) {
        out = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: frame.centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.stretch,
          children: [
            out,
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: align,
              textScaler: widget.scaler,
              style: morphInlineSubtitleStyle(widget.subtitleColor),
            ),
          ],
        );
      }
      if (widget.motion == null) out = ExcludeSemantics(child: out);
      out = morphLiveVeiledGlyphs(
        live: frames,
        blur: () => _blur,
        opacity: () => _opacity,
        child: out,
      );
      out = MorphLiveTransform.matrix(
        live: frames,
        alignment: null,
        matrixOf: () {
          final shift = widget.shift();
          return Matrix4.translationValues(
            rtl ? -shift : shift,
            widget.motion?.titleOffset ?? 0,
            0,
          );
        },
        child: out,
      );
      if (debugMorphInlineTitleLayer) out = RepaintBoundary(child: out);
    }
    return Positioned(
      left: frame.left,
      width: frame.width,
      top: capsuleCenter - textHeight / 2,
      height: textHeight,
      child: Semantics(header: true, child: RepaintBoundary(child: out)),
    );
  }
}

/// The large title of a screen: 34 point bold text at the leading edge,
/// in a [MorphNavigationBarMetrics.largeTitleHeight] tall area that
/// scrolls with the content.
///
/// Put it first in the scroll view under a [MorphNavigationBar]; once it
/// has scrolled fully under the bar, show the bar's inline title. With
/// [MorphLargeTitleScrollPhysics] a drag released halfway snaps it back
/// out or fully under, as UIKit does.
class MorphLargeTitle extends StatelessWidget {
  /// Creates a large title.
  const MorphLargeTitle(
    this.title, {
    this.subtitle,
    this.appearance,
    super.key,
  });

  /// The title.
  final String title;

  /// The line under the large title (UIKit `largeSubtitle`, iOS 26), or
  /// null. With it the title turns 22 point bold and the 11 point medium
  /// subtitle sits with its baseline 16 points above the area's bottom,
  /// the title's baseline 6 points above the subtitle's line; the area
  /// grows by [MorphNavigationBarMetrics.largeSubtitleHeight]. Read from
  /// UIKit (notes private), not yet checked on a device.
  final String? subtitle;

  /// The height of the large title area, with or without a [subtitle].
  static double extentFor({required bool subtitle}) =>
      MorphNavigationBarMetrics.largeTitleHeight +
      (subtitle ? MorphNavigationBarMetrics.largeSubtitleHeight : 0);

  /// The look; null resolves it from the theme.
  final MorphBarAppearance? appearance;

  @override
  Widget build(BuildContext context) {
    final look = MorphBarAppearance.resolve(context, appearance);
    final head = Semantics(
      header: true,
      child: SizedBox(
        height: MorphNavigationBarMetrics.largeTitleHeight,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: MorphNavigationBarMetrics.largeTitleInset,
            end: MorphNavigationBarMetrics.largeTitleInset,
            top: MorphNavigationBarMetrics.largeTitleTop,
          ),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: morphLargeTitleStyle(look.titleColor),
              ),
            ),
          ),
        ),
      ),
    );
    final subtitle = this.subtitle;
    if (subtitle == null) return head;
    final titleStyle = morphLargeTitleWithSubtitleStyle(look.titleColor);
    final subtitleStyle = morphLargeSubtitleStyle(look.subtitleColor);
    const height =
        MorphNavigationBarMetrics.largeTitleHeight +
        MorphNavigationBarMetrics.largeSubtitleHeight;
    const subtitleBaseline =
        height - MorphNavigationBarMetrics.largeBaselineInset;
    final ascent = _ascent(subtitle, subtitleStyle);
    final titleBaseline =
        subtitleBaseline -
        ascent -
        MorphNavigationBarMetrics.largeTitleSubtitleGap;
    Widget line(String text, TextStyle style, double baseline) => Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: MorphNavigationBarMetrics.largeTitleInset,
        ),
        child: Baseline(
          baseline: baseline,
          baselineType: TextBaseline.alphabetic,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      header: true,
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            line(title, titleStyle, titleBaseline),
            line(subtitle, subtitleStyle, subtitleBaseline),
          ],
        ),
      ),
    );
  }

  static double _ascent(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    painter.layout();
    final ascent = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.dispose();
    return ascent;
  }
}

/// Scroll physics that settle a large title out of or fully under the
/// bar: a scroll that comes to rest with the title partly scrolled
/// ([collapseExtent] is its height) springs to the nearer end.
///
/// UIKit snaps a release at 25 points back out and one at 35 points
/// under (the threshold is taken as half the title, 26 points); the snap
/// is fitted as a critically damped spring of response [snapSpring].
class MorphLargeTitleScrollPhysics extends ScrollPhysics {
  /// Creates the physics.
  const MorphLargeTitleScrollPhysics({
    this.collapseExtent = MorphNavigationBarMetrics.largeTitleHeight,
    super.parent,
  });

  /// The scroll distance over which the large title goes under the bar.
  final double collapseExtent;

  /// The spring the snap runs on (fitted 0.33 s, damping 1.0..1.2).
  static const snapSpring = MorphSpring(0.33, 1);

  @override
  MorphLargeTitleScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      MorphLargeTitleScrollPhysics(
        collapseExtent: collapseExtent,
        parent: buildParent(ancestor),
      );

  double _restOf(Simulation? simulation, ScrollMetrics position) {
    if (simulation == null) return position.pixels;
    var t = 0.0;
    var x = simulation.x(0);
    while (t < 8 && !simulation.isDone(t)) {
      t += 1 / 60;
      x = simulation.x(t);
    }
    return x;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final base = super.createBallisticSimulation(position, velocity);
    if (position.outOfRange) return base;
    final start = position.minScrollExtent;
    final rest = _restOf(base, position) - start;
    if (rest <= 0.5 || rest >= collapseExtent - 0.5) return base;
    final target = start + (rest < collapseExtent / 2 ? 0 : collapseExtent);
    return ScrollSpringSimulation(
      snapSpring.description,
      position.pixels,
      math.min(target, position.maxScrollExtent),
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}
