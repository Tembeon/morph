import 'dart:math' as math;
import 'dart:ui';

import 'package:morph/src/widgets/menu_entries.dart';

/// The measured layout of the inside of an iOS 27 menu.
///
/// Read from the view tree of `UIButton` menus on the iPhone 16 Pro (iOS
/// 27.0.1, light and dark, 2026-10-03): `_UIContextMenuListView`,
/// `_UIContextMenuCell`, `_UIContextMenuHeaderView`,
/// `_UIContextMenuSeparatorView`, `_UIContextMenuSubmenuTitleView`.
/// Lengths are points from the menu's leading edge or top.
class MorphMenuMetrics {
  /// Creates metrics from explicit values.
  const MorphMenuMetrics({
    this.width = 250,
    this.topInset = 10,
    this.bottomInset = 10,
    this.rowHeight = 42,
    this.subtitleRowHeight = 60,
    this.extraLineHeight = 22,
    this.imageCenter = 40,
    this.titleStart = 64,
    this.selectionCheckCenter = 27.7,
    this.selectionImageCenter = 55,
    this.selectionTitleStart = 79,
    this.selectionOnlyTitleStart = 52,
    this.plainTitleStart = 28,
    this.titleEnd = 222,
    this.chevronCenter = 219,
    this.headerHeight = 40.33,
    this.headerLabelTop = 12,
    this.headerStart = 28,
    this.selectionHeaderStart = 43,
    this.rowsAfterHeader = 38.33,
    this.cellsAfterHeader = 28.33,
    this.groupGap = 21,
    this.cellGroupGap = 1,
    this.separatorInset = 24,
    this.paletteCellWidth = 42.67,
    this.paletteMaxCellWidth = 62.67,
    this.paletteCellHeight = 54,
    this.paletteImageSize = 22,
    this.palettePlatter = 38,
    this.palettePlatterRadius = 10,
    this.cellInset = 8,
    this.smallCellHeight = 51.67,
    this.smallPerRow = 4,
    this.mediumCellHeight = 77,
    this.mediumPerRow = 3,
    this.mediumLabelTop = 44.67,
    this.cardHeaderHeight = 62,
    this.widgetInset = 16,
    this.maxHeight = 520,
  });

  /// The width of the menu.
  final double width;

  /// The space above the first row.
  final double topInset;

  /// The space below the last row.
  final double bottomInset;

  /// The height of a row.
  final double rowHeight;

  /// The height of a row with a subtitle (title 17 pt, subtitle 13 pt 23 pt
  /// below the title's top).
  final double subtitleRowHeight;

  /// The height a row gains per extra title line; not measured (the line
  /// height of the 17 pt title).
  final double extraLineHeight;

  /// The center of a row's glyph.
  final double imageCenter;

  /// The start of a row's title.
  final double titleStart;

  /// The center of the checkmark in a menu with a selection column.
  final double selectionCheckCenter;

  /// The center of a row's glyph in a menu with a selection column.
  final double selectionImageCenter;

  /// The start of a row's title in a menu with a selection column.
  final double selectionTitleStart;

  /// The start of a row's title in a menu with a selection column and no
  /// glyphs; not measured.
  final double selectionOnlyTitleStart;

  /// The start of a row's title in a menu without glyphs.
  final double plainTitleStart;

  /// The end of a row's title, before the trailing chevron.
  final double titleEnd;

  /// The center of a submenu row's chevron and of a card header's.
  final double chevronCenter;

  /// The height of a section header.
  final double headerHeight;

  /// The top of a section header's 13 pt label.
  final double headerLabelTop;

  /// The start of a section header's label.
  final double headerStart;

  /// The start of a section header's label in a menu with a selection
  /// column.
  final double selectionHeaderStart;

  /// The distance from a section header's top to its first row: the rows
  /// overlap the header's lower part.
  final double rowsAfterHeader;

  /// The distance from a section header's top to a row of cells.
  final double cellsAfterHeader;

  /// The gap between two groups of rows, with the hairline in its middle.
  final double groupGap;

  /// The gap after a group of small or medium cells, which holds the
  /// hairline; a palette is followed by no gap and no line.
  final double cellGroupGap;

  /// The inset of the group hairline from both sides of the menu.
  final double separatorInset;

  /// The width of a palette cell for five or more cells.
  final double paletteCellWidth;

  /// The widest palette cell (three cells, SwiftUI's palette picker).
  final double paletteMaxCellWidth;

  /// The height of a palette cell.
  final double paletteCellHeight;

  /// The size of a palette cell's glyph.
  final double paletteImageSize;

