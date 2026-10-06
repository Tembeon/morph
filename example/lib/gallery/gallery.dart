import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

import 'package:morph_example/gallery/alert_page.dart';
import 'package:morph_example/gallery/control_pages.dart';
import 'package:morph_example/gallery/date_picker_page.dart';
import 'package:morph_example/gallery/glass_page.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/indicator_page.dart';
import 'package:morph_example/gallery/lens_pages.dart';
import 'package:morph_example/gallery/list_page.dart';
import 'package:morph_example/gallery/menu_page.dart';
import 'package:morph_example/gallery/navigation_page.dart';
import 'package:morph_example/gallery/search_page.dart';
import 'package:morph_example/gallery/sheet_page.dart';
import 'package:morph_example/gallery/spec_inspector.dart';

/// The example app: widgets that move exactly like UIKit, each checked
/// against recordings of the real controls.
///
/// The gallery follows the system appearance unless its glass page picks
/// one, and every control below the root draws its glass through the
/// package's [MorphGlassRenderer] at the tier the [GalleryGlassSettings]
/// select, or the one [MorphAdaptiveGlass] picks by the device's GPU.
class GalleryApp extends StatefulWidget {
  /// Creates the app.
  const GalleryApp({this.navigatorKey, super.key});

  /// The key of the gallery's page navigator (the navigation stack's),
  /// for a driver that walks the pages.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  final _settings = GalleryGlassSettings();

  static ThemeData _theme(Brightness brightness) {
    final list = switch (brightness) {
      Brightness.light => MorphListStyle.light,
      Brightness.dark => MorphListStyle.dark,
    };
    final edge = switch (brightness) {
      Brightness.light => MorphScrollEdgeEffectThemeData(
        backgroundColor: list.backgroundColor,
      ),
      Brightness.dark => MorphScrollEdgeEffectThemeData.dark,
    };
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF007AFF),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: list.backgroundColor,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      extensions: [MorphWidgetsTheme(scrollEdgeEffect: edge)],
    );
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (BuildContext context, Widget? _) {
        final renderer = _settings.renderer;
        final tier = _settings.tier;
        return MaterialApp(
          title: 'Morph widgets',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: _settings.appearance,
          builder: (BuildContext context, Widget? child) {
            final app = MorphAdaptiveGlass(
              renderer: renderer,
              tier: tier,
              child: BackdropGroup(child: MorphScope(child: child!)),
            );
            return GalleryGlassScope(
              settings: _settings,
              child: Directionality(
                textDirection: _settings.rtl ? .rtl : .ltr,
                child: MorphGlassInspector(
                  enabled: _settings.inspector,
                  child: app,
                ),
              ),
            );
          },
          home: MorphNavigationStack(
            navigatorKey: widget.navigatorKey,
            home: const GalleryHome(),
          ),
        );
      },
    );
  }
}

/// The grouped background of a gallery page: iOS systemGroupedBackground.
Color galleryBackgroundColor(Brightness brightness) => switch (brightness) {
  Brightness.light => MorphListStyle.light.backgroundColor,
  Brightness.dark => MorphListStyle.dark.backgroundColor,
};

/// The fill of a grouped card on a gallery page: iOS
/// secondarySystemGroupedBackground.
Color galleryCardColor(BuildContext context) =>
    MorphListStyle.resolve(context, null).cellColor;

/// The secondary text of a gallery page: iOS secondaryLabel.
Color gallerySecondaryColor(BuildContext context) =>
    MorphListStyle.resolve(context, null).secondaryColor;

/// One screen of the gallery: a [MorphNavigationScaffold] on the grouped
/// background whose navigation bar ends with the slow-motion button.
///
/// The slow-motion button cycles the app's time dilation through 1x, 5x
/// and 10x, and turns prominent while the motion is slowed. The measured
/// motion runs on ticker time, its per-frame deformation filters step on
/// a fixed 60 or 120 Hz sub-clock in that same time, and touches are
/// stamped on it too, so the widgets slow down as a whole and trace the
/// same curves as at full speed; only the finger keeps real time, so a
/// drag reads faster relative to the motion.
class GalleryPage extends StatefulWidget {
  /// Creates a page.
  const GalleryPage({
    required this.title,
    required this.slivers,
    this.largeTitle = false,
    this.leading,
    this.trailing = const [],
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.edgeEffect = MorphScrollEdgeEffectStyle.hard,
    this.backgroundColor,
    super.key,
  });

  /// The page's title.
  final String title;

  /// The page's content.
  final List<Widget> slivers;

  /// Whether the title shows large above the content.
  final bool largeTitle;

  /// The group at the leading edge of the navigation bar.
  final MorphBarButtonGroup? leading;

  /// The page's own bar button groups, before the slow-motion button.
  final List<MorphBarButtonGroup> trailing;

  /// The groups at the leading edge of the toolbar.
  final List<MorphBarButtonGroup> toolbarLeading;

