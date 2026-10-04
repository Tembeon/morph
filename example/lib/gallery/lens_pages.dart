import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Segmented controls in every shape the native lens was measured in.
class SegmentedPage extends StatefulWidget {
  /// Creates the page.
  const SegmentedPage({super.key});

  @override
  State<SegmentedPage> createState() => _SegmentedPageState();
}

class _SegmentedPageState extends State<SegmentedPage> {
  final Map<String, int> _selected = {};

  static const _rows = <(String, List<String>, bool)>[
    ('Two', ['Day', 'Night'], false),
    ('Three', ['A', 'B', 'C'], false),
    ('Four', ['1', '2', '3', '4'], false),
    ('Five', ['1', '2', '3', '4', '5'], false),
    ('Sized by content', ['All', 'Unread messages', 'VIP'], true),
    ('Uneven', ['A', 'Wide segment here', 'B', 'Mid size'], true),
  ];

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Segmented control',
      slivers: [
        SliverPadding(
          padding: const .all(20),
          sliver: SliverList.list(
            children: [
              for (final (title, segments, byContent) in _rows) ...[
                Padding(
                  padding: const .only(left: 4, bottom: 8, top: 12),
                  child: Text(
                    title,
                    style: TextStyle(color: gallerySecondaryColor(context)),
                  ),
                ),
                MorphSegmentedControl(
                  segments: segments,
                  sizeByContent: byContent,
                  selected: _selected[title] ?? 0,
                  onChanged: GalleryGlassScope.enabled(
                    context,
                    (int i) => setState(() => _selected[title] = i),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Tap a segment: the lens moves on release. Press the selected '
                'segment and drag it; past the ends it rubber-bands.',
                style: TextStyle(color: gallerySecondaryColor(context)),
              ),
              Padding(
                padding: const .symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 150,
                    child: MorphSegmentedControl(
                      segments: const ['X', 'Y', 'Z'],
                      selected: _selected['narrow'] ?? 0,
                      onChanged: GalleryGlassScope.enabled(
                        context,
                        (int i) => setState(() => _selected['narrow'] = i),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The floating tab bar with two to five tabs over scrolling content.
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
    MorphTabItem(icon: Icons.library_music_rounded, label: 'Library'),
    MorphTabItem(icon: Icons.radio_rounded, label: 'Radio'),
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
                        segments: const ['2', '3', '4', '5'],
                        selected: _count - 2,
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