  /// The side of the platter under the selected palette cell, read from a
  /// screenshot.
  final double palettePlatter;

  /// The corner radius of the palette platter; not measured.
  final double palettePlatterRadius;

  /// The inset of small and medium cells from the menu's sides.
  final double cellInset;

  /// The height of a small cell.
  final double smallCellHeight;

  /// Small cells per line.
  final int smallPerRow;

  /// The height of a medium cell.
  final double mediumCellHeight;

  /// Medium cells per line.
  final int mediumPerRow;

  /// The top of a medium cell's 12 pt label.
  final double mediumLabelTop;

  /// The height of a submenu card's header.
  final double cardHeaderHeight;

  /// The inset of a [MorphMenuWidget] row from the menu's sides; morph's
  /// own (no native element).
  final double widgetInset;

  /// The tallest a menu gets; taller content scrolls inside it.
  final double maxHeight;

  /// The measured iOS 27 menu.
  static const standard = MorphMenuMetrics();
}

/// What choosing a [MorphMenuTarget] does.
enum MorphMenuTargetKind {
  /// Runs an item's action.
  action,

  /// Opens a submenu card.
  submenu,

  /// Closes the top submenu card.
  back,
}

/// A place in a menu that reacts to a touch.
class MorphMenuTarget {
  /// Creates a target.
  const MorphMenuTarget({
    required this.rect,
    this.kind = MorphMenuTargetKind.action,
    this.keepsOpen = false,
    this.entry,
    this.element = -1,
  });

  /// The frame, in the coordinates of its card's content.
  final Rect rect;

  /// What choosing the target does.
  final MorphMenuTargetKind kind;

  /// Whether the menu stays open after the target's action.
  final bool keepsOpen;

  /// The entry behind the target.
  final MorphMenuEntry? entry;

  /// The index of the element the target belongs to in
  /// [MorphMenuLayout.elements], or -1.
  final int element;
}

/// The kind of a [MorphMenuPlaced] element.
enum MorphMenuPlacedKind {
  /// A full-width row of an item or a submenu.
  row,

  /// A section header.
  header,

  /// The hairline between two groups.
  separator,

  /// A palette cell.
  palette,

  /// A small cell.
  small,

  /// A medium cell.
  medium,

  /// The row shown while a deferred group loads.
  loading,

  /// A free-form row.
  widget,

  /// The header of a submenu card.
  cardHeader,
}

/// One element of a laid out menu.
class MorphMenuPlaced {
  /// Creates an element.
  const MorphMenuPlaced({
    required this.kind,
    required this.rect,
    this.entry,
    this.title,
    this.checkCenter,
    this.imageCenter,
    this.titleStart = 0,
    this.titleEnd = 0,
    this.maxLines = 1,
    this.target = -1,
    this.key,
  });

  /// The kind of the element.
  final MorphMenuPlacedKind kind;

  /// The frame, in the coordinates of its card's content.
  final Rect rect;

  /// The entry drawn, if any.
  final MorphMenuEntry? entry;

  /// The text of a header or a loading row.
  final String? title;

  /// The center of the selection mark from the leading edge, when the
  /// menu has a selection column.
  final double? checkCenter;

  /// The center of the glyph from the leading edge, when the menu has a
  /// glyph column.
  final double? imageCenter;

  /// The start of the title from the leading edge.
  final double titleStart;

  /// The end of the title from the leading edge.
  final double titleEnd;

  /// The most lines the title wraps to.
  final int maxLines;

  /// The index of the element's target in [MorphMenuLayout.targets], or -1.
  final int target;

  /// The identity of a free-form row's measured height.
  final Object? key;
}

/// The laid out content of one menu card: its height, what it draws and
/// where it reacts to touches.
class MorphMenuLayout {
  /// Creates a layout.
  const MorphMenuLayout({
    required this.height,
    this.width = 250,
    this.targets = const [],
    this.elements = const [],
    this.loading = false,
  });

  /// [rows] rows of [rowHeight] between [inset]s, reversed when
  /// [reversed]: target `i` is row `i`.
  factory MorphMenuLayout.uniform(
    int rows, {
    double width = 250,
    double rowHeight = 42,
    double inset = 10,
    bool reversed = false,
  }) {
    return MorphMenuLayout(
      height: 2 * inset + rowHeight * rows,
      width: width,
      targets: [
        for (var i = 0; i < rows; i++)
          MorphMenuTarget(
            rect: Rect.fromLTWH(
              0,
              inset + rowHeight * (reversed ? rows - 1 - i : i),
              width,
              rowHeight,
            ),
          ),
      ],
    );
  }

