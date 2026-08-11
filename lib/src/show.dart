import 'package:flutter/material.dart';

import 'package:morph/src/flight.dart';
import 'package:morph/src/scope.dart';
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
MorphFlight showMorph(
  BuildContext context, {
  Object? from,
  required MorphTargetSpec target,
  required MorphContentBuilder builder,
  MorphMotion? motion,
  bool barrierDismissible = true,
  double? maxScrimOpacity,
  Color? scrimColor,
  Color? shadowColor,
  VoidCallback? onDismissRequested,
  String? semanticLabel,
}) {
  final MorphTheme? theme = MorphTheme.maybeOf(context);
  return .launch(
    context,
    from: from ?? MorphTag.idOf(context),
    target: target,
    builder: builder,
    motion: motion ?? theme?.motion,
    barrierDismissible: barrierDismissible,
    maxScrimOpacity: maxScrimOpacity ?? theme?.maxScrimOpacity ?? 0.45,
    scrimColor: scrimColor ?? theme?.scrimColor ?? Colors.black,
    shadowColor: shadowColor ?? theme?.shadowColor ?? const Color(0x99000000),
    onDismissRequested: onDismissRequested,
    semanticLabel: semanticLabel,
  );
}

/// The sheet adopts its look from the app's BottomSheetTheme (shape,
/// color) unless overridden explicitly: a morph sheet inside a foreign
/// design system looks native with zero configuration.
MorphFlight showMorphSheet(
  BuildContext context, {
  Object? from,
  required MorphContentBuilder builder,
  double? height,
  double heightFactor = 0.5,
  double maxWidth = 560,
  MorphSurfaceSpec? surface,
  ShapeBorder? shape,
  Color? surfaceColor,
  MorphMotion? motion,
  bool barrierDismissible = true,
  double? maxScrimOpacity,
  Color? scrimColor,
  Color? shadowColor,
  VoidCallback? onDismissRequested,
  String? semanticLabel,
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
      surface: surface,
      shape: shape ?? theme.shape,
      surfaceColor: surfaceColor ?? theme.backgroundColor,
    ),
    builder: builder,
    motion: motion,
    barrierDismissible: barrierDismissible,
    maxScrimOpacity: maxScrimOpacity,
    scrimColor: scrimColor,
    shadowColor: shadowColor,
    onDismissRequested: onDismissRequested,
    semanticLabel: semanticLabel,
  );
}

/// The dialog adopts its look from the app's DialogTheme (shape, color)
/// unless overridden explicitly.
MorphFlight showMorphDialog(
  BuildContext context, {
  Object? from,
  required MorphContentBuilder builder,
  double width = 440,
  double height = 360,
  MorphSurfaceSpec? surface,
  ShapeBorder? shape,
  Color? surfaceColor,
  MorphMotion? motion,
  bool barrierDismissible = true,
  double? maxScrimOpacity,
  Color? scrimColor,
  Color? shadowColor,
  VoidCallback? onDismissRequested,
  String? semanticLabel,
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
      surface: surface,
      shape: shape ?? theme.shape,
      surfaceColor: surfaceColor ?? theme.backgroundColor,
    ),
    builder: builder,
    motion: motion,
    barrierDismissible: barrierDismissible,
    maxScrimOpacity: maxScrimOpacity,
    scrimColor: scrimColor,
    shadowColor: shadowColor,
    onDismissRequested: onDismissRequested,
    semanticLabel: semanticLabel,
  );
}
