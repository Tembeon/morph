import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/control_pages.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// One constructor of [MorphGlassButton], with or without a tint.
enum _Style {
  regular('Regular'),
  prominent('Prominent'),
  prominentTint('Prominent, tint'),
  clear('Clear'),
  prominentClear('Prominent clear'),
  prominentClearTint('Prominent clear, tint');

  const _Style(this.label);

  final String label;

  bool get clearGlass => switch (this) {
    .clear || .prominentClear || .prominentClearTint => true,
    .regular || .prominent || .prominentTint => false,
  };
}

/// The space around a button's label, picked on the options sheet.
enum _Padding {
  standard('Default', EdgeInsets.symmetric(horizontal: 20, vertical: 11)),
  zero('Zero', EdgeInsets.zero),
  wide('Wide', EdgeInsets.symmetric(horizontal: 32, vertical: 16));

  const _Padding(this.label, this.insets);

  final String label;
  final EdgeInsets insets;
}

/// Every glass button constructor, enabled and disabled, with a menu, a
/// minimum size and an appearance.
///
/// Each style shows enabled next to disabled: the regular glass
/// (`UIButton.Configuration.glass()`), the prominent glass filled with the
/// accent or a tint, and both on clear glass over a picture-like
/// gradient. A button with a menu opens it on a tap; one with an action
/// and a menu acts on a tap and opens the menu on a hold. The last section
/// sets a prominent button's fill through the theme's accent and through
/// its appearance's [MorphGlassButtonAppearance.prominentColor]. The page
/// options pick the tint, the fill, the padding, the minimum size and an
/// appearance table.
class GlassButtonsPage extends StatefulWidget {
  /// Creates the page.
  const GlassButtonsPage({super.key});

  @override
  State<GlassButtonsPage> createState() => _GlassButtonsPageState();
}

class _GlassButtonsPageState extends State<GlassButtonsPage> {
  int _taps = 0;
  String _last = 'nothing yet';
  Color? _tint = const Color(0xFFFF9500);
  Color? _prominentColor = const Color(0xFFAF52DE);
  _Padding _padding = .standard;
  double _minSide = 44;
  GalleryLook _look = .theme;

  static const _tints = <(String, Color?)>[
    ('Orange', Color(0xFFFF9500)),
    ('Purple', Color(0xFFAF52DE)),
    ('Pink', Color(0xFFFF2D55)),
    ('Green', Color(0xFF34C759)),
    ('Teal', Color(0xFF30B0C7)),
  ];

  static final _minSides = <double, String>{44: '44', 60: '60', 80: '80'};

  static final _paddings = <_Padding, String>{
    for (final p in _Padding.values) p: p.label,
  };

  MorphGlassButtonAppearance? get _appearance => _look.pick(
    MorphGlassButtonAppearance.light,
    MorphGlassButtonAppearance.dark,
  );

  void _did(String what) => setState(() {
    _taps++;
    _last = what;
  });

  VoidCallback? _action(BuildContext context, String what, bool enabled) =>
      enabled ? GalleryGlassScope.enabled(context, () => _did(what)) : null;

  Widget _button(
    BuildContext context,
    _Style style, {
    required bool enabled,
    required Widget child,
    MorphGlassButtonAppearance? appearance,
  }) {
    final onPressed = _action(context, style.label, enabled);
    final padding = _padding.insets;
    final minSize = Size.square(_minSide);
    final look = appearance ?? _appearance;
    return switch (style) {
      .regular => MorphGlassButton(
        onPressed: onPressed,
        enabled: enabled,
        padding: padding,
        minSize: minSize,
        appearance: look,
        child: child,
      ),
      .prominent => MorphGlassButton.prominent(
        onPressed: onPressed,
        enabled: enabled,
        padding: padding,
        minSize: minSize,
        appearance: look,
        child: child,
      ),
      .prominentTint => MorphGlassButton.prominent(
        onPressed: onPressed,
        enabled: enabled,
        tint: _tint,
        padding: padding,
        minSize: minSize,
        appearance: look,
        child: child,
      ),
      .clear => MorphGlassButton.clear(
        onPressed: onPressed,
        enabled: enabled,
        padding: padding,
        minSize: minSize,
        appearance: look,
        child: child,
      ),
      .prominentClear => MorphGlassButton.prominentClear(
        onPressed: onPressed,
        enabled: enabled,
        padding: padding,
        minSize: minSize,
        appearance: look,
        child: child,
      ),
      .prominentClearTint => MorphGlassButton.prominentClear(
        onPressed: onPressed,
        enabled: enabled,
        tint: _tint,
        padding: padding,
        minSize: minSize,
        appearance: look,
        child: child,
      ),
    };
  }

