import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// The geometry of an inset grouped list, read from the view tree of an
/// iOS 27 `UITableView(style: .insetGrouped)` with
/// `UIListContentConfiguration` cells on a 402 pt wide screen (probe scene
/// `list`, iPhone 18 Pro simulator; tool/ios_reference/spec/lists.md).
abstract final class MorphListMetrics {
  /// How far a section's card stands in from the screen edges: the table's
  /// layout margin on a 402 pt screen.
  static const double sectionInset = 20;

  /// The corner radius of a section's card, fitted to its screenshot
  /// outline (0.3 pt).
  static const double cornerRadius = 26;

  /// The leading inset of a row's text, of the separators and of the
  /// header and footer labels, and the trailing inset of a row without an
  /// accessory.
  static const double contentInset = 16;

  /// The trailing inset of a row's accessory (chevron, switch).
  static const double accessoryInset = 20;

  /// The gap between a row's title and its detail, and between the text
  /// and the accessory (`textToSecondaryTextHorizontalPadding` and the
  /// content's trailing margin, both 8).
  static const double gap = 8;

  /// The height of a single-line row.
  static const double minRowHeight = 53;

  /// The space above and below a row's content: a two-line row is its
  /// content plus twice this (69.33 for a 17 pt title over a 15 pt
  /// subtitle).
  static const double rowPadding = 15.5;

  /// The width of the leading slot that centers a row's symbol 28 pt from
  /// the card's edge; the text then starts 56 pt in.
  static const double leadingWidth = 24;

  /// The gap after the leading slot (`imageToTextPadding`).
  static const double leadingGap = 16;

  /// The point size of a row's leading symbol.
  static const double leadingIconSize = 22;

  /// The thickness of a separator: one point, three pixels at 3x.
  static const double separatorThickness = 1;

  /// The space above a section header's label.
  static const double headerTop = 11.67;

  /// The space between a section header's label and its card.
  static const double headerBottom = 6;

  /// The space above a card without a header.
  static const double noHeaderTop = 17.67;

  /// The space between a card and its footer's label.
  static const double footerTop = 7.67;

  /// The space below a section footer's label.
  static const double footerBottom = 6.67;

  /// The space below a card without a footer.
  static const double noFooterBottom = 17.33;

  /// The size of the disclosure chevron's glyph box.
  static const Size chevronSize = Size(10.33, 14);
}

/// The look of an inset grouped list: [MorphListSection] and
/// [MorphListRow].
///
/// The colors are the iOS 27 system colors the table resolves (probe
/// scene `list`, light and dark).
@immutable
class MorphListStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphListStyle({
    this.backgroundColor = const Color(0xFFF2F2F7),
    this.cellColor = const Color(0xFFFFFFFF),
    this.highlightColor = const Color(0xFFD1D1D6),
    this.separatorColor = const Color(0x1F3C3C43),
    this.titleColor = const Color(0xFF000000),
    this.secondaryColor = const Color(0x993C3C43),
    this.chevronColor = const Color(0x4C3C3C43),
    this.iconColor = const Color(0xFF0088FF),
  });

  /// The page behind the sections: systemGroupedBackground.
  final Color backgroundColor;

  /// The fill of a section's card: secondarySystemGroupedBackground.
  final Color cellColor;

  /// The fill of a pressed row: systemGray4, the grouped cell background
  /// configuration's highlighted and selected color.
  final Color highlightColor;

  /// The separators between rows: separator.
  final Color separatorColor;

  /// A row's title and detail-free text: label.
  final Color titleColor;

  /// A row's subtitle and detail, section headers and footers:
  /// secondaryLabel.
  final Color secondaryColor;

  /// The disclosure chevron: tertiaryLabel (the rendered glyph peaks at
  /// 197 over white and 90 over the dark card).
  final Color chevronColor;

  /// A row's leading symbol: the tint, systemBlue.
  final Color iconColor;

  /// The light appearance.
  static const light = MorphListStyle();

  /// The dark appearance.
  static const dark = MorphListStyle(
    backgroundColor: Color(0xFF000000),
    cellColor: Color(0xFF1C1C1E),
    highlightColor: Color(0xFF3A3A3C),
    separatorColor: Color(0x80545458),
    titleColor: Color(0xFFFFFFFF),
    secondaryColor: Color(0x99EBEBF5),
    chevronColor: Color(0x4CEBEBF5),
    iconColor: Color(0xFF0091FF),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphListStyle resolve(
    BuildContext context,
    MorphListStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.list,
    light: light,
    dark: dark,
  );

  /// Copies this style with the given colors replaced.
  MorphListStyle copyWith({
    Color? backgroundColor,
    Color? cellColor,
    Color? highlightColor,
    Color? separatorColor,
    Color? titleColor,
    Color? secondaryColor,
    Color? chevronColor,
    Color? iconColor,
  }) => MorphListStyle(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    cellColor: cellColor ?? this.cellColor,
    highlightColor: highlightColor ?? this.highlightColor,
    separatorColor: separatorColor ?? this.separatorColor,
    titleColor: titleColor ?? this.titleColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    chevronColor: chevronColor ?? this.chevronColor,
    iconColor: iconColor ?? this.iconColor,
  );

  @override
  bool operator ==(Object other) =>
      other is MorphListStyle &&
      other.backgroundColor == backgroundColor &&
      other.cellColor == cellColor &&
      other.highlightColor == highlightColor &&
      other.separatorColor == separatorColor &&
      other.titleColor == titleColor &&
      other.secondaryColor == secondaryColor &&
      other.chevronColor == chevronColor &&
      other.iconColor == iconColor;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    cellColor,
    highlightColor,
    separatorColor,
    titleColor,
    secondaryColor,
    chevronColor,
    iconColor,
  );
}

