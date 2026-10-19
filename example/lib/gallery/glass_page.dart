import 'package:flutter/foundation.dart';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Icons;
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';
// The renderer lab reads the built-in renderer's internal knobs.
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_tier.dart';

/// The gallery's glass settings and a sample of every control over a
/// colorful backdrop.
///
/// The settings belong to the whole gallery: the glass tier, its material
/// and optics, the appearance, the text direction and the disabled demo
/// controls apply to every page at once, and last for the session.
class GlassPage extends StatefulWidget {
  /// Creates the page.
  const GlassPage({super.key});

  @override
  State<GlassPage> createState() => _GlassPageState();
}

class _GlassPageState extends State<GlassPage> {
  int _segment = 0;
  int _tab = 0;
  bool _toggle = true;
  double _value = 0.4;
  double _count = 3;
  int _page = 1;

  static const _tiers = <MorphGlassTier?, String>{
    null: 'Auto',
    MorphGlassTier.liquid: 'Liquid',
    MorphGlassTier.flat: 'Flat',
  };
  static const _materials = {
    MorphGlassMaterial.regular: 'Regular',
    MorphGlassMaterial.toolbar: 'Toolbar',
    MorphGlassMaterial.clear: 'Clear',
  };

  /// The iOS Settings > Display & Brightness > Liquid Glass choice; the
  /// knob below sets any position between the two.
  static final _liquidGlass = {0.0: 'Clear', 1.0: 'Tinted'};
  static const _appearances = <Brightness?, String>{
    null: 'System',
    Brightness.light: 'Light',
    Brightness.dark: 'Dark',
  };
  static const _frameRates = {
    GalleryFrameRate.auto: 'Auto',
    GalleryFrameRate.hz60: '60 Hz',
    GalleryFrameRate.hz120: '120 Hz',
  };

