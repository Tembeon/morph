import 'package:material_ui/material_ui.dart';

import 'package:morph/src/flight.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/scrim.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/theme.dart';

/// The public entry point: all the plumbing (Ticker, listener, Overlay,
/// ghost, and the handoff latch) is under the hood. If a flight for the
/// tag already exists, the call retargets it instead of creating a new
/// one (RETARGET CONTRACT: the existing flight keeps its target,
/// builder, barrier and scrim; only motion, dismissal routing and the
/// semantic label are updated).
///
/// [from] may be omitted when the call happens INSIDE the source tag's
/// own subtree (an onTap on the surface itself): the nearest enclosing
/// [MorphTag] is the source. Calls from elsewhere name it explicitly.
///
/// Ambient defaults resolve as explicit parameter > [MorphTheme] >
/// built-in.
///
/// The shuttle renders in the NEAREST enclosing [Overlay] - a nested
/// navigator keeps its flights inside itself. [overlay] chooses another
/// home: the overlay of whatever navigator owns the page, to fly above
/// chrome layered over nested navigators (a floating bar over tab
/// navigators). It must be an ancestor of [context]; anchors for such
/// a flight are measured in its space ([morphAnchorRect] takes the
/// same `overlay:`), and the target's rect is computed in it.
///
/// [scrimMotion] gives the scrim springs of its own (see
/// [MorphScrimMotion]); without it (and without
/// [MorphTheme.scrimMotion]) the scrim follows the flight value. Like
/// the rest of the scrim it is fixed at launch.
///
/// A non-modal flight ([modal] false) mounts no scrim: the page under
/// the surface stays fully interactive - a tool flying over live
/// content. Tap-outside dismissal disappears with the scrim; Esc and
/// the local history entry still close.
MorphFlight showMorph(
  BuildContext context, {
  Object? from,
  required MorphTargetSpec target,
  required MorphContentBuilder builder,
  MorphMotion? motion,
  bool modal = true,
  bool barrierDismissible = true,
  double? maxScrimOpacity,
  Color? scrimColor,
  MorphScrimMotion? scrimMotion,
  Color? shadowColor,
  VoidCallback? onDismissRequested,
  String? semanticLabel,
  OverlayState? overlay,
}) {
  final MorphTheme? theme = MorphTheme.maybeOf(context);
  return .launch(
    context,
    from: from ?? MorphTag.idOf(context),
    target: target,
    builder: builder,
    motion: motion ?? theme?.motion,
    modal: modal,
    barrierDismissible: barrierDismissible,
    maxScrimOpacity:
        maxScrimOpacity ??
        theme?.maxScrimOpacity ??
        MorphTheme.defaultMaxScrimOpacity,
    scrimColor: scrimColor ?? theme?.scrimColor ?? MorphTheme.defaultScrimColor,
    scrimMotion: scrimMotion ?? theme?.scrimMotion,
    shadowColor:
        shadowColor ?? theme?.shadowColor ?? MorphTheme.defaultShadowColor,
    onDismissRequested: onDismissRequested,
    semanticLabel: semanticLabel,
    overlay: overlay,
  );
}

/// The sheet adopts its look from the app's BottomSheetTheme (shape,
/// color) unless overridden explicitly: a morph sheet inside a foreign
/// design system looks native with zero configuration. The flight
/// parameters ([modal], the scrim, [overlay]) mean what they mean on
/// [showMorph].
///
/// With [fitContent] the sheet is as tall as its content, [height] (or
/// [heightFactor]) being the ceiling - see [MorphTargetSpec.sheet].
MorphFlight showMorphSheet(
  BuildContext context, {
  Object? from,
  required MorphContentBuilder builder,
  double? height,
  double heightFactor = 0.5,
  double maxWidth = 560,
  bool fitContent = false,
  MorphSurfaceSpec? surface,
  ShapeBorder? shape,
  Color? surfaceColor,
  MorphMotion? motion,
  bool modal = true,
  bool barrierDismissible = true,
  double? maxScrimOpacity,
  Color? scrimColor,
  MorphScrimMotion? scrimMotion,
  Color? shadowColor,
  VoidCallback? onDismissRequested,
  String? semanticLabel,
  OverlayState? overlay,
}) {
  assert(
    height == null || height > 0,
    'height must be positive; omit it to use heightFactor.',
  );
  assert(
    heightFactor > 0 && heightFactor <= 1,
    'heightFactor is a fraction of the screen height in (0, 1]; '
    'got $heightFactor. For a fixed size pass height instead.',
  );
  assert(maxWidth > 0, 'maxWidth must be positive.');
  final BottomSheetThemeData theme = Theme.of(context).bottomSheetTheme;
  return showMorph(
    context,
    from: from,
    target: MorphTargetSpec.sheet(
      height: height,
      heightFactor: heightFactor,
      maxWidth: maxWidth,
      fitContent: fitContent,
      surface: surface,
      shape: shape ?? theme.shape,
      surfaceColor: surfaceColor ?? theme.backgroundColor,
    ),
    builder: builder,
    motion: motion,
    modal: modal,
    barrierDismissible: barrierDismissible,
    maxScrimOpacity: maxScrimOpacity,
    scrimColor: scrimColor,
    scrimMotion: scrimMotion,
    shadowColor: shadowColor,
    onDismissRequested: onDismissRequested,
    semanticLabel: semanticLabel,
    overlay: overlay,
  );
}

/// The dialog adopts its look from the app's DialogTheme (shape, color)
/// unless overridden explicitly. The flight parameters ([modal], the
/// scrim, [overlay]) mean what they mean on [showMorph].
///
/// With [fitContent] the dialog is as tall as its content, [height]
/// being the ceiling - see [MorphTargetSpec.dialog].
MorphFlight showMorphDialog(
  BuildContext context, {
  Object? from,
  required MorphContentBuilder builder,
  double width = 440,
  double height = 360,
  bool fitContent = false,
  MorphSurfaceSpec? surface,
  ShapeBorder? shape,
  Color? surfaceColor,
  MorphMotion? motion,
  bool modal = true,
  bool barrierDismissible = true,
  double? maxScrimOpacity,
  Color? scrimColor,
  MorphScrimMotion? scrimMotion,
  Color? shadowColor,
  VoidCallback? onDismissRequested,
  String? semanticLabel,
  OverlayState? overlay,
}) {
  assert(
    width > 0 && height > 0,
    'Dialog dimensions must be positive; got $width x $height.',
  );
  final DialogThemeData theme = Theme.of(context).dialogTheme;
  return showMorph(
    context,
    from: from,
    target: MorphTargetSpec.dialog(
      width: width,
      height: height,
      fitContent: fitContent,
      surface: surface,
      shape: shape ?? theme.shape,
      surfaceColor: surfaceColor ?? theme.backgroundColor,
    ),
    builder: builder,
    motion: motion,
    modal: modal,
    barrierDismissible: barrierDismissible,
    maxScrimOpacity: maxScrimOpacity,
    scrimColor: scrimColor,
    scrimMotion: scrimMotion,
    shadowColor: shadowColor,
    onDismissRequested: onDismissRequested,
    semanticLabel: semanticLabel,
    overlay: overlay,
  );
}
