import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/scope.dart';

/// Description of a flight target: how to compute its rect from the
/// current overlay geometry (re-evaluated every frame - the target is
/// live; a window resize or the keyboard retargets it automatically)
/// and what surface it has.
///
/// Two kinds of target exist. A FIXED target knows its box: [rectFor]
/// returns it. A MEASURED target ([MorphTargetSpec.measured], or a
/// factory with `fitContent`) lets its content decide: the content is
/// laid out under [constraintsFor], its size is measured, and
/// [placeFor] turns the measured size into the rect. When the content
/// changes size while the flight is up (a capsule growing on
/// selection, a chip unfolding), the measured size is spring-smoothed
/// on the flight's open motion and the surface follows it - the
/// content itself lays out at its natural size and the surface reveals
/// it as it catches up.
///
/// The surface model is the same [MorphSurfaceSpec] as on the source
/// side: one vocabulary describes buttons and their destinations, so an
/// app's named archetypes serve both ends of a flight. When [surface]
/// is set it wins over the individual fields (mirroring
/// [MorphTag.spec]); inside the shuttle the target content can read the
/// resolved model back via [MorphTag.specOf].
///
/// The class may be extended: a target whose geometry follows state of
/// its own (a column of slots whose heights spring live) overrides
/// [contentAlignment] and notifies through [repaint], and every
/// renderer of the flight re-lays the frame on each notification.
class MorphTargetSpec {
  /// Creates a fixed target from a live [rectFor] and a surface model.
  MorphTargetSpec({
    required this.rectFor,
    MorphSurfaceSpec? surface,
    ShapeBorder shape = const RoundedRectangleBorder(),
    Color? surfaceColor,
    double elevation = 24,
    this._contentAlignment = Alignment.topCenter,
    this.clipBehavior = Clip.antiAlias,
    this.repaint,
  }) : constraintsFor = null,
       placeFor = null,
       isVessel = false,
       shape = surface != null ? surface.shape : shape,
       surfaceColor = surface != null ? surface.color : surfaceColor,
       elevation = surface != null ? surface.elevation : elevation;

  /// Creates a target measured by its content.
  ///
  /// The content is laid out under [constraintsFor] (typically a tight
  /// width and a loose height up to a cap), and [placeFor] places the
  /// measured size. Until the first measurement lands the shuttle
  /// stays invisible and the source visible, so a launch never shows
  /// a guessed box; afterwards every size change springs.
  MorphTargetSpec.measured({
    required BoxConstraints Function(Size overlaySize, EdgeInsets padding)
    constraintsFor,
    required Rect Function(Size overlaySize, EdgeInsets padding, Size content)
    placeFor,
    MorphSurfaceSpec? surface,
    ShapeBorder shape = const RoundedRectangleBorder(),
    Color? surfaceColor,
    double elevation = 24,
    this._contentAlignment = Alignment.topCenter,
    this.clipBehavior = Clip.antiAlias,
    this.repaint,
  }) : constraintsFor = constraintsFor,
       placeFor = placeFor,
       isVessel = false,
       // Before any measurement the placement of the smallest allowed
       // content stands in; the shuttle is invisible until then.
       rectFor = ((Size overlaySize, EdgeInsets padding) => placeFor(
         overlaySize,
         padding,
         constraintsFor(overlaySize, padding).smallest,
       )),
       shape = surface != null ? surface.shape : shape,
       surfaceColor = surface != null ? surface.color : surfaceColor,
       elevation = surface != null ? surface.elevation : elevation;

  /// Creates a vessel: a target whose content draws the whole morph
  /// itself.
  ///
  /// The shuttle draws no surface, no shadow and no source ghost, and
  /// runs no crossfade: the content is laid out over the entire
  /// overlay, in the overlay's own coordinates, at full opacity from
  /// the first frame, and takes pointers for as long as the flight is
  /// open or opening. It reads the flight value through
  /// `MorphFlightScope` and paints every frame of the transition as a
  /// function of it - a control that becomes its own menu draws both
  /// shapes and their crossfade where it wants them.
  ///
  /// Everything else the flight provides still applies: the overlay
  /// choice, the scrim as a modal barrier while the flight is open or
  /// opening (pass a zero scrim opacity for no dimming; a closing vessel
  /// lets touches through to the page, so its source can re-open it),
  /// the pop layering, the focus trap, the events, and
  /// the dissolve of a flight whose source is gone. [rectFor] names
  /// where the surface ends up; its padding argument is the safe area
  /// unioned with the keyboard, as for every target.
  MorphTargetSpec.vessel({required this.rectFor, this.repaint})
    : constraintsFor = null,
      placeFor = null,
      isVessel = true,
      shape = const RoundedRectangleBorder(),
      surfaceColor = const Color(0x00000000),
      elevation = 0,
      _contentAlignment = Alignment.topLeft,
      clipBehavior = Clip.none;

