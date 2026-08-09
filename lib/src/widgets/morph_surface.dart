import 'package:flutter/material.dart';

import 'package:morph/foundation.dart';

/// The surface-less sibling of [MorphSurface], for content inside a
/// [MorphPiece]: the skin IS the surface there ("one mass - one
/// shadow"), so this recipe adds only what the glass cannot - button
/// semantics, a click cursor and the tap, with the same
/// context-under-the-tag contract that lets showMorph* omit `from:`.
/// A Material here would paint a second outline that splits from the
/// mass the moment anything deforms it.
class MorphTapTarget extends StatelessWidget {
  /// Creates a tap target for content whose surface the skin draws.
  const MorphTapTarget({
    super.key,
    required this.label,
    this.onTap,
    required this.child,
  });

  /// The button's semantic label.
  final String label;

  /// Receives a context inside the tag's subtree - pass it straight to
  /// showMorph*/showMorphRoute.
  final void Function(BuildContext context)? onTap;

  /// The content the skin's mass sits behind.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext context) => Semantics(
        button: onTap != null,
        label: label,
        // The label IS the semantic content: without the exclusion a
        // text child is announced twice ("Compose. Compose. Button").
        child: ExcludeSemantics(
          child: MouseRegion(
            cursor: onTap == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: .opaque,
              onTap: onTap == null ? null : () => onTap!(context),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Material adapter of the widget layer: renders the visible
/// surface of the nearest [MorphTag] FROM its declared spec
/// (Material + InkWell with the spec's shape), so the button and the
/// flight can never disagree about the surface. The tap handler
/// receives a context UNDER the tag, which is why showMorph* can omit
/// `from:` - the morph flies from the surface the finger is already
/// on.
///
/// An opinion, not the contract: Material + Ink is one design system's
/// answer, and button accessibility is an app-wide decision - fork
/// this if your app renders surfaces differently. The ENGINE's
/// contract ends at MorphTag.specOf; everything below it is
/// replaceable.
class MorphSurface extends StatelessWidget {
  /// Creates a surface for the enclosing tag's spec.
  const MorphSurface({super.key, this.onTap, required this.child});

  /// Receives a context inside the tag's subtree - pass it straight to
  /// showMorph*/showMorphRoute.
  final void Function(BuildContext context)? onTap;

  /// The surface content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext context) {
        final MorphSurfaceSpec spec = MorphTag.specOf(context);
        return Semantics(
          button: onTap != null,
          child: Material(
            shape: spec.shape,
            // The same fallback the flight resolves a null color to:
            // Material's own default (canvas) would pop to the engine's
            // at the first frame of a launch.
            color:
                spec.color ??
                Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: spec.elevation,
            clipBehavior: .antiAlias,
            child: InkWell(
              customBorder: spec.shape,
              onTap: onTap == null ? null : () => onTap!(context),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
