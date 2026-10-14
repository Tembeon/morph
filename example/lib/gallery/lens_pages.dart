import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/control_pages.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// Segmented controls in every shape the native lens was measured in.
///
/// The page options clear every selection (no segment selected), disable
/// the second segment, fix the first segment's width and pin the controls
/// to an appearance table.
class SegmentedPage extends StatefulWidget {
  /// Creates the page.
  const SegmentedPage({super.key});

  @override
  State<SegmentedPage> createState() => _SegmentedPageState();
}

class _SegmentedPageState extends State<SegmentedPage> {
  final Map<String, int?> _selected = {};
  bool _secondDisabled = false;
  bool _firstFixed = false;
  GalleryLook _look = .theme;
  bool _highContrast = false;

  /// The width the first segment is fixed to by the page options.
  static const double _fixedWidth = 96;

  int? _selectedOf(String key) =>
      _selected.containsKey(key) ? _selected[key] : 0;

  void _clear() {
    setState(() {
      for (final (title, _, _) in _rows) {
        _selected[title] = null;
      }
      _selected['narrow'] = null;
    });
  }

  List<MorphSegment> _segments(List<String> titles, {bool sized = true}) => [
    for (final (i, title) in titles.indexed)
      MorphSegment(
        title,
        enabled: !(_secondDisabled && i == 1),
        width: sized && _firstFixed && i == 0 ? _fixedWidth : null,
      ),
  ];

  MorphSegmentedControlAppearance? get _appearance => _look.pick(
    MorphSegmentedControlAppearance.light,
    MorphSegmentedControlAppearance.dark,
    onLightHighContrast: MorphSegmentedControlAppearance.lightHighContrast,
    onDarkHighContrast: MorphSegmentedControlAppearance.darkHighContrast,
    highContrast: _highContrast,
  );

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Selection'),
      footer: const Text(
        'With no segment selected the lens hides; the next tap shows it at '
        'rest on the chosen segment.',
      ),
      children: [
        MorphListRow(
          title: const Text('Clear every selection'),
          onTap: GalleryGlassScope.enabled(context, _clear),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Segments'),
      children: [
        GalleryToggle(
          label: 'Disable the second segment',
          value: _secondDisabled,
          onChanged: (bool v) => setState(() => _secondDisabled = v),
        ),
        GalleryToggle(
          label: 'First segment ${_fixedWidth.round()} wide',
          value: _firstFixed,
          onChanged: (bool v) => setState(() => _firstFixed = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Appearance'),
      children: [
        GalleryChoice<GalleryLook>(
          label: 'Look',
          options: GalleryLook.options,
          value: _look,
          onChanged: (GalleryLook l) => setState(() => _look = l),
        ),
        GalleryToggle(
          label: 'High-contrast table',
          value: _highContrast,
          onChanged: _look == .theme
              ? null
              : (bool v) => setState(() => _highContrast = v),
        ),
      ],
    ),
  ];

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
    final appearance = _appearance;
    return GalleryPage(
      title: 'Segmented control',
      options: _options,
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
                  segments: _segments(segments),
                  proportionalWidth: byContent,
                  appearance: appearance,
                  selectedIndex: _selectedOf(title),
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
                      segments: _segments(const ['X', 'Y', 'Z'], sized: false),
                      appearance: appearance,
                      selectedIndex: _selectedOf('narrow'),
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