/// One section of an inset grouped list, as iOS 27 settings and index
/// screens draw it: an optional [header], the [children] on one rounded
/// card inset from the screen edges, and an optional [footer].
///
/// [MorphListRow]s on the card draw the separators between them. Other
/// children are laid out on the card as they are. Sections stack in a
/// column or as box slivers; the space between two of them comes from
/// their own headers and footers (35 pt between a card without a footer
/// and one without a header).
///
/// The card shades the resting glass in its rows - glass buttons in their
/// trailing or leading slots, say - in one glass layer, as a
/// [MorphGlassContainer] would, and since that glass can read nothing but
/// the card's opaque color, it shades it over that color without reading
/// the backdrop: no backdrop filter at all, instead of one per button. A
/// [MorphListRow] whose highlight shows draws its glass
/// in a layer of its own until the highlight goes, so the glass reads the
/// highlight under it. Frosted controls ([MorphGlassRenderer.frostControls])
/// keep their own layers: their blur reads the rows around them. Content a
/// row's child paints under its own glass belongs in a layer of its own:
/// wrap it in its own [MorphGlassContainer].
///
/// The section paints in a layer of its own, so a scroll view moving it
/// composites that layer instead of repainting its rows.
class MorphListSection extends StatelessWidget {
  /// Creates a section.
  const MorphListSection({
    required this.children,
    this.header,
    this.footer,
    this.style,
    super.key,
  });

  /// The rows on the card.
  final List<Widget> children;

  /// The label above the card: 17 pt semibold secondary text.
  final String? header;

  /// The label below the card: 13 pt secondary text.
  final String? footer;

