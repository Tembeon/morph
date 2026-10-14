import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// The width of a knob's label column, so the controls of a section line
/// up.
const double galleryKnobLabelWidth = 96;

/// A list row that picks one of a few [options] with a segmented control.
class GalleryChoice<T> extends StatelessWidget {
  /// Creates a choice.
  const GalleryChoice({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The row's label.
  final String label;

  /// Each value and its segment's label, in order.
  final Map<T, String> options;

  /// The selected value; one of the keys of [options], or a value outside
  /// them for no selection.
  final T value;

  /// Called with the value picked, or null to disable the row.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final values = options.keys.toList();
    final index = values.indexOf(value);
    final onChanged = this.onChanged;
    return MorphListRow(
      child: Row(
        children: [
          SizedBox(width: galleryKnobLabelWidth, child: Text(label)),
          Expanded(
            child: MorphSegmentedControl(
              segments: [for (final s in options.values) MorphSegment(s)],
              selectedIndex: index < 0 ? null : index,
              onChanged: onChanged == null
                  ? null
                  : (int i) => onChanged(values[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// A list row with a slider over `min..max` and the value at its end.
class GallerySliderKnob extends StatelessWidget {
  /// Creates a slider knob.
  const GallerySliderKnob({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.fractionDigits = 2,
    super.key,
  });

  /// The row's label, also the slider's semantic label.
  final String label;

  /// The value, between [min] and [max].
  final double value;

  /// The smallest value.
  final double min;

  /// The largest value.
  final double max;

  /// The digits after the point of the value shown.
  final int fractionDigits;

  /// Called with the new value, or null to disable the row.
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final span = max - min;
    return MorphListRow(
      child: Row(
        children: [
          SizedBox(width: galleryKnobLabelWidth, child: Text(label)),
          Expanded(
            child: MorphSlider(
              value: (value - min) / span,
              semanticLabel: label,
              onChanged: onChanged == null
                  ? null
                  : (double v) => onChanged(min + v * span),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              value.toStringAsFixed(fractionDigits),
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

/// A list row with a switch.
class GalleryToggle extends StatelessWidget {
  /// Creates a toggle.
  const GalleryToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The row's title, also the switch's semantic label.
  final String label;

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value, or null to disable the row.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MorphListRow(
      title: Text(label),
      trailing: MorphSwitch(
        value: value,
        semanticLabel: label,
        onChanged: onChanged,
      ),
    );
  }
}

/// The iOS system colors a [GalleryColorChoice] offers by default; null is
/// the control's own color.
const List<(String, Color?)> galleryAccentColors = [
  ('Default', null),
  ('Purple', Color(0xFFAF52DE)),
  ('Pink', Color(0xFFFF2D55)),
  ('Orange', Color(0xFFFF9500)),
  ('Green', Color(0xFF34C759)),
  ('Teal', Color(0xFF30B0C7)),
];

/// A list row that picks a color from a row of swatches.
///
/// The null color draws as a split swatch: the control's own color.
class GalleryColorChoice extends StatelessWidget {
  /// Creates a color choice.
  const GalleryColorChoice({
    required this.label,
    required this.value,
    required this.onChanged,
    this.colors = galleryAccentColors,
    super.key,
  });

  /// The row's label.
  final String label;

  /// The selected color, or null for the default.
  final Color? value;

  /// Each swatch's name, its semantic label, and color.
  final List<(String, Color?)> colors;

  /// Called with the color picked, or null to disable the row.
  final ValueChanged<Color?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final style = MorphListAppearance.resolve(context, null);
    return MorphListRow(
      child: Row(
        children: [
          SizedBox(width: galleryKnobLabelWidth, child: Text(label)),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (name, color) in colors)
                  Semantics(
                    button: true,
                    selected: color == value,
                    label: name,
                    child: GestureDetector(
                      behavior: .opaque,
                      onTap: onChanged == null ? null : () => onChanged(color),
                      child: _Swatch(
                        color: color,
                        selected: color == value,
                        ring: style.titleColor,
                        enabled: onChanged != null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.ring,
    required this.enabled,
  });

  final Color? color;
  final bool selected;
  final Color ring;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = this.color;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        width: 30,
        height: 30,
        padding: const .all(3),
        decoration: BoxDecoration(
          shape: .circle,
          border: Border.all(
            color: selected ? ring : const Color(0x00000000),
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: .circle,
            color: color,
            gradient: color == null
                ? const SweepGradient(
                    colors: [
                      Color(0xFF007AFF),
                      Color(0xFF007AFF),
                      Color(0xFFE5E5EA),
                      Color(0xFFE5E5EA),
                    ],
                    stops: [0, 0.5, 0.5, 1],
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