  /// Whether this is a vessel ([MorphTargetSpec.vessel]): the content
  /// covers the overlay and draws the transition itself.
  final bool isVessel;

  /// Computes the destination rect; re-evaluated every frame.
  ///
  /// The padding argument is the overlay's obstructed edges: the safe
  /// area, unioned edge by edge with the keyboard while it is up. A
  /// target placed inside it stays clear of both - a sheet docks above
  /// the keyboard, a dialog centers in the room that is left - and the
  /// content sees only the part of the keyboard the surface still
  /// overlaps (a fullscreen target, which ignores the padding, keeps
  /// the full insets for its own layout).
  ///
  /// For a measured target this is the placement of the smallest
  /// allowed content; [resolveRect] is what the renderers call.
  final Rect Function(Size overlaySize, EdgeInsets padding) rectFor;

  /// For a measured target: the constraints its content is laid out
  /// under. Null for a fixed target, whose content is laid out tight at
  /// the rect's size.
  final BoxConstraints Function(Size overlaySize, EdgeInsets padding)?
  constraintsFor;

  /// For a measured target: the rect for a measured content size.
  final Rect Function(Size overlaySize, EdgeInsets padding, Size content)?
  placeFor;

  /// Whether the target is measured by its content.
  bool get isMeasured => constraintsFor != null;

  /// Notifies when the target's geometry inputs changed on their own -
  /// a [rectFor] that reads state of the owner's, an alignment that
  /// follows live slots. The flight re-lays its frame on every
  /// notification, the way a CustomPainter repaints on its `repaint`.
  final Listenable? repaint;

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
  /// Overridable for geometry that moves with state of its own.
  Alignment get contentAlignment => _contentAlignment;
  final Alignment _contentAlignment;

  /// How the flying container clips its content. [Clip.antiAlias] (the
  /// default) clips to the morphing outline, so content never spills
  /// past the surface mid-flight. [Clip.none] lets content overflow the
  /// container: for a target whose surface is transparent and whose
  /// content draws its own surfaces (a held hero with satellites
  /// unfolding around it), the container is a layout vessel rather
  /// than a visible mass, and its clip would wipe the satellites in
  /// along the growing edge.
  final Clip clipBehavior;

  /// The rect this frame: [placeFor] of the measured [content] for a
  /// measured target that has one, [rectFor] otherwise. The one
  /// resolution every renderer of the flight calls.
  Rect resolveRect(Size overlaySize, EdgeInsets padding, Size? content) {
    final Rect Function(Size, EdgeInsets, Size)? place = placeFor;
    if (place == null || content == null) {
      return rectFor(overlaySize, padding);
    }
    return place(overlaySize, padding, content);
  }

