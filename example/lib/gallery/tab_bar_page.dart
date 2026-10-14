import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// The floating tab bar with two to five tabs over scrolling content; Library
/// carries a count badge, Radio a dot.
class TabBarPage extends StatefulWidget {
  /// Creates the page.
  const TabBarPage({super.key});

  @override
  State<TabBarPage> createState() => _TabBarPageState();
}

class _TabBarPageState extends State<TabBarPage> {
  int _count = 4;
  int _selected = 0;

  static const _items = [
    MorphTabItem(icon: Icons.home_rounded, label: 'Home'),
    MorphTabItem(
      icon: Icons.library_music_rounded,
      label: 'Library',
      badge: MorphBadge.count(3),
    ),
    MorphTabItem(
      icon: Icons.radio_rounded,
      label: 'Radio',
      badge: MorphBadge.indicator(),
    ),
    MorphTabItem(icon: Icons.person_rounded, label: 'Profile'),
    MorphTabItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GalleryPage(
          title: 'Tab bar',
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
                      '${_items[_selected].label} row $i',
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
              items: _items.sublist(0, _count),
              selected: _selected,
              onChanged: GalleryGlassScope.enabled(
                context,
                (int i) => setState(() => _selected = i),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
