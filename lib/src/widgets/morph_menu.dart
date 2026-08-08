import 'package:flutter/material.dart';

import 'package:morph/foundation.dart';
import 'package:morph/src/widgets/spring_button.dart';

/// An entry of [showMorphMenu].
class MorphMenuItem {
  /// Creates a menu entry.
  const MorphMenuItem({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.tint,
  });

  /// Leading icon of the row.
  final IconData icon;

  /// The row label.
  final String label;

  /// Called on tap, before the menu plays its close - so the action
  /// lands even if the owner tears the screen down right after.
  final VoidCallback onSelected;

  /// Overrides the row's icon and label color - destructive entries
  /// typically pass the app's danger color.
  final Color? tint;
}

/// The iOS 26 staple as one call: a control becomes ITS OWN menu.
///
/// The control's surface expands into a popover anchored to where the
/// control stands, the rows cascade in on sub-ranges of the SAME
/// spring ([MorphReveal] - the cascade is the menu's opening, not a
/// separate clock), and closing collapses the menu back into the
/// control. Identity is never broken: the thing you tapped is the
/// thing you use.
///
/// [context] should sit at (or under) the control: its render box
/// anchors the popover, and inside a [MorphTag]'s subtree the flight
/// source is inferred - a dragged or scrolled control anchors its menu
/// wherever it currently stands. The popover surface adopts the
/// ambient defaults unless [surface] overrides them.
MorphFlight showMorphMenu(
  BuildContext context, {
  Object? from,
  required List<MorphMenuItem> items,
  MorphSurfaceSpec? surface,
  MorphMotion? motion,
  double width = 250,
  double maxScrimOpacity = 0.2,
  String? semanticLabel,
}) {
  final RenderBox box = context.findRenderObject()! as RenderBox;
  final Rect anchor = box.localToGlobal(.zero) & box.size;
  return showMorph(
    context,
    from: from,
    motion: motion,
    maxScrimOpacity: maxScrimOpacity,
    semanticLabel: semanticLabel,
    target: MorphTargetSpec.popover(
      anchor: anchor,
      size: Size(width, 48.0 * items.length + 24),
      surface: surface,
    ),
    builder: (BuildContext context, MorphFlight flight) => Padding(
      padding: const .symmetric(vertical: 10),
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          for (int i = 0; i < items.length; i++)
            MorphReveal(
              from: 0.3 + i * 0.1,
              to: 0.7 + i * 0.06,
              child: _MorphMenuRow(item: items[i], flight: flight),
            ),
        ],
      ),
    ),
  );
}

class _MorphMenuRow extends StatelessWidget {
  const _MorphMenuRow({required this.item, required this.flight});

  final MorphMenuItem item;
  final MorphFlight flight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SpringButton(
      onPressed: () {
        item.onSelected();
        flight.close();
      },
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: <Widget>[
            Icon(
              item.icon,
              size: 18,
              color: item.tint ?? scheme.onSurface.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 14),
            Text(
              item.label,
              style: TextStyle(fontSize: 13.5, color: item.tint),
            ),
          ],
        ),
      ),
    );
  }
}
