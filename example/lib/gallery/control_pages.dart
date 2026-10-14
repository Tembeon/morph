import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// The appearance table a demo control is pinned to, or none to let the
/// control resolve it from the theme.
enum GalleryLook {
  /// No explicit appearance: the theme, brightness and contrast pick it.
  theme('Theme'),

  /// The control's light table.
  light('Light'),

  /// The control's dark table.
  dark('Dark');

  const GalleryLook(this.label);

  /// The segment label of the look.
  final String label;

  /// The looks with their labels, for a [GalleryChoice].
  static final Map<GalleryLook, String> options = {
    for (final look in values) look: look.label,
  };

  /// The table this look names among [onLight] and [onDark], or their
  /// high-contrast variants when [highContrast] is set and they exist;
  /// null for [theme].
  T? pick<T extends Object>(
    T onLight,
    T onDark, {
    T? onLightHighContrast,
    T? onDarkHighContrast,
    bool highContrast = false,
  }) => switch (this) {
    .theme => null,
    .light => highContrast ? onLightHighContrast ?? onLight : onLight,
    .dark => highContrast ? onDarkHighContrast ?? onDark : onDark,
  };
}

/// The small UIKit controls: switch, slider, glass button and stepper.
///
/// The page options pin each control to an appearance table, recolor its
/// tracks, change the slider's range, ticks and animation, and the
/// stepper's range, step and screen-reader texts.
class ControlsPage extends StatefulWidget {
  /// Creates the page.
  const ControlsPage({super.key});

  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  final _random = math.Random();

  bool _off = false;
  bool _on = true;
  double _wide = 0.3;
  double _narrow = 0.6;
  double _stepped = 0.5;
  double _stepper = 5;
  int _taps = 0;

  Color? _switchOnColor;
  Color? _switchOffColor;
  GalleryLook _switchLook = .theme;
  bool _switchHighContrast = false;

  (double, double) _sliderRange = (0, 1);
  bool _sliderAnimated = false;
  double? _dragStart;
  double? _dragEnd;
  int _ticks = 5;
  Color? _sliderActiveColor;
  Color? _sliderInactiveColor;
  GalleryLook _sliderLook = .theme;
  bool _sliderHighContrast = false;

  (double, double, double) _stepperRange = (0, 10, 1);
  bool _stepperSemantics = false;
  Color? _stepperBackground;
  Color? _stepperForeground;
  GalleryLook _stepperLook = .theme;

  static const _buttons = <(String, Size, bool)>[
    ('44 x 44', Size(44, 44), true),
    ('60 x 44', Size(60, 44), true),
    ('120 x 44', Size(120, 44), false),
    ('200 x 44', Size(200, 44), false),
    ('200 x 100', Size(200, 100), false),
  ];

  static final _sliderRanges = <(double, double), String>{
    (0, 1): '0 to 1',
    (0, 100): '0 to 100',
    (-1, 1): '-1 to 1',
  };

  static const _tickCounts = <int, String>{0: 'None', 3: '3', 5: '5', 11: '11'};

  static final _stepperRanges = <(double, double, double), String>{
    (0, 10, 1): '0-10 by 1',
    (0, 1, 0.1): '0-1 by 0.1',
    (-5, 5, 0.5): '-5-5 by 0.5',
  };

  /// The light tints offered for the tracks a control draws when off or
  /// unfilled.
  static const _trackColors = <(String, Color?)>[
    ('Default', null),
    ('Pale purple', Color(0x4DAF52DE)),
    ('Pale orange', Color(0x4DFF9500)),
    ('Pale teal', Color(0x4D30B0C7)),
  ];

  MorphSwitchAppearance? get _switchAppearance => _switchLook.pick(
    MorphSwitchAppearance.light,
    MorphSwitchAppearance.dark,
    onLightHighContrast: MorphSwitchAppearance.lightHighContrast,
    onDarkHighContrast: MorphSwitchAppearance.darkHighContrast,
    highContrast: _switchHighContrast,
  );

  MorphSliderAppearance? get _sliderAppearance => _sliderLook.pick(
    MorphSliderAppearance.light,
    MorphSliderAppearance.dark,
    onLightHighContrast: MorphSliderAppearance.lightHighContrast,
    onDarkHighContrast: MorphSliderAppearance.darkHighContrast,
    highContrast: _sliderHighContrast,
  );

