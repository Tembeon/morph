import 'package:flutter/material.dart';

import 'package:morph/morph.dart';

/// A recipe, deliberately not package API - copy it into your app and
/// standardize it there.
///
/// Renders the visible surface of the nearest [MorphTag] FROM its
/// declared spec (Material + InkWell with the spec's shape), so the
/// button and the flight can never disagree about the surface. The tap
/// handler receives a context UNDER the tag, which is why showMorph*
/// can omit `from:` - the morph flies from the surface the finger is
/// already on.
///
/// Why this is example code and not a library widget: Material + Ink
/// is one design system's answer (a Cupertino or custom-canvas app
/// renders its surfaces differently), and button accessibility is an
/// app-wide decision - this recipe adds `Semantics(button:)`, but your
/// app may want labels, traversal order or platform-specific
/// affordances the library cannot guess. The engine's contract ends at
/// MorphTag.specOf; everything below it is yours.
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
            color: spec.color,
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
