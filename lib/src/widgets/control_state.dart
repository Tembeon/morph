import 'package:flutter/widgets.dart';

/// Read-only interaction flags for custom control content.
///
/// These change at input edges, never on the animation's frame stream.
@immutable
class MorphControlState {
  /// Creates the flags of one control or selectable item.
  const MorphControlState({
    this.selected = false,
    this.active = false,
    this.pressed = false,
    this.focused = false,
    this.hovered = false,
    this.enabled = true,
  });

  /// Whether the owner has selected this item.
  final bool selected;

  /// Whether this item is the current touch preview.
  final bool active;

  /// Whether a press is held inside the activation bounds.
  final bool pressed;

  /// Whether keyboard focus is highlighted.
  final bool focused;

  /// Whether a mouse is over this item.
  final bool hovered;

  /// Whether activation is available.
  final bool enabled;
}

/// Builds content at interaction edges, retaining an optional [child].
typedef MorphControlBuilder =
    Widget Function(
      BuildContext context,
      MorphControlState state,
      Widget? child,
    );
