import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Inset grouped sections whose rows carry glass buttons.
///
/// Each section shades the resting glass of its rows' accessories in one
/// layer; a pressed row's button leaves it while the row's highlight
/// shows.
class ListPage extends StatefulWidget {
  /// Creates the page.
  const ListPage({super.key});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  String _last = 'Nothing tapped yet';

  static const _apps = <(String, String, IconData)>[
    ('Notes', 'Productivity', Icons.note_outlined),
    ('Weather', 'Forecasts and maps', Icons.cloud_outlined),
    ('Photos', 'Memories and albums', Icons.photo_outlined),
    ('Maps', 'Navigation', Icons.map_outlined),
    ('Music', 'Songs and radio', Icons.music_note_outlined),
    ('Books', 'Reading', Icons.menu_book_outlined),
  ];

  static const _shows = <(String, String)>[
    ('Morning brief', '12 min'),
    ('Deep dive', '58 min'),
    ('Field notes', '23 min'),
    ('The long view', '41 min'),
    ('Small talk', '9 min'),
    ('After hours', '35 min'),
  ];

  void _say(String what) => setState(() => _last = what);

  @override
  Widget build(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    return GalleryPage(
      title: 'Lists',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const .symmetric(horizontal: 32),
            child: GalleryCaption(_last),
          ),
        ),
        SliverToBoxAdapter(
          child: BackdropGroup(
            child: MorphListSection(
              header: 'Apps',
              children: [
                for (final (name, kind, icon) in _apps)
                  MorphListRow(
                    leading: Icon(icon),
                    title: Text(name),
                    subtitle: Text(kind),
                    onTap: () => _say('Opened $name'),
                    trailing: SizedBox(
                      width: 72,
                      height: 34,
                      child: MorphGlassButton(
                        padding: .zero,
                        onPressed: on(() => _say('Getting $name')),
                        child: const Text('Get'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: BackdropGroup(
            child: MorphListSection(
              header: 'Episodes',
              footer:
                  'Each section shades the resting glass of its rows in one '
                  'layer. A pressed row draws its button in a layer of its '
                  'own while its highlight shows.',
              children: [
                for (final (name, length) in _shows)
                  MorphListRow(
                    title: Text(name),
                    detail: Text(length),
                    onTap: () => _say('Playing $name'),
                    trailing: SizedBox.square(
                      dimension: 36,
                      child: MorphGlassButton(
                        padding: .zero,
                        onPressed: on(() => _say('Queued $name')),
                        child: const Icon(Icons.add, size: 20),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}