  Widget _scene(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    final enabled = !GalleryGlassScope.of(context, .disabled).disabled;
    return Padding(
      padding: const .fromLTRB(20, 24, 20, 28),
      child: Column(
        children: [
          MorphSegmentedControl(
            segments: const [
              MorphSegment('Photos'),
              MorphSegment('Albums'),
              MorphSegment('Search'),
            ],
            selectedIndex: _segment,
            onChanged: on((int i) => setState(() => _segment = i)),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              MorphSwitch(
                value: _toggle,
                semanticLabel: 'Sample switch',
                onChanged: on((bool v) => setState(() => _toggle = v)),
              ),
              const Spacer(),
              MorphStepper(
                value: _count,
                max: 9,
                onChanged: on((double v) => setState(() => _count = v)),
              ),
            ],
          ),
          const SizedBox(height: 28),
          MorphSlider(
            value: _value,
            semanticLabel: 'Sample slider',
            onChanged: on((double v) => setState(() => _value = v)),
          ),
          const SizedBox(height: 28),
          MorphGlassContainer(
            child: Wrap(
              alignment: .center,
              spacing: 16,
              runSpacing: 12,
              children: [
                MorphGlassButton(
                  onPressed: on(() {}),
                  child: const Text('Glass'),
                ),
                MorphGlassButton.prominent(
                  onPressed: on(() {}),
                  tint: const Color(0xFF0088FF),
                  child: const Text('Prominent'),
                ),
                MorphGlassButton(
                  onPressed: on(() {}),
                  child: const Icon(Icons.favorite_border),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: .center,
            children: [
              MorphMenuButton(
                enabled: enabled,
                menu: const [
                  MorphMenuItem(title: 'Copy', icon: Icon(Icons.copy)),
                  MorphMenuItem(title: 'Share', icon: Icon(Icons.ios_share)),
                ],
              ),
              const SizedBox(width: 24),
              MorphPageControl(
                count: 5,
                page: _page,
                onChanged: on((int i) => setState(() => _page = i)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          MorphSearchField(enabled: enabled),
          const SizedBox(height: 36),
          MorphTabBar(
            items: const [
              MorphTabItem(icon: Icons.photo_outlined, label: 'Library'),
              MorphTabItem(
                icon: Icons.favorite_border,
                selectedIcon: Icons.favorite,
                label: 'For You',
                badge: MorphBadge.count(3),
              ),
              MorphTabItem(icon: Icons.search, label: 'Search'),
            ],
            selected: _tab,
            onChanged: on((int i) => setState(() => _tab = i)),
          ),
          const SizedBox(height: 28),
          Wrap(
            alignment: .center,
            spacing: 16,
            runSpacing: 12,
            children: [
              MorphGlassButton.clear(
                onPressed: on(() {}),
                child: const Text('Clear'),
              ),
              MorphGlassButton.prominentClear(
                onPressed: on(() {}),
                child: const Text('Prominent clear'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Wrap(
            alignment: .center,
            spacing: 12,
            runSpacing: 12,
            children: [
              MorphGlassEffect(
                interactive: true,
                child: Padding(
                  padding: .symmetric(horizontal: 18, vertical: 12),
                  child: Text('Regular'),
                ),
              ),
              MorphGlassEffect(
                style: .clear,
                interactive: true,
                child: Padding(
                  padding: .symmetric(horizontal: 18, vertical: 12),
                  child: Text('Clear'),
                ),
              ),
              MorphGlassEffect(
                shape: RoundedRectangleBorder(
                  borderRadius: .all(.circular(14)),
                ),
                tint: Color(0xFFFF9500),
                child: Padding(
                  padding: .symmetric(horizontal: 18, vertical: 12),
                  child: Text('Tinted'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = GalleryGlassScope.of(context);
    final brightness = galleryBrightnessOf(context);
    final drawn = GlassAdaptiveScope.tierOf(context);
    final liquid = drawn == MorphGlassTier.liquid;
    return GalleryPage(
      title: 'Glass renderer',
      slivers: [
        SliverToBoxAdapter(
          child: BackdropGroup(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _Backdrop(dark: brightness == Brightness.dark),
                ),
                DefaultTextStyle.merge(
                  style: TextStyle(color: galleryLabelColor(brightness)),
                  child: _scene(context),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: BackdropGroup(
            child: MorphListSection(
              header: const Text('Renderer'),
              children: [
                GalleryChoice<MorphGlassTier?>(
                  label: 'Tier',
                  options: _tiers,
                  value: settings.tier,
                  onChanged: (MorphGlassTier? tier) => settings.tier = tier,
                ),
                MorphListRow(
                  title: const Text('Drawing'),
                  detail: Text(drawn?.name ?? 'none'),
                ),
                GalleryChoice<MorphGlassMaterial>(
                  label: 'Material',
                  options: _materials,
                  value: settings.material,
                  onChanged: liquid
                      ? (MorphGlassMaterial m) => settings.material = m
                      : null,
                ),
                GallerySliderKnob(
                  label: 'Blur',
                  value: settings.blur,
                  max: 3,
                  onChanged: liquid ? (double v) => settings.blur = v : null,
                ),
                GallerySliderKnob(
                  label: 'Refraction',
                  value: settings.refraction,
                  max: 2,
                  onChanged: liquid
                      ? (double v) => settings.refraction = v
                      : null,
                ),
                GallerySliderKnob(
                  label: 'Rim light',
                  value: settings.light,
                  max: 2,
                  onChanged: liquid ? (double v) => settings.light = v : null,
                ),
                GalleryChoice<double>(
                  label: 'Liquid Glass',
                  options: _liquidGlass,
                  value: settings.tint < 0.5 ? 0 : 1,
                  onChanged: liquid ? (double v) => settings.tint = v : null,
                ),
                GallerySliderKnob(
                  label: 'Clear to tinted',
                  value: settings.tint,
                  max: 1,
                  onChanged: liquid ? (double v) => settings.tint = v : null,
                ),
                GalleryToggle(
                  label: 'Frost controls',
                  value: settings.frostControls,
                  onChanged: liquid
                      ? (bool v) => settings.frostControls = v
                      : null,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: BackdropGroup(
            child: MorphListSection(
              header: const Text('Gallery'),
              footer: const Text(
                'These settings apply to every page of the gallery. The '
                'glass inspector counts the glass layers of each frame '
                'and names neighbouring resting glass that one '
                'MorphGlassContainer could shade together. Frame rate asks '
                'an Android display for that rate. Reduce motion and '
                'increase contrast add to the system settings; accent '
                'and haptics set the theme of every control.',
              ),
              children: [
                GalleryChoice<Brightness?>(
                  label: 'Appearance',
                  options: _appearances,
                  value: settings.appearance,
                  onChanged: (Brightness? appearance) =>
                      settings.appearance = appearance,
                ),
                GalleryToggle(
                  label: 'Right to left',
                  value: settings.rtl,
                  onChanged: (bool v) => settings.rtl = v,
                ),
                GalleryToggle(
                  label: 'Disabled',
                  value: settings.disabled,
                  onChanged: (bool v) => settings.disabled = v,
                ),
                GalleryChoice<GalleryFrameRate>(
                  label: 'Frame rate',
                  options: _frameRates,
                  value: settings.frameRate,
                  onChanged: (GalleryFrameRate rate) =>
                      settings.frameRate = rate,
                ),
                if (!kReleaseMode)
                  GalleryToggle(
                    label: 'Glass inspector',
                    value: settings.inspector,
                    onChanged: (bool v) => settings.inspector = v,
                  ),
                GalleryToggle(
                  label: 'Reduce motion',
                  value: settings.reduceMotion,
                  onChanged: (bool v) => settings.reduceMotion = v,
                ),
                GalleryToggle(
                  label: 'Increase contrast',
                  value: settings.highContrast,
                  onChanged: (bool v) => settings.highContrast = v,
                ),
                GalleryToggle(
                  label: 'Haptics',
                  value: settings.haptics,
                  onChanged: (bool v) => settings.haptics = v,
                ),
                GalleryColorChoice(
                  label: 'Accent',
                  value: settings.accent,
                  onChanged: (Color? c) => settings.accent = c,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    const blobs = <(Alignment, double, Color)>[
      (Alignment(-0.9, -0.8), 180, Color(0xFFFF2D55)),
      (Alignment(0.8, -0.4), 220, Color(0xFFFFCC00)),
      (Alignment(-0.5, 0.3), 200, Color(0xFF34C759)),
      (Alignment(0.7, 0.8), 240, Color(0xFF5856D6)),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: .topLeft,
          end: .bottomRight,
          colors: dark
              ? const [Color(0xFF0B1E3D), Color(0xFF2B0B3D)]
              : const [Color(0xFF8EC5FC), Color(0xFFE0C3FC)],
        ),
      ),
      child: Stack(
        children: [
          for (final (alignment, size, color) in blobs)
            Align(
              alignment: alignment,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: .circle,
                  color: color.withValues(alpha: dark ? 0.55 : 0.8),
                ),
              ),
            ),
          const Align(
            alignment: Alignment(0, -0.1),
            child: Text(
              'morph',
              style: TextStyle(
                fontSize: 96,
                fontWeight: .w900,
                color: Color(0x66FFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
