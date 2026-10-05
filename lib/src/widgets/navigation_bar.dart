import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/bar_motion.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/navigation_motion.dart';
import 'package:morph/src/widgets/scroll_edge_effect.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

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

  /// The least space between the inline title and the bar's buttons: the
  /// title stays centered unless it would come closer, then it moves away
  /// from them (`titleControlPadding`).
  static const double titlePadding = 12;
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

/// The buttons a navigation bar leans toward while an interactive pop is
/// in progress: those of the screen the pop leads to.
///
/// While a finger drags a page off the screen, UIKit moves the bar's
/// capsules part of the way toward the places they take on the screen
/// below: each capsule that the destination bar also has (the same group
/// id, or the same place on its side) travels and resizes
/// [MorphNavigationTransition.barDrift] times the page's [progress] of the
/// way, a pure function of the page's position. A cancelled pop drifts
/// back with the returning page; a committed one hands the drifted
/// capsules to the bar's item transition.
@immutable
class MorphNavigationBarDrift {
  /// Creates a drift toward [leading] and [trailing].
  const MorphNavigationBarDrift({
    required this.progress,
    this.leading,
    this.trailing = const [],
  });

  /// The group at the leading edge of the destination bar.
  final MorphBarButtonGroup? leading;

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
    this.leading,
    this.trailing = const [],
    this.titleVisible = true,
    this.scrolledUnder = false,
    this.animate = true,
    this.edgeEffect = MorphScrollEdgeEffectStyle.hard,
    this.edgeEffectTheme,
    this.titleExitShift = -MorphNavigationTransition.parallax,
    this.drift,
    this.style,
    this.menuStyle,
    this.menuTuning = MorphBarMenuTuning.standard,
    this.menuOverlay,
    this.sideInset = MorphNavigationBarMetrics.sideInset,
    super.key,
  });

  /// The inline title.
  final String? title;

  /// The group at the leading edge, such as a back button.
  final MorphBarButtonGroup? leading;

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
  final MorphScrollEdgeEffectThemeData? edgeEffectTheme;

  /// How far a replaced title travels while it fades out, as a share of
  /// the bar's width: on a push the old title rides the page underneath
  /// (-0.3), on a pop the page that leaves (1). The new title fades in
  /// where it stands. Both ride [MorphNavigationTransition.pushSpring].
  final double titleExitShift;

  /// The bar the capsules lean toward during an interactive pop; null
  /// keeps them in place.
  final MorphNavigationBarDrift? drift;

  /// The look; null resolves it from the theme.
  final MorphBarStyle? style;

  /// The look of the buttons' menus, such as the back button's; null
  /// resolves it from the theme.
  final MorphMenuStyle? menuStyle;

  /// The bar buttons' menu recognition, opening delay and menu motion.
  final MorphBarMenuTuning menuTuning;

  /// The overlay the buttons' menus fly in; null uses
  /// [morphPresentationOverlayOf].
  final OverlayState? menuOverlay;

  /// The space between the screen's sides and the outer capsules.
  final double sideInset;

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
  List<double> _capsuleEdges = const [];
  final MorphSpringState _swap = MorphSpringState(
    MorphNavigationTransition.pushSpring,
    1,
  );
  String? _outgoing;
  double _exitShift = 0;
  final Map<(String, TextScaler, TextDirection), Size> _titleSizes = {};

  Size _titleSize(String title, TextScaler scaler, TextDirection direction) {
    if (_titleSizes.length > 8) _titleSizes.clear();
    return _titleSizes.putIfAbsent((title, scaler, direction), () {
      final painter = TextPainter(
        text: TextSpan(
          text: title,
          style: morphInlineTitleStyle(const Color(0xFF000000)),
        ),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      );
      painter.layout();
      final size = painter.size;
      painter.dispose();
      return size;
    });
  }

  @override
  void advanceMotion(double t) {
    _motion.advance(t);
    if (_outgoing != null && _swap.isAtRest(t, 1e-3)) {
      setState(() => _outgoing = null);
    }
  }

  @override
  bool get motionSettled =>
      _motion.isSettled && (_outgoing == null || _swap.isAtRest(clock, 1e-3));

  double get _swapProgress {
    if (_outgoing == null) return 1;
    if (_swap.isAtRest(clock, 1e-3)) return 1;
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
      _exitShift = widget.titleExitShift;
      _swap.setState(clock, 0, MorphNavigationTransition.pushVelocity);
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

  void _onLayout(List<double> edges) {
    if (_listEquals(edges, _capsuleEdges)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _capsuleEdges = edges);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphBarStyle.resolve(context, widget.style);
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
                      style: widget.style,
                      menuStyle: widget.menuStyle,
                      menuTuning: widget.menuTuning,
                      menuOverlay: widget.menuOverlay,
                      onLayout: (layout) => _onLayout([
                        for (final c in layout) ...[c.rect.left, c.rect.right],
                      ]),
                      groups: _placed(leading, widget.trailing),
                      driftGroups: drift == null
                          ? null
                          : _placed(drift.leading, drift.trailing),
                      driftProgress: drift?.progress,
                      driftFactor: MorphNavigationTransition.barDrift,
                      transition: MorphBarTransitionSpec.navigation,
                    ),
                  ),
                  if (_outgoing case final outgoing?)
                    _InlineTitle(
                      title: outgoing,
                      size: _titleSize(outgoing, scaler, direction),
                      scaler: scaler,
                      opacity: () => 1 - _swapProgress,
                      shift: () => _exitShift * width * _swapProgress,
                      motion: null,
                      frames: frames,
                      color: style.titleColor,
                      width: width,
                      edges: _capsuleEdges,
                      direction: direction,
                    ),
                  if (widget.title case final title?)
                    _InlineTitle(
                      title: title,
                      size: _titleSize(title, scaler, direction),
                      scaler: scaler,
                      opacity: () => _swapProgress,
                      shift: () => 0,
                      motion: _motion,
                      frames: frames,
                      color: style.titleColor,
                      width: width,
                      edges: _capsuleEdges,
                      direction: direction,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (edge == null) return bar;
    final extent = MorphNavigationBar.heightFor(top);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: MorphScrollEdgeEffect.bandExtent(
            edge,
            extent,
            MorphScrollEdgeEffectThemeData.resolve(
              context,
              widget.edgeEffectTheme,
            ),
          ),
          child: MorphScrollEdgeEffect.driven(
            extent: extent,
            style: edge,
            theme: widget.edgeEffectTheme,
            opacity: () => _motion.edgeOpacity,
            repaint: frames,
          ),
        ),
        bar,
      ],
    );
  }
}

