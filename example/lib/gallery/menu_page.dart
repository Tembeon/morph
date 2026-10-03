import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Glass menu buttons at the center, near every corner and in the
/// navigation bar, with two, five and ten rows.
class MenuPage extends StatefulWidget {
  /// Creates the page.
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String _last = 'Tap or hold a button';

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
    return Scaffold(
      appBar: GalleryBar(
        title: 'Menu',
        actions: [
          MorphMenuButton(
            items: _items(3),
            style: MorphMenuStyle.resolve(
              context,
              null,
            ).copyWith(buttonSize: 44),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: const Alignment(0, 0.35),
              child: Text(
                _last,
                style: const TextStyle(color: Color(0xFF8E8E93)),
              ),
            ),
            Center(child: MorphMenuButton(items: _items(5))),
            Align(
              alignment: const Alignment(0, -0.45),
              child: MorphMenuButton(items: _items(2)),
            ),
            Align(
              alignment: const Alignment(0, 0.7),
              child: MorphMenuButton(items: _items(10)),
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
                  child: MorphMenuButton(items: _items(3)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
