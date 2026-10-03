import 'package:flutter/widgets.dart';

/// One element of a menu: a row, a section, a submenu, a divider, a
/// deferred group or a free-form row.
///
/// The entries mirror UIKit's menu elements (`UIAction`, `UIMenu`,
/// `UIDeferredMenuElement`) and SwiftUI's `Menu` content (`Button`,
/// `Section`, `Divider`, nested `Menu`); [MorphMenuWidget] is morph's own
/// extension with no native twin.
sealed class MorphMenuEntry {
  /// Creates an entry.
  const MorphMenuEntry();
}

/// The selection mark of a [MorphMenuItem]: UIKit's `UIMenuElementState`.
enum MorphMenuState {
  /// No mark.
  off,

  /// A checkmark in the selection column.
  on,

  /// A dash in the selection column.
  mixed,
}

/// Whether a row shows its glyph: UIKit's `preferredImageVisibility`.
enum MorphMenuIconVisibility {
  /// The glyph shows when the row has one.
  automatic,

  /// The glyph shows when the row has one.
  visible,

  /// The glyph is left out; the row keeps the menu's columns.
  hidden,
}

/// How a section lays out its rows: UIKit's `preferredElementSize`.
enum MorphMenuElementSize {
  /// Icon-only cells, four across (58.33 x 51.67 pt).
  small,

  /// Icon over a 12 pt label, three across (78 x 77 pt).
  medium,

  /// Full-width rows.
  large,

  /// The system's choice, which is full-width rows.
  automatic,
}

/// The order of a menu's entries relative to its button:
/// `preferredMenuElementOrder`.
enum MorphMenuOrder {
  /// The first entry sits next to the button: a menu that opens upward
  /// reverses its entries, as UIKit's button menus do.
  automatic,

  /// The first entry sits next to the button, like [automatic].
  priority,

  /// The entries keep their order whichever way the menu opens.
  fixed,
}

/// A row that runs an action: `UIAction` or a SwiftUI `Button`.
class MorphMenuItem extends MorphMenuEntry {
  /// Creates a menu row.
  const MorphMenuItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.selectedIcon,
    this.iconColor,
    this.iconVisibility = MorphMenuIconVisibility.automatic,
    this.enabled = true,
    this.destructive = false,
    this.hidden = false,
    this.keepsMenuOpen = false,
    this.state = MorphMenuState.off,
    this.onSelected,
    this.onHighlightChanged,
  });

  /// The row's title.
  final String title;

  /// A second line under the title in the secondary color; the row is
  /// 60 pt tall with one.
  final String? subtitle;

  /// The leading glyph, if any.
  final IconData? icon;

  /// The glyph shown instead of [icon] while [state] is not
  /// [MorphMenuState.off].
  final IconData? selectedIcon;

  /// The color of the glyph, for glyphs that carry their own color (a
  /// palette of colors); the row's text color when null.
  final Color? iconColor;

  /// Whether the glyph shows.
  final MorphMenuIconVisibility iconVisibility;

  /// Whether the row can be chosen; a disabled row is drawn in the
  /// tertiary color and ignores touches.
  final bool enabled;

  /// Whether the row is drawn in the destructive color.
  final bool destructive;

  /// Whether the row is left out of the menu.
  final bool hidden;

  /// Whether the menu stays open after the row is chosen.
  ///
  /// UIKit runs the action and keeps the menu; the menu redraws only from
  /// the app's state, so a row that toggles a mark changes it by
  /// rebuilding the button with new entries.
  final bool keepsMenuOpen;

  /// The selection mark.
  final MorphMenuState state;

  /// Called when the row is chosen; before the menu starts closing.
  final VoidCallback? onSelected;

  /// Called when the row gains or loses the highlight under a finger or
  /// the keyboard.
  final ValueChanged<bool>? onHighlightChanged;
}