  Widget _styleRow(BuildContext context, _Style style, Color labelColor) =>
      Padding(
        padding: const .only(bottom: 16),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Padding(
              padding: const .only(left: 4, bottom: 8),
              child: Text(style.label, style: TextStyle(color: labelColor)),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: .center,
              children: [
                _button(
                  context,
                  style,
                  enabled: true,
                  child: const Text('Enabled'),
                ),
                _button(
                  context,
                  style,
                  enabled: false,
                  child: const Text('Disabled'),
                ),
                _button(
                  context,
                  style,
                  enabled: true,
                  child: const Icon(Icons.favorite_border),
                ),
              ],
            ),
          ],
        ),
      );

  List<MorphMenuEntry> _menu(String source) => [
    MorphMenuItem(
      title: 'Copy',
      icon: const Icon(Icons.copy),
      onSelected: () => setState(() => _last = '$source: Copy'),
    ),
    MorphMenuItem(
      title: 'Share',
      icon: const Icon(Icons.ios_share),
      onSelected: () => setState(() => _last = '$source: Share'),
    ),
    MorphMenuItem(
      title: 'Delete',
      icon: const Icon(Icons.delete_outline),
      destructive: true,
      onSelected: () => setState(() => _last = '$source: Delete'),
    ),
  ];

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Fill'),
      footer: const Text(
        'The tint fills the tinted styles. The prominent color is set '
        'through the appearance of the last button, over the accent.',
      ),
      children: [
        GalleryColorChoice(
          label: 'Tint',
          value: _tint,
          colors: _tints,
          onChanged: (Color? c) => setState(() => _tint = c),
        ),
        GalleryColorChoice(
          label: 'Prominent color',
          value: _prominentColor,
          colors: _tints,
          onChanged: (Color? c) => setState(() => _prominentColor = c),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Size'),
      children: [
        GalleryChoice<_Padding>(
          label: 'Padding',
          options: _paddings,
          value: _padding,
          onChanged: (_Padding p) => setState(() => _padding = p),
        ),
        GalleryChoice<double>(
          label: 'Min size',
          options: _minSides,
          value: _minSide,
          onChanged: (double s) => setState(() => _minSide = s),
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
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final secondary = gallerySecondaryColor(context);
    final background = MorphListAppearance.resolve(
      context,
      null,
    ).backgroundColor;
    final demosEnabled = !GalleryGlassScope.of(context, .disabled).disabled;
    final prominentColor = _prominentColor;
    return GalleryPage(
      title: 'Glass buttons',
      options: _options,
      slivers: [
        SliverPadding(
          padding: const .all(20),
          sliver: SliverList.list(
            children: [
              GalleryCaption('Tapped $_taps times, last: $_last'),
              MorphGlassContainer(
                solidBackdrop: background,
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    for (final style in _Style.values)
                      if (!style.clearGlass)
                        _styleRow(context, style, secondary),
                  ],
                ),
              ),
              const GalleryCaption('Clear glass, over a picture'),
              DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: .all(.circular(20)),
                  gradient: LinearGradient(
                    begin: .topLeft,
                    end: .bottomRight,
                    colors: [
                      Color(0xFF1B3B6F),
                      Color(0xFF3E8E7E),
                      Color(0xFFF2A65A),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const .fromLTRB(16, 16, 16, 0),
                  child: MorphGlassContainer(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        for (final style in _Style.values)
                          if (style.clearGlass)
                            _styleRow(context, style, const Color(0xE6FFFFFF)),
                      ],
                    ),
                  ),
                ),
              ),
              const GalleryCaption('Menus: a tap opens one, or a hold does'),
              MorphGlassContainer(
                solidBackdrop: background,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    MorphGlassButton(
                      onPressed: null,
                      menu: _menu('Menu'),
                      enabled: demosEnabled,
                      padding: _padding.insets,
                      minSize: Size.square(_minSide),
                      appearance: _appearance,
                      child: const Text('Menu'),
                    ),
                    MorphGlassButton.prominent(
                      onPressed: GalleryGlassScope.enabled(
                        context,
                        () => _did('Tap or hold'),
                      ),
                      menu: _menu('Tap or hold'),
                      enabled: demosEnabled,
                      tint: _tint,
                      padding: _padding.insets,
                      minSize: Size.square(_minSide),
                      appearance: _appearance,
                      child: const Text('Tap or hold'),
                    ),
                  ],
                ),
              ),
              const GalleryCaption('Accent and prominent color'),
              MorphGlassContainer(
                solidBackdrop: background,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    _button(
                      context,
                      .prominent,
                      enabled: true,
                      child: const Text('Accent'),
                    ),
                    _button(
                      context,
                      .prominent,
                      enabled: true,
                      appearance: prominentColor == null
                          ? null
                          : MorphGlassButtonAppearance.resolve(
                              context,
                              _appearance,
                            ).copyWith(prominentColor: prominentColor),
                      child: const Text('Prominent color'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const .only(left: 4, top: 10),
                child: Text(
                  'Accent follows the theme: the accent of the Theming '
                  'settings, or systemBlue. Prominent color sets the '
                  "appearance's prominentColor, which wins over the accent.",
                  style: TextStyle(color: secondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