  /// A bottom sheet: full-width up to [maxWidth], docked above the
  /// bottom safe area (and above the keyboard while it is up).
  ///
  /// With [fitContent] the sheet is as tall as its content: [height]
  /// (or [heightFactor]) becomes the ceiling, the content is laid out
  /// at the sheet's width and measured, and the sheet springs to every
  /// size change.
  factory MorphTargetSpec.sheet({
    double? height,
    double heightFactor = 0.5,
    double maxWidth = 560,
    double margin = 14,
    bool fitContent = false,
    MorphSurfaceSpec? surface,
    ShapeBorder? shape,
    Color? surfaceColor,
  }) {
    // Floors at zero: an overlay narrower than its margins (a
    // collapsing split pane) must degrade to an empty rect, not feed
    // negative constraints to the shuttle.
    double widthFor(Size size, EdgeInsets padding) => math.max(
      0,
      math.min(
        maxWidth,
        size.width - padding.left - padding.right - margin * 2,
      ),
    );
    double capFor(Size size, EdgeInsets padding) {
      final double desired = height ?? size.height * heightFactor;
      return math.max(
        0,
        math.min(
          desired,
          size.height - padding.top - padding.bottom - margin * 2,
        ),
      );
    }

    Rect place(Size size, EdgeInsets padding, double h) {
      final double w = widthFor(size, padding);
      final double roomLeft = padding.left + margin;
      final double roomRight = size.width - padding.right - margin;
      return Rect.fromLTWH(
        (roomLeft + roomRight - w) / 2,
        size.height - h - padding.bottom - margin,
        w,
        h,
      );
    }

    final ShapeBorder resolvedShape =
        shape ??
        const RoundedRectangleBorder(borderRadius: .all(.circular(28)));
    if (!fitContent) {
      return MorphTargetSpec(
        surface: surface,
        shape: resolvedShape,
        surfaceColor: surfaceColor,
        rectFor: (Size size, EdgeInsets padding) =>
            place(size, padding, capFor(size, padding)),
      );
    }
    return MorphTargetSpec.measured(
      surface: surface,
      shape: resolvedShape,
      surfaceColor: surfaceColor,
      constraintsFor: (Size size, EdgeInsets padding) => BoxConstraints(
        minWidth: widthFor(size, padding),
        maxWidth: widthFor(size, padding),
        maxHeight: capFor(size, padding),
      ),
      placeFor: (Size size, EdgeInsets padding, Size content) =>
          place(size, padding, math.min(content.height, capFor(size, padding))),
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
  ///
  /// With [fitContent] the popover is as tall as its content: the
  /// height of [size] becomes the ceiling (infinite means the overlay's
  /// safe height), the content is laid out at the popover's width and
  /// measured, and the flip decision reads the measured height.
  factory MorphTargetSpec.popover({
    required Rect anchor,
    Size size = const Size(260, 300),
    double gap = 10,
    double margin = 12,
    bool fitContent = false,
    MorphSurfaceSpec? surface,
    ShapeBorder? shape,
    Color? surfaceColor,
  }) {
    double widthFor(Size overlay, EdgeInsets padding) => math.max(
      0,
      math.min(
        size.width,
        overlay.width - padding.left - padding.right - margin * 2,
      ),
    );

    Rect place(Size overlay, EdgeInsets padding, double height) {
      // All four safe-area sides count: a home indicator or a
      // landscape notch is system chrome the popover must not sit
      // under.
      final double width = widthFor(overlay, padding);
      final double leftMin = padding.left + margin;
      final double leftMax = math.max(
        leftMin,
        overlay.width - padding.right - width - margin,
      );
      final double left = (anchor.center.dx - width / 2).clamp(
        leftMin,
        leftMax,
      );
      double top = anchor.bottom + gap;
      if (top + height > overlay.height - padding.bottom - margin) {
        top = anchor.top - gap - height;
      }
      final double topMin = padding.top + margin;
      final double topMax = math.max(
        topMin,
        overlay.height - padding.bottom - height - margin,
      );
      top = top.clamp(topMin, topMax);
      return Rect.fromLTWH(left, top, width, height);
    }

    double capFor(Size overlay, EdgeInsets padding) => math.max(
      0,
      math.min(
        size.height,
        overlay.height - padding.top - padding.bottom - margin * 2,
      ),
    );

    final ShapeBorder resolvedShape =
        shape ??
        const RoundedRectangleBorder(borderRadius: .all(.circular(20)));
    if (!fitContent) {
      return MorphTargetSpec(
        surface: surface,
        shape: resolvedShape,
        surfaceColor: surfaceColor,
        rectFor: (Size overlay, EdgeInsets padding) =>
            place(overlay, padding, capFor(overlay, padding)),
      );
    }
    return MorphTargetSpec.measured(
      surface: surface,
      shape: resolvedShape,
      surfaceColor: surfaceColor,
      constraintsFor: (Size overlay, EdgeInsets padding) => BoxConstraints(
        minWidth: widthFor(overlay, padding),
        maxWidth: widthFor(overlay, padding),
        maxHeight: capFor(overlay, padding),
      ),
      placeFor: (Size overlay, EdgeInsets padding, Size content) => place(
        overlay,
        padding,
        math.min(content.height, capFor(overlay, padding)),
      ),
    );
  }

  /// A centered dialog of at most [width] x [height].
  ///
  /// With [fitContent] the dialog is as tall as its content, [height]
  /// being the ceiling: the content is laid out at the dialog's width
  /// and measured, and the dialog springs to every size change.
  factory MorphTargetSpec.dialog({
    double width = 440,
    double height = 360,
    double margin = 24,
    bool fitContent = false,
    MorphSurfaceSpec? surface,
    ShapeBorder? shape,
    Color? surfaceColor,
  }) {
    double widthFor(Size size, EdgeInsets padding) => math.max(
      0,
      math.min(width, size.width - padding.left - padding.right - margin * 2),
    );
    double capFor(Size size, EdgeInsets padding) => math.max(
      0,
      math.min(height, size.height - padding.top - padding.bottom - margin * 2),
    );
    Rect place(Size size, EdgeInsets padding, double h) {
      final double roomLeft = padding.left + margin;
      final double roomRight = size.width - padding.right - margin;
      final double roomTop = padding.top + margin;
      final double roomBottom = size.height - padding.bottom - margin;
      return Rect.fromCenter(
        center: Offset((roomLeft + roomRight) / 2, (roomTop + roomBottom) / 2),
        width: widthFor(size, padding),
        height: h,
      );
    }

    final ShapeBorder resolvedShape =
        shape ??
        const RoundedRectangleBorder(borderRadius: .all(.circular(24)));
    if (!fitContent) {
      return MorphTargetSpec(
        surface: surface,
        shape: resolvedShape,
        surfaceColor: surfaceColor,
        rectFor: (Size size, EdgeInsets padding) =>
            place(size, padding, capFor(size, padding)),
      );
    }
    return MorphTargetSpec.measured(
      surface: surface,
      shape: resolvedShape,
      surfaceColor: surfaceColor,
      constraintsFor: (Size size, EdgeInsets padding) => BoxConstraints(
        minWidth: widthFor(size, padding),
        maxWidth: widthFor(size, padding),
        maxHeight: capFor(size, padding),
      ),
      placeFor: (Size size, EdgeInsets padding, Size content) =>
          place(size, padding, math.min(content.height, capFor(size, padding))),
    );
  }
}

/// The overlay's obstructed edges as every target's rectFor sees them:
/// the safe area unioned edge by edge with the keyboard. ONE
/// implementation for the shuttle and the settled route page.
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
  final EdgeInsets insets = morphOverlayViewInsetsOf(
    context,
    overlaySize,
    overlayBox: overlayBox,
  );
  return EdgeInsets.fromLTRB(
    math.max(padding.left, insets.left),
    math.max(padding.top, insets.top),
    math.max(padding.right, insets.right),
    math.max(padding.bottom, insets.bottom),
  );
}

/// Window view-insets expressed in the coordinate space of the overlay
/// hosting the flight. A nested overlay may begin below the status bar or
/// end above the keyboard; forwarding raw window insets would count the
/// obscured strip twice, or reserve pixels that do not intersect it.
@internal
EdgeInsets morphOverlayViewInsetsOf(
  BuildContext context,
  Size overlaySize, {
  RenderBox? overlayBox,
}) => _morphOverlayInsets(
  context,
  overlaySize,
  MediaQuery.viewInsetsOf(context),
  overlayBox: overlayBox,
);

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

/// The view insets the target content should see: only the part of
/// each inset the container still overlaps. A surface that moved clear
/// of the keyboard hands its content no keyboard at all (a Scaffold
/// inside must not avoid it a second time); a fullscreen surface
/// passes the insets through untouched.
@internal
EdgeInsets morphContentViewInsets(
  EdgeInsets insets,
  Rect rect,
  Size overlaySize,
) {
  return EdgeInsets.fromLTRB(
    math.max(0, insets.left - rect.left),
    math.max(0, insets.top - rect.top),
    math.max(0, insets.right - (overlaySize.width - rect.right)),
    math.max(0, insets.bottom - (overlaySize.height - rect.bottom)),
  );
}

/// The rect of [context]'s render box in the coordinate space of the
/// enclosing [Overlay] - the space every flight, and therefore every
/// [MorphTargetSpec.rectFor], works in. Use it to capture popover
/// anchors at tap time: a raw `localToGlobal` returns SCREEN
/// coordinates, which silently drift from overlay coordinates the
/// moment the morph lives inside a nested navigator.
///
/// A flight that renders in a chosen overlay (the `overlay:` of
/// showMorph*) works in THAT overlay's space: pass the same [overlay]
/// here, or the anchor drifts by the nested navigator's own offset.
/// The overlay must be an ancestor of [context].
Rect morphAnchorRect(BuildContext context, {OverlayState? overlay}) {
  final Rect? rect = maybeMorphAnchorRect(context, overlay: overlay);
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
Rect? maybeMorphAnchorRect(BuildContext context, {OverlayState? overlay}) {
  if (!context.mounted) {
    return null;
  }
  final RenderObject? render = context.findRenderObject();
  if (render is! RenderBox || !render.attached || !render.hasSize) {
    return null;
  }
  final OverlayState? host = overlay ?? Overlay.maybeOf(context);
  final RenderObject? overlayBox = host != null && host.mounted
      ? host.context.findRenderObject()
      : null;
  return render.localToGlobal(
        Offset.zero,
        ancestor: overlayBox is RenderBox ? overlayBox : null,
      ) &
      render.size;
}
