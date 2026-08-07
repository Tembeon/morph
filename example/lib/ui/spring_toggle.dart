import 'package:flutter/material.dart';

import 'package:morph/morph.dart';
import 'package:motor/motor.dart';

/// A switch whose knob rides a spring (motor's [SingleMotionController]:
/// mid-flight taps retarget with velocity carry-over for free), and the
/// knob deforms by its own velocity - stretched along the motion,
/// squashed across it - so the liquid feel costs nothing but a pure
/// function of (position, velocity). Track color follows the knob
/// position, not the model.
class SpringToggle extends StatefulWidget {
  /// Creates a spring toggle.
  const SpringToggle({super.key, required this.value, required this.onChanged});

  /// The current state.
  final bool value;

  /// Called with the flipped state on tap.
  final ValueChanged<bool> onChanged;

  static const double _width = 42;
  static const double _height = 24;
  static const double _knob = 18;

  @override
  State<SpringToggle> createState() => _SpringToggleState();
}

class _SpringToggleState extends State<SpringToggle>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _t = SingleMotionController(
    motion: MorphMotion.normal.closeMotion,
    vsync: this,
    initialValue: widget.value ? 1 : 0,
  );

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SpringToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _t.animateTo(widget.value ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const double travel = SpringToggle._width - SpringToggle._knob - 6;
    return GestureDetector(
      behavior: .opaque,
      onTap: () => widget.onChanged(!widget.value),
      child: SizedBox(
        width: SpringToggle._width,
        height: SpringToggle._height,
        child: ListenableBuilder(
          listenable: _t,
          builder: (BuildContext context, Widget? child) {
            final double fraction = _t.value.clamp(0.0, 1.0);
            // Velocity deformation: stretch along the travel, squash
            // across.
            final double stretch = (1 + (_t.velocity.abs() * 0.06)).clamp(
              1.0,
              1.45,
            );
            return Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                Container(
                  width: SpringToggle._width,
                  height: SpringToggle._height,
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: Color.lerp(
                      Colors.white.withValues(alpha: 0.1),
                      scheme.primary.withValues(alpha: 0.75),
                      fraction,
                    ),
                  ),
                ),
                Positioned(
                  left: 3 + travel * _t.value,
                  child: Container(
                    width: SpringToggle._knob * stretch,
                    height: SpringToggle._knob / stretch,
                    decoration: const ShapeDecoration(
                      shape: StadiumBorder(),
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The lab's replacement for SwitchListTile, on [SpringToggle].
class SpringToggleTile extends StatelessWidget {
  /// Creates a labeled toggle row.
  const SpringToggleTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  /// The row label.
  final String label;

  /// The current state.
  final bool value;

  /// Called with the flipped state on tap.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          SpringToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