  /// Lays out [entries] as the iOS 27 menu does.
  ///
  /// [header] makes it a submenu card under that submenu's header.
  /// [resolve] answers a deferred group, null while it loads;
  /// [widgetHeight] answers the height of a free-form row (keyed by its
  /// id or its place); [titleLines] answers how many lines a title takes
  /// when it may wrap to more than one. [reversed] reverses the groups
  /// and the rows inside them, for a menu opening upward; [rtl] mirrors
  /// the frames.
  factory MorphMenuLayout.build(
    List<MorphMenuEntry> entries, {
    MorphMenuMetrics metrics = MorphMenuMetrics.standard,
    bool reversed = false,
    bool rtl = false,
    bool singleSelection = false,
    MorphMenuElementSize elementSize = MorphMenuElementSize.large,
    MorphSubmenu? header,
    List<MorphMenuEntry>? Function(MorphMenuDeferred deferred)? resolve,
    double? Function(Object key)? widgetHeight,
    int Function(String title, double width, int maxLines)? titleLines,
  }) {
    final groups = <_Group>[];
    var loading = false;
    _Group? open;
    var widgetIndex = 0;
    _Kind kindOf(MorphMenuElementSize size, {required bool palette}) => palette
        ? _Kind.palette
        : switch (size) {
            MorphMenuElementSize.small => _Kind.small,
            MorphMenuElementSize.medium => _Kind.medium,
            MorphMenuElementSize.large ||
            MorphMenuElementSize.automatic => _Kind.rows,
          };
    final rootKind = kindOf(elementSize, palette: false);
    void flush() {
      final group = open;
      if (group != null && group.items.isNotEmpty) groups.add(group);
      open = null;
    }

    void add(
      List<MorphMenuEntry> list,
      _Kind kind,
      int maxLines, {
      required bool section,
    }) {
      for (final entry in list) {
        switch (entry) {
          case MorphMenuItem(:final hidden) when hidden:
          case MorphSubmenu(:final hidden) when hidden:
            break;
          case MorphMenuItem() || MorphSubmenu():
            (open ??= _Group(kind, maxLines)).items.add(entry);
          case MorphMenuWidget():
            (open ??= _Group(
              kind,
              maxLines,
            )).items.add(_WidgetSlot(entry, entry.id ?? widgetIndex));
            widgetIndex++;
          case MorphMenuDivider():
            if (!section) flush();
          case MorphMenuDeferred():
            final answer = resolve?.call(entry);
            if (answer == null) {
              loading = true;
              (open ??= _Group(
                kind,
                maxLines,
              )).items.add(_LoadingSlot(entry.loadingTitle));
            } else {
              add(answer, kind, maxLines, section: section);
            }
          case MorphMenuSection():
            flush();
            final sectionKind = kindOf(
              entry.elementSize,
              palette: entry.palette,
            );
            open = _Group(
              sectionKind,
              entry.maxTitleLines ?? 1,
              header: entry.title,
              singleSelection: entry.singleSelection,
            );
            add(
              entry.children,
              sectionKind,
              entry.maxTitleLines ?? 1,
              section: true,
            );
            final group = open;
            if (group != null && group.items.isEmpty && entry.title != null) {
              open = null;
            } else {
              flush();
            }
        }
      }
    }

    add(entries, rootKind, 1, section: false);
    flush();
    if (reversed) {
      groups.setAll(0, groups.reversed.toList());
      for (final group in groups) {
        if (group.kind == _Kind.rows) {
          group.items.setAll(0, group.items.reversed.toList());
        }
      }
    }

    var selection = singleSelection;
    for (final group in groups) {
      if (group.singleSelection) selection = true;
      if (group.kind != _Kind.rows) continue;
      for (final item in group.items) {
        if (item is MorphMenuItem && item.state != MorphMenuState.off) {
          selection = true;
        }
      }
    }
    bool imagesOf(_Group group) => group.items.any(
      (Object item) => switch (item) {
        MorphMenuItem(:final icon, :final iconVisibility) =>
          icon != null && iconVisibility != .hidden,
        MorphSubmenu(:final icon) => icon != null,
        _LoadingSlot() => true,
        _ => false,
      },
    );
    final m = metrics;
    final width = m.width;
    final double? check = selection ? m.selectionCheckCenter : null;
    final headerStart = selection ? m.selectionHeaderStart : m.headerStart;

    final elements = <MorphMenuPlaced>[];
    final targets = <MorphMenuTarget>[];
    Rect mirror(Rect r) => rtl
        ? Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom)
        : r;
    void place(
      MorphMenuPlaced Function(int target) element, {
      MorphMenuTargetKind? kind,
      bool keepsOpen = false,
      MorphMenuEntry? entry,
      required Rect rect,
    }) {
      final index = elements.length;
      var target = -1;
      if (kind != null) {
        target = targets.length;
        targets.add(
          MorphMenuTarget(
            rect: mirror(rect),
            kind: kind,
            keepsOpen: keepsOpen,
            entry: entry,
            element: index,
          ),
        );
      }
      elements.add(element(target));
    }

