import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

enum _Titles { title, subtitle, both }

enum _Badge { none, count, text, dot }

/// The knobs of the page; the pushed screens follow them too.
class _Options extends ChangeNotifier {
  _Titles titles = .subtitle;
  bool large = false;
  _Badge badge = .count;
  Color? badgeColor;
  MorphBackButtonDisplayMode backMode = .standard;
  bool backTitle = false;
  bool hidesBack = false;
  bool backMenu = false;
  bool parentLarge = true;
  bool scrolledUnder = true;
  MorphScrollEdgeEffectStyle edge = .hard;
  bool standaloneLarge = false;
  bool toolbar = true;

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  String? get subtitle => titles == .title ? null : 'Bars, buttons, badges';

  String? get largeSubtitle => titles == .both ? 'Three demos below' : null;

  MorphBadge? get badgeValue => switch (badge) {
    _Badge.none => null,
    _Badge.count => MorphBadge.count(3, backgroundColor: badgeColor),
    _Badge.text => MorphBadge.string('New', backgroundColor: badgeColor),
    _Badge.dot => MorphBadge.indicator(backgroundColor: badgeColor),
  };

  /// The title the child screen's back button shows for its parent.
  String? get backLabel => switch (backMode) {
    MorphBackButtonDisplayMode.standard => backTitle ? 'Boxes' : 'Mailboxes',
    MorphBackButtonDisplayMode.generic => 'Back',
    MorphBackButtonDisplayMode.minimal => null,
  };
}

const List<Color> _palette = [
  Color(0xFF5E5CE6),
  Color(0xFFFF9F0A),
  Color(0xFF30B0C7),
  Color(0xFFFF375F),
  Color(0xFF34C759),
  Color(0xFFBF5AF2),
];

/// The navigation bar beyond the scaffold defaults: subtitles, back
/// button modes, bar button badges, a page zooming out of its source, and
/// the bars, large title, toolbar and scroll edge effect on their own.
class NavigationBarPage extends StatefulWidget {
  /// Creates the page.
  const NavigationBarPage({super.key});

  @override
  State<NavigationBarPage> createState() => _NavigationBarPageState();
}

class _NavigationBarPageState extends State<NavigationBarPage> {
  final _Options _options = _Options();
  int _mail = 0;

  @override
  void initState() {
    super.initState();
    _options.addListener(_changed);
  }

