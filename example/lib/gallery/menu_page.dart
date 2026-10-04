import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Glass menu buttons at the center and near every corner, with two,
/// five and ten rows, a bar button whose tap opens its menu, and
/// one rich menu at the top: sections, a selection that stays open, a
/// palette, small and medium cells, subtitles, a disabled row, submenus,
/// a deferred section and a free-form slider row.
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
      MorphMenuItem(title: 'Notes.txt', icon: Icons.description_outlined),
      MorphMenuItem(title: 'Budget.numbers', icon: Icons.table_chart_outlined),
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
            icon: Icons.circle,
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
            icon: icon,
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
            icon: icon,
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
            icon: icon,
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
          icon: Icons.visibility_outlined,
          state: _hidden ? MorphMenuState.on : MorphMenuState.off,
          keepsMenuOpen: true,
          onSelected: () => setState(() => _hidden = !_hidden),
        ),
        if (_hidden)
          MorphMenuItem(
            title: 'Hidden files',
            subtitle: '12 items',
            icon: Icons.folder_open_outlined,
            onSelected: () => _pick('Hidden files'),
          ),
        const MorphMenuItem(
          title: 'Disabled row',
          icon: Icons.block,
          enabled: false,
        ),
      ],
    ),
    MorphSubmenu(
      title: 'More',
      icon: Icons.folder_outlined,
      children: [
        MorphMenuItem(
          title: 'Rename',
          icon: Icons.edit,
          onSelected: () => _pick('Rename'),
        ),
        MorphMenuItem(
          title: 'Duplicate',
          icon: Icons.control_point_duplicate,
          onSelected: () => _pick('Duplicate'),
        ),
        MorphSubmenu(
          title: 'Move to',
          icon: Icons.drive_file_move_outline,
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
      icon: Icons.delete_outline,
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
        icon: icon,
        onSelected: () => setState(() => _last = title),
      ),
    MorphMenuItem(
      title: 'Delete',
      icon: Icons.delete_outline,
      destructive: true,
      onSelected: () => setState(() => _last = 'Delete'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    MorphMenuButton button(List<MorphMenuEntry> items, {Widget? child}) =>
        MorphMenuButton(
          items: items,
          semanticLabel: child == null ? null : 'Options',
          child: child,
        );
    return GalleryPage(
      title: 'Menu',
      trailing: [
        MorphBarButtonGroup([
          MorphBarButton(
            id: 'menu',
            icon: const Icon(Icons.more_horiz),
            semanticLabel: 'More',
            enabled: !GalleryGlassScope.of(context).disabled,
            menu: _items(3),
          ),
        ]),
      ],
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
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
      ],
    );
  }
}