    var y = 0.0;
    if (header != null) {
      final rect = Rect.fromLTWH(0, 0, width, m.cardHeaderHeight);
      place(
        (int target) => MorphMenuPlaced(
          kind: MorphMenuPlacedKind.cardHeader,
          rect: mirror(rect),
          entry: header,
          title: header.title,
          imageCenter: header.icon == null ? null : m.imageCenter,
          titleStart: header.icon == null ? m.plainTitleStart : m.titleStart,
          titleEnd: m.titleEnd,
          target: target,
        ),
        kind: MorphMenuTargetKind.back,
        entry: header,
        rect: rect,
      );
      y = m.cardHeaderHeight;
    }
    _Kind? previous;
    for (final group in groups) {
      if (previous == null) {
        if (group.header == null) y += m.topInset;
      } else {
        final gap = switch (previous) {
          _Kind.rows => m.groupGap,
          _Kind.small || _Kind.medium => m.cellGroupGap,
          _Kind.palette => 0.0,
        };
        if (previous != _Kind.palette) {
          final line = y + gap / 2;
          elements.add(
            MorphMenuPlaced(
              kind: MorphMenuPlacedKind.separator,
              rect: Rect.fromLTRB(
                m.separatorInset,
                line - 0.5,
                width - m.separatorInset,
                line + 0.5,
              ),
            ),
          );
        }
        y += gap;
      }
      final title = group.header;
      if (title != null) {
        elements.add(
          MorphMenuPlaced(
            kind: MorphMenuPlacedKind.header,
            rect: mirror(Rect.fromLTWH(0, y, width, m.headerHeight)),
            title: title,
            titleStart: headerStart,
            titleEnd: m.titleEnd,
          ),
        );
        y += group.kind == _Kind.rows ? m.rowsAfterHeader : m.cellsAfterHeader;
      }
      switch (group.kind) {
        case _Kind.rows:
          final images = imagesOf(group);
          final double? image = images
              ? (selection ? m.selectionImageCenter : m.imageCenter)
              : null;
          final titleStart = switch ((selection, images)) {
            (true, true) => m.selectionTitleStart,
            (false, true) => m.titleStart,
            (true, false) => m.selectionOnlyTitleStart,
            (false, false) => m.plainTitleStart,
          };
          for (final item in group.items) {
            switch (item) {
              case MorphMenuItem():
                var lines = 1;
                if (group.maxLines > 1 && titleLines != null) {
                  lines = math.min(
                    group.maxLines,
                    titleLines(
                      item.title,
                      m.titleEnd - titleStart,
                      group.maxLines,
                    ),
                  );
                }
                final height =
                    (item.subtitle == null
                        ? m.rowHeight
                        : m.subtitleRowHeight) +
                    (lines - 1) * m.extraLineHeight;
                final rect = Rect.fromLTWH(0, y, width, height);
                place(
                  (int target) => MorphMenuPlaced(
                    kind: MorphMenuPlacedKind.row,
                    rect: mirror(rect),
                    entry: item,
                    checkCenter: check,
                    imageCenter: image,
                    titleStart: titleStart,
                    titleEnd: m.titleEnd,
                    maxLines: group.maxLines,
                    target: target,
                  ),
                  kind: item.enabled ? MorphMenuTargetKind.action : null,
                  keepsOpen: item.keepsMenuOpen,
                  entry: item,
                  rect: rect,
                );
                y += height;
              case MorphSubmenu():
                final height = item.subtitle == null
                    ? m.rowHeight
                    : m.subtitleRowHeight;
                final rect = Rect.fromLTWH(0, y, width, height);
                place(
                  (int target) => MorphMenuPlaced(
                    kind: MorphMenuPlacedKind.row,
                    rect: mirror(rect),
                    entry: item,
                    checkCenter: check,
                    imageCenter: image,
                    titleStart: titleStart,
                    titleEnd: m.titleEnd,
                    target: target,
                  ),
                  kind: item.enabled ? MorphMenuTargetKind.submenu : null,
                  entry: item,
                  rect: rect,
                );
                y += height;
              case _WidgetSlot(:final widget, :final key):
                final height =
                    widget.height ?? widgetHeight?.call(key) ?? m.rowHeight;
                elements.add(
                  MorphMenuPlaced(
                    kind: MorphMenuPlacedKind.widget,
                    rect: mirror(Rect.fromLTWH(0, y, width, height)),
                    entry: widget,
                    titleStart: m.widgetInset,
                    titleEnd: width - m.widgetInset,
                    key: key,
                  ),
                );
                y += height;
              case _LoadingSlot(:final title):
                elements.add(
                  MorphMenuPlaced(
                    kind: MorphMenuPlacedKind.loading,
                    rect: mirror(Rect.fromLTWH(0, y, width, m.rowHeight)),
                    title: title,
                    checkCenter: check,
                    imageCenter: image ?? m.imageCenter,
                    titleStart: images ? titleStart : m.titleStart,
                    titleEnd: m.titleEnd,
                  ),
                );
                y += m.rowHeight;
            }
          }
        case _Kind.palette:
          final cells = group.items.whereType<MorphMenuEntry>().toList();
          final n = math.max(1, cells.length);
          final cell = math.min(
            m.paletteMaxCellWidth,
            m.paletteCellWidth * 5 / n,
          );
          var x = (width - cell * n) / 2;
          for (final entry in cells) {
            final rect = Rect.fromLTWH(x, y, cell, m.paletteCellHeight);
            _placeCell(place, entry, rect, mirror, MorphMenuPlacedKind.palette);
            x += cell;
          }
          y += m.paletteCellHeight;
        case _Kind.small || _Kind.medium:
          final small = group.kind == _Kind.small;
          final perRow = small ? m.smallPerRow : m.mediumPerRow;
          final height = small ? m.smallCellHeight : m.mediumCellHeight;
          final cells = group.items.whereType<MorphMenuEntry>().toList();
          final cell = (width - 2 * m.cellInset) / perRow;
          for (var i = 0; i < cells.length; i++) {
            final column = i % perRow;
            if (column == 0 && i > 0) y += height;
            final rect = Rect.fromLTWH(
              m.cellInset + column * cell,
              y,
              cell,
              height,
            );
            _placeCell(
              place,
              cells[i],
              rect,
              mirror,
              small ? MorphMenuPlacedKind.small : MorphMenuPlacedKind.medium,
            );
          }
          if (cells.isNotEmpty) y += height;
      }
      previous = group.kind;
    }
    y += groups.isEmpty && header == null ? m.topInset : m.bottomInset;
    return MorphMenuLayout(
      height: y,
      width: width,
      targets: targets,
      elements: elements,
      loading: loading,
    );
  }

  /// The height of the content.
  final double height;

  /// The width of the content.
  final double width;

  /// The places that react to touches.
  final List<MorphMenuTarget> targets;

  /// What the content draws.
  final List<MorphMenuPlaced> elements;

  /// Whether a deferred group is still loading.
  final bool loading;

  /// The index of the target at [position] in content coordinates, or
  /// null.
  int? targetAt(Offset position) {
    for (var i = 0; i < targets.length; i++) {
      if (targets[i].rect.contains(position)) return i;
    }
    return null;
  }
}

