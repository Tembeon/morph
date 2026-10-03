import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';

/// The lab's standard action chip on [MorphGlassButton]: a compact
/// tinted glass capsule with an optional icon. All sidebar actions share
/// it, so every tap in the shell answers with the measured glass press.
class LabActionButton extends StatelessWidget {
  /// Creates a labeled action chip.
  const LabActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.filled = true,
  });

  /// The chip label.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Tap handler; null renders the chip disabled.
  final VoidCallback? onPressed;

  /// Filled surface (true) or a faint one (false).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: MorphGlassButton(
        onPressed: onPressed,
        tint: filled
            ? scheme.secondaryContainer.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.05),
        padding: const .symmetric(horizontal: 10, vertical: 8),
        minSize: const Size(0, 32),
        child: Row(
          mainAxisSize: .min,
          mainAxisAlignment: .center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: .fade,
                softWrap: false,
                style: const TextStyle(fontSize: 11.5, fontWeight: .w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round tinted glass button around an icon: the lab's back and add
/// buttons.
class LabIconButton extends StatelessWidget {
  /// Creates an icon button.
  const LabIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tint,
    this.size = 18,
    this.padding = 8,
    this.color,
  });

  /// The glyph.
  final IconData icon;

  /// Tap handler; null renders the button disabled.
  final VoidCallback? onPressed;

  /// The glass tint; a faint white when null.
  final Color? tint;

  /// The glyph size.
  final double size;

  /// The space around the glyph.
  final double padding;

  /// The glyph color; the button's foreground when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: MorphGlassButton(
        onPressed: onPressed,
        tint: tint ?? Colors.white.withValues(alpha: 0.07),
        padding: .all(padding),
        minSize: Size.zero,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

/// The lab's segmented control: [MorphSegmentedControl] in a dark
/// appearance. A null [index] means no option matches the current
/// state: the control dims and keeps showing the last option that did.
class LabSegmented extends StatefulWidget {
  /// Creates a segmented control over [labels].
  const LabSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelect,
  });

  /// Segment labels, one per option.
  final List<String> labels;

  /// The selected option, or null when none matches.
  final int? index;

  /// Called with the selected segment's index.
  final ValueChanged<int> onSelect;

  /// The dark appearance of the lab's segmented controls.
  static const MorphSegmentedStyle style = MorphSegmentedStyle(
    trackColor: Color(0x1FFFFFFF),
    lensColor: Color(0xFF55506A),
    liftedLensColor: Color(0x40FFFFFF),
    lensBorderColor: Color(0x40FFFFFF),
    shadowColor: Color(0x33000000),
    textStyle: TextStyle(
      fontSize: 12,
      fontWeight: .w500,
      color: Color(0xB3FFFFFF),
    ),
    selectedTextStyle: TextStyle(
      fontSize: 12,
      fontWeight: .w600,
      color: Color(0xFFFFFFFF),
    ),
  );

  @override
  State<LabSegmented> createState() => _LabSegmentedState();
}

class _LabSegmentedState extends State<LabSegmented> {
  late int _shown = widget.index ?? 0;

  @override
  void didUpdateWidget(LabSegmented oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int? index = widget.index;
    if (index != null) {
      _shown = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.index == null ? 0.5 : 1,
      child: MorphSegmentedControl(
        segments: widget.labels,
        selected: _shown.clamp(0, widget.labels.length - 1),
        onChanged: widget.onSelect,
        style: LabSegmented.style,
      ),
    );
  }
}

/// The lab's replacement for SwitchListTile, on [MorphSwitch].
class LabSwitchTile extends StatelessWidget {
  /// Creates a labeled switch row.
  const LabSwitchTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  /// The row label.
  final String label;

  /// The current state.
  final bool value;

  /// Called with the flipped state.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const .symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          MorphSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: scheme.primary,
            trackColor: Colors.white.withValues(alpha: 0.16),
          ),
        ],
      ),
    );
  }
}
