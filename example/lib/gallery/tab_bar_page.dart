import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

enum _Badge { none, count, text, dot }

/// The floating tab bar with two to five tabs over scrolling content; Library
/// carries a count badge, Radio a dot.
///
/// Page options pick each badge and its color, outlined icons with filled
/// selected ones, a disabled Profile tab and the selection tint, and count
/// the taps on the selected tab (`onReselected`).
class TabBarPage extends StatefulWidget {
  /// Creates the page.
  const TabBarPage({super.key});

  @override
  State<TabBarPage> createState() => _TabBarPageState();
}

class _TabBarPageState extends State<TabBarPage> {
  int _count = 4;
  int _selected = 0;
  int _reselected = 0;
  _Badge _libraryBadge = .count;
  _Badge _radioBadge = .dot;
  Color? _badgeColor;
  bool _selectedIcons = false;
  bool _disabledProfile = false;
  Color? _tint;

  MorphBadge? _badge(_Badge badge, int count) => switch (badge) {
    _Badge.none => null,
    _Badge.count => MorphBadge.count(count, backgroundColor: _badgeColor),
    _Badge.text => MorphBadge.string('New', backgroundColor: _badgeColor),
    _Badge.dot => MorphBadge.indicator(backgroundColor: _badgeColor),
  };

  /// The tabs: with selected icons, each tab shows an outlined glyph and
  /// its filled one inside the lens.
  List<MorphTabItem> get _items {
    final outlined = _selectedIcons;
    return [
      MorphTabItem(
        icon: outlined ? Icons.home_outlined : Icons.home_rounded,
        selectedIcon: outlined ? Icons.home_rounded : null,
        label: 'Home',
      ),
      MorphTabItem(
        icon: outlined
            ? Icons.library_music_outlined
            : Icons.library_music_rounded,
        selectedIcon: outlined ? Icons.library_music_rounded : null,
        label: 'Library',
        badge: _badge(_libraryBadge, 3),
      ),
      MorphTabItem(
        icon: outlined ? Icons.radio_outlined : Icons.radio_rounded,
        selectedIcon: outlined ? Icons.radio_rounded : null,
        label: 'Radio',
        badge: _badge(_radioBadge, 12),
      ),
      MorphTabItem(
        icon: outlined ? Icons.person_outline_rounded : Icons.person_rounded,
        selectedIcon: outlined ? Icons.person_rounded : null,
        label: 'Profile',
        enabled: !_disabledProfile,
      ),
      MorphTabItem(
        icon: outlined ? Icons.settings_outlined : Icons.settings_rounded,
        selectedIcon: outlined ? Icons.settings_rounded : null,
        label: 'Settings',
      ),
    ];
  }

  static const Map<_Badge, String> _badges = {
    _Badge.none: 'None',
    _Badge.count: 'Count',
    _Badge.text: 'Text',
    _Badge.dot: 'Dot',
  };

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Tabs'),
      children: [
        GalleryChoice<_Badge>(
          label: 'Library',
          options: _badges,
          value: _libraryBadge,
          onChanged: (v) => setState(() => _libraryBadge = v),
        ),
        GalleryChoice<_Badge>(
          label: 'Radio',
          options: _badges,
          value: _radioBadge,
          onChanged: (v) => setState(() => _radioBadge = v),
        ),
        GalleryColorChoice(
          label: 'Badge color',
          value: _badgeColor,
          onChanged: (v) => setState(() => _badgeColor = v),
        ),
        GalleryToggle(
          label: 'Selected icons',
          value: _selectedIcons,
          onChanged: (v) => setState(() => _selectedIcons = v),
        ),
        GalleryToggle(
          label: 'Disable Profile',
          value: _disabledProfile,
          onChanged: (v) => setState(() => _disabledProfile = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Appearance'),
      children: [
        GalleryColorChoice(
          label: 'Tint',
          value: _tint,
          onChanged: (v) => setState(() => _tint = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Reselection'),
      footer: const Text('Tap the selected tab again.'),
      children: [
        MorphListRow(
          title: const Text('Reselected'),
          detail: Text('$_reselected'),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final tint = _tint;
    return Stack(
      children: [
        GalleryPage(
          title: 'Tab bar',
          options: _options,
          slivers: [
            SliverPadding(
              padding: const .fromLTRB(16, 8, 16, 120),
              sliver: SliverList.builder(
                itemCount: 40,
                itemBuilder: (BuildContext context, int i) {
                  if (i == 0) {
                    return Padding(
                      padding: const .only(bottom: 12),
                      child: MorphSegmentedControl(
                        segments: const [
                          MorphSegment('2'),
                          MorphSegment('3'),
                          MorphSegment('4'),
                          MorphSegment('5'),
                        ],
                        selectedIndex: _count - 2,
                        onChanged: (int v) => setState(() {
                          _count = v + 2;
                          _selected = _selected.clamp(0, _count - 1);
                        }),
                      ),
                    );
                  }
                  return Container(
                    height: 64,
                    margin: const .only(bottom: 8),
                    decoration: BoxDecoration(
                      color: HSLColor.fromAHSL(
                        1,
                        (i * 37) % 360,
                        0.55,
                        0.62,
                      ).toColor(),
                      borderRadius: .circular(14),
                    ),
                    alignment: .centerLeft,
                    padding: const .symmetric(horizontal: 16),
                    child: Text(
                      '${items[_selected].label} row $i',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 21,
          child: Center(
            child: MorphTabBar(
              key: ValueKey(_count),
              items: items.sublist(0, _count),
              selected: _selected,
              onChanged: GalleryGlassScope.enabled(
                context,
                (int i) => setState(() => _selected = i),
              ),
              onReselected: GalleryGlassScope.enabled(
                context,
                (int _) => setState(() => _reselected++),
              ),
              appearance: tint == null
                  ? null
                  : MorphTabBarAppearance.resolve(
                      context,
                      null,
                    ).copyWith(selectedColor: tint),
            ),
          ),
        ),
      ],
    );
  }
}
