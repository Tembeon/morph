# morph recipes

Copyable call sites. Each block compiles against `package:morph/morph.dart`
together with `package:flutter/widgets.dart` (the skill's check extracts
every block and analyzes it). Exact parameters: `api.md`.

## Tab bar

A floating iOS 27 tab bar with its lens; put it at the bottom of a
`Stack` over the page so the page scrolls under its glass.

```dart
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: _pages[_tab]),
      Align(
        alignment: Alignment.bottomCenter,
        child: MorphTabBar(
          items: const [
            MorphTabItem(icon: IconData(0xe318), label: 'Home'),
            MorphTabItem(
              icon: IconData(0xe567),
              label: 'Inbox',
              badge: MorphBadge.count(3),
            ),
            MorphTabItem(
              icon: IconData(0xe8b6),
              label: 'Search',
              role: MorphTabRole.search,
            ),
          ],
          selected: _tab,
          onChanged: (int tab) => setState(() => _tab = tab),
          minimizeBehavior: MorphTabBarMinimizeBehavior.onScrollDown,
        ),
      ),
    ],
  );

  static const List<Widget> _pages = [
    SizedBox.expand(),
    SizedBox.expand(),
    SizedBox.expand(),
  ];
}
```

A tab bar that minimizes on scroll reads the page's scroll through
`contentScroll:` (`MorphContentScroll`); `bottomAccessory:` adds the
mini-player style accessory above it.

## Glass buttons, joined glass, glass on any widget

```dart
Widget buttons(VoidCallback onShare, VoidCallback onLike) =>
    MorphGlassContainer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MorphGlassButton(onPressed: onShare, child: const Text('Share')),
          const SizedBox(width: 8),
          MorphGlassButton.prominent(
            onPressed: onLike,
            child: const Text('Like'),
          ),
        ],
      ),
    );

Widget glassBadge() => const MorphGlassEffect(
  shape: StadiumBorder(),
  style: MorphGlassStyle.clear,
  child: Padding(padding: EdgeInsets.all(12), child: Text('Live')),
);
```

`MorphGlassButton.clear` is the clear variant. A button with `menu:`
opens that menu out of itself instead of calling `onPressed`.

## Menus

```dart
List<MorphMenuEntry> sortMenu(String sort, ValueChanged<String> onSort) => [
  MorphMenuSection(
    title: 'Sort by',
    singleSelection: true,
    children: [
      for (final key in const ['Name', 'Date', 'Size'])
        MorphMenuItem(
          title: key,
          state: key == sort ? MorphMenuState.on : MorphMenuState.off,
          onSelected: () => onSort(key),
        ),
    ],
  ),
  MorphSubmenu(
    title: 'View',
    children: [
      MorphMenuItem(title: 'Icons', onSelected: () {}),
      MorphMenuItem(title: 'List', onSelected: () {}),
    ],
  ),
  MorphMenuItem(title: 'Delete', destructive: true, onSelected: () {}),
];

Widget menuButton(String sort, ValueChanged<String> onSort) =>
    MorphMenuButton(menu: sortMenu(sort, onSort));
```

Context menu with a preview, as a long press on a cell:

```dart
Widget photoCell(Widget thumbnail, Widget Function(BuildContext) preview) =>
    MorphContextMenuRegion(
      preview: preview,
      menu: [
        MorphMenuItem(title: 'Copy', onSelected: () {}),
        MorphMenuItem(title: 'Delete', destructive: true, onSelected: () {}),
      ],
      child: thumbnail,
    );
```

`MorphMenuDeferred` loads entries lazily; `MorphMenuWidget` puts a
custom widget row in a menu. `MorphContextMenuRegion.close(context)`
closes the open context menu from inside it.

## Navigation

```dart
class Library extends StatelessWidget {
  const Library({super.key});

  @override
  Widget build(BuildContext context) =>
      const MorphNavigationStack(prefersLargeTitles: true, home: AlbumsPage());
}

class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) => MorphNavigationScaffold(
    title: 'Albums',
    trailing: [
      MorphBarButtonGroup([
        MorphBarButton(id: 'add', label: 'Add', onPressed: () {}),
      ]),
    ],
    toolbarTrailing: [
      MorphBarButtonGroup([
        MorphBarButton(
          id: 'more',
          label: 'More',
          menu: [MorphMenuItem(title: 'Select', onSelected: () {})],
        ),
      ]),
    ],
    slivers: [
      SliverList.builder(
        itemCount: 20,
        itemBuilder: (context, index) => MorphListRow(
          title: Text('Album $index'),
          accessory: MorphListAccessory.disclosureIndicator,
          onTap: () => Navigator.of(context).push(
            MorphNavigationRoute<void>(builder: (_) => AlbumPage(index: index)),
          ),
        ),
      ),
    ],
  );
}

class AlbumPage extends StatelessWidget {
  const AlbumPage({required this.index, super.key});

  final int index;

  @override
  Widget build(BuildContext context) => MorphNavigationScaffold(
    title: 'Album $index',
    largeTitleDisplayMode: MorphLargeTitleDisplayMode.never,
    slivers: const [SliverToBoxAdapter(child: SizedBox(height: 400))],
  );
}
```