  /// The look; null resolves it from the theme.
  final MorphListStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = MorphListStyle.resolve(context, style);
    final header = this.header;
    final footer = this.footer;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MorphListMetrics.sectionInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header == null)
              const SizedBox(height: MorphListMetrics.noHeaderTop)
            else
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  MorphListMetrics.contentInset,
                  MorphListMetrics.headerTop,
                  MorphListMetrics.contentInset,
                  MorphListMetrics.headerBottom,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    header,
                    style: MorphTypography.resolve(
                      MorphTypography.listHeader.copyWith(
                        color: look.secondaryColor,
                      ),
                    ),
                  ),
                ),
              ),
            ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(MorphListMetrics.cornerRadius),
              ),
              child: ColoredBox(
                color: look.cellColor,
                child: MorphGlassStage(
                  open: true,
                  sharpOnly: true,
                  // The rows paint above the stage's glass, which sits
                  // straight on the card: it reads nothing but the card.
                  solidBackdrop: look.cellColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++)
                        _RowPlace(
                          last: i == children.length - 1,
                          style: look,
                          child: children[i],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (footer == null)
              const SizedBox(height: MorphListMetrics.noFooterBottom)
            else
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  MorphListMetrics.contentInset,
                  MorphListMetrics.footerTop,
                  MorphListMetrics.contentInset,
                  MorphListMetrics.footerBottom,
                ),
                child: Text(
                  footer,
                  style: MorphTypography.resolve(
                    MorphTypography.listFooter.copyWith(
                      color: look.secondaryColor,
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

class _RowPlace extends InheritedWidget {
  const _RowPlace({
    required this.last,
    required this.style,
    required super.child,
  });

  final bool last;
  final MorphListStyle style;

  static _RowPlace? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowPlace>();

  @override
  bool updateShouldNotify(_RowPlace oldWidget) =>
      last != oldWidget.last || style != oldWidget.style;
}

/// A row of an inset grouped list in the manner of a UIKit list cell
/// (`UIListContentConfiguration` cell, subtitle cell and value cell).
///
/// The [title] reads 17 pt in the label color with an optional 15 pt
/// [subtitle] below it; a [detail] sits at the trailing edge in the
/// secondary color (the value cell), taking at most half the text
/// area and wrapping past it; a [leading] symbol is centered in a
/// slot 28 pt from the card's edge and moves the text and the separator
/// to 56 pt; a [trailing] control (a switch, say) and the
/// disclosure [chevron] end 20 pt from the card's edge. A single-line row
/// is 53 pt tall. Instead of a title, a [child] can fill the row's text
/// area with any content.
///
/// With [onTap] the row is a button: it fills with the highlight color
/// while a finger is down on it (UIKit's grouped cell highlighted color;
/// the highlight's timing is not measured, the row follows Flutter's tap
/// recognizer) and while it has the keyboard focus, and Space or Enter
/// tap it. A disabled row ([enabled] false) ignores touches and keeps its
/// look: the disabled cell look is not measured.
///
/// Inside a [MorphListSection] the row draws the separator below itself,
/// except on the section's last row. Right-to-left text mirrors the row
/// and the chevron.
class MorphListRow extends StatefulWidget {
  /// Creates a row.
  const MorphListRow({
    this.title,
    this.subtitle,
    this.detail,
    this.leading,
    this.trailing,
    this.chevron = false,
    this.child,
    this.onTap,
    this.enabled = true,
    this.style,
    super.key,
  }) : assert(
         title != null || child != null,
         'A row needs a title or a child.',
       );

  /// The primary text, usually a [Text].
  final Widget? title;

  /// The secondary line below [title].
  final Widget? subtitle;

  /// The value at the trailing edge, in the secondary color.
  final Widget? detail;

  /// The symbol before the text, usually an [Icon]; drawn 22 pt in the
  /// tint color unless it sets its own.
  final Widget? leading;

  /// A control at the trailing edge, such as a switch.
  final Widget? trailing;

  /// Whether the disclosure chevron shows at the trailing edge, as on a
  /// row that pushes a screen.
  final bool chevron;

  /// Content that fills the text area instead of [title] and [subtitle].
  final Widget? child;

  /// Called when the row is tapped; null makes the row inert.
  final VoidCallback? onTap;

  /// Whether the row accepts taps.
  final bool enabled;

  /// The look; null takes the enclosing section's, then the theme's.
  final MorphListStyle? style;

  @override
  State<MorphListRow> createState() => _MorphListRowState();
}

class _MorphListRowState extends State<MorphListRow> {
  bool _pressed = false;
  bool _focused = false;

  bool get _active => widget.onTap != null && widget.enabled;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  void didUpdateWidget(MorphListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_active) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final place = _RowPlace.of(context);
    final look =
        widget.style ?? place?.style ?? MorphListStyle.resolve(context, null);
    final titleStyle = MorphTypography.resolve(
      MorphTypography.body.copyWith(color: look.titleColor),
    );
    final secondary = MorphTypography.resolve(
      MorphTypography.body.copyWith(color: look.secondaryColor),
    );
    final subtitleStyle = MorphTypography.resolve(
      MorphTypography.listSubtitle.copyWith(color: look.secondaryColor),
    );
    final leading = widget.leading;
    final title = widget.title;
    final subtitle = widget.subtitle;
    final detail = widget.detail;
    final trailing = widget.trailing;
    final accessory = trailing != null || widget.chevron;
    final textStart =
        MorphListMetrics.contentInset +
        (leading == null
            ? 0
            : MorphListMetrics.leadingWidth + MorphListMetrics.leadingGap);
    Widget content(double width) => Row(
      children: [
        if (leading != null) ...[
          SizedBox(
            width: MorphListMetrics.leadingWidth,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(
                  size: MorphListMetrics.leadingIconSize,
                  color: look.iconColor,
                ),
                child: leading,
              ),
            ),
          ),
          const SizedBox(width: MorphListMetrics.leadingGap),
        ],
        Expanded(
          child: DefaultTextStyle(
            style: titleStyle,
            child:
                widget.child ??
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?title,
                    if (subtitle != null)
                      DefaultTextStyle(style: subtitleStyle, child: subtitle),
                  ],
                ),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(width: MorphListMetrics.gap),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width / 2),
            child: DefaultTextStyle(
              style: secondary,
              textAlign: TextAlign.end,
              child: detail,
            ),
          ),
        ],
        if (accessory) const SizedBox(width: MorphListMetrics.gap),
        ?trailing,
        if (trailing != null && widget.chevron)
          const SizedBox(width: MorphListMetrics.gap),
        if (widget.chevron) _Chevron(color: look.chevronColor),
      ],
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: MorphListMetrics.minRowHeight,
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          MorphListMetrics.contentInset,
          MorphListMetrics.rowPadding,
          accessory
              ? MorphListMetrics.accessoryInset
              : MorphListMetrics.contentInset,
          MorphListMetrics.rowPadding,
        ),
        child: Center(
          widthFactor: 1,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                content(constraints.maxWidth),
          ),
        ),
      ),
    );
    final highlighted = _active && (_pressed || _focused);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? look.highlightColor : null,
      ),
      position: DecorationPosition.background,
      child: row,
    );
    if (place != null && !place.last) {
      body = CustomPaint(
        foregroundPainter: _SeparatorPainter(
          color: look.separatorColor,
          start: textStart,
          direction: Directionality.of(context),
        ),
        child: body,
      );
    }
    body = MorphGlassContainerBarrier(clear: !highlighted, child: body);
    final onTap = widget.onTap;
    return Semantics(
      container: true,
      button: onTap != null,
      enabled: onTap == null ? null : widget.enabled,
      child: MorphControlFocus(
        enabled: _active,
        onHighlight: (bool on) {
          if (_focused != on) setState(() => _focused = on);
        },
        onActivate: _active ? onTap : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: _active ? (_) => _press(true) : null,
          onTapUp: _active ? (_) => _press(false) : null,
          onTapCancel: _active ? () => _press(false) : null,
          onTap: _active ? onTap : null,
          child: body,
        ),
      ),
    );
  }
}

class _SeparatorPainter extends CustomPainter {
  const _SeparatorPainter({
    required this.color,
    required this.start,
    required this.direction,
  });

  final Color color;
  final double start;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    const end = MorphListMetrics.contentInset;
    final left = direction == TextDirection.ltr ? start : end;
    final right = size.width - (direction == TextDirection.ltr ? end : start);
    final paint = Paint();
    paint.color = color;
    canvas.drawRect(
      Rect.fromLTRB(
        left,
        size.height - MorphListMetrics.separatorThickness,
        right,
        size.height,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SeparatorPainter oldDelegate) =>
      color != oldDelegate.color ||
      start != oldDelegate.start ||
      direction != oldDelegate.direction;
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: MorphListMetrics.chevronSize,
      painter: _ChevronPainter(
        color: color,
        mirrored: Directionality.of(context) == TextDirection.rtl,
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => mirrored ? size.width - v : v;
    final path = Path();
    path.moveTo(x(3.7), 1.8);
    path.lineTo(x(8.7), 7);
    path.lineTo(x(3.7), 12.2);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      color != oldDelegate.color || mirrored != oldDelegate.mirrored;
}
