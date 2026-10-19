import 'package:flutter/widgets.dart';
import 'package:morph/src/theme/localizations.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/highlight_motion.dart';
import 'package:morph/src/widgets/sheet.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/theme/theme.dart';

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

  /// The height of a single-line row: the least height of a row, its
  /// content centered in it.
  static const double minRowHeight = 53;

  /// The space above and below a row's text: a two-line row is its labels
  /// plus twice this (69.33 for a 20.33 pt title over an 18 pt subtitle).
  /// A trailing control and the accessory get none: UIKit centers an
  /// accessory view in the row (a 28 pt switch 12.67 below the top of a
  /// 53 pt row, list-tree fixtures).
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
class MorphListAppearance implements MorphAppearance {
  /// Creates an appearance; the defaults are the iOS light appearance.
  const MorphListAppearance({
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
  static const light = MorphListAppearance();

  /// The dark appearance.
  static const dark = MorphListAppearance(
    backgroundColor: Color(0xFF000000),
    cellColor: Color(0xFF1C1C1E),
    highlightColor: Color(0xFF3A3A3C),
    separatorColor: Color(0x80545458),
    titleColor: Color(0xFFFFFFFF),
    secondaryColor: Color(0x99EBEBF5),
    chevronColor: Color(0x4CEBEBF5),
    iconColor: Color(0xFF0091FF),
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness with [MorphThemeData.tint] as its
  /// [iconColor].
  static MorphListAppearance resolve(
    BuildContext context,
    MorphListAppearance? explicit,
  ) => morphResolveAppearance(
    context,
    explicit,
    light: light,
    dark: dark,
    tinted: (table, tint) => table.copyWith(iconColor: tint),
  );

  /// Copies this appearance with the given colors replaced.
  MorphListAppearance copyWith({
    Color? backgroundColor,
    Color? cellColor,
    Color? highlightColor,
    Color? separatorColor,
    Color? titleColor,
    Color? secondaryColor,
    Color? chevronColor,
    Color? iconColor,
  }) => MorphListAppearance(
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
      other is MorphListAppearance &&
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

/// The page behind an inset grouped list:
/// [MorphListAppearance.backgroundColor] under [child], the
/// `backgroundColor` of a `UITableView(style: .insetGrouped)`.
///
/// Inside a sheet presented with [showMorphSheet] it follows the sheet's
/// background as UIKit's table does: clear while the sheet floats as
/// glass, so the glass shows between the cards, and the grouped gray once
/// the sheet docks at the large detent, fading with the sheet's opaque
/// fill on the same spring and at the same point of a drag (simulator
/// capture: an inset grouped table is clear at the medium detent and
/// systemGroupedBackground at the large one). The fill is read on every
/// frame of the sheet's motion without a rebuild.
class MorphListBackground extends StatelessWidget {
  /// Creates the background.
  const MorphListBackground({this.appearance, this.child, super.key});

  /// The look; null resolves the ambient one.
  final MorphListAppearance? appearance;

  /// The list.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final color = MorphListAppearance.resolve(
      context,
      appearance,
    ).backgroundColor;
    final sheet = morphSheetFillOf(context);
    if (sheet == null) return ColoredBox(color: color, child: child);
    return MorphLiveColoredBox(
      live: sheet.frames,
      colorOf: () => color.withValues(alpha: color.a * sheet.fill()),
      child: child,
    );
  }
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
/// the card's opaque color, on the liquid tier it shades it over that
/// color without reading the backdrop: no backdrop filter at all, instead
/// of one per button. A custom child's glass must be inset from the card's
/// rounded edge by more than its refraction reaches: nearer, it shows the
/// card's color where it would refract the page around the card. A
/// [MorphListRow] whose highlight shows draws its glass
/// in a layer of its own until the highlight goes, so the glass reads the
/// highlight under it. Frosted controls ([GlassBuiltInPainter.frostControls])
/// keep their own backdrop-reading layers: their blur reads the rows
/// around them. Content a
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
    this.appearance,
    super.key,
  });

  /// The rows on the card.
  final List<Widget> children;

  /// The label above the card, usually a [Text]: drawn 17 pt semibold in
  /// the secondary color unless it sets its own style.
  final Widget? header;

  /// The label below the card, usually a [Text]: drawn 13 pt in the
  /// secondary color unless it sets its own style.
  final Widget? footer;

  /// The look; null resolves it from the theme.
  final MorphListAppearance? appearance;

  @override
  Widget build(BuildContext context) {
    final look = MorphListAppearance.resolve(context, appearance);
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
            _sectionHeader(look, header),
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
            _sectionFooter(look, footer),
          ],
        ),
      ),
    );
  }
}

