import 'package:flutter/material.dart';

import 'package:morph/morph.dart';
import 'package:motor/motor.dart';

/// Press physics on a real spring: pointer-down retargets the scale
/// toward the pressed depth, release retargets back with bounce and
/// velocity carry-over - interruptible mid-press like everything else
/// in the system. No timelines, no curves.
///
/// The spring itself is motor's [SingleMotionController]: retargeting
/// with velocity carry-over is built in, so the recipe is three lines.
class SpringButton extends StatefulWidget {
  /// Creates a press-spring wrapper around [child].
  const SpringButton({
    super.key,
    required this.child,
    this.onPressed,
    this.pressedScale = 0.93,
  });

  /// The button face.
  final Widget child;

  /// Tap handler; null renders the button disabled.
  final VoidCallback? onPressed;

  /// Scale while the pointer is down.
  final double pressedScale;

  @override
  State<SpringButton> createState() => _SpringButtonState();
}

class _SpringButtonState extends State<SpringButton>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _scale = SingleMotionController(
    motion: MorphMotion.normal.closeMotion,
    vsync: this,
    initialValue: 1,
  );

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _down(TapDownDetails details) {
    _scale.motion = MorphMotion.fast.openMotion;
    _scale.animateTo(widget.pressedScale);
  }

  void _release() {
    _scale.motion = MorphMotion.normal.closeMotion;
    _scale.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTapDown: enabled ? _down : null,
        onTapUp: enabled ? (TapUpDetails details) => _release() : null,
        onTapCancel: enabled ? _release : null,
        onTap: widget.onPressed,
        child: ListenableBuilder(
          listenable: _scale,
          child: Opacity(opacity: enabled ? 1 : 0.38, child: widget.child),
          builder: (BuildContext context, Widget? child) =>
              Transform.scale(scale: _scale.value, child: child),
        ),
      ),
    );
  }
}

/// The lab's standard action chip on [SpringButton]: a small filled
/// surface with an optional icon. All sidebar actions share it so every
/// tap in the shell answers with spring feel.
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

  /// Filled surface (true) or hairline surface (false).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SpringButton(
      onPressed: onPressed,
      child: Container(
        padding: const .symmetric(horizontal: 10, vertical: 8),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: filled
              ? scheme.secondaryContainer.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.05),
        ),
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
