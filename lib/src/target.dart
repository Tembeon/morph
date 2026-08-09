import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:morph/src/scope.dart';

/// Description of a flight target: how to compute its rect from the
/// current overlay size (re-evaluated every frame - the target is live;
/// a window resize or the keyboard retargets it automatically) and what
/// surface it has.
///
/// The surface model is the same [MorphSurfaceSpec] as on the source
/// side: one vocabulary describes buttons and their destinations, so an
/// app's named archetypes serve both ends of a flight. When [surface]
/// is set it wins over the individual fields (mirroring
/// [MorphTag.spec]); inside the shuttle the target content can read the
/// resolved model back via [MorphTag.specOf].
class MorphTargetSpec {
  /// Creates a target from a live [rectFor] and a surface model.
  MorphTargetSpec({
    required this.rectFor,
    MorphSurfaceSpec? surface,
    ShapeBorder shape = const RoundedRectangleBorder(),
    Color? surfaceColor,
    double elevation = 24,
    this.contentAlignment = Alignment.topCenter,
  }) : shape = surface != null ? surface.shape : shape,
       surfaceColor = surface != null ? surface.color : surfaceColor,
       elevation = surface != null ? surface.elevation : elevation;

  /// Computes the destination rect; re-evaluated every frame. The
  /// padding argument is MediaQuery.padding (safe areas) - keyboard
  /// insets are not available here, keyboard avoidance belongs in the
  /// content.
  final Rect Function(Size overlaySize, EdgeInsets viewPadding) rectFor;

  /// The destination outline.
  final ShapeBorder shape;

  /// The destination surface color; null adopts
  /// colorScheme.surfaceContainerHigh.
  final Color? surfaceColor;

  /// Container shadow in the fully open state.
  final double elevation;

  /// The target's surface model as a value.
  MorphSurfaceSpec get surface =>
      MorphSurfaceSpec(shape: shape, color: surfaceColor, elevation: elevation);

  /// Which edge the target content is glued to inside the growing
  /// container. Top - as in iOS/Material container transforms: the
  /// header appears near the origin and the rest "unrolls" downward.
  final Alignment contentAlignment;

  /// A bottom sheet: full-width up to [maxWidth], docked above the
  /// bottom safe area.
  factory MorphTargetSpec.sheet({
    double? height,
    double heightFactor = 0.5,
    double maxWidth = 560,
    double margin = 14,
    MorphSurfaceSpec? surface,
    ShapeBorder? shape,
    Color? surfaceColor,
  }) {
    return MorphTargetSpec(
      surface: surface,
      shape:
          shape ??
          const RoundedRectangleBorder(borderRadius: .all(.circular(28))),
      surfaceColor: surfaceColor,
      rectFor: (Size size, EdgeInsets padding) {
        // Floors at zero: an overlay narrower than its margins (a
        // collapsing split pane) must degrade to an empty rect, not
        // feed negative constraints to the shuttle.
        final double w = math.max(
          0,
          math.min(maxWidth, size.width - margin * 2),
        );
        final double desired = height ?? size.height * heightFactor;
        final double h = math.max(
          0,
          math.min(
            desired,
            size.height - padding.top - padding.bottom - margin * 2,
          ),
        );
        return Rect.fromLTWH(
          (size.width - w) / 2,
          size.height - h - padding.bottom - margin,
          w,
          h,
        );
      },
    );
  }

  /// The container-transform destination: the whole screen. The bread
  /// and butter of [MorphPageRoute] - a card that becomes a page.
  factory MorphTargetSpec.fullscreen({
    MorphSurfaceSpec? surface,
    ShapeBorder? shape,
    Color? surfaceColor,
  }) {
    return MorphTargetSpec(
      surface: surface,
      shape: shape ?? const RoundedRectangleBorder(),
      surfaceColor: surfaceColor,
      rectFor: (Size size, EdgeInsets padding) => Offset.zero & size,
    );
  }