  /// The groups at the trailing edge of the toolbar.
  final List<MorphBarButtonGroup> toolbarTrailing;

  /// The scroll edge effect under the navigation bar.
  final MorphScrollEdgeEffectStyle? edgeEffect;

  /// The color behind the content; null is the grouped background.
  final Color? backgroundColor;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  static const _factors = [1.0, 5.0, 10.0];

  int get _index {
    final i = _factors.indexOf(timeDilation);
    return i < 0 ? 0 : i;
  }

  void _cycle() {
    setState(() => timeDilation = _factors[(_index + 1) % _factors.length]);
  }

  @override
  Widget build(BuildContext context) {
    final factor = _factors[_index];
    final slowMotion = MorphBarButtonGroup(
      [
        MorphBarButton(
          id: 'slowmo',
          label: '${factor.round()}x',
          semanticLabel: 'Slow motion ${factor.round()}x',
          onPressed: _cycle,
        ),
      ],
      id: 'slowmo',
      prominent: factor != 1,
    );
    return MorphNavigationScaffold(
      title: widget.title,
      largeTitle: widget.largeTitle,
      leading: widget.leading,
      trailing: [...widget.trailing, slowMotion],
      toolbarLeading: widget.toolbarLeading,
      toolbarTrailing: widget.toolbarTrailing,
      edgeEffect: widget.edgeEffect,
      backgroundColor:
          widget.backgroundColor ??
          MorphListStyle.resolve(context, null).backgroundColor,
      slivers: widget.slivers,
    );
  }
}

/// A caption above a demo on a gallery page, in the list header's
/// secondary color.
class GalleryCaption extends StatelessWidget {
  /// Creates a caption.
  const GalleryCaption(this.text, {super.key});

  /// The caption.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .only(left: 4, bottom: 10, top: 24),
      child: Text(
        text,
        style: TextStyle(color: gallerySecondaryColor(context)),
      ),
    );
  }
}

/// One entry of the gallery.
class GalleryEntry {
  /// Creates an entry.
  const GalleryEntry(this.title, this.subtitle, this.builder);

  /// The entry's name.
  final String title;

  /// What the entry shows.
  final String subtitle;

  /// Builds the entry's page.
  final WidgetBuilder builder;
}

/// The gallery's entries, in order.
final List<GalleryEntry> galleryEntries = [
  GalleryEntry(
    'Segmented control',
    'The selection lens: travel, lift, stretch, drag',
    (_) => const SegmentedPage(),
  ),
  GalleryEntry(
    'Tab bar',
    'Floating bar with 2 to 5 tabs, press growth and scrub',
    (_) => const TabBarPage(),
  ),
  GalleryEntry(
    'Controls',
    'Switch, slider, glass button and stepper',
    (_) => const ControlsPage(),
  ),
  GalleryEntry(
    'Menu',
    'A glass button morphing into its menu and back',
    (_) => const MenuPage(),
  ),
  GalleryEntry(
    'Sheets',
    'Floating glass detents, docking at large, drag and scroll hand-off',
    (_) => const SheetPage(),
  ),
  GalleryEntry(
    'Indicators',
    'Progress view and activity indicator',
    (_) => const IndicatorPage(),
  ),
  GalleryEntry(
    'Glass renderer',
    'Liquid glass for the whole gallery: material, optics, dark, RTL',
    (_) => const GlassPage(),
  ),
  GalleryEntry(
    'Size to physics',
    'How UIKit derives deformation and lift from a surface size',
    (_) => const SpecInspectorPage(),
  ),
  GalleryEntry(
    'Navigation',
    'Large title, morphing bar buttons, toolbar sets, scroll edge effect',
    (_) => const NavigationDemoPage(),
  ),
  GalleryEntry(
    'Alerts',
    'Alerts and action sheets growing out of their source',
    (_) => const AlertPage(),
  ),
  GalleryEntry(
    'Search',
    'Bottom search field, tab bar search tab, inline field',
    (_) => const SearchPage(),
  ),
  GalleryEntry(
    'Date picker',
    'Compact date and time labels opening their calendar',
    (_) => const DatePickerPage(),
  ),
  GalleryEntry(
    'Lists',
    'Inset grouped sections with glass buttons in their rows',
    (_) => const ListPage(),
  ),
];

/// The gallery's home: a grouped list of entries under a large title;
/// each row pushes its page onto the gallery's navigation stack.
class GalleryHome extends StatelessWidget {
  /// Creates the home page.
  const GalleryHome({super.key});

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Widgets',
      largeTitle: true,
      slivers: [
        SliverToBoxAdapter(
          child: MorphListSection(
            children: [
              for (final entry in galleryEntries)
                MorphListRow(
                  title: Text(entry.title),
                  subtitle: Text(entry.subtitle),
                  chevron: true,
                  onTap: () => Navigator.of(
                    context,
                  ).push(MorphNavigationRoute<void>(builder: entry.builder)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
