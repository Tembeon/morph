import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

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

  static const _tiers = ['Auto', 'Liquid', 'Frosted', 'Flat'];
  static const _materials = ['Regular', 'Toolbar', 'Clear'];

  /// The iOS Settings > Display & Brightness > Liquid Glass choice; the
  /// knob below sets any position between the two.
  static const _liquidGlass = ['Clear', 'Tinted'];
  static const _appearances = ['System', 'Light', 'Dark'];

  Widget _scene(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    return Padding(
      padding: const .fromLTRB(20, 24, 20, 28),
      child: Column(
        children: [
          MorphSegmentedControl(
            segments: const ['Photos', 'Albums', 'Search'],
            selected: _segment,
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
          Row(
            mainAxisAlignment: .center,
            children: [
              MorphGlassButton(
                onPressed: on(() {}),
                child: const Text('Glass'),
              ),
              const SizedBox(width: 16),
              MorphGlassButton(
                onPressed: on(() {}),
                child: const Icon(Icons.favorite_border),
              ),
            ],
          ),
          const SizedBox(height: 36),
          MorphTabBar(
            items: const [
              MorphTabItem(icon: Icons.photo_outlined, label: 'Library'),
              MorphTabItem(icon: Icons.favorite_border, label: 'For You'),
              MorphTabItem(icon: Icons.search, label: 'Search'),
            ],
            selected: _tab,
            onChanged: on((int i) => setState(() => _tab = i)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = GalleryGlassScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final drawn = MorphAdaptiveGlass.tierOf(context);
    final liquid = drawn == MorphGlassTier.liquid;
    return Scaffold(
      appBar: const GalleryBar(title: 'Glass renderer'),
      body: ListView(
        padding: const .only(bottom: 40),
        children: [
          BackdropGroup(
            child: Stack(
              children: [
                Positioned.fill(child: _Backdrop(dark: dark)),
                DefaultTextStyle.merge(
                  style: TextStyle(color: dark ? Colors.white : Colors.black),
                  child: _scene(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const .fromLTRB(16, 20, 16, 0),
            child: _Card(
              children: [
                _Choice(
                  label: 'Tier',
                  segments: _tiers,
                  selected: switch (settings.tier) {
                    null => 0,
                    MorphGlassTier.liquid => 1,
                    MorphGlassTier.frosted => 2,
                    MorphGlassTier.flat => 3,
                  },
                  onChanged: (int i) => settings.tier = switch (i) {
                    1 => MorphGlassTier.liquid,
                    2 => MorphGlassTier.frosted,
                    3 => MorphGlassTier.flat,
                    _ => null,
                  },
                ),
                Padding(
                  padding: const .symmetric(vertical: 4),
                  child: Text(
                    'Drawing: ${drawn?.name ?? 'none'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                _Choice(
                  label: 'Material',
                  segments: _materials,
                  selected: settings.material.index,
                  onChanged: liquid
                      ? (int i) =>
                            settings.material = MorphGlassMaterial.values[i]
                      : null,
                ),
                _Knob(
                  label: 'Blur',
                  value: settings.blur,
                  max: 3,
                  onChanged: liquid ? (double v) => settings.blur = v : null,
                ),
                _Knob(
                  label: 'Refraction',
                  value: settings.refraction,
                  max: 2,
                  onChanged: liquid
                      ? (double v) => settings.refraction = v
                      : null,
                ),
                _Knob(
                  label: 'Rim light',
                  value: settings.light,
                  max: 2,
                  onChanged: liquid ? (double v) => settings.light = v : null,
                ),
                _Choice(
                  label: 'Liquid Glass',
                  segments: _liquidGlass,
                  selected: settings.tint < 0.5 ? 0 : 1,
                  onChanged: liquid
                      ? (int i) => settings.tint = i.toDouble()
                      : null,
                ),
                _Knob(
                  label: 'Clear to tinted',
                  value: settings.tint,
                  max: 1,
                  onChanged: liquid ? (double v) => settings.tint = v : null,
                ),
                _Toggle(
                  label: 'Frost controls',
                  value: settings.frostControls,
                  onChanged: liquid
                      ? (bool v) => settings.frostControls = v
                      : null,
                ),
                _Choice(
                  label: 'Appearance',
                  segments: _appearances,
                  selected: settings.appearance.index,
                  onChanged: (int i) =>
                      settings.appearance = ThemeMode.values[i],
                ),
                _Toggle(
                  label: 'Right to left',
                  value: settings.rtl,
                  onChanged: (bool v) => settings.rtl = v,
                ),
                _Toggle(
                  label: 'Disabled',
                  value: settings.disabled,
                  onChanged: (bool v) => settings.disabled = v,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: galleryCardColor(context),
      borderRadius: .circular(26),
      child: BackdropGroup(
        child: Padding(
          padding: const .symmetric(horizontal: 16, vertical: 8),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<String> segments;
  final int selected;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label)),
          Expanded(
            child: MorphSegmentedControl(
              segments: segments,
              selected: selected,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return Padding(
      padding: const .symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label)),
          Expanded(
            child: MorphSlider(
              value: value / max,
              semanticLabel: label,
              onChanged: onChanged == null
                  ? null
                  : (double v) => onChanged(v * max),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: .end,
              style: const TextStyle(
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          MorphSwitch(value: value, semanticLabel: label, onChanged: onChanged),
        ],
      ),
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
