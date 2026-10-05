import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// The small UIKit controls: switch, slider, glass button and stepper.
class ControlsPage extends StatefulWidget {
  /// Creates the page.
  const ControlsPage({super.key});

  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  bool _off = false;
  bool _on = true;
  double _wide = 0.3;
  double _narrow = 0.6;
  double _stepped = 0.5;
  double _stepper = 5;
  int _taps = 0;

  static const _buttons = <(String, Size, bool)>[
    ('44 x 44', Size(44, 44), true),
    ('60 x 44', Size(60, 44), true),
    ('120 x 44', Size(120, 44), false),
    ('200 x 44', Size(200, 44), false),
    ('200 x 100', Size(200, 100), false),
  ];

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Controls',
      slivers: [
        SliverPadding(
          padding: const .all(20),
          sliver: SliverList.list(
            children: [
              const GalleryCaption('Switch'),
              Row(
                children: [
                  MorphSwitch(
                    value: _off,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _off = v),
                    ),
                  ),
                  const SizedBox(width: 24),
                  MorphSwitch(
                    value: _on,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _on = v),
                    ),
                  ),
                ],
              ),
              GalleryCaption('Slider, 300 wide: ${_wide.toStringAsFixed(2)}'),
              Align(
                alignment: .centerLeft,
                child: SizedBox(
                  width: 300,
                  child: MorphSlider(
                    value: _wide,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _wide = v),
                    ),
                  ),
                ),
              ),
              GalleryCaption('Slider, 200 wide: ${_narrow.toStringAsFixed(2)}'),
              Align(
                alignment: .centerLeft,
                child: SizedBox(
                  width: 200,
                  child: MorphSlider(
                    value: _narrow,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _narrow = v),
                    ),
                  ),
                ),
              ),
              GalleryCaption('Slider, 5 ticks: ${_stepped.toStringAsFixed(2)}'),
              Align(
                alignment: .centerLeft,
                child: SizedBox(
                  width: 300,
                  child: MorphSlider(
                    value: _stepped,
                    ticks: 5,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _stepped = v),
                    ),
                  ),
                ),
              ),
              GalleryCaption('Glass buttons, tapped $_taps times'),
              MorphGlassContainer(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  crossAxisAlignment: .center,
                  children: [
                    for (final (label, size, icon) in _buttons)
                      SizedBox.fromSize(
                        size: size,
                        child: MorphGlassButton(
                          padding: .zero,
                          onPressed: GalleryGlassScope.enabled(
                            context,
                            () => setState(() => _taps++),
                          ),
                          child: icon
                              ? const Icon(Icons.favorite_border)
                              : Text(label),
                        ),
                      ),
                    SizedBox(
                      width: 120,
                      height: 44,
                      child: MorphGlassButton(
                        padding: .zero,
                        tint: const Color(0xFF007AFF),
                        onPressed: GalleryGlassScope.enabled(
                          context,
                          () => setState(() => _taps++),
                        ),
                        child: const Text('Prominent'),
                      ),
                    ),
                  ],
                ),
              ),
              GalleryCaption('Stepper: ${_stepper.toInt()}'),
              Align(
                alignment: .centerLeft,
                child: MorphStepper(
                  value: _stepper,
                  max: 10,
                  onChanged: GalleryGlassScope.enabled(
                    context,
                    (v) => setState(() => _stepper = v),
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
