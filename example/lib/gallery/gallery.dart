import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

import 'package:morph_example/gallery/alert_page.dart';
import 'package:morph_example/gallery/context_menu_page.dart';
import 'package:morph_example/gallery/control_pages.dart';
import 'package:morph_example/gallery/date_picker_page.dart';
import 'package:morph_example/gallery/engine_page.dart';
import 'package:morph_example/gallery/glass_buttons_page.dart';
import 'package:morph_example/gallery/glass_effects_page.dart';
import 'package:morph_example/gallery/glass_page.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/indicator_page.dart';
import 'package:morph_example/gallery/lens_pages.dart';
import 'package:morph_example/gallery/list_page.dart';
import 'package:morph_example/gallery/menu_page.dart';
import 'package:morph_example/gallery/menu_source_page.dart';
import 'package:morph_example/gallery/minimize_page.dart';
import 'package:morph_example/gallery/navigation_bar_page.dart';
import 'package:morph_example/gallery/navigation_page.dart';
import 'package:morph_example/gallery/navigator_pages_page.dart';
import 'package:morph_example/gallery/search_page.dart';
import 'package:morph_example/gallery/sheet_page.dart';
import 'package:morph_example/gallery/spec_inspector.dart';
import 'package:morph_example/gallery/tab_bar_page.dart';
import 'package:morph_example/gallery/theming_page.dart';

/// The example app: widgets that move exactly like UIKit, each checked
/// against recordings of the real controls.
///
/// The gallery follows the system appearance unless its glass page picks
/// one, and every control below the root draws its glass through the
/// package's [MorphGlassRenderer] at the tier the [GalleryGlassSettings]
/// select, or the one [MorphAdaptiveGlass] picks by the device's GPU.
class GalleryApp extends StatefulWidget {
  /// Creates the app.
  const GalleryApp({this.navigatorKey, this.home, super.key});

  /// The key of the gallery's page navigator (the navigation stack's),
  /// for a driver that walks the pages.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// A page shown instead of the gallery, with the gallery's theme, glass
  /// renderer and tier: a bench stage.
  final Widget? home;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  final _settings = GalleryGlassSettings();

  /// The GPU resource cache the gallery asks Skia for, in bytes.
  ///
  /// The engine sizes its default budget from the screen. On a small
  /// screen a menu's animated blurs outgrow it every frame, and Skia frees
  /// and recreates its scratch textures (Redmi 6A: 419 texture creations in three menu windows; 25
  /// with this budget, menu raster p95 23.3 -> 21.5 ms). Impeller ignores
  /// it.
  static const int skiaResourceCacheBytes = 128 << 20;

  @override
  void initState() {
    super.initState();
    SystemChannels.skia
        .invokeMethod<void>(
          'Skia.setResourceCacheMaxBytes',
          skiaResourceCacheBytes,
        )
        .ignore();
  }