void _placeCell(
  void Function(
    MorphMenuPlaced Function(int target) element, {
    MorphMenuTargetKind? kind,
    bool keepsOpen,
    MorphMenuEntry? entry,
    required Rect rect,
  })
  place,
  MorphMenuEntry entry,
  Rect rect,
  Rect Function(Rect) mirror,
  MorphMenuPlacedKind kind,
) {
  final (enabled, targetKind, keepsOpen) = switch (entry) {
    MorphMenuItem(:final enabled, :final keepsMenuOpen) => (
      enabled,
      MorphMenuTargetKind.action,
      keepsMenuOpen,
    ),
    MorphSubmenu(:final enabled) => (
      enabled,
      MorphMenuTargetKind.submenu,
      false,
    ),
    _ => (false, MorphMenuTargetKind.action, false),
  };
  place(
    (int target) => MorphMenuPlaced(
      kind: kind,
      rect: mirror(rect),
      entry: entry,
      target: target,
    ),
    kind: enabled ? targetKind : null,
    keepsOpen: keepsOpen,
    entry: entry,
    rect: rect,
  );
}

enum _Kind { rows, palette, small, medium }

class _Group {
  _Group(this.kind, this.maxLines, {this.header, this.singleSelection = false});

  final _Kind kind;
  final int maxLines;
  final String? header;
  final bool singleSelection;
  final List<Object> items = [];
}

class _WidgetSlot {
  const _WidgetSlot(this.widget, this.key);

  final MorphMenuWidget widget;
  final Object key;
}

class _LoadingSlot {
  const _LoadingSlot(this.title);

  final String title;
}
