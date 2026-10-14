import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/control_pages.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// The progress view, the activity indicator and the page control:
/// animated progress changes, the eight-spoke spinner in both sizes, and
/// page dots, plain, on their platter and with a timed progress. Start
/// runs the spinners and the timed page control.
///
/// The page options turn the progress animation off, recolor the tracks,
/// spokes and dots, pick the first page control's background style and
/// spoken value, keep a stopped spinner visible and pin each control to
/// an appearance table.
class IndicatorPage extends StatefulWidget {
  /// Creates the page.
  const IndicatorPage({super.key});

  @override
  State<IndicatorPage> createState() => _IndicatorPageState();
}

class _IndicatorPageState extends State<IndicatorPage>
    with SingleTickerProviderStateMixin<IndicatorPage> {
  double _progress = 0.2;
  bool _spinning = false;
  int _page = 0;
  int _timedPage = 0;
  double _timed = 0;
  Duration _pageStart = Duration.zero;
  late final Ticker _timer = createTicker(_tick);

  bool _progressAnimated = true;
  Color? _progressFill;
  Color? _progressTrack;
  GalleryLook _progressLook = .theme;
  bool _progressHighContrast = false;

  MorphPageControlBackgroundStyle _background = .automatic;
  bool _photoValue = false;
  Color? _dotColor;
  GalleryLook _pageLook = .theme;
  bool _pageHighContrast = false;

  bool _hidesWhenStopped = true;
  Color? _spokeColor;
  GalleryLook _spinnerLook = .theme;

  static const _pageDuration = Duration(seconds: 3);

  static const _backgrounds = <MorphPageControlBackgroundStyle, String>{
    .automatic: 'Automatic',
    .prominent: 'Prominent',
    .minimal: 'Minimal',
  };

  static const _trackColors = <(String, Color?)>[
    ('Default', null),
    ('Pale purple', Color(0x4DAF52DE)),
    ('Pale orange', Color(0x4DFF9500)),
    ('Pale teal', Color(0x4D30B0C7)),
  ];

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _spinning = !_spinning);
    if (_spinning) {
      _pageStart = Duration.zero;
      _timer.start();
    } else {
      _timer.stop();
    }
  }

  void _tick(Duration elapsed) {
    var f =
        (elapsed - _pageStart).inMicroseconds / _pageDuration.inMicroseconds;
    if (f >= 1) {
      _pageStart = elapsed;
      f = 0;
      _timedPage = (_timedPage + 1) % 5;
    }
    setState(() => _timed = f);
  }

  MorphProgressViewAppearance? get _progressAppearance => _progressLook.pick(
    MorphProgressViewAppearance.light,
    MorphProgressViewAppearance.dark,
    onLightHighContrast: MorphProgressViewAppearance.lightHighContrast,
    onDarkHighContrast: MorphProgressViewAppearance.darkHighContrast,
    highContrast: _progressHighContrast,
  );

  MorphPageControlAppearance? get _pageAppearance {
    final dot = _dotColor;
    if (dot != null) {
      return MorphPageControlAppearance(
        pageIndicatorColor: dot.withValues(alpha: 0.35),
        currentPageIndicatorColor: dot,
      );
    }
    return _pageLook.pick(
      MorphPageControlAppearance.light,
      MorphPageControlAppearance.dark,
      onLightHighContrast: MorphPageControlAppearance.lightHighContrast,
      onDarkHighContrast: MorphPageControlAppearance.darkHighContrast,
      highContrast: _pageHighContrast,
    );
  }

  MorphActivityIndicatorAppearance? get _spinnerAppearance => _spinnerLook.pick(
    MorphActivityIndicatorAppearance.light,
    MorphActivityIndicatorAppearance.dark,
  );

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Progress'),
      children: [
        GalleryToggle(
          label: 'Animated',
          value: _progressAnimated,
          onChanged: (bool v) => setState(() => _progressAnimated = v),
        ),
        GalleryColorChoice(
          label: 'Fill',
          value: _progressFill,
          onChanged: (Color? c) => setState(() => _progressFill = c),
        ),
        GalleryColorChoice(
          label: 'Track',
          value: _progressTrack,
          colors: _trackColors,
          onChanged: (Color? c) => setState(() => _progressTrack = c),
        ),
        GalleryChoice<GalleryLook>(
          label: 'Look',
          options: GalleryLook.options,
          value: _progressLook,
          onChanged: (GalleryLook l) => setState(() => _progressLook = l),
        ),
        GalleryToggle(
          label: 'Progress high-contrast table',
          value: _progressHighContrast,
          onChanged: _progressLook == .theme
              ? null
              : (bool v) => setState(() => _progressHighContrast = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Page control'),
      footer: const Text(
        'The platter style applies to the first page control. Photo values '
        'announce "photo n of count" instead of "page n of count". A dot '
        'color replaces the look.',
      ),
      children: [
        GalleryChoice<MorphPageControlBackgroundStyle>(
          label: 'Platter',
          options: _backgrounds,
          value: _background,
          onChanged: (MorphPageControlBackgroundStyle b) =>
              setState(() => _background = b),
        ),
        GalleryToggle(
          label: 'Photo values',
          value: _photoValue,
          onChanged: (bool v) => setState(() => _photoValue = v),
        ),
        GalleryColorChoice(
          label: 'Dots',
          value: _dotColor,
          onChanged: (Color? c) => setState(() => _dotColor = c),
        ),
        GalleryChoice<GalleryLook>(
          label: 'Look',
          options: GalleryLook.options,
          value: _pageLook,
          onChanged: _dotColor == null
              ? (GalleryLook l) => setState(() => _pageLook = l)
              : null,
        ),
        GalleryToggle(
          label: 'Page control high-contrast table',
          value: _pageHighContrast,
          onChanged: _dotColor == null && _pageLook != .theme
              ? (bool v) => setState(() => _pageHighContrast = v)
              : null,
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Activity indicator'),
      children: [
        GalleryToggle(
          label: 'Hides when stopped',
          value: _hidesWhenStopped,
          onChanged: (bool v) => setState(() => _hidesWhenStopped = v),
        ),
        GalleryColorChoice(
          label: 'Spokes',
          value: _spokeColor,
          onChanged: (Color? c) => setState(() => _spokeColor = c),
        ),
        GalleryChoice<GalleryLook>(
          label: 'Look',
          options: GalleryLook.options,
          value: _spinnerLook,
          onChanged: (GalleryLook l) => setState(() => _spinnerLook = l),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final progressAppearance = _progressAppearance;
    final pageAppearance = _pageAppearance;
    final spinnerAppearance = _spinnerAppearance;
    final formatter = _photoValue
        ? (int page, int count) => 'photo $page of $count'
        : null;
    void setPage(int p) => setState(() => _page = p);
    return GalleryPage(
      title: 'Indicators',
      options: _options,
      slivers: [
        SliverPadding(
          padding: const .all(20),
          sliver: SliverList.list(
            children: [
              GalleryCaption('Progress: ${(_progress * 100).round()}%'),
              MorphProgressView(
                value: _progress,
                semanticLabel: 'Download',
                animated: _progressAnimated,
                activeTrackColor: _progressFill,
                inactiveTrackColor: _progressTrack,
                appearance: progressAppearance,
              ),
              const SizedBox(height: 20),
              MorphProgressView(
                value: _progress,
                style: MorphProgressViewStyle.bar,
                animated: _progressAnimated,
                activeTrackColor: _progressFill,
                inactiveTrackColor: _progressTrack,
                appearance: progressAppearance,
              ),
              const SizedBox(height: 16),
              MorphGlassContainer(
                solidBackdrop: MorphListAppearance.resolve(
                  context,
                  null,
                ).backgroundColor,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final v in const [0.0, 0.05, 0.3, 0.8, 1.0])
                      SizedBox(
                        width: 72,
                        height: 40,
                        child: MorphGlassButton(
                          padding: .zero,
                          onPressed: GalleryGlassScope.enabled(
                            context,
                            () => setState(() => _progress = v),
                          ),
                          child: Text('${(v * 100).round()}%'),
                        ),
                      ),
                  ],
                ),
              ),
              GalleryCaption('Page control: page ${_page + 1} of 5'),
              Center(
                child: MorphPageControl(
                  count: 5,
                  page: _page,
                  semanticLabel: 'Pages',
                  backgroundStyle: _background,
                  semanticValueFormatter: formatter,
                  appearance: pageAppearance,
                  onChanged: GalleryGlassScope.enabled(context, setPage),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: MorphPageControl(
                  count: 5,
                  page: _page,
                  backgroundStyle: MorphPageControlBackgroundStyle.prominent,
                  semanticValueFormatter: formatter,
                  appearance: pageAppearance,
                  onChanged: GalleryGlassScope.enabled(context, setPage),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: ColoredBox(
                  color: const Color(0xFF3A3A3C),
                  child: Padding(
                    padding: const .all(8),
                    child: MorphPageControl(
                      count: 5,
                      page: _timedPage,
                      progress: _timed,
                      semanticValueFormatter: formatter,
                      appearance: pageAppearance,
                      onChanged: GalleryGlassScope.enabled(
                        context,
                        (int p) => setState(() => _timedPage = p),
                      ),
                    ),
                  ),
                ),
              ),
              const GalleryCaption('Activity indicators'),
              MorphGlassContainer(
                solidBackdrop: MorphListAppearance.resolve(
                  context,
                  null,
                ).backgroundColor,
                child: Row(
                  children: [
                    MorphActivityIndicator(
                      animating: _spinning,
                      hidesWhenStopped: _hidesWhenStopped,
                      color: _spokeColor,
                      appearance: spinnerAppearance,
                      semanticLabel: 'Loading',
                    ),
                    const SizedBox(width: 32),
                    MorphActivityIndicator(
                      animating: _spinning,
                      hidesWhenStopped: _hidesWhenStopped,
                      size: MorphActivityIndicatorSize.large,
                      color: _spokeColor,
                      appearance: spinnerAppearance,
                    ),
                    const SizedBox(width: 32),
                    SizedBox(
                      width: 100,
                      height: 40,
                      child: MorphGlassButton(
                        padding: .zero,
                        onPressed: GalleryGlassScope.enabled(context, _toggle),
                        child: Text(_spinning ? 'Stop' : 'Start'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
