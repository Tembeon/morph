import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Glass menu buttons at the center and near every corner, with two,
/// five and ten rows, a bar button whose tap opens its menu, and
/// one rich menu at the top: sections, a selection that stays open, a
/// palette, small and medium cells, subtitles, a disabled row, submenus,
/// a deferred section and a free-form slider row. The leading bar button
/// opens the long-press [ContextMenuPage].
class MenuPage extends StatefulWidget {
  /// Creates the page.
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String _last = 'Tap or hold a button';
  String _sort = 'Name';
  bool _hidden = true;
  int _color = 3;
  final Set<String> _styles = {'Bold'};
  double _volume = 0.6;

  static const _colors = [
    ('Red', Color(0xFFFF3B30)),
    ('Orange', Color(0xFFFF9500)),
    ('Green', Color(0xFF34C759)),
    ('Blue', Color(0xFF0091FF)),
    ('Purple', Color(0xFFAF52DE)),
  ];

  static Future<List<MorphMenuEntry>> _recent() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return const [
      MorphMenuItem(title: 'Notes.txt', icon: Icon(Icons.description_outlined)),
      MorphMenuItem(
        title: 'Budget.numbers',
        icon: Icon(Icons.table_chart_outlined),
      ),
    ];
  }

  void _pick(String title) => setState(() => _last = title);

  List<MorphMenuEntry> _rich() => [
    MorphMenuSection(
      title: 'Color',
      palette: true,
      children: [
        for (var i = 0; i < _colors.length; i++)
          MorphMenuItem(
            title: _colors[i].$1,
            icon: const Icon(Icons.circle),
            iconColor: _colors[i].$2,
            state: i == _color ? MorphMenuState.on : MorphMenuState.off,
            keepsMenuOpen: true,
            onSelected: () => setState(() => _color = i),
          ),
      ],
    ),
    MorphMenuSection(
      elementSize: MorphMenuElementSize.small,
      children: [
        for (final (title, icon) in const [
          ('Cut', Icons.content_cut),
          ('Copy', Icons.copy),
          ('Paste', Icons.content_paste),
          ('Share', Icons.ios_share),
        ])
          MorphMenuItem(
            title: title,
            icon: Icon(icon),
            onSelected: () => _pick(title),
          ),
      ],
    ),
    MorphMenuSection(
      elementSize: MorphMenuElementSize.medium,
      children: [
        for (final (title, icon) in const [
          ('Bold', Icons.format_bold),
          ('Italic', Icons.format_italic),
          ('Underline', Icons.format_underline),
        ])
          MorphMenuItem(
            title: title,
            icon: Icon(icon),
            state: _styles.contains(title)
                ? MorphMenuState.on
                : MorphMenuState.off,
            keepsMenuOpen: true,
            onSelected: () => setState(() {
              if (!_styles.remove(title)) _styles.add(title);
            }),
          ),
      ],
    ),
    MorphMenuSection(
      title: 'Sort by',
      singleSelection: true,
      children: [
        for (final (title, icon) in const [
          ('Name', Icons.sort_by_alpha),
          ('Date', Icons.calendar_today_outlined),
          ('Size', Icons.swap_vert),
        ])
          MorphMenuItem(
            title: title,
            icon: Icon(icon),
            state: _sort == title ? MorphMenuState.on : MorphMenuState.off,
            keepsMenuOpen: true,
            onSelected: () => setState(() => _sort = title),
          ),
      ],
    ),
    MorphMenuSection(
      children: [
        MorphMenuItem(
          title: 'Show hidden',
          icon: const Icon(Icons.visibility_outlined),
          state: _hidden ? MorphMenuState.on : MorphMenuState.off,
          keepsMenuOpen: true,
          onSelected: () => setState(() => _hidden = !_hidden),
        ),
        if (_hidden)
          MorphMenuItem(
            title: 'Hidden files',
            subtitle: '12 items',
            icon: const Icon(Icons.folder_open_outlined),
            onSelected: () => _pick('Hidden files'),
          ),
        const MorphMenuItem(
          title: 'Disabled row',
          icon: Icon(Icons.block),
          enabled: false,
        ),
      ],
    ),
    MorphSubmenu(
      title: 'More',
      icon: const Icon(Icons.folder_outlined),
      children: [
        MorphMenuItem(
          title: 'Rename',
          icon: const Icon(Icons.edit),
          onSelected: () => _pick('Rename'),
        ),
        MorphMenuItem(
          title: 'Duplicate',
          icon: const Icon(Icons.control_point_duplicate),
          onSelected: () => _pick('Duplicate'),
        ),
        MorphSubmenu(
          title: 'Move to',
          icon: const Icon(Icons.drive_file_move_outline),
          children: [
            for (final place in const ['Desktop', 'Documents', 'Downloads'])
              MorphMenuItem(title: place, onSelected: () => _pick(place)),
          ],
        ),
      ],
    ),
    const MorphMenuSection(
      title: 'Recent',
      children: [MorphMenuDeferred(_recent, cache: false)],
    ),
    MorphMenuWidget(
      id: 'volume',
      builder: (BuildContext context) => Padding(
        padding: const .symmetric(vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.volume_down, size: 20),
            Expanded(
              child: MorphSlider(
                value: _volume,
                semanticLabel: 'Volume',
                onChanged: (double value) => setState(() => _volume = value),
              ),
            ),
            const Icon(Icons.volume_up, size: 20),
          ],
        ),
      ),
    ),
    MorphMenuItem(
      title: 'Delete',
      icon: const Icon(Icons.delete_outline),
      destructive: true,
      onSelected: () => _pick('Delete'),
    ),
  ];

  static const _titles = [
    ('Copy', Icons.copy),
    ('Share', Icons.ios_share),
    ('Rename', Icons.edit),
    ('Duplicate', Icons.control_point_duplicate),
    ('Move', Icons.drive_file_move_outline),
    ('Tag', Icons.label_outline),
    ('Pin', Icons.push_pin_outlined),
    ('Archive', Icons.archive_outlined),
    ('Print', Icons.print_outlined),
  ];

  List<MorphMenuItem> _items(int count) => [
    for (final (title, icon) in _titles.take(count - 1))
      MorphMenuItem(
        title: title,
        icon: Icon(icon),
        onSelected: () => setState(() => _last = title),
      ),
    MorphMenuItem(
      title: 'Delete',
      icon: const Icon(Icons.delete_outline),
      destructive: true,
      onSelected: () => setState(() => _last = 'Delete'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    MorphMenuButton button(List<MorphMenuEntry> items, {Widget? child}) =>
        MorphMenuButton(
          menu: items,
          semanticLabel: child == null ? null : 'Options',
          child: child,
        );
    return GalleryPage(
      title: 'Menu',
      leading: [
        MorphBarButtonGroup([
          MorphBarButton(
            id: 'context',
            label: 'Context menu',
            onPressed: () => Navigator.of(context).push(
              MorphNavigationRoute<void>(
                builder: (_) => const ContextMenuPage(),
              ),
            ),
          ),
        ]),
      ],
      trailing: [
        MorphBarButtonGroup([
          MorphBarButton(
            id: 'menu',
            icon: const Icon(Icons.more_horiz),
            semanticLabel: 'More',
            enabled: !GalleryGlassScope.of(context, .disabled).disabled,
            menu: _items(3),
          ),
        ]),
      ],
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MorphGlassContainer(
            solidBackdrop: MorphListAppearance.resolve(
              context,
              null,
            ).backgroundColor,
            child: Stack(
              children: [
                Align(
                  alignment: const Alignment(0, 0.35),
                  child: Text(
                    _last,
                    style: TextStyle(color: gallerySecondaryColor(context)),
                  ),
                ),
                Center(child: button(_items(5))),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const .all(16),
                    child: button(
                      _rich(),
                      child: const Icon(Icons.tune, size: 22),
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, -0.45),
                  child: button(_items(2)),
                ),
                Align(
                  alignment: const Alignment(0, 0.7),
                  child: button(_items(10)),
                ),
                for (final alignment in const [
                  Alignment.topLeft,
                  Alignment.topRight,
                  Alignment.bottomLeft,
                  Alignment.bottomRight,
                ])
                  Align(
                    alignment: alignment,
                    child: Padding(
                      padding: const .all(16),
                      child: button(_items(3)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Long-press context menus: list rows and photo tiles lift under the
/// finger, then open into a card of action rows next to the lifted hero; a
/// tap still reaches the row.
class ContextMenuPage extends StatefulWidget {
  /// Creates the page.
  const ContextMenuPage({super.key});

  @override
  State<ContextMenuPage> createState() => _ContextMenuPageState();
}

class _ContextMenuPageState extends State<ContextMenuPage> {
  String _last = 'Hold a row or a photo';

  static const _rows = [
    ('Anna', 'Lunch tomorrow?', Color(0xFF34C759)),
    ('Ben', 'The slides are ready', Color(0xFF007AFF)),
    ('Chloe', 'Photos from the trip', Color(0xFFFF9500)),
    ('Dmitri', 'Call me back', Color(0xFFAF52DE)),
  ];

  static const _photos = [
    Color(0xFFFF3B30),
    Color(0xFF30B0C7),
    Color(0xFF5856D6),
  ];

  static const _actions = [
    ('Reply', Icons.reply, false),
    ('Copy', Icons.copy, false),
    ('Pin', Icons.push_pin_outlined, false),
    ('Share', Icons.ios_share, false),
    ('Delete', Icons.delete_outline, true),
  ];

  MorphSatellite _menu(String subject) => MorphSatellite(
    height: _actions.length * _ContextActions.rowHeight + 20,
    builder: (BuildContext context, MorphFlight flight) => _ContextActions(
      actions: [
        for (final (title, icon, destructive) in _actions)
          (
            title: title,
            icon: icon,
            destructive: destructive,
            onTap: () {
              setState(() => _last = '$title: $subject');
              flight.close();
            },
          ),
      ],
    ),
  );

  Widget _row(BuildContext context, (String, String, Color) row) {
    final (name, text, color) = row;
    final list = MorphListAppearance.resolve(context, null);
    return Padding(
      padding: const .only(bottom: 8),
      child: MorphContextMenuRegion(
        below: _menu(name),
        semanticLabel: name,
        child: GestureDetector(
          onTap: () => setState(() => _last = 'Opened $name'),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: list.cellColor,
              borderRadius: const .all(.circular(14)),
            ),
            // Taller than its text: a copy of the hero in the opening's
            // first frame is laid out a pixel or two short of its natural
            // height, and the text must not overflow it.
            child: Container(
              height: 72,
              padding: const .symmetric(horizontal: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color,
                    radius: 18,
                    child: Text(
                      name.substring(0, 1),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          style: TextStyle(
                            color: list.titleColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          text,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TextStyle(color: list.secondaryColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Context menu',
      slivers: [
        SliverPadding(
          padding: const .fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: [
              GalleryCaption(_last),
              for (final row in _rows) _row(context, row),
              const GalleryCaption('Photos'),
              Row(
                children: [
                  for (var i = 0; i < _photos.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: MorphContextMenuRegion(
                        alignment: AlignmentDirectional.center,
                        below: _menu('Photo ${i + 1}'),
                        semanticLabel: 'Photo ${i + 1}',
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _photos[i],
                              borderRadius: const .all(.circular(12)),
                            ),
                            child: const Center(
                              child: Icon(Icons.photo, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

typedef _Action = ({
  String title,
  IconData icon,
  bool destructive,
  VoidCallback onTap,
});

/// The action rows of a context menu on one glass card.
class _ContextActions extends StatelessWidget {
  const _ContextActions({required this.actions});

  final List<_Action> actions;

  static const double rowHeight = 44;

  @override
  Widget build(BuildContext context) {
    final style = MorphMenuAppearance.resolve(context, null);
    return MorphGlassEffect(
      shape: RoundedRectangleBorder(
        borderRadius: .all(.circular(MorphMenuTuning.standard.cornerRadius)),
      ),
      child: Padding(
        padding: const .symmetric(vertical: 10),
        child: Column(
          mainAxisSize: .min,
          children: [
            for (final action in actions)
              GestureDetector(
                behavior: .opaque,
                onTap: action.onTap,
                child: SizedBox(
                  height: rowHeight,
                  child: Padding(
                    padding: const .symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            action.title,
                            style: style.textStyle.copyWith(
                              color: action.destructive
                                  ? style.destructiveColor
                                  : null,
                            ),
                          ),
                        ),
                        Icon(
                          action.icon,
                          size: 20,
                          color: action.destructive
                              ? style.destructiveColor
                              : style.iconColor,
                        ),
                      ],
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
