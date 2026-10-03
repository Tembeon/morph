import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

const List<String> _fruits = [
  'Apple',
  'Apricot',
  'Banana',
  'Blackberry',
  'Blueberry',
  'Cherry',
  'Coconut',
  'Fig',
  'Grape',
  'Kiwi',
  'Lemon',
  'Lime',
  'Mango',
  'Melon',
  'Orange',
  'Papaya',
  'Peach',
  'Pear',
  'Pineapple',
  'Plum',
  'Raspberry',
  'Strawberry',
  'Watermelon',
];

/// The iOS 27 search field in its three homes: the bottom toolbar, where
/// focusing it lifts it above the keyboard and swaps the toolbar's buttons
/// for a close button; the tab bar, whose search tab turns into the
/// field; and inline at the top of a list.
class SearchPage extends StatefulWidget {
  /// Creates the page.
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  int _mode = 0;
  String _query = '';
  int _tab = 0;
  bool _searching = false;
  String _last = '';

  List<String> get _matches => [
    for (final f in _fruits)
      if (f.toLowerCase().contains(_query.toLowerCase())) f,
  ];

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const .fromLTRB(16, 8, 16, 140),
      children: [
        Padding(
          padding: const .symmetric(vertical: 8),
          child: MorphSegmentedControl(
            segments: const ['Toolbar', 'Tab bar', 'Inline'],
            selected: _mode,
            onChanged: (int i) => setState(() {
              _mode = i;
              _query = '';
              _searching = false;
            }),
          ),
        ),
        if (_mode == 2)
          Padding(
            padding: const .symmetric(vertical: 8),
            child: MorphSearchField(
              enabled: !GalleryGlassScope.of(context).disabled,
              placeholder: 'Search fruit',
              onChanged: (String q) => setState(() => _query = q),
            ),
          ),
        if (_last.isNotEmpty)
          Padding(
            padding: const .symmetric(vertical: 8),
            child: Text(
              _last,
              style: const TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
        for (final f in _matches) ListTile(title: Text(f)),
      ],
    );
    return Scaffold(
      appBar: const GalleryBar(title: 'Search'),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: list),
          if (_mode == 0)
            Positioned.fill(
              child: MorphSearchToolbar(
                placeholder: 'Search fruit',
                onChanged: (String q) => setState(() => _query = q),
                onActiveChanged: (bool on) =>
                    setState(() => _last = on ? 'Searching' : 'Search ended'),
                leading: [
                  MorphBarButton(
                    id: 'filter',
                    icon: const Icon(Icons.filter_list),
                    semanticLabel: 'Filter',
                    onPressed: () => setState(() => _last = 'Filter'),
                  ),
                ],
                trailing: [
                  MorphBarButton(
                    id: 'compose',
                    icon: const Icon(Icons.edit_outlined),
                    semanticLabel: 'Compose',
                    onPressed: () => setState(() => _last = 'Compose'),
                  ),
                ],
              ),
            ),
          if (_mode == 1)
            Positioned.fill(
              child: MorphSearchTabBar(
                items: const [
                  MorphTabItem(icon: Icons.home_outlined, label: 'Home'),
                  MorphTabItem(icon: Icons.library_books, label: 'Library'),
                ],
                selected: _tab,
                onChanged: (int i) => setState(() => _tab = i),
                searching: _searching,
                onSearchingChanged: (bool on) => setState(() {
                  _searching = on;
                  if (!on) _query = '';
                }),
                placeholder: 'Search fruit',
                onQueryChanged: (String q) => setState(() => _query = q),
              ),
            ),
        ],
      ),
    );
  }
}