Declarative stacks use `MorphNavigationStack.pages(pages:,
onDidRemovePage:)` with `MorphNavigationPage`. A standalone bar is
`MorphNavigationBar`; a bottom toolbar is `MorphToolbar`.

## Presentations that grow out of their source

```dart
class AlbumCard extends StatelessWidget {
  AlbumCard({required this.title, super.key});

  final String title;
  final MorphSourceLink _link = MorphSourceLink();

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => showMorphSheet<void>(
      context,
      from: _link,
      detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
      grabberVisible: true,
      builder: (context) => Center(child: Text(title)),
    ),
    onLongPress: () => Navigator.of(context).push(
      MorphNavigationRoute<void>(
        from: _link,
        builder: (_) => MorphNavigationScaffold(
          title: title,
          slivers: const [SliverToBoxAdapter(child: SizedBox(height: 600))],
        ),
      ),
    ),
    child: MorphSource(
      link: _link,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: SizedBox(width: 160, height: 160, child: Text(title)),
    ),
  );
}
```

Keep the `MorphSourceLink` in state that lives as long as the source
(a `State` field, or a final field of a widget that is rebuilt with the
same instance). Without `from:` a sheet rises from the bottom edge.

## Alerts and action sheets

```dart
Future<void> confirmDelete(BuildContext context) async {
  final choice = await showMorphAlert(
    context,
    title: 'Delete photo?',
    message: 'This cannot be undone.',
    actions: const [
      MorphAlertAction(title: 'Cancel', style: MorphAlertActionStyle.cancel),
      MorphAlertAction(
        title: 'Delete',
        style: MorphAlertActionStyle.destructive,
      ),
    ],
  );
  if (choice?.title == 'Delete') {
    // delete
  }
}

Future<void> share(BuildContext context, BuildContext source) async {
  await showMorphActionSheet(
    context,
    title: 'Share',
    anchor: source,
    actions: [
      MorphAlertAction(title: 'Copy link', onPressed: () {}),
      const MorphAlertAction(
        title: 'Cancel',
        style: MorphAlertActionStyle.cancel,
      ),
    ],
  );
}
```

`anchor:` (or `anchorRect:`) presents the action sheet as a popover
pointing at its source; without it, it rises from the bottom.

## Lists

```dart
Widget settings({required bool wifi, required ValueChanged<bool> onWifi}) =>
    ListView(
      children: [
        MorphListSection(
          header: const Text('Network'),
          footer: const Text('Changes apply at once.'),
          children: [
            MorphListRow(
              title: const Text('Wi-Fi'),
              trailing: MorphSwitch(value: wifi, onChanged: onWifi),
            ),
            MorphListRow(
              title: const Text('Bluetooth'),
              detail: const Text('On'),
              accessory: MorphListAccessory.disclosureIndicator,
              onTap: () {},
            ),
          ],
        ),
      ],
    );
```

Inside a `CustomScrollView`, use `MorphSliverListSection`.

## Value controls

```dart
class Controls extends StatefulWidget {
  const Controls({super.key});

  @override
  State<Controls> createState() => _ControlsState();
}

class _ControlsState extends State<Controls> {
  int _segment = 0;
  bool _on = true;
  double _volume = 0.5;
  double _count = 1;
  DateTime _date = DateTime(2026, 10, 20);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      MorphSegmentedControl(
        segments: const [MorphSegment('Day'), MorphSegment('Week')],
        selectedIndex: _segment,
        onChanged: (int i) => setState(() => _segment = i),
      ),
      MorphSwitch(value: _on, onChanged: (v) => setState(() => _on = v)),
      MorphSlider(
        value: _volume,
        onChanged: (v) => setState(() => _volume = v),
      ),
      MorphStepper(
        value: _count,
        min: 1,
        max: 10,
        onChanged: (v) => setState(() => _count = v),
      ),
      MorphDatePicker(
        value: _date,
        mode: MorphDatePickerMode.dateAndTime,
        onChanged: (d) => setState(() => _date = d),
      ),
      MorphPageControl(count: 4, page: _segment, onChanged: (_) {}),
      const MorphProgressView(value: 0.3),
      const MorphActivityIndicator(),
    ],
  );
}
```

`MorphSlider(ticks:)` makes a stepped slider that lands on stops.

## Search

```dart
Widget searchBar(ValueChanged<String> onQuery) => MorphSearchToolbar(
  placeholder: 'Search',
  onChanged: onQuery,
  trailing: [
    MorphBarButtonGroup([
      MorphBarButton(id: 'compose', label: 'Compose', onPressed: () {}),
    ]),
  ],
);
```

A page's own search field in the navigation bar is
`MorphNavigationScaffold(search: MorphNavigationSearch(...))`; a tab
bar's search tab is `MorphSearchTabBar`.

## Theme

```dart
const MorphThemeData theme = MorphThemeData(
  glass: MorphGlassRenderer.adaptive(),
  tint: Color(0xFF34C759),
  appearances: [MorphTabBarAppearance(selectedColor: Color(0xFF34C759))],
);
```

`MorphGlassRenderer.tier(MorphGlassTier.flat)` forces the flat look,
for example from a user setting; `MorphTheme.of(context)` reads it back.