Widget _sectionHeader(MorphListAppearance look, Widget? header) =>
    header == null
    ? const SizedBox(height: MorphListMetrics.noHeaderTop)
    : Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          MorphListMetrics.contentInset,
          MorphListMetrics.headerTop,
          MorphListMetrics.contentInset,
          MorphListMetrics.headerBottom,
        ),
        child: Semantics(
          header: true,
          child: DefaultTextStyle.merge(
            style: MorphTypography.resolve(
              MorphTypography.listHeader.copyWith(color: look.secondaryColor),
            ),
            child: MorphLabelHeight(child: header),
          ),
        ),
      );

Widget _sectionFooter(MorphListAppearance look, Widget? footer) =>
    footer == null
    ? const SizedBox(height: MorphListMetrics.noFooterBottom)
    : Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          MorphListMetrics.contentInset,
          MorphListMetrics.footerTop,
          MorphListMetrics.contentInset,
          MorphListMetrics.footerBottom,
        ),
        child: DefaultTextStyle.merge(
          style: MorphTypography.resolve(
            MorphTypography.listFooter.copyWith(color: look.secondaryColor),
          ),
          child: MorphLabelHeight(child: footer),
        ),
      );

/// A [MorphListSection] as a sliver that builds its rows lazily, for a
/// long list in a [CustomScrollView] (a `UITableView` section of many
/// cells, SwiftUI `Section` in a `List`).
///
/// It looks like [MorphListSection]: [header], the [itemCount] rows that
/// [itemBuilder] builds on one rounded card, [footer]. Rows are built only
/// while they are in view. Each row shades its resting glass over the
/// card's color in a layer of its own, where the column section shades
/// all of them in one.
class MorphSliverListSection extends StatelessWidget {
  /// Creates a section of [itemCount] rows built by [itemBuilder].
  const MorphSliverListSection({
    required this.itemBuilder,
    required this.itemCount,
    this.header,
    this.footer,
    this.appearance,
    super.key,
  });

  /// Builds the row at an index, usually a [MorphListRow].
  final IndexedWidgetBuilder itemBuilder;

  /// The number of rows.
  final int itemCount;

  /// The label above the card; see [MorphListSection.header].
  final Widget? header;

  /// The label below the card; see [MorphListSection.footer].
  final Widget? footer;

  /// The look; null resolves it from the theme.
  final MorphListAppearance? appearance;

