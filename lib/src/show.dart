import 'package:flutter/widgets.dart';

import 'package:morph/src/flight.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/scrim.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/target.dart';

/// The public entry point: all the plumbing (Ticker, listener, Overlay
/// and the handoff latch) is under the hood. If a flight for the
/// tag already exists, the call retargets it instead of creating a new
/// one (RETARGET CONTRACT: the existing flight keeps its target,
/// builder, barrier and scrim; only motion, dismissal routing and the
/// semantic label are updated).
///
/// [from] may be omitted when the call happens INSIDE the source tag's
/// own subtree (an onTap on the surface itself): the nearest enclosing
/// [MorphTag] is the source. Calls from elsewhere name it explicitly.
///
/// The shuttle renders in [morphPresentationOverlayOf]: the nearest
/// enclosing [Overlay] outside any [MorphPresentationBoundary] - a nested
/// navigator keeps its flights inside itself, a navigation stack's page
/// flies above the stack's bars. [overlay] chooses another
/// home: the overlay of whatever navigator owns the page, to fly above
/// chrome layered over nested navigators (a floating bar over tab
/// navigators). It must be an ancestor of [context]; anchors for such
/// a flight are measured in its space ([morphAnchorRect] takes the
/// same `overlay:`), and the target's rect is computed in it.
///
/// [scrimMotion] gives the scrim springs of its own (see
/// [MorphScrimMotion]); without it the scrim follows the flight value. Like
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
  double maxScrimOpacity = 0.45,
  Color scrimColor = const Color(0xFF000000),
  MorphScrimMotion? scrimMotion,
  VoidCallback? onDismissRequested,
  String? semanticLabel,
  OverlayState? overlay,
}) => .launch(
  context,
  from: from ?? MorphTag.idOf(context),
  target: target,
  builder: builder,
  motion: motion,
  modal: modal,
  barrierDismissible: barrierDismissible,
  maxScrimOpacity: maxScrimOpacity,
  scrimColor: scrimColor,
  scrimMotion: scrimMotion,
  onDismissRequested: onDismissRequested,
  semanticLabel: semanticLabel,
  overlay: overlay,
);
