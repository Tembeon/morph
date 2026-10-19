import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

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
///
/// Page options hand the fields a controller and a focus node the page
/// drives, autofocus the inline field, swap the spoken labels for custom
/// ones and tint the fields; a search key press shows what was submitted.
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
  bool _ownController = false;
  bool _autofocus = false;
  bool _customLabels = false;
  Color? _tint;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_typed);
  }

  @override
  void dispose() {
    _controller.removeListener(_typed);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Follows text the page put in its own controller, which no field
  /// reports through its onChanged.
  void _typed() {
    if (_ownController && _controller.text != _query) {
      setState(() => _query = _controller.text);
    }
  }

  void _submitted(String query) => setState(() => _last = 'Submitted "$query"');

  TextEditingController? get _fieldController =>
      _ownController ? _controller : null;

  FocusNode? get _fieldFocus => _ownController ? _focus : null;

  /// The search field look with the magnifier and the cursor in the tint,
  /// or null for the theme's.
  MorphSearchFieldAppearance? _searchLook(BuildContext context) {
    final tint = _tint;
    if (tint == null) return null;
    final base = MorphSearchFieldAppearance.resolve(context, null);
    return MorphSearchFieldAppearance(
      capsuleColor: base.capsuleColor,
      rimColor: base.rimColor,
      shadowColor: base.shadowColor,
      textColor: base.textColor,
      placeholderColor: base.placeholderColor,
      restingPlaceholderColor: base.restingPlaceholderColor,
      glyphColor: tint,
      clearColor: base.clearColor,
      clearGlyphColor: base.clearGlyphColor,
      cursorColor: tint,
      disabledFillColor: base.disabledFillColor,
    );
  }

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Text and focus'),
      footer: const Text(
        'With the page\'s controller and focus node, the rows below type, '
        'focus and clear the field of the current mode.',
      ),
      children: [
        GalleryToggle(
          label: 'Page controller',
          value: _ownController,
          onChanged: (v) {
            _controller.clear();
            setState(() {
              _ownController = v;
              _query = '';
            });
          },
        ),
        MorphListRow(
          title: const Text('Type "berry"'),
          enabled: _ownController,
          onTap: _ownController ? () => _controller.text = 'berry' : null,
        ),
        MorphListRow(
          title: const Text('Focus the field'),
          enabled: _ownController,
          onTap: _ownController ? _focus.requestFocus : null,
        ),
        MorphListRow(
          title: const Text('Clear the field'),
          enabled: _ownController,
          onTap: _ownController ? _controller.clear : null,
        ),
        GalleryToggle(
          label: 'Autofocus inline field',
          value: _autofocus,
          onChanged: (v) => setState(() => _autofocus = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Labels and look'),
      footer: const Text(
        'Custom labels: Find for the search tab, Cancel for the close '
        'button, Erase for the clear button, Fruit search for the field.',
      ),
      children: [
        GalleryToggle(
          label: 'Custom labels',
          value: _customLabels,
          onChanged: (v) => setState(() => _customLabels = v),
        ),
        GalleryColorChoice(
          label: 'Tint',
          value: _tint,
          onChanged: (v) => setState(() => _tint = v),
        ),
      ],
    ),
  ];

  List<String> get _matches => [
    for (final f in _fruits)
      if (f.toLowerCase().contains(_query.toLowerCase())) f,
  ];

  @override
  Widget build(BuildContext context) {
    final tint = _searchLook(context);
    final buttonTint = _tint;
    final close = _customLabels ? 'Cancel' : 'Close';
    final list = GalleryPage(
      title: 'Search',
      options: _options,
      slivers: [
        SliverPadding(
          padding: const .fromLTRB(16, 8, 16, 0),
          sliver: SliverList.list(
            children: [
              Padding(
                padding: const .symmetric(vertical: 8),
                child: MorphSegmentedControl(
                  segments: const [
                    MorphSegment('Toolbar'),
                    MorphSegment('Tab bar'),
                    MorphSegment('Inline'),
                  ],
                  selectedIndex: _mode,
                  onChanged: (int i) {
                    _controller.clear();
                    setState(() {
                      _mode = i;
                      _query = '';
                      _searching = false;
                    });
                  },
                ),
              ),
              if (_mode == 2)
                Padding(
                  padding: const .symmetric(vertical: 8),
                  child: MorphSearchField(
                    key: ValueKey((_ownController, _autofocus)),
                    controller: _fieldController,
                    focusNode: _fieldFocus,
                    autofocus: _autofocus,
                    enabled: !GalleryGlassScope.of(context, .disabled).disabled,
                    placeholder: 'Search fruit',
                    semanticLabel: _customLabels ? 'Fruit search' : null,
                    clearLabel: _customLabels ? 'Erase' : 'Clear text',
                    appearance: tint,
                    onChanged: (String q) => setState(() => _query = q),
                    onSubmitted: _submitted,
                  ),
                ),
              if (_last.isNotEmpty)
                Padding(
                  padding: const .symmetric(vertical: 8),
                  child: Text(
                    _last,
                    style: TextStyle(color: gallerySecondaryColor(context)),
                  ),
                ),
            ],
          ),
        ),
        if (_matches.isNotEmpty)
          SliverToBoxAdapter(
            child: MorphListSection(
              children: [
                for (final f in _matches) MorphListRow(title: Text(f)),
              ],
            ),
          ),
        const SliverPadding(padding: .only(bottom: 140)),
      ],
    );
    return Stack(
      children: [
        Positioned.fill(child: list),
        if (_mode == 0)
          Positioned.fill(
            child: MorphSearchToolbar(
              key: ValueKey(_ownController),
              controller: _fieldController,
              focusNode: _fieldFocus,
              placeholder: 'Search fruit',
              closeLabel: close,
              appearance: tint,
              buttonAppearance: buttonTint == null
                  ? null
                  : MorphGlassButtonAppearance.resolve(
                      context,
                      null,
                    ).copyWith(foregroundColor: buttonTint),
              onChanged: (String q) => setState(() => _query = q),
              onSubmitted: _submitted,
              onActiveChanged: (bool on) =>
                  setState(() => _last = on ? 'Searching' : 'Search ended'),
              leading: [
                MorphBarButtonGroup([
                  MorphBarButton(
                    id: 'filter',
                    icon: const Icon(Icons.filter_list),
                    semanticLabel: 'Filter',
                    onPressed: () => setState(() => _last = 'Filter'),
                  ),
                ]),
              ],
              trailing: [
                MorphBarButtonGroup([
                  MorphBarButton(
                    id: 'compose',
                    icon: const Icon(Icons.edit_outlined),
                    semanticLabel: 'Compose',
                    onPressed: () => setState(() => _last = 'Compose'),
                  ),
                ]),
              ],
            ),
          ),
        if (_mode == 1)
          Positioned.fill(
            child: MorphSearchTabBar(
              key: ValueKey(_ownController),
              controller: _fieldController,
              focusNode: _fieldFocus,
              searchLabel: _customLabels ? 'Find' : 'Search',
              closeLabel: close,
              searchAppearance: tint,
              appearance: buttonTint == null
                  ? null
                  : MorphTabBarAppearance.resolve(
                      context,
                      null,
                    ).copyWith(selectedColor: buttonTint),
              onSubmitted: _submitted,
              items: const [
                MorphTabItem(icon: Icons.home_outlined, label: 'Home'),
                MorphTabItem(icon: Icons.library_books, label: 'Library'),
              ],
              selected: _tab,
              onChanged: (int i) => setState(() => _tab = i),
              active: _searching,
              onActiveChanged: (bool on) => setState(() {
                _searching = on;
                if (!on) _query = '';
              }),
              placeholder: 'Search fruit',
              onQueryChanged: (String q) => setState(() => _query = q),
            ),
          ),
      ],
    );
  }
}
