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
        final double w = math.min(maxWidth, size.width - margin * 2);
        final double desired = height ?? size.height * heightFactor;
        final double h = math.min(
          desired,
          size.height - padding.top - margin * 2,
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
  /// [margin]. Capture the anchor rect at tap time:
  /// `(context.findRenderObject()! as RenderBox).localToGlobal(...)`.
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
        final double left = (anchor.center.dx - size.width / 2).clamp(
          margin,
          math.max(margin, overlay.width - size.width - margin),
        );
        double top = anchor.bottom + gap;
        if (top + size.height > overlay.height - margin) {
          top = anchor.top - gap - size.height;
        }
        top = top.clamp(
          padding.top + margin,
          math.max(padding.top + margin, overlay.height - size.height - margin),
        );
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
        final double w = math.min(width, size.width - margin * 2);
        final double h = math.min(height, size.height - margin * 2);
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
