import 'package:flutter/widgets.dart';

import 'package:morph/src/flight.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/show.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/target.dart';

/// The declarative layer on top of the engine: a morph as a function of
/// state, in the spirit of SwiftUI's matchedGeometryEffect, adapted to
/// Flutter's rules.
///
/// The anchor and the overlay are colocated in the tree (like
/// MenuAnchor); the source of truth is [isOpen] owned by the state
/// holder. Opening, closing, and interruption are just a bool flip:
/// toggled mid-flight - the spring retargets with velocity carry-over.
/// A scrim tap and Esc do not close the overlay themselves; they call
/// [onDismiss] - state flows down, events flow up.
///
/// Identity is implicit: the State itself serves as the tag (analogous
/// to a SwiftUI Namespace); no global string ids required.
///
/// ```dart
/// MorphAnchor(
///   isOpen: _sharing,
///   onDismiss: () => setState(() => _sharing = false),
///   target: MorphTargetSpec.sheet(),
///   shape: const StadiumBorder(),
///   closedBuilder: (context) =>
///       ShareButton(onTap: () => setState(() => _sharing = true)),
///   openBuilder: (context) => ShareSheet(),
/// )
/// ```
///
/// The imperative [showMorph] remains alongside as an escape hatch -
/// like showDialog next to OpenContainer.
class MorphAnchor extends StatefulWidget {
  /// Creates a declarative morph driven by [isOpen].
  const MorphAnchor({
    super.key,
    required this.isOpen,
    required this.onDismiss,
    required this.target,
    required this.closedBuilder,
    required this.openBuilder,
    this.tagId,
    this.spec,
    this.shape = const RoundedRectangleBorder(),
    this.surfaceColor,
    this.elevation = 0,
    this.replica,
    this.snapshotGhost = false,
    this.motion,
    this.barrierDismissible = true,
    this.maxScrimOpacity,
    this.scrimColor,
    this.shadowColor,
    this.semanticLabel,
    this.overlay,
  });

  /// Whether the overlay should be open; changes retarget the flight.
  final bool isOpen;

  /// Called when the user dismisses (scrim tap, Esc, back): flip the
  /// state that feeds [isOpen] - state down, events up.
  final VoidCallback onDismiss;

  /// The destination description.
  final MorphTargetSpec target;

  /// Builds the inline widget (the flight's source).
  final WidgetBuilder closedBuilder;

  /// Builds the overlay content. Rebuilt when the anchor rebuilds, so
  /// content derived from the owner's state stays fresh in the open
  /// overlay.
  final MorphContentBuilder openBuilder;

  /// An explicit tag id instead of identity-by-State. Needed when the
  /// anchor's flight must be visible to outside consumers by name - for
  /// example, a MorphPiece with the same id gets the flight neck for
  /// free. Must stay stable for the anchor's whole lifetime.
  final Object? tagId;

  /// The source surface model as one value ([MorphTag.spec] semantics:
  /// wins over [shape]/[surfaceColor]/[elevation]).
  final MorphSurfaceSpec? spec;

  /// The source outline the shuttle takes off from.
  final ShapeBorder shape;

  /// The source surface color.
  final Color? surfaceColor;

  /// The source elevation ([MorphTag.elevation] semantics): a source
  /// with its own shadow must declare it, or the shadow pops at launch
  /// and handoff.
  final double elevation;

  /// The in-flight copy for the shuttle ([MorphTag.replica] semantics).
  final Widget? replica;

  /// Fly a pixel snapshot instead of a widget replica
  /// ([MorphTag.snapshotGhost] semantics).
  final bool snapshotGhost;

  /// Motion profile; null resolves MorphTheme, then the default.
  final MorphMotion? motion;

  /// Whether scrim taps and Esc request dismissal.
  final bool barrierDismissible;

  /// Scrim ceiling; null resolves MorphTheme, then the default.
  final double? maxScrimOpacity;

  /// Scrim hue; null resolves MorphTheme, then black.
  final Color? scrimColor;

  /// Shadow color of the flying surface, opacity included; null
  /// resolves MorphTheme, then 60% black.
  final Color? shadowColor;

  /// Accessibility name of the opened overlay (screen readers announce
  /// it).
  final String? semanticLabel;

  /// The overlay the flight renders in; null is the nearest enclosing
  /// one ([showMorph]'s `overlay:` semantics).
  final OverlayState? overlay;

  @override
  State<MorphAnchor> createState() => _MorphAnchorState();
}

class _MorphAnchorState extends State<MorphAnchor> {
  MorphFlight? _flight;

  Object get _tagId => widget.tagId ?? this;

  @override
  void initState() {
    super.initState();
    if (widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted && widget.isOpen) {
          _open();
        }
      });
    }
  }

  @override
  void didUpdateWidget(MorphAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      // didUpdateWidget runs during build, while launching a flight
      // touches the Overlay outside our subtree - sync after the frame.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) {
          return;
        }
        if (widget.isOpen) {
          _open();
        } else {
          _flight?.close();
        }
      });
    } else {
      // The anchor rebuilt while open: the overlay content derives from
      // the owner's state exactly like the inline widget does, so it
      // rebuilds with the anchor - an OverlayEntry does not follow the
      // owner's build on its own. The entry is no ancestor of this
      // subtree, so marking it during build is illegal - defer, like
      // the isOpen sync above.
      if (_flight != null && !_flight!.isFinished) {
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          final MorphFlight? flight = _flight;
          if (mounted && flight != null && !flight.isFinished) {
            flight.markNeedsBuild();
          }
        });
      }
    }
  }

  void _open() {
    _flight = showMorph(
      context,
      from: _tagId,
      target: widget.target,
      motion: widget.motion,
      barrierDismissible: widget.barrierDismissible,
      maxScrimOpacity: widget.maxScrimOpacity,
      scrimColor: widget.scrimColor,
      shadowColor: widget.shadowColor,
      onDismissRequested: widget.onDismiss,
      semanticLabel: widget.semanticLabel,
      overlay: widget.overlay,
      builder: (BuildContext context, MorphFlight flight) =>
          widget.openBuilder(context, flight),
    );
  }

  @override
  void dispose() {
    _flight?.abort();
    _flight = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MorphTag(
      id: _tagId,
      spec: widget.spec,
      shape: widget.shape,
      surfaceColor: widget.surfaceColor,
      elevation: widget.elevation,
      replica: widget.replica,
      snapshotGhost: widget.snapshotGhost,
      child: Builder(builder: widget.closedBuilder),
    );
  }
}
