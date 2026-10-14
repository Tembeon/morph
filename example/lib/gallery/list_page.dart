import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// Inset grouped sections whose rows carry glass buttons.
///
/// Each section shades the resting glass of its rows' accessories in one
/// layer; a pressed row's button leaves it while the row's highlight
/// shows.
///
/// Below them: a single selection with checkmarks, info buttons, a
/// disabled row and a sliver section that builds its many rows lazily.
/// The page options set the lazy section's row count and its icons.
class ListPage extends StatefulWidget {
  /// Creates the page.
  const ListPage({super.key});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  String _last = 'Nothing tapped yet';
  int _sort = 0;
  bool _rowEnabled = false;
  int _lazyCount = 500;
  bool _lazyIcons = true;

  static const _sorts = ['Name', 'Date added', 'Size'];

  static const _counts = {50: '50', 500: '500', 5000: '5000'};

  static const _devices = <(String, String, MorphListAccessory)>[
    ('Living room', 'Connected', .detailButton),
    ('Kitchen speaker', 'Idle', .detailDisclosureButton),
    ('Bedroom TV', 'Asleep', .detailDisclosureButton),
  ];

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

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Lazy section'),
      children: [
        GalleryChoice<int>(
          label: 'Rows',
          options: _counts,
          value: _lazyCount,
          onChanged: (int n) => setState(() => _lazyCount = n),
        ),
        GalleryToggle(
          label: 'Row icons',
          value: _lazyIcons,
          onChanged: (bool v) => setState(() => _lazyIcons = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Disabled row'),
      children: [
        GalleryToggle(
          label: 'Enable the row',
          value: _rowEnabled,
          onChanged: (bool v) => setState(() => _rowEnabled = v),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    return GalleryPage(
      title: 'Lists',
      options: _options,
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
              header: const Text('Apps'),
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
              header: const Text('Episodes'),
              footer: const Text(
                'Each section shades the resting glass of its rows in one '
                'layer. A pressed row draws its button in a layer of its '
                'own while its highlight shows.',
              ),
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
        SliverToBoxAdapter(
          child: MorphListSection(
            header: const Text('Sort by'),
            footer: const Text(
              'A single selection: the chosen row shows a checkmark.',
            ),
            children: [
              for (final (i, name) in _sorts.indexed)
                MorphListRow(
                  title: Text(name),
                  accessory: i == _sort ? .checkmark : null,
                  onTap: on(() {
                    setState(() => _sort = i);
                    _say('Sorted by $name');
                  }),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: MorphListSection(
            header: const Text('Devices'),
            footer: const Text(
              'The info button runs its own action; the rest of the row '
              'runs the row\'s.',
            ),
            children: [
              for (final (name, state, accessory) in _devices)
                MorphListRow(
                  title: Text(name),
                  detail: Text(state),
                  accessory: accessory,
                  onTap: on(() => _say('Selected $name')),
                  onAccessoryTap: on(() => _say('Info for $name')),
                ),
              MorphListRow(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Garage door'),
                subtitle: Text(_rowEnabled ? 'Enabled' : 'Disabled row'),
                accessory: .disclosureIndicator,
                enabled: _rowEnabled,
                onTap: on(() => _say('Opened Garage door')),
              ),
            ],
          ),
        ),
        MorphSliverListSection(
          header: Text('$_lazyCount lazy rows'),
          footer: const Text(
            'MorphSliverListSection builds only the rows in view.',
          ),
          itemCount: _lazyCount,
          itemBuilder: (BuildContext context, int i) => MorphListRow(
            leading: _lazyIcons
                ? Icon(i.isEven ? Icons.circle_outlined : Icons.square_outlined)
                : null,
            title: Text('Item ${i + 1}'),
            onTap: on(() => _say('Tapped item ${i + 1}')),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}