  static ThemeData _theme(
    Brightness brightness, {
    Color? accent,
    bool haptics = true,
  }) {
    final list = switch (brightness) {
      Brightness.light => MorphListAppearance.light,
      Brightness.dark => MorphListAppearance.dark,
    };
    final edge = switch (brightness) {
      Brightness.light => MorphScrollEdgeEffectAppearance(
        backgroundColor: list.backgroundColor,
      ),
      Brightness.dark => MorphScrollEdgeEffectAppearance.dark,
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
      extensions: [
        MorphWidgetsTheme(
          scrollEdgeEffect: edge,
          tint: accent,
          haptics: haptics ? null : false,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GalleryGlassHost(
    settings: _settings,
    child: _GalleryMaterialApp(
      home:
          widget.home ??
          MorphNavigationStack(
            navigatorKey: widget.navigatorKey,
            home: const GalleryHome(),
          ),
    ),
  );
}

class _GalleryMaterialApp extends StatelessWidget {
  const _GalleryMaterialApp({required this.home});

  final Widget home;

  /// Built once per look, so a ThemeData stays identical between builds
  /// and the controls below do not rebuild for an unchanged theme.
  static final _themes = <(Brightness, Color?, bool), ThemeData>{};

  static ThemeData _theme(Brightness brightness, Color? accent, bool haptics) =>
      _themes.putIfAbsent(
        (brightness, accent, haptics),
        () => _GalleryAppState._theme(
          brightness,
          accent: accent,
          haptics: haptics,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theming = GalleryGlassScope.of(context, .theming);
    return MaterialApp(
      title: 'Morph widgets',
      debugShowCheckedModeBanner: false,
      theme: _theme(.light, theming.accent, theming.haptics),
      darkTheme: _theme(.dark, theming.accent, theming.haptics),
      themeMode: GalleryGlassScope.of(context, .appearance).appearance,
      builder: (BuildContext context, Widget? child) =>
          _GalleryChrome(child: child!),
      home: home,
    );
  }
}

class _GalleryChrome extends StatelessWidget {
  const _GalleryChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = GalleryGlassScope.of(context, .glass);
    final accessibility = GalleryGlassScope.of(context, .accessibility);
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        disableAnimations:
            media.disableAnimations || accessibility.reduceMotion,
        highContrast: media.highContrast || accessibility.highContrast,
      ),
      child: Directionality(
        textDirection: GalleryGlassScope.of(context, .rtl).rtl ? .rtl : .ltr,
        child: MorphGlassInspector(
          enabled: GalleryGlassScope.of(context, .inspector).inspector,
          child: MorphAdaptiveGlass(
            renderer: glass.renderer,
            tier: glass.tier,
            child: BackdropGroup(child: MorphScope(child: child)),
          ),
        ),
      ),
    );
  }
}

/// The grouped background of a gallery page: iOS systemGroupedBackground.
Color galleryBackgroundColor(Brightness brightness) => switch (brightness) {
  Brightness.light => MorphListAppearance.light.backgroundColor,
  Brightness.dark => MorphListAppearance.dark.backgroundColor,
};

/// The fill of a grouped card on a gallery page: iOS
/// secondarySystemGroupedBackground.
Color galleryCardColor(BuildContext context) =>
    MorphListAppearance.resolve(context, null).cellColor;

/// The secondary text of a gallery page: iOS secondaryLabel.
Color gallerySecondaryColor(BuildContext context) =>
    MorphListAppearance.resolve(context, null).secondaryColor;

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
    this.subtitle,
    this.largeSubtitle,
    this.leading = const [],
    this.trailing = const [],
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.edgeEffect = MorphScrollEdgeEffectStyle.hard,
    this.backgroundColor,
    this.options,
    this.optionsListenable,
    super.key,
  });

  /// The page's title.
  final String title;

  /// The page's content.
  final List<Widget> slivers;

  /// Whether the title shows large above the content.
  final bool largeTitle;

  /// The line under the inline title, or null.
  final String? subtitle;

  /// The line under the large title, or null for [subtitle].
  final String? largeSubtitle;

  /// The groups at the leading edge of the navigation bar.
  final List<MorphBarButtonGroup> leading;

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

  /// The rows of the page's options sheet, or null for a page without
  /// options.
  ///
  /// When set, the navigation bar shows a 'Page options' button before
  /// the slow-motion one, and the button opens [showGalleryOptions] with
  /// these rows: usually [MorphListSection]s of the knobs in `knobs.dart`.
  /// The sheet stops at a medium detent without dimming the page, so the
  /// demo stays live and touchable under the knobs.
  final GalleryOptionsBuilder? options;

  /// Rebuilds the open options sheet when it notifies.
  ///
  /// The sheet also rebuilds after every rebuild of this page, one frame
  /// late; a knob dragged continuously (a slider) keeps its value in a
  /// listenable passed here to follow the finger without that frame.
  final Listenable? optionsListenable;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

/// Builds the rows of a page's options sheet.
typedef GalleryOptionsBuilder = List<Widget> Function(BuildContext context);

/// Opens the options sheet of a gallery page: a glass sheet with medium
/// and large detents and a grabber whose content scrolls the [options]
/// rows, and that leaves the page undimmed and touchable at medium.
///
/// The sheet rebuilds its rows whenever [listenable] notifies.
Future<void> showGalleryOptions(
  BuildContext context, {
  required GalleryOptionsBuilder options,
  Listenable? listenable,
}) => showMorphSheet<void>(
  context,
  detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
  largestUndimmedDetent: .medium,
  grabberVisible: true,
  semanticLabel: 'Page options',
  builder: (BuildContext context) =>
      _GalleryOptionsSheet(options: options, listenable: listenable),
);

class _GalleryOptionsSheet extends StatelessWidget {
  const _GalleryOptionsSheet({required this.options, this.listenable});

  final GalleryOptionsBuilder options;
  final Listenable? listenable;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    Widget list(BuildContext context) => ListView(
      controller: MorphSheet.scrollControllerOf(context),
      padding: const .only(top: 24, bottom: 32),
      children: options(context),
    );
    if (listenable == null) return list(context);
    return ListenableBuilder(
      listenable: listenable,
      builder: (BuildContext context, Widget? _) => list(context),
    );
  }
}

