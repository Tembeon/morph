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
                  segments: [for (final s in segments) MorphSegment(s)],
                  proportionalWidth: byContent,
                  selectedIndex: _selected[title] ?? 0,
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
                      segments: const [
                        MorphSegment('X'),
                        MorphSegment('Y'),
                        MorphSegment('Z'),
                      ],
                      selectedIndex: _selected['narrow'] ?? 0,
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