/// A group of entries shown inline: `UIMenu` with `displayInline`, or a
/// SwiftUI `Section`.
///
/// Adjacent groups are set apart by a 21 pt gap with a hairline.
class MorphMenuSection extends MorphMenuEntry {
  /// Creates a section.
  const MorphMenuSection({
    required this.children,
    this.title,
    this.singleSelection = false,
    this.elementSize = MorphMenuElementSize.large,
    this.palette = false,
    this.maxTitleLines,
  });

  /// The entries of the section.
  final List<MorphMenuEntry> children;

  /// A header above the rows in the secondary color, or none.
  final String? title;

  /// Whether the rows form one choice; the menu keeps a selection column
  /// for their marks.
  final bool singleSelection;

  /// How the rows are laid out.
  final MorphMenuElementSize elementSize;

  /// Whether the rows are one row of glyph cells, the selected one on a
  /// platter: `displayAsPalette`.
  final bool palette;

  /// The most lines a row title wraps to; one when null.
  final int? maxTitleLines;
}

/// A row that opens a nested menu as a card stacked over this one: a
/// nested `UIMenu` or SwiftUI `Menu`.
class MorphSubmenu extends MorphMenuEntry {
  /// Creates a submenu.
  const MorphSubmenu({
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.hidden = false,
    this.singleSelection = false,
    this.elementSize = MorphMenuElementSize.large,
  });

  /// The row's title, also the bold title of the card's header.
  final String title;

  /// The entries of the nested menu.
  final List<MorphMenuEntry> children;

  /// A second line under the title.
  final String? subtitle;

  /// The leading glyph, if any.
  final IconData? icon;

  /// Whether the row is drawn in the destructive color.
  final bool destructive;

  /// Whether the submenu can be opened.
  final bool enabled;

  /// Whether the row is left out of the menu.
  final bool hidden;

  /// Whether the nested rows form one choice.
  final bool singleSelection;

  /// How the nested rows are laid out.
  final MorphMenuElementSize elementSize;
}

/// A break between two groups of rows: a SwiftUI `Divider`.
class MorphMenuDivider extends MorphMenuEntry {
  /// Creates a divider.
  const MorphMenuDivider();
}

/// Entries that load when the menu opens: `UIDeferredMenuElement`.
///
/// Until [load] answers the menu shows a 42 pt "Loading..." row with a
/// spinner; the answer replaces it and the menu grows on the measured
/// resize spring.
class MorphMenuDeferred extends MorphMenuEntry {
  /// Creates a deferred group.
  const MorphMenuDeferred(
    this.load, {
    this.cache = true,
    this.id,
    this.loadingTitle = 'Loading...',
  });

  /// Loads the entries.
  final Future<List<MorphMenuEntry>> Function() load;

  /// Whether the first answer is kept for later openings
  /// (`elementWithProvider`), or [load] runs at every opening
  /// (`elementWithUncachedProvider`).
  final bool cache;

  /// The identity the cached answer is kept under; [load] itself when
  /// null, so a closure created in every build needs an [id] to be
  /// cached across builds.
  final Object? id;

  /// The title of the loading row.
  final String loadingTitle;

  /// The key the answer is cached under.
  Object get cacheKey => id ?? load;
}

/// A free-form row built by the app, for content no native element
/// covers (a slider, a stepper, a custom control).
///
/// UIKit and SwiftUI have no such element in iOS 27 (a SwiftUI `Slider`
/// in a `Menu` turns into two buttons), so this is morph's extension:
/// its look is the app's, its motion is the menu's. The row spans the
/// menu width minus [MorphMenuMetrics.widgetInset] on each side and is as
/// tall as [builder]'s widget, measured after its first layout unless
/// [height] is given. Touches go to the widget; the menu neither
/// highlights nor closes on them.
class MorphMenuWidget extends MorphMenuEntry {
  /// Creates a free-form row.
  const MorphMenuWidget({required this.builder, this.height, this.id});

  /// Builds the row's content.
  final WidgetBuilder builder;

  /// The height of the row; measured when null.
  final double? height;

  /// The identity the measured height is kept under across builds; the
  /// row's place in the menu when null.
  final Object? id;
}