/// Hands the open options sheet the page's latest rows: a page rebuilds
/// in its own route, so the sheet hears of it only through this.
class _GalleryOptionsHub extends ChangeNotifier {
  _GalleryOptionsHub(this.options);

  GalleryOptionsBuilder options;
  bool _disposed = false;

  List<Widget> build(BuildContext context) => options(context);

  void update(GalleryOptionsBuilder next) {
    options = next;
    if (!hasListeners) return;
    // The sheet lives in another route; marking it dirty while this page
    // builds is not allowed, so it follows after the frame.
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _GalleryPageState extends State<GalleryPage> {
  static const _factors = [1.0, 5.0, 10.0];

  _GalleryOptionsHub? _hub;

  int get _index {
    final i = _factors.indexOf(timeDilation);
    return i < 0 ? 0 : i;
  }

  void _cycle() {
    setState(() => timeDilation = _factors[(_index + 1) % _factors.length]);
  }

  @override
  void didUpdateWidget(GalleryPage old) {
    super.didUpdateWidget(old);
    final options = widget.options;
    if (options != null) _hub?.update(options);
  }

  @override
  void dispose() {
    _hub?.dispose();
    super.dispose();
  }

  void _openOptions(GalleryOptionsBuilder options) {
    final hub = _hub ??= _GalleryOptionsHub(options);
    hub.options = options;
    final listenable = widget.optionsListenable;
    showGalleryOptions(
      context,
      options: hub.build,
      listenable: listenable == null
          ? hub
          : Listenable.merge([hub, listenable]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final factor = _factors[_index];
    final options = widget.options;
    final optionsButton = options == null
        ? null
        : MorphBarButtonGroup([
            MorphBarButton(
              id: 'options',
              icon: const Icon(Icons.tune),
              semanticLabel: 'Page options',
              onPressed: () => _openOptions(options),
            ),
          ], id: 'options');
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
      style: factor != 1 ? .prominent : .plain,
    );
    return MorphNavigationScaffold(
      title: widget.title,
      largeTitleDisplayMode: widget.largeTitle ? .always : .never,
      subtitle: widget.subtitle,
      largeSubtitle: widget.largeSubtitle,
      leading: widget.leading,
      trailing: [...widget.trailing, ?optionsButton, slowMotion],
      toolbarLeading: widget.toolbarLeading,
      toolbarTrailing: widget.toolbarTrailing,
      edgeEffect: widget.edgeEffect,
      backgroundColor:
          widget.backgroundColor ??
          MorphListAppearance.resolve(context, null).backgroundColor,
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

/// A family of gallery entries: one titled section of the home.
///
/// A header never equals an entry title, so `find.text(title)` finds the
/// row alone.
enum GalleryFamily {
  /// Navigation bars, toolbars and the navigation stack.
  navigation('Bars and navigation'),

  /// Tab bars, their minimizing and the search fields.
  tabBars('Tab bars and search'),

  /// Buttons, value controls, pickers and indicators.
  controls('Buttons and inputs'),

  /// Pull-down and context menus.
  menus('Menus'),

  /// Sheets, alerts and action sheets.
  presentation('Presentation'),

  /// Lists.
  content('Content'),

  /// The glass renderer and its effects.
  glass('Glass'),

  /// The theme and the accessibility settings.
  theming('Theming and accessibility'),

  /// The morph engine under the widgets.
  engine('Engine');

  const GalleryFamily(this.header);

  /// The section header on the home.
  final String header;
}

/// One entry of the gallery.
class GalleryEntry {
  /// Creates an entry.
  const GalleryEntry(
    this.title,
    this.subtitle,
    this.builder, {
    required this.family,
  });

  /// The entry's name.
  final String title;

  /// What the entry shows.
  final String subtitle;

  /// Builds the entry's page.
  final WidgetBuilder builder;

  /// The home section the entry sits in.
  final GalleryFamily family;
}

/// The gallery's entries, in the order of the home: grouped by
/// [GalleryFamily], each family in its declared order.
final List<GalleryEntry> galleryEntries = [
  GalleryEntry(
    'Navigation',
    'Large title and subtitles, bar button badges, toolbar sets, edge effect',
    (_) => const NavigationDemoPage(),
    family: .navigation,
  ),
  GalleryEntry(
    'Navigation bar',
    'Subtitles, back button modes, badges, standalone bars and toolbars',
    (_) => const NavigationBarPage(),
    family: .navigation,
  ),
  GalleryEntry(
    'Navigator pages',
    'A navigation stack driven by a list of pages: slide and zoom',
    (_) => const NavigatorPagesPage(),
    family: .navigation,
  ),
  GalleryEntry(
    'Tab bar',
    'Floating bar with 2 to 5 tabs, press growth, scrub and badges',
    (_) => const TabBarPage(),
    family: .tabBars,
  ),
  GalleryEntry(
    'Tab bar minimize',
    'Minimizing on scroll, bottom accessory inline next to the circle',
    (_) => const MinimizeTabBarPage(),
    family: .tabBars,
  ),
  GalleryEntry(
    'Search',
    'Bottom search field, tab bar search tab, inline field',
    (_) => const SearchPage(),
    family: .tabBars,
  ),
  GalleryEntry(
    'Segmented control',
    'The selection lens: travel, lift, stretch, drag',
    (_) => const SegmentedPage(),
    family: .controls,
  ),
  GalleryEntry(
    'Controls',
    'Switch, slider, glass button and stepper',
    (_) => const ControlsPage(),
    family: .controls,
  ),
  GalleryEntry(
    'Glass buttons',
    'Every glass button style, enabled and disabled, with a menu',
    (_) => const GlassButtonsPage(),
    family: .controls,
  ),
  GalleryEntry(
    'Date picker',
    'Compact date and time labels opening their calendar',
    (_) => const DatePickerPage(),
    family: .controls,
  ),
  GalleryEntry(
    'Indicators',
    'Progress view and activity indicator',
    (_) => const IndicatorPage(),
    family: .controls,
  ),
  GalleryEntry(
    'Menu',
    'A glass button morphing into its menu; long-press context menus',
    (_) => const MenuPage(),
    family: .menus,
  ),
  GalleryEntry(
    'Context menu',
    'Hold a list row or a photo: it lifts and opens its actions',
    (_) => const ContextMenuPage(),
    family: .menus,
  ),
  GalleryEntry(
    'Menu source',
    'Any widget as its own menu: tap or hold, dividers, deferred rows',
    (_) => const MenuSourcePage(),
    family: .menus,
  ),
  GalleryEntry(
    'Sheets',
    'Floating glass detents, docking at large, drag and scroll hand-off',
    (_) => const SheetPage(),
    family: .presentation,
  ),
  GalleryEntry(
    'Alerts',
    'Alerts and action sheets growing out of their source',
    (_) => const AlertPage(),
    family: .presentation,
  ),
  GalleryEntry(
    'Lists',
    'Inset grouped sections with glass buttons in their rows',
    (_) => const ListPage(),
    family: .content,
  ),
  GalleryEntry(
    'Glass renderer',
    'Liquid glass for the whole gallery: material, optics, dark, RTL',
    (_) => const GlassPage(),
    family: .glass,
  ),
  GalleryEntry(
    'Glass effects',
    'Glass shapes, styles and tints, with and without a container',
    (_) => const GlassEffectsPage(),
    family: .glass,
  ),
  GalleryEntry(
    'Size to physics',
    'How UIKit derives deformation and lift from a surface size',
    (_) => const SpecInspectorPage(),
    family: .glass,
  ),
  GalleryEntry(
    'Theming',
    'Accent, per-control looks, high contrast and reduced motion',
    (_) => const ThemingPage(),
    family: .theming,
  ),
  GalleryEntry(
    'Morph engine',
    'A widget becoming a dialog, a page or a sheet; shared elements, skins',
    (_) => const EnginePage(),
    family: .engine,
  ),
];

/// The gallery's home: one grouped section of entries per
/// [GalleryFamily] under a large title; each row pushes its page onto the
/// gallery's navigation stack.
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
          child: Column(
            children: [
              for (final family in GalleryFamily.values)
                if (galleryEntries.any((e) => e.family == family))
                  MorphListSection(
                    header: Text(family.header),
                    children: [
                      for (final entry in galleryEntries)
                        if (entry.family == family)
                          MorphListRow(
                            title: Text(entry.title),
                            subtitle: Text(entry.subtitle),
                            accessory: .disclosureIndicator,
                            onTap: () => Navigator.of(context).push(
                              MorphNavigationRoute<void>(
                                builder: entry.builder,
                              ),
                            ),
                          ),
                    ],
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