List<MorphPlacedGroup> _placed(
  MorphBarButtonGroup? leading,
  List<MorphBarButtonGroup> trailing,
) => [
  if (leading != null) MorphPlacedGroup(leading, MorphBarSide.leading),
  for (final g in trailing) MorphPlacedGroup(g, MorphBarSide.trailing),
];

bool _listEquals(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 0.01) return false;
  }
  return true;
}

class _InlineTitle extends StatelessWidget {
  const _InlineTitle({
    required this.title,
    required this.size,
    required this.scaler,
    required this.opacity,
    required this.shift,
    required this.motion,
    required this.frames,
    required this.color,
    required this.width,
    required this.edges,
    required this.direction,
  });

  final String title;
  final Size size;
  final TextScaler scaler;
  final double Function() opacity;
  final double Function() shift;
  final MorphNavigationTitleMotion? motion;
  final Listenable frames;
  final Color color;
  final double width;
  final List<double> edges;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    final style = morphInlineTitleStyle(color);
    final textWidth = size.width;
    final textHeight = size.height;
    const pad = MorphNavigationBarMetrics.titlePadding;
    final center = width / 2;
    var lo = 0.0;
    var hi = width;
    for (var i = 0; i + 1 < edges.length; i += 2) {
      final l = edges[i];
      final r = edges[i + 1];
      if (r <= center) lo = math.max(lo, r + pad);
      if (l >= center) hi = math.min(hi, l - pad);
    }
    final room = math.max(0.0, hi - lo);
    final w = math.min(textWidth, room);
    var left = center - w / 2;
    if (left < lo) left = lo;
    if (left + w > hi) left = math.max(lo, hi - w);
    final capsuleCenter = MorphBarMetrics.navigation.capsuleHeight / 2;
    return Positioned(
      left: left,
      width: w,
      top: capsuleCenter - textHeight / 2,
      height: textHeight,
      child: Semantics(
        header: true,
        child: ListenableBuilder(
          listenable: frames,
          builder: (BuildContext context, Widget? child) {
            final m = motion;
            final opacity = (m?.titleOpacity ?? 1) * this.opacity();
            if (opacity <= 0.001) {
              return const ExcludeSemantics(child: SizedBox.shrink());
            }
            Widget out = child!;
            if (m == null) out = ExcludeSemantics(child: out);
            final blur = m?.titleBlur ?? 0;
            if (blur > 0.05) {
              out = ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.decal,
                ),
                child: out,
              );
            }
            return Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(
                  direction == TextDirection.rtl ? -shift() : shift(),
                  m?.titleOffset ?? 0,
                ),
                child: out,
              ),
            );
          },
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: scaler,
            style: style,
          ),
        ),
      ),
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
  const MorphLargeTitle(this.title, {this.style, super.key});

  /// The title.
  final String title;

  /// The look; null resolves it from the theme.
  final MorphBarStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = MorphBarStyle.resolve(context, style);
    return Semantics(
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
