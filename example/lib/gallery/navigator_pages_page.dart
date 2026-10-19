import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

const List<Color> _palette = [
  Color(0xFF5E5CE6),
  Color(0xFFFF9F0A),
  Color(0xFF30B0C7),
  Color(0xFFFF375F),
];

/// A navigation stack driven by a list of pages in state, as a router
/// drives one: each page slides in, or zooms out of its source.
///
/// The stack has bars of its own, so it opens full screen in a route of
/// the app's root navigator, above the gallery's stack.
class NavigatorPagesPage extends StatefulWidget {
  /// Creates the page.
  const NavigatorPagesPage({super.key});

  @override
  State<NavigatorPagesPage> createState() => _NavigatorPagesPageState();
}

class _NavigatorPagesPageState extends State<NavigatorPagesPage> {
  bool _prefersLargeTitles = true;

  void _open(List<_Entry> path) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) =>
              _Demo(prefersLargeTitles: _prefersLargeTitles, initialPath: path),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Navigator pages',
      options: (BuildContext context) => [
        MorphListSection(
          header: const Text('Stack'),
          footer: const Text(
            'Screens that ask for an automatic large title show it large '
            'when the stack prefers large titles.',
          ),
          children: [
            GalleryToggle(
              label: 'Prefers large titles',
              value: _prefersLargeTitles,
              onChanged: (v) => setState(() => _prefersLargeTitles = v),
            ),
          ],
        ),
      ],
      slivers: [
        const SliverPadding(
          padding: .symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: GalleryCaption(
              'MorphNavigationStack.pages: the screens are a list in '
              'state. Adding a page pushes it, removing one pops it, and '
              'the back button and the edge swipe report the page they '
              'remove.',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: MorphListSection(
            children: [
              MorphListRow(
                title: const Text('Open the stack'),
                subtitle: const Text('Library first'),
                accessory: .disclosureIndicator,
                onTap: GalleryGlassScope.enabled(context, () => _open([])),
              ),
              MorphListRow(
                title: const Text('Open at Album 3'),
                subtitle: const Text('Three pages at once, a deep link'),
                accessory: .disclosureIndicator,
                onTap: GalleryGlassScope.enabled(
                  context,
                  () => _open(const [
                    (key: 'deep-1', kind: .album, index: 1),
                    (key: 'deep-2', kind: .album, index: 2),
                    (key: 'deep-3', kind: .album, index: 3),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What a screen above the library of [_Demo] shows.
enum _Kind {
  /// An album, which slides in.
  album,

  /// A photo, which zooms out of its tile.
  photo,
}

/// One screen above the library: its page key, kind and number.
typedef _Entry = ({String key, _Kind kind, int index});

/// A full-screen [MorphNavigationStack.pages] whose screens are the
/// library and the [initialPath] above it, kept as a list in state.
class _Demo extends StatefulWidget {
  /// Creates the demo.
  const _Demo({required this.prefersLargeTitles, this.initialPath = const []});

  /// Whether the stack shows automatic large titles large.
  final bool prefersLargeTitles;

  /// The screens above the library when the demo opens.
  final List<_Entry> initialPath;

  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  late List<_Entry> _path = List.of(widget.initialPath);
  late List<Page<Object?>> _pages = _build();
  int _next = 0;

  static final _photoLinks = <int, MorphSourceLink>{};

  static MorphSourceLink _photoTag(int i) =>
      _photoLinks.putIfAbsent(i, MorphSourceLink.new);

  void _set(List<_Entry> path) => setState(() {
    _path = path;
    _pages = _build();
  });

  void _push(_Kind kind, int index) =>
      _set([..._path, (key: 'page-${_next++}', kind: kind, index: index)]);

  void _removed(Page<Object?> page) => _set([
    for (final e in _path)
      if (ValueKey(e.key) != page.key) e,
  ]);

  String get _trail => [
    'Library',
    for (final e in _path)
      switch (e.kind) {
        _Kind.album => 'Album ${e.index}',
        _Kind.photo => 'Photo ${e.index + 1}',
      },
  ].join(' / ');

  List<Page<Object?>> _build() => [
    MorphNavigationPage<void>(
      key: const ValueKey('library'),
      child: _Library(state: this),
    ),
    for (final e in _path)
      MorphNavigationPage<void>(
        key: ValueKey(e.key),
        from: e.kind == .photo ? _photoTag(e.index) : null,
        child: switch (e.kind) {
          _Kind.album => _Album(state: this, index: e.index),
          _Kind.photo => _Photo(index: e.index),
        },
      ),
  ];

  @override
  Widget build(BuildContext context) => MorphNavigationStack.pages(
    pages: _pages,
    onDidRemovePage: _removed,
    prefersLargeTitles: widget.prefersLargeTitles,
  );
}

class _Trail extends StatelessWidget {
  const _Trail({required this.state});

  final _DemoState state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(horizontal: 16),
    child: GalleryCaption('Pages: ${state._trail}'),
  );
}

class _Library extends StatelessWidget {
  const _Library({required this.state});

  final _DemoState state;

  @override
  Widget build(BuildContext context) => MorphNavigationScaffold(
    title: 'Library',
    largeTitleDisplayMode: .automatic,
    backgroundColor: MorphListAppearance.resolve(context, null).backgroundColor,
    leading: [
      MorphBarButtonGroup([
        MorphBarButton(
          id: 'close',
          label: 'Close',
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ]),
    ],
    trailing: [
      MorphBarButtonGroup([
        MorphBarButton(
          id: 'deep',
          label: 'Album 3',
          onPressed: GalleryGlassScope.enabled(
            context,
            () => state._set([
              for (var i = 1; i <= 3; i++)
                (key: 'page-${state._next++}', kind: .album, index: i),
            ]),
          ),
        ),
      ]),
    ],
    slivers: [
      SliverToBoxAdapter(child: _Trail(state: state)),
      SliverToBoxAdapter(
        child: Padding(
          padding: const .fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              for (var i = 0; i < _palette.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Semantics(
                      button: true,
                      label: 'Photo ${i + 1}',
                      child: GestureDetector(
                        onTap: GalleryGlassScope.enabled(
                          context,
                          () => state._push(.photo, i),
                        ),
                        child: MorphSource(
                          link: _DemoState._photoTag(i),
                          shape: const RoundedRectangleBorder(
                            borderRadius: .all(.circular(12)),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _palette[i],
                              borderRadius: const .all(.circular(12)),
                            ),
                            child: const Center(
                              child: Icon(Icons.photo, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: MorphListSection(
          header: const Text('Albums'),
          children: [
            for (var i = 1; i <= 5; i++)
              MorphListRow(
                title: Text('Album $i'),
                accessory: .disclosureIndicator,
                onTap: GalleryGlassScope.enabled(
                  context,
                  () => state._push(.album, i),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Album extends StatelessWidget {
  const _Album({required this.state, required this.index});

  final _DemoState state;
  final int index;

  @override
  Widget build(BuildContext context) => MorphNavigationScaffold(
    title: 'Album $index',
    largeTitleDisplayMode: .automatic,
    backgroundColor: MorphListAppearance.resolve(context, null).backgroundColor,
    trailing: [
      MorphBarButtonGroup([
        MorphBarButton(
          id: 'root',
          label: 'Library',
          onPressed: GalleryGlassScope.enabled(context, () => state._set([])),
        ),
      ]),
    ],
    slivers: [
      SliverToBoxAdapter(child: _Trail(state: state)),
      SliverToBoxAdapter(
        child: MorphListSection(
          children: [
            MorphListRow(
              title: Text('Album ${index + 1}'),
              subtitle: const Text('Adds a page to the list'),
              accessory: .disclosureIndicator,
              onTap: GalleryGlassScope.enabled(
                context,
                () => state._push(.album, index + 1),
              ),
            ),
            MorphListRow(
              title: const Text('Remove this page'),
              subtitle: const Text('Drops it from the list: a pop'),
              onTap: GalleryGlassScope.enabled(
                context,
                () =>
                    state._set(state._path.sublist(0, state._path.length - 1)),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Photo extends StatelessWidget {
  const _Photo({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => MorphNavigationScaffold(
    title: 'Photo ${index + 1}',
    largeTitleDisplayMode: .never,
    backgroundColor: _palette[index],
    edgeEffect: null,
    slivers: const [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Icon(Icons.photo, color: Colors.white, size: 120)),
      ),
    ],
  );
}
