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
    this.shape = const RoundedRectangleBorder(),
    this.surfaceColor,
    this.motion,
    this.barrierDismissible = true,
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

  /// Builds the overlay content.
  final WidgetBuilder openBuilder;

  /// An explicit tag id instead of identity-by-State. Needed when the
  /// anchor's flight must be visible to outside consumers by name - for
  /// example, a MorphPiece with the same id gets the flight neck for
  /// free. Must stay stable for the anchor's whole lifetime.
  final Object? tagId;

  /// The source outline the shuttle takes off from.
  final ShapeBorder shape;

  /// The source surface color.
  final Color? surfaceColor;

  /// Motion profile; null resolves MorphTheme, then the default.
  final MorphMotion? motion;

  /// Whether scrim taps and Esc request dismissal.
  final bool barrierDismissible;

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
    }
  }

  void _open() {
    _flight = showMorph(
      context,
      from: _tagId,
      target: widget.target,
      motion: widget.motion,
      barrierDismissible: widget.barrierDismissible,
      onDismissRequested: widget.onDismiss,
      builder: (BuildContext context, MorphFlight flight) =>
          widget.openBuilder(context),
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
      shape: widget.shape,
      surfaceColor: widget.surfaceColor,
      child: Builder(builder: widget.closedBuilder),
    );
  }
}