  /// A popover anchored to the control that summoned it (the iOS 26
  /// button-to-menu shape). Prefers sitting below the anchor, flips
  /// above when there is no room, and stays inside the overlay with
  /// [margin]. Capture the anchor rect at tap time with
  /// [morphAnchorRect] - it measures in the coordinates of the overlay
  /// the flight renders in, so a popover inside a nested navigator
  /// stays anchored instead of drifting by the navigator's own offset.
  factory MorphTargetSpec.popover({
    required Rect anchor,
    Size size = const Size(260, 300),
    double gap = 10,
    double margin = 12,
    MorphSurfaceSpec? surface,
    ShapeBorder? shape,
    Color? surfaceColor,
  }) {
    return MorphTargetSpec(
      surface: surface,
      shape:
          shape ??
          const RoundedRectangleBorder(borderRadius: .all(.circular(20))),
      surfaceColor: surfaceColor,
      rectFor: (Size overlay, EdgeInsets padding) {
        // All four safe-area sides count: a home indicator or a
        // landscape notch is system chrome the popover must not sit
        // under.
        final double leftMin = padding.left + margin;
        final double leftMax = math.max(
          leftMin,
          overlay.width - padding.right - size.width - margin,
        );
        final double left = (anchor.center.dx - size.width / 2).clamp(
          leftMin,
          leftMax,
        );
        double top = anchor.bottom + gap;
        if (top + size.height > overlay.height - padding.bottom - margin) {
          top = anchor.top - gap - size.height;
        }
        final double topMin = padding.top + margin;
        final double topMax = math.max(
          topMin,
          overlay.height - padding.bottom - size.height - margin,
        );
        top = top.clamp(topMin, topMax);
        return Rect.fromLTWH(left, top, size.width, size.height);
      },
    );
  }

  /// A centered dialog of at most [width] x [height].
  factory MorphTargetSpec.dialog({
    double width = 440,
    double height = 360,
    double margin = 24,
    MorphSurfaceSpec? surface,
    ShapeBorder? shape,
    Color? surfaceColor,
  }) {
    return MorphTargetSpec(
      surface: surface,
      shape:
          shape ??
          const RoundedRectangleBorder(borderRadius: .all(.circular(24))),
      surfaceColor: surfaceColor,
      rectFor: (Size size, EdgeInsets padding) {
        final double w = math.max(0, math.min(width, size.width - margin * 2));
        final double h = math.max(
          0,
          math.min(height, size.height - margin * 2),
        );
        return Rect.fromCenter(
          center: Offset(
            size.width / 2,
            (size.height + padding.top - padding.bottom) / 2,
          ),
          width: w,
          height: h,
        );
      },
    );
  }
}

/// The rect of [context]'s render box in the coordinate space of the
/// enclosing [Overlay] - the space every flight, and therefore every
/// [MorphTargetSpec.rectFor], works in. Use it to capture popover
/// anchors at tap time: a raw `localToGlobal` returns SCREEN
/// coordinates, which silently drift from overlay coordinates the
/// moment the morph lives inside a nested navigator.
Rect morphAnchorRect(BuildContext context) {
  final Rect? rect = maybeMorphAnchorRect(context);
  assert(
    rect != null,
    'morphAnchorRect: the context has no laid-out RenderBox (called '
    'before the first layout, or from a removed widget). Capture the '
    'anchor at tap time, or use maybeMorphAnchorRect to degrade.',
  );
  return rect!;
}

/// Like [morphAnchorRect], but null when the context has no laid-out
/// box - for callers that can fall back (a centered dialog instead of
/// an anchored popover) rather than crash.
Rect? maybeMorphAnchorRect(BuildContext context) {
  if (!context.mounted) {
    return null;
  }
  final RenderObject? render = context.findRenderObject();
  if (render is! RenderBox || !render.attached || !render.hasSize) {
    return null;
  }
  final RenderObject? overlay = Overlay.maybeOf(
    context,
  )?.context.findRenderObject();
  return render.localToGlobal(
        Offset.zero,
        ancestor: overlay is RenderBox ? overlay : null,
      ) &
      render.size;
}