  MorphStepperAppearance? get _stepperAppearance => _stepperLook.pick(
    MorphStepperAppearance.light,
    MorphStepperAppearance.dark,
  );

  void _setSliderRange((double, double) next) {
    final (min, max) = _sliderRange;
    final (nextMin, nextMax) = next;
    setState(() {
      _wide = nextMin + (_wide - min) / (max - min) * (nextMax - nextMin);
      _sliderRange = next;
      _dragStart = null;
      _dragEnd = null;
    });
  }

  void _jump() {
    final (min, max) = _sliderRange;
    setState(() => _wide = min + _random.nextDouble() * (max - min));
  }

  void _setStepperRange((double, double, double) next) {
    final (min, max, _) = next;
    setState(() {
      _stepperRange = next;
      _stepper = _stepper.clamp(min, max);
    });
  }

  String _stepperText(double v) {
    final (_, _, step) = _stepperRange;
    return step == step.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  }

  String get _wideCaption {
    final start = _dragStart;
    final end = _dragEnd;
    final drag = start == null
        ? ''
        : ', last drag ${start.toStringAsFixed(2)} to '
              '${end == null ? '...' : end.toStringAsFixed(2)}';
    return 'Slider, 300 wide: ${_wide.toStringAsFixed(2)}$drag';
  }

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Switch'),
      children: [
        GalleryColorChoice(
          label: 'On track',
          value: _switchOnColor,
          onChanged: (Color? c) => setState(() => _switchOnColor = c),
        ),
        GalleryColorChoice(
          label: 'Off track',
          value: _switchOffColor,
          colors: _trackColors,
          onChanged: (Color? c) => setState(() => _switchOffColor = c),
        ),
        GalleryChoice<GalleryLook>(
          label: 'Look',
          options: GalleryLook.options,
          value: _switchLook,
          onChanged: (GalleryLook l) => setState(() => _switchLook = l),
        ),
        GalleryToggle(
          label: 'Switch high-contrast table',
          value: _switchHighContrast,
          onChanged: _switchLook == .theme
              ? null
              : (bool v) => setState(() => _switchHighContrast = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Slider, 300 wide'),
      footer: const Text(
        'Animated moves the thumb on a spring when the value is set from '
        'outside, as setValue(_:animated: true) does.',
      ),
      children: [
        GalleryChoice<(double, double)>(
          label: 'Range',
          options: _sliderRanges,
          value: _sliderRange,
          onChanged: _setSliderRange,
        ),
        GalleryToggle(
          label: 'Animated',
          value: _sliderAnimated,
          onChanged: (bool v) => setState(() => _sliderAnimated = v),
        ),
        MorphListRow(
          title: const Text('Jump to a random value'),
          onTap: GalleryGlassScope.enabled(context, _jump),
        ),
        MorphListRow(
          title: const Text('Last drag'),
          detail: Text(
            _dragStart == null
                ? 'none'
                : '${_dragStart!.toStringAsFixed(2)} to '
                      '${_dragEnd?.toStringAsFixed(2) ?? '...'}',
          ),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Every slider'),
      children: [
        GalleryChoice<int>(
          label: 'Ticks',
          options: _tickCounts,
          value: _ticks,
          onChanged: (int t) => setState(() => _ticks = t),
        ),
        GalleryColorChoice(
          label: 'Fill',
          value: _sliderActiveColor,
          onChanged: (Color? c) => setState(() => _sliderActiveColor = c),
        ),
        GalleryColorChoice(
          label: 'Track',
          value: _sliderInactiveColor,
          colors: _trackColors,
          onChanged: (Color? c) => setState(() => _sliderInactiveColor = c),
        ),
        GalleryChoice<GalleryLook>(
          label: 'Look',
          options: GalleryLook.options,
          value: _sliderLook,
          onChanged: (GalleryLook l) => setState(() => _sliderLook = l),
        ),
        GalleryToggle(
          label: 'Slider high-contrast table',
          value: _sliderHighContrast,
          onChanged: _sliderLook == .theme
              ? null
              : (bool v) => setState(() => _sliderHighContrast = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Stepper'),
      footer: const Text(
        'Spoken texts name the halves "Fewer cups" and "More cups" and '
        'announce the value as "n cups".',
      ),
      children: [
        GalleryChoice<(double, double, double)>(
          label: 'Range',
          options: _stepperRanges,
          value: _stepperRange,
          onChanged: _setStepperRange,
        ),
        GalleryToggle(
          label: 'Spoken texts',
          value: _stepperSemantics,
          onChanged: (bool v) => setState(() => _stepperSemantics = v),
        ),
        GalleryColorChoice(
          label: 'Fill',
          value: _stepperBackground,
          colors: _trackColors,
          onChanged: (Color? c) => setState(() => _stepperBackground = c),
        ),
        GalleryColorChoice(
          label: 'Glyphs',
          value: _stepperForeground,
          onChanged: (Color? c) => setState(() => _stepperForeground = c),
        ),
        GalleryChoice<GalleryLook>(
          label: 'Look',
          options: GalleryLook.options,
          value: _stepperLook,
          onChanged: (GalleryLook l) => setState(() => _stepperLook = l),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final switchAppearance = _switchAppearance;
    final sliderAppearance = _sliderAppearance;
    final (sliderMin, sliderMax) = _sliderRange;
    final (stepperMin, stepperMax, step) = _stepperRange;
    return GalleryPage(
      title: 'Controls',
      options: _options,
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
                    activeTrackColor: _switchOnColor,
                    inactiveTrackColor: _switchOffColor,
                    appearance: switchAppearance,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _off = v),
                    ),
                  ),
                  const SizedBox(width: 24),
                  MorphSwitch(
                    value: _on,
                    activeTrackColor: _switchOnColor,
                    inactiveTrackColor: _switchOffColor,
                    appearance: switchAppearance,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _on = v),
                    ),
                  ),
                ],
              ),
              GalleryCaption(_wideCaption),
              Align(
                alignment: .centerLeft,
                child: SizedBox(
                  width: 300,
                  child: MorphSlider(
                    value: _wide,
                    min: sliderMin,
                    max: sliderMax,
                    animated: _sliderAnimated,
                    activeTrackColor: _sliderActiveColor,
                    inactiveTrackColor: _sliderInactiveColor,
                    appearance: sliderAppearance,
                    onChangeStart: (double v) => setState(() {
                      _dragStart = v;
                      _dragEnd = null;
                    }),
                    onChangeEnd: (double v) => setState(() => _dragEnd = v),
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
                    activeTrackColor: _sliderActiveColor,
                    inactiveTrackColor: _sliderInactiveColor,
                    appearance: sliderAppearance,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _narrow = v),
                    ),
                  ),
                ),
              ),
              GalleryCaption(
                _ticks < 2
                    ? 'Slider, no ticks: ${_stepped.toStringAsFixed(2)}'
                    : 'Slider, $_ticks ticks: ${_stepped.toStringAsFixed(2)}',
              ),
              Align(
                alignment: .centerLeft,
                child: SizedBox(
                  width: 300,
                  child: MorphSlider(
                    value: _stepped,
                    ticks: _ticks,
                    activeTrackColor: _sliderActiveColor,
                    inactiveTrackColor: _sliderInactiveColor,
                    appearance: sliderAppearance,
                    onChanged: GalleryGlassScope.enabled(
                      context,
                      (v) => setState(() => _stepped = v),
                    ),
                  ),
                ),
              ),
              GalleryCaption('Glass buttons, tapped $_taps times'),
              MorphGlassContainer(
                solidBackdrop: MorphListAppearance.resolve(
                  context,
                  null,
                ).backgroundColor,
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
                      child: MorphGlassButton.prominent(
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
              GalleryCaption('Stepper: ${_stepperText(_stepper)}'),
              Align(
                alignment: .centerLeft,
                child: MorphStepper(
                  value: _stepper,
                  min: stepperMin,
                  max: stepperMax,
                  step: step,
                  backgroundColor: _stepperBackground,
                  foregroundColor: _stepperForeground,
                  appearance: _stepperAppearance,
                  decrementLabel: _stepperSemantics
                      ? 'Fewer cups'
                      : 'Decrement',
                  incrementLabel: _stepperSemantics ? 'More cups' : 'Increment',
                  semanticFormatterCallback: _stepperSemantics
                      ? (double v) => '${_stepperText(v)} cups'
                      : null,
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
