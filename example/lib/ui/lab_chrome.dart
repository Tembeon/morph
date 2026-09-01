import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';

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
