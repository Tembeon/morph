import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/presentation.dart';
import 'package:morph/src/scope.dart';

/// A flight target whose content draws the whole morph itself: a control
/// that becomes its own menu.
///
/// The content is laid out over the entire overlay, in the overlay's own
/// coordinates, at full opacity from the first frame, and takes pointers
/// for as long as the flight is open or opening. The flight still
/// provides the overlay choice, the scrim as a modal barrier while it is
/// open or opening, the pop layering, the focus trap, the events and the
/// dissolve of a flight whose source is gone. [rectFor] names where the
/// surface ends up; its padding argument is the safe area unioned with
/// the keyboard.
class MorphTargetSpec {
  /// Creates a vessel from a live [rectFor].
  MorphTargetSpec.vessel({required this.rectFor, this.repaint});

  /// Computes the destination rect; re-evaluated every frame.
  final Rect Function(Size overlaySize, EdgeInsets padding) rectFor;

  /// Notifies when the target's geometry inputs changed on their own,
  /// so the flight re-lays its frame.
  final Listenable? repaint;

  /// The target's surface model: a vessel draws its own surface.
  MorphSurfaceSpec get surface => const MorphSurfaceSpec(
    shape: RoundedRectangleBorder(),
    color: Color(0x00000000),
    elevation: 0,
  );

  /// The rect this frame.
  Rect resolveRect(Size overlaySize, EdgeInsets padding) =>
      rectFor(overlaySize, padding);
}

/// The overlay's obstructed edges as every target's rectFor sees them:
/// the safe area unioned edge by edge with the keyboard.
@internal
EdgeInsets morphTargetPaddingOf(
  BuildContext context,
  Size overlaySize, {
  RenderBox? overlayBox,
}) {
  final EdgeInsets padding = _morphOverlayInsets(
    context,
    overlaySize,
    MediaQuery.viewPaddingOf(context),
    overlayBox: overlayBox,
  );
  final EdgeInsets insets = _morphOverlayInsets(
    context,
    overlaySize,
    MediaQuery.viewInsetsOf(context),
    overlayBox: overlayBox,
  );
  return EdgeInsets.fromLTRB(
    math.max(padding.left, insets.left),
    math.max(padding.top, insets.top),
    math.max(padding.right, insets.right),
    math.max(padding.bottom, insets.bottom),
  );
}

EdgeInsets _morphOverlayInsets(
  BuildContext context,
  Size overlaySize,
  EdgeInsets windowInsets, {
  RenderBox? overlayBox,
}) {
  final Size windowSize = MediaQuery.sizeOf(context);
  Rect overlayRect = Offset.zero & overlaySize;
  final OverlayState? overlay = overlayBox == null
      ? Overlay.maybeOf(context)
      : null;
  final RenderObject? render =
      overlayBox ?? overlay?.context.findRenderObject();
  if (render is RenderBox && render.attached && render.hasSize) {
    overlayRect = MatrixUtils.transformRect(
      render.getTransformTo(null),
      Offset.zero & render.size,
    );
  }

  double bounded(double value, double extent) => value.clamp(0.0, extent);
  return EdgeInsets.fromLTRB(
    bounded(windowInsets.left - overlayRect.left, overlaySize.width),
    bounded(windowInsets.top - overlayRect.top, overlaySize.height),
    bounded(
      overlayRect.right - (windowSize.width - windowInsets.right),
      overlaySize.width,
    ),
    bounded(
      overlayRect.bottom - (windowSize.height - windowInsets.bottom),
      overlaySize.height,
    ),
  );
}

/// The rect of [context]'s render box in the coordinate space of the
/// overlay a presentation from [context] renders in
/// ([morphPresentationOverlayOf]) - the space every flight, and therefore
/// every [MorphTargetSpec.rectFor], works in. Use it to capture popover
/// anchors at tap time: a raw `localToGlobal` returns SCREEN
/// coordinates, which silently drift from overlay coordinates the
/// moment the morph lives inside a nested navigator.
///
/// A flight that renders in a chosen overlay (the `overlay:` of
/// showMorph*) works in THAT overlay's space: pass the same [overlay]
/// here, or the anchor drifts by the nested navigator's own offset.
/// The overlay must live in the same render tree as [context].
///
/// The rect is the box's whole painted bounds: a paint transform above
/// it (a press scale) is part of the rect, not just its translation.
///
/// Throws a [FlutterError] (in every build mode) when the context has
/// no laid-out box; [maybeMorphAnchorRect] degrades to null instead.
Rect morphAnchorRect(BuildContext context, {OverlayState? overlay}) {
  final Rect? rect = maybeMorphAnchorRect(context, overlay: overlay);
  if (rect == null) {
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('morphAnchorRect: the context has no laid-out RenderBox.'),
      ErrorDescription(
        'It was called before the first layout, or from a removed widget.',
      ),
      ErrorHint(
        'Capture the anchor at tap time, or use maybeMorphAnchorRect to '
        'degrade.',
      ),
    ]);
  }
  return rect;
}

/// Like [morphAnchorRect], but null when the context has no laid-out
/// box - for callers that can fall back (a centered dialog instead of
/// an anchored popover) rather than crash.
Rect? maybeMorphAnchorRect(BuildContext context, {OverlayState? overlay}) {
  if (!context.mounted) {
    return null;
  }
  final RenderObject? render = context.findRenderObject();
  if (render is! RenderBox || !render.attached || !render.hasSize) {
    return null;
  }
  final OverlayState? host = overlay ?? morphPresentationOverlayOf(context);
  final RenderObject? overlayBox = host != null && host.mounted
      ? host.context.findRenderObject()
      : null;
  return MatrixUtils.transformRect(
    render.getTransformTo(overlayBox is RenderBox ? overlayBox : null),
    Offset.zero & render.size,
  );
}