  @override
  Widget build(BuildContext context) {
    final look = MorphListAppearance.resolve(context, appearance);
    const radius = Radius.circular(MorphListMetrics.cornerRadius);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: MorphListMetrics.sectionInset,
      ),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: _sectionHeader(look, header)),
          SliverList.builder(
            itemCount: itemCount,
            itemBuilder: (BuildContext context, int i) {
              final first = i == 0;
              final last = i == itemCount - 1;
              return RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: first ? radius : Radius.zero,
                    topRight: first ? radius : Radius.zero,
                    bottomLeft: last ? radius : Radius.zero,
                    bottomRight: last ? radius : Radius.zero,
                  ),
                  child: ColoredBox(
                    color: look.cellColor,
                    child: MorphGlassStage(
                      open: true,
                      sharpOnly: true,
                      solidBackdrop: look.cellColor,
                      child: _RowPlace(
                        last: last,
                        style: look,
                        child: itemBuilder(context, i),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SliverToBoxAdapter(child: _sectionFooter(look, footer)),
        ],
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
  final MorphListAppearance style;

  static _RowPlace? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowPlace>();

  @override
  bool updateShouldNotify(_RowPlace oldWidget) =>
      last != oldWidget.last || style != oldWidget.style;
}

/// The standard accessory of a [MorphListRow], after UIKit's
/// `UITableViewCell.AccessoryType`.
///
/// The checkmark and the detail button are drawn in the tint
/// ([MorphListAppearance.iconColor]). UIKit draws the SF symbol
/// `checkmark` at the emphasized body text style (17 point semibold),
/// medium scale, and the detail button as the SF symbol `info.circle` at
/// its default configuration (read from UIKit, notes private); morph
/// paints both by eye in a 22 point box - the outlines are not read and
/// need a device check.
enum MorphListAccessory {
  /// The disclosure chevron of a row that pushes a screen.
  disclosureIndicator,

  /// A checkmark: the row is the chosen one of a list of options.
  checkmark,

  /// An info button ("i" in a circle); a tap on it calls
  /// [MorphListRow.onAccessoryTap] instead of the row's [MorphListRow.onTap].
  detailButton,

  /// An info button followed by the disclosure chevron.
  detailDisclosureButton,
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
/// [accessory] end 20 pt from the card's edge, centered in the row's
/// height as UIKit centers an accessory view: they take none of the
/// text's padding, so a row with a switch is 53 pt tall like a plain one
/// (a control taller than the row makes it as tall as the control). A
/// single-line row is 53 pt tall. Each line of text is as tall as UIKit
/// makes a label, its font's line height rounded up to the device pixel
/// (20.33 pt for 17 pt SF Pro at 3x), where the text engine rounds it to
/// a whole point. Instead of a title, a [child] can fill the row's text
/// area with any content.
///
/// With [onTap] the row is a button: it fills with the highlight color
/// (UIKit's grouped cell highlighted color) while a finger is down on it,
/// with UIKit's timing ([MorphListRowHighlightMotion]: inside a
/// scrollable after its 0.15 s touch delay, gone at once when a scroll
/// takes the touch, faded out over 0.5 s after a tap), and while it has
/// the keyboard focus, and Space or Enter tap it. A disabled row ([enabled] false) ignores touches and keeps its
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
    this.accessory,
    this.onAccessoryTap,
    this.child,
    this.onTap,
    this.enabled = true,
    this.appearance,
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

  /// The standard accessory at the trailing edge, after [trailing]
  /// (UIKit `accessoryType`); null shows none.
  final MorphListAccessory? accessory;

  /// Called when the info button of a [MorphListAccessory.detailButton] or
  /// [MorphListAccessory.detailDisclosureButton] is tapped (UIKit
  /// `accessoryButtonTappedForRowWith`).
  final VoidCallback? onAccessoryTap;

  /// Content that fills the text area instead of [title] and [subtitle].
  final Widget? child;

  /// Called when the row is tapped; null makes the row inert.
  final VoidCallback? onTap;

  /// Whether the row accepts taps.
  final bool enabled;

  /// The look; null takes the enclosing section's, then the theme's.
  final MorphListAppearance? appearance;

  @override
  State<MorphListRow> createState() => _MorphListRowState();
}

class _MorphListRowState extends State<MorphListRow>
    with SingleTickerProviderStateMixin, MorphClock {
  final MorphListRowHighlightMotion _highlight = MorphListRowHighlightMotion();
  final ValueNotifier<double> _strength = ValueNotifier(0);
  bool _focused = false;
  double? _downAt;
  double? _upAt;

  bool get _active => widget.onTap != null && widget.enabled;

  @override
  void advanceMotion(double t) => _strength.value = _highlight.opacity(t);

  @override
  bool get motionSettled => _highlight.isSettled(clock);

  @override
  double? get motionWakeTime => _highlight.wakeTime(clock);

  void _pointerDown(PointerDownEvent event) {
    final t = _downAt = stamp(event);
    _highlight.touch(t);
    wake();
  }

  void _tapDown() {
    final delay = Scrollable.maybeOf(context) == null
        ? 0.0
        : MorphListRowHighlightMotion.touchDelay;
    _highlight.press(_downAt ?? clock, clock, delay: delay);
    wake();
  }

  void _tapUp() {
    _highlight.release(_upAt ?? clock);
    wake();
  }

  void _tapCancel() {
    _highlight.cancel();
    _strength.value = 0;
  }

  @override
  void didUpdateWidget(MorphListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_active) _tapCancel();
  }

  @override
  void dispose() {
    _strength.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final place = _RowPlace.of(context);
    final look =
        widget.appearance ??
        place?.style ??
        MorphListAppearance.resolve(context, null);
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
    final kind = widget.accessory;
    final chevron =
        kind == MorphListAccessory.disclosureIndicator ||
        kind == MorphListAccessory.detailDisclosureButton;
    final info =
        kind == MorphListAccessory.detailButton ||
        kind == MorphListAccessory.detailDisclosureButton;
    final check = kind == MorphListAccessory.checkmark;
    final mark = chevron || info || check;
    final accessory = trailing != null || mark;
    final textStart =
        MorphListMetrics.contentInset +
        (leading == null
            ? 0
            : MorphListMetrics.leadingWidth + MorphListMetrics.leadingGap);
    Widget content(double width) => Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: MorphListMetrics.rowPadding,
            ),
            child: Row(
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
                            if (title != null) MorphLabelHeight(child: title),
                            if (subtitle != null)
                              DefaultTextStyle(
                                style: subtitleStyle,
                                child: MorphLabelHeight(child: subtitle),
                              ),
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
                      child: MorphLabelHeight(child: detail),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (accessory) const SizedBox(width: MorphListMetrics.gap),
        ?trailing,
        if (trailing != null && mark)
          const SizedBox(width: MorphListMetrics.gap),
        if (check) _Glyph(painter: _CheckPainter(look.iconColor)),
        if (info)
          Semantics(
            container: true,
            button: true,
            label: MorphLocalizations.of(context).moreInfoLabel,
            onTap: widget.onAccessoryTap,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: widget.onAccessoryTap,
              child: _Glyph(painter: _InfoPainter(look.iconColor)),
            ),
          ),
        if (info && chevron) const SizedBox(width: MorphListMetrics.gap),
        if (chevron) _Chevron(color: look.chevronColor),
      ],
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: MorphListMetrics.minRowHeight,
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: MorphListMetrics.contentInset,
          end: accessory
              ? MorphListMetrics.accessoryInset
              : MorphListMetrics.contentInset,
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
    final separator = place != null && !place.last
        ? _SeparatorPainter(
            color: look.separatorColor,
            start: textStart,
            direction: Directionality.of(context),
          )
        : null;
    final focused = _active && _focused;
    final Widget body = ValueListenableBuilder<double>(
      valueListenable: _strength,
      child: row,
      builder: (BuildContext context, double strength, Widget? row) {
        final shown = focused ? 1.0 : strength;
        final color = look.highlightColor;
        Widget body = DecoratedBox(
          decoration: BoxDecoration(
            color: shown <= 0
                ? null
                : shown >= 1
                ? color
                : color.withValues(alpha: color.a * shown),
          ),
          position: DecorationPosition.background,
          child: row,
        );
        if (separator != null) {
          body = CustomPaint(foregroundPainter: separator, child: body);
        }
        return MorphGlassContainerBarrier(clear: shown <= 0, child: body);
      },
    );
    final onTap = widget.onTap;
    return Semantics(
      container: true,
      button: onTap != null,
      selected: check ? true : null,
      enabled: onTap == null ? null : widget.enabled,
      child: MorphControlFocus(
        enabled: _active,
        onHighlight: (bool on) {
          if (_focused != on) setState(() => _focused = on);
        },
        onActivate: _active ? onTap : null,
        child: Listener(
          onPointerDown: _active ? _pointerDown : null,
          onPointerUp: _active ? (event) => _upAt = stamp(event) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: _active ? (_) => _tapDown() : null,
            onTapUp: _active ? (_) => _tapUp() : null,
            onTapCancel: _active ? _tapCancel : null,
            onTap: _active ? onTap : null,
            child: body,
          ),
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

/// The box of a checkmark or an info button: 22 pt, the size of a body
/// symbol (by eye, not measured).
class _Glyph extends StatelessWidget {
  const _Glyph({required this.painter});

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(22), painter: painter);
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.52);
    path.lineTo(size.width * 0.42, size.height * 0.74);
    path.lineTo(size.width * 0.82, size.height * 0.26);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}

class _InfoPainter extends CustomPainter {
  const _InfoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 0.75;
    final ring = Paint();
    ring.color = color;
    ring.style = PaintingStyle.stroke;
    ring.strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ring);
    final fill = Paint();
    fill.color = color;
    canvas.drawCircle(center.translate(0, -radius * 0.45), 1.3, fill);
    final stem = Paint();
    stem.color = color;
    stem.strokeWidth = 2;
    stem.strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(0, -radius * 0.12),
      center.translate(0, radius * 0.5),
      stem,
    );
  }

  @override
  bool shouldRepaint(_InfoPainter oldDelegate) => color != oldDelegate.color;
}
