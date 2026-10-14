import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/widgets/tab_bar.dart';
import 'package:morph/src/widgets/typography.dart';

/// The capsule that fills [rect], at the origin.
@internal
RRect morphCapsuleIn(Rect rect) => RRect.fromRectAndRadius(
  Offset.zero & rect.size,
  Radius.circular(math.min(rect.width, rect.height) / 2),
);

/// A tab bar shrinking into a circle that keeps its selected tab's glyph,
/// as UIKit's floating tab bar collapses while a search tab is active or
/// while the bar is minimized.
///
/// [rect] is the glass's box now and [restRect] the expanded bar's, both in
/// the parent's coordinates; the widget is laid out at [rect]. [progress]
/// runs the content from the bar (0) to the circle (1): the other tabs
/// fade, the selected glyph travels to the circle's center and its label
/// shrinks away. With [drawsGlass] false the caller draws the glass.
@internal
class MorphCollapsingTabs extends StatelessWidget {
  /// Creates the collapsing tabs.
  const MorphCollapsingTabs({
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
    required this.enabled,
    this.drawsGlass = true,
    super.key,
  });

  /// Notifies on every frame of the morph.
  final Listenable live;

  /// The bar's tabs.
  final List<MorphTabItem> items;

  /// The selected tab.
  final int selected;

  /// The content's progress from the bar (0) to the circle (1).
  final double Function() progress;

  /// The expanded bar's box.
  final Rect restRect;

  /// The glass's box now.
  final Rect Function() rect;

  /// Whether the selected tab's label still shows.
  final ValueListenable<bool> labelShown;

  /// The bar's look.
  final MorphTabBarAppearance style;

  /// The installed glass painter, if any.
  final MorphGlassPainter? glass;

  /// The glass's brightness.
  final Brightness brightness;

  /// Whether the tabs run right to left.
  final bool rtl;

  /// What screen readers announce for the circle.
  final String label;

  /// Called when the circle is tapped.
  final VoidCallback onTap;

  /// Whether the circle takes keyboard focus; it does while it takes
  /// touches.
  final ValueListenable<bool> enabled;

  /// Whether the widget draws its glass itself.
  final bool drawsGlass;

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
      child: ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (BuildContext context, bool enabled, Widget? child) =>
            MorphPress(
              enabled: enabled,
              onActivate: onTap,
              focusRing: true,
              focusSemantics: false,
              child: child!,
            ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (drawsGlass)
                Positioned.fill(
                  child: glass == null
                      ? CustomPaint(
                          painter: MorphCapsulePainter(
                            live: live,
                            shape: () => morphCapsuleIn(rect()),
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
                              shape: morphCapsuleIn(rect()),
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
                      BorderRadius.circular(morphCapsuleIn(rect()).tlRadiusX),
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
                        child: ValueListenableBuilder<bool>(
                          valueListenable: labelShown,
                          builder:
                              (BuildContext context, bool shown, Widget? _) =>
                                  _SelectedGlyph(
                                    live: live,
                                    item: items[selected],
                                    color: () => Color.lerp(
                                      style.selectedColor,
                                      style.color,
                                      q(),
                                    )!,
                                    fade: fade,
                                    labelShown: shown,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

/// Paints a flat capsule body with its shadow, repainting on [live]: the
/// glass of a tab bar part when no painter is installed.
@internal
class MorphCapsulePainter extends CustomPainter {
  /// Creates the painter.
  MorphCapsulePainter({
    required Listenable live,
    required this.shape,
    required this.color,
    required this.shadow,
  }) : super(repaint: live);

  /// The capsule now.
  final RRect Function() shape;

  /// The fill now.
  final Color Function() color;

  /// The shadow's color.
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
  bool shouldRepaint(MorphCapsulePainter oldDelegate) => true;
}
