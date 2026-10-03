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
/// painter the [GalleryGlassSettings] select.
class GalleryApp extends StatefulWidget {
  /// Creates the app.
  const GalleryApp({this.navigatorKey, super.key});

  /// The key of the app's navigator, for a driver that walks the pages.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  final _settings = GalleryGlassSettings();

  static ThemeData _theme(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF007AFF),
      brightness: brightness,
    ),
    scaffoldBackgroundColor: galleryBackgroundColor(brightness),
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );

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
        final painter = _settings.painter;
        return MaterialApp(
          navigatorKey: widget.navigatorKey,
          title: 'Morph widgets',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: _settings.appearance,
          builder: (BuildContext context, Widget? child) {
            Widget app = MorphScope(child: child!);
            if (painter != null) {
              app = MorphGlass(
                painter: painter,
                child: BackdropGroup(child: app),
              );
            }
            return GalleryGlassScope(
              settings: _settings,
              child: Directionality(
                textDirection: _settings.rtl ? .rtl : .ltr,
                child: app,
              ),
            );
          },
          home: const GalleryHome(),
        );
      },
    );
  }
}

/// The grouped background of a gallery page: iOS systemGroupedBackground.
Color galleryBackgroundColor(Brightness brightness) => switch (brightness) {
  Brightness.light => const Color(0xFFF2F2F7),
  Brightness.dark => const Color(0xFF000000),
};

/// The fill of a grouped card on a gallery page: iOS
/// secondarySystemGroupedBackground.
Color galleryCardColor(BuildContext context) =>
    switch (Theme.of(context).brightness) {
      Brightness.light => const Color(0xFFFFFFFF),
      Brightness.dark => const Color(0xFF1C1C1E),
    };

/// The navigation bar of every gallery page: the title, the page's own
/// [actions] and the [SlowMotionToggle] at the trailing edge, inset like
/// a UIKit navigation bar's buttons.
class GalleryBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the bar.
  const GalleryBar({required this.title, this.actions = const [], super.key});

  /// The page's title.
  final String title;

  /// The page's own bar buttons, before the slow-motion toggle.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      backgroundColor: Colors.transparent,
      actions: [
        const SlowMotionToggle(),
        for (final action in actions) ...[const SizedBox(width: 8), action],
        const SizedBox(width: 16),
      ],
    );
  }
}

/// A magnifier for the eye: cycles the app's time dilation through 1x,
/// 5x and 10x. The measured motion runs on ticker time, its per-frame
/// deformation filters step on a fixed 60 or 120 Hz sub-clock in that same
/// time, and touches are stamped on it too, so the widgets slow down as a
/// whole and trace the same curves as at full speed; only the finger keeps
/// real time, so a drag reads faster relative to the motion.
class SlowMotionToggle extends StatefulWidget {
  /// Creates the toggle.
  const SlowMotionToggle({super.key});

  @override
  State<SlowMotionToggle> createState() => _SlowMotionToggleState();
}

class _SlowMotionToggleState extends State<SlowMotionToggle> {
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final idle = factor == 1;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: _cycle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: idle
                ? (dark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF))
                : const Color(0xFFFF9500),
            borderRadius: .circular(16),
          ),
          child: Padding(
            padding: const .symmetric(horizontal: 12, vertical: 7),
            child: DefaultTextStyle(
              style: TextStyle(
                fontSize: 13,
                fontWeight: .w600,
                color: idle
                    ? (dark ? const Color(0xFFEBEBF5) : const Color(0xFF3C3C43))
                    : Colors.white,
              ),
              child: Text(idle ? 'Slow-mo off' : 'Slow-mo ${factor.round()}x'),
            ),
          ),
        ),
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
];

/// The gallery's home: a grouped list of entries.
class GalleryHome extends StatelessWidget {
  /// Creates the home page.
  const GalleryHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GalleryBar(title: 'Widgets'),
      body: ListView(
        padding: const .all(16),
        children: [
          Material(
            color: galleryCardColor(context),
            borderRadius: .circular(26),
            clipBehavior: .antiAlias,
            child: Column(
              children: [
                for (final entry in galleryEntries)
                  ListTile(
                    title: Text(entry.title),
                    subtitle: Text(entry.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: entry.builder)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