  @override
  void dispose() {
    _options.removeListener(_changed);
    _options.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _openMailboxes() => Navigator.of(context).push(
    MorphNavigationRoute<void>(builder: (_) => _Mailboxes(options: _options)),
  );

  List<Widget> _rows(BuildContext context) {
    final o = _options;
    return [
      MorphListSection(
        header: const Text('This page'),
        children: [
          GalleryChoice<_Titles>(
            label: 'Titles',
            options: const {
              _Titles.title: 'Title',
              _Titles.subtitle: 'Subtitle',
              _Titles.both: 'Both',
            },
            value: o.titles,
            onChanged: (v) => o.update(() => o.titles = v),
          ),
          GalleryToggle(
            label: 'Large title',
            value: o.large,
            onChanged: (v) => o.update(() => o.large = v),
          ),
          GalleryChoice<_Badge>(
            label: 'Badge',
            options: const {
              _Badge.none: 'None',
              _Badge.count: 'Count',
              _Badge.text: 'Text',
              _Badge.dot: 'Dot',
            },
            value: o.badge,
            onChanged: (v) => o.update(() => o.badge = v),
          ),
          GalleryColorChoice(
            label: 'Badge color',
            value: o.badgeColor,
            onChanged: (v) => o.update(() => o.badgeColor = v),
          ),
        ],
      ),
      MorphListSection(
        header: const Text('Back button'),
        footer: const Text(
          'The mode and title belong to Mailboxes; Inbox shows them in '
          'its back button. Inbox takes the large title of the screen '
          'below it (automatic).',
        ),
        children: [
          GalleryChoice<MorphBackButtonDisplayMode>(
            label: 'Mode',
            options: const {
              MorphBackButtonDisplayMode.standard: 'Title',
              MorphBackButtonDisplayMode.generic: 'Generic',
              MorphBackButtonDisplayMode.minimal: 'Minimal',
            },
            value: o.backMode,
            onChanged: (v) => o.update(() => o.backMode = v),
          ),
          GalleryToggle(
            label: 'Short back title',
            value: o.backTitle,
            onChanged: (v) => o.update(() => o.backTitle = v),
          ),
          GalleryToggle(
            label: 'Hide back button',
            value: o.hidesBack,
            onChanged: (v) => o.update(() => o.hidesBack = v),
          ),
          GalleryToggle(
            label: 'Own back button with a menu',
            value: o.backMenu,
            onChanged: (v) => o.update(() => o.backMenu = v),
          ),
          GalleryToggle(
            label: 'Large Mailboxes title',
            value: o.parentLarge,
            onChanged: (v) => o.update(() => o.parentLarge = v),
          ),
        ],
      ),
      MorphListSection(
        header: const Text('Standalone bars'),
        children: [
          GalleryToggle(
            label: 'Scrolled under',
            value: o.scrolledUnder,
            onChanged: (v) => o.update(() => o.scrolledUnder = v),
          ),
          GalleryChoice<MorphScrollEdgeEffectStyle>(
            label: 'Edge',
            options: const {
              MorphScrollEdgeEffectStyle.hard: 'Hard',
              MorphScrollEdgeEffectStyle.soft: 'Soft',
            },
            value: o.edge,
            onChanged: (v) => o.update(() => o.edge = v),
          ),
          GalleryToggle(
            label: 'Standalone large title',
            value: o.standaloneLarge,
            onChanged: (v) => o.update(() => o.standaloneLarge = v),
          ),
          GalleryToggle(
            label: 'Toolbar',
            value: o.toolbar,
            onChanged: (v) => o.update(() => o.toolbar = v),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final o = _options;
    return GalleryPage(
      title: 'Navigation bar',
      largeTitle: o.large,
      subtitle: o.subtitle,
      largeSubtitle: o.largeSubtitle,
      options: _rows,
      trailing: [
        MorphBarButtonGroup([
          MorphBarButton(
            id: 'mail',
            icon: const Icon(Icons.mail_outline),
            semanticLabel: 'Mail',
            badge: o.badgeValue,
            onPressed: GalleryGlassScope.enabled(
              context,
              () => setState(() => _mail++),
            ),
          ),
        ], id: 'mail'),
      ],
      slivers: [
        SliverPadding(
          padding: const .symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: GalleryCaption(
              'The mail button carries a badge; Page options picks it. '
              'Mail tapped $_mail times.',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: MorphListSection(
            header: const Text('Back button'),
            children: [
              MorphListRow(
                title: const Text('Open Mailboxes'),
                subtitle: Text(_backSummary(o)),
                accessory: .disclosureIndicator,
                onTap: GalleryGlassScope.enabled(context, _openMailboxes),
              ),
            ],
          ),
        ),
        const SliverPadding(
          padding: .symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: GalleryCaption('A page zooming out of its source'),
          ),
        ),
        const SliverToBoxAdapter(child: _ZoomTiles()),
        const SliverPadding(
          padding: .symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: GalleryCaption(
              'A navigation bar, large title, toolbar and edge effects '
              'placed by hand',
            ),
          ),
        ),
        SliverPadding(
          padding: const .fromLTRB(16, 0, 16, 48),
          sliver: SliverToBoxAdapter(child: _StandaloneBars(options: o)),
        ),
      ],
    );
  }

  static String _backSummary(_Options o) {
    final mode = switch (o.backMode) {
      MorphBackButtonDisplayMode.standard => 'title',
      MorphBackButtonDisplayMode.generic => 'generic',
      MorphBackButtonDisplayMode.minimal => 'minimal',
    };
    return [
      'Back button: $mode',
      if (o.backTitle) 'short title',
      if (o.hidesBack) 'hidden',
      if (o.backMenu) 'own with a menu',
    ].join(', ');
  }
}

class _ZoomTiles extends StatelessWidget {
  const _ZoomTiles();

  static final _links = List<MorphSourceLink>.generate(
    3,
    (_) => MorphSourceLink(),
  );

  static MorphSourceLink _id(int i) => _links[i];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .fromLTRB(16, 0, 16, 0),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Semantics(
                button: true,
                label: 'Zoom photo ${i + 1}',
                child: GestureDetector(
                  onTap: GalleryGlassScope.enabled(
                    context,
                    () => Navigator.of(context).push(
                      MorphNavigationRoute<void>(
                        from: _id(i),
                        builder: (_) => _Zoomed(index: i),
                      ),
                    ),
                  ),
                  child: MorphSource(
                    link: _id(i),
                    shape: const RoundedRectangleBorder(
                      borderRadius: .all(.circular(16)),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _palette[i],
                        borderRadius: const .all(.circular(16)),
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
  );
}

class _Zoomed extends StatelessWidget {
  const _Zoomed({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => MorphNavigationScaffold(
    title: 'Photo ${index + 1}',
    largeTitleDisplayMode: .never,
    subtitle: 'Drag down to zoom back',
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

/// The parent screen: its back button mode and title shape the back
/// button of the screen pushed above it.
class _Mailboxes extends StatelessWidget {
  const _Mailboxes({required this.options});

  final _Options options;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: options,
    builder: (BuildContext context, Widget? _) {
      final o = options;
      return MorphNavigationScaffold(
        title: 'Mailboxes',
        largeTitleDisplayMode: o.parentLarge ? .always : .never,
        backButtonTitle: o.backTitle ? 'Boxes' : null,
        backButtonDisplayMode: o.backMode,
        backgroundColor: MorphListAppearance.resolve(
          context,
          null,
        ).backgroundColor,
        slivers: [
          SliverToBoxAdapter(
            child: MorphListSection(
              children: [
                for (final (name, icon) in const [
                  ('Inbox', Icons.inbox_outlined),
                  ('Drafts', Icons.drafts_outlined),
                  ('Sent', Icons.send_outlined),
                ])
                  MorphListRow(
                    leading: Icon(icon),
                    title: Text(name),
                    accessory: .disclosureIndicator,
                    onTap: GalleryGlassScope.enabled(
                      context,
                      () => Navigator.of(context).push(
                        MorphNavigationRoute<void>(
                          builder: (_) => _Mailbox(name: name, options: o),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// The child screen: automatic large title, and a back button hidden,
/// standard, or its own with a menu.
class _Mailbox extends StatelessWidget {
  const _Mailbox({required this.name, required this.options});

  final String name;
  final _Options options;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: options,
    builder: (BuildContext context, Widget? _) {
      final o = options;
      final navigator = Navigator.of(context);
      void popTwice() {
        var popped = 0;
        navigator.popUntil((_) => popped++ == 2);
      }

      return MorphNavigationScaffold(
        title: name,
        subtitle: '12 messages',
        largeTitleDisplayMode: .automatic,
        hidesBackButton: o.hidesBack,
        backgroundColor: MorphListAppearance.resolve(
          context,
          null,
        ).backgroundColor,
        leading: [
          if (o.backMenu)
            MorphBarButtonGroup([
              MorphBarButton.back(
                label: o.backLabel,
                semanticLabel: 'Back',
                onPressed: navigator.pop,
                menu: [
                  MorphMenuItem(title: 'Mailboxes', onSelected: navigator.pop),
                  MorphMenuItem(title: 'Navigation bar', onSelected: popTwice),
                ],
              ),
            ]),
        ],
        slivers: [
          SliverPadding(
            padding: const .symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: GalleryCaption(
                o.hidesBack && !o.backMenu
                    ? 'No back button: swipe from the edge to go back.'
                    : 'Hold the back button for its menu.',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: MorphListSection(
              children: [
                for (var i = 0; i < 12; i++)
                  MorphListRow(
                    title: Text('Message ${i + 1}'),
                    subtitle: const Text('From Anna'),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// A navigation bar, a large title, a toolbar and a bottom edge effect
/// laid over striped content inside a card, driven by the knobs.
class _StandaloneBars extends StatelessWidget {
  const _StandaloneBars({required this.options});

  final _Options options;

  @override
  Widget build(BuildContext context) {
    final o = options;
    const toolbar = MorphToolbar(sideInset: 16, bottomInset: 16);
    return ClipRRect(
      borderRadius: const .all(.circular(24)),
      child: SizedBox(
        height: 320,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    for (var i = 0; i < 8; i++)
                      Expanded(
                        child: ColoredBox(
                          color: _palette[i % _palette.length].withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (o.standaloneLarge)
                Positioned(
                  top: MorphNavigationBar.heightFor(0),
                  left: 0,
                  right: 0,
                  child: MorphLargeTitle('Notes', subtitle: o.largeSubtitle),
                ),
              if (o.toolbar)
                Positioned.fill(
                  child: MorphScrollEdgeEffect(
                    extent: toolbar.extent,
                    edge: .down,
                    style: o.edge,
                    scrolledUnder: o.scrolledUnder,
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MorphNavigationBar(
                  title: 'Notes',
                  subtitle: o.subtitle,
                  titleVisible: !o.standaloneLarge,
                  scrolledUnder: o.scrolledUnder,
                  edgeEffect: o.edge,
                  sideInset: 16,
                  leading: [
                    MorphBarButtonGroup([
                      MorphBarButton.back(
                        label: 'Folders',
                        onPressed: GalleryGlassScope.enabled(context, () {}),
                      ),
                    ]),
                  ],
                  trailing: [
                    MorphBarButtonGroup([
                      MorphBarButton(
                        id: 'compose',
                        icon: const Icon(Icons.edit_outlined),
                        semanticLabel: 'Compose',
                        badge: o.badgeValue,
                        onPressed: GalleryGlassScope.enabled(context, () {}),
                      ),
                    ]),
                  ],
                ),
              ),
              if (o.toolbar)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MorphToolbar(
                    sideInset: toolbar.sideInset,
                    bottomInset: toolbar.bottomInset,
                    leading: [
                      MorphBarButtonGroup([
                        MorphBarButton(
                          id: 'folder',
                          icon: const Icon(Icons.folder_outlined),
                          semanticLabel: 'Folder',
                          onPressed: GalleryGlassScope.enabled(context, () {}),
                        ),
                        MorphBarButton(
                          id: 'check',
                          icon: const Icon(Icons.checklist),
                          semanticLabel: 'Checklist',
                          onPressed: GalleryGlassScope.enabled(context, () {}),
                        ),
                      ], id: 'left'),
                    ],
                    trailing: [
                      MorphBarButtonGroup(
                        [
                          MorphBarButton(
                            id: 'new',
                            label: 'New note',
                            onPressed: GalleryGlassScope.enabled(
                              context,
                              () {},
                            ),
                          ),
                        ],
                        id: 'right',
                        style: .prominent,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
