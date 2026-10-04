import 'package:flutter/widgets.dart';

/// Marks a container whose chrome sits above its own navigator, so that
/// what is presented from inside it goes to the world around it.
///
/// A navigation stack draws its bars over its navigator; a menu, a
/// context menu, a dialog or a sheet presented from a page in that
/// navigator would land in the navigator's own overlay, UNDER the bars.
/// UIKit presents them above everything the presenting controller sits
/// in. A boundary makes [morphPresentationOverlayOf] and
/// [morphPresentationNavigatorOf] skip past the container: they return
/// the overlay and navigator around the OUTERMOST boundary above the
/// context, so the presentation covers the bars of every stack it is
/// nested in and still stays inside an enclosing navigator that is not
/// a boundary (a tab, an embedded device mockup).
///
/// `MorphNavigationStack` installs one around itself. Wrap your own
/// chrome-over-navigator shell in one to get the same default; an
/// explicit `overlay:` or `useRootNavigator:` on a presenter still wins.
class MorphPresentationBoundary extends InheritedWidget {
  /// Creates a boundary around [child].
  const MorphPresentationBoundary({required super.child, super.key});

  @override
  bool updateShouldNotify(MorphPresentationBoundary oldWidget) => false;
}

Element? _outermostBoundary(BuildContext context) {
  Element? found = context
      .getElementForInheritedWidgetOfExactType<MorphPresentationBoundary>();
  while (found != null) {
    Element? parent;
    found.visitAncestorElements((Element element) {
      parent = element;
      return false;
    });
    final Element? outer = parent
        ?.getElementForInheritedWidgetOfExactType<MorphPresentationBoundary>();
    if (outer == null) return found;
    found = outer;
  }
  return null;
}

/// The overlay a presentation from [context] renders in: the one around
/// the outermost [MorphPresentationBoundary] above [context], else the
/// nearest overlay; null when there is none.
///
/// Every morph presenter (`showMorph*`, `MorphAnchor`, the menu button,
/// the context menu) uses it when no explicit overlay is passed, and
/// [morphAnchorRect] measures in it by default, so a flight and its
/// anchors share one coordinate space.
OverlayState? morphPresentationOverlayOf(BuildContext context) {
  final Element? boundary = _outermostBoundary(context);
  if (boundary != null) {
    final OverlayState? outer = Overlay.maybeOf(boundary);
    if (outer != null) return outer;
  }
  return Overlay.maybeOf(context);
}

/// The navigator a presented route from [context] is pushed on: the one
/// around the outermost [MorphPresentationBoundary] above [context],
/// else the nearest navigator; null when there is none.
NavigatorState? morphPresentationNavigatorOf(BuildContext context) {
  final Element? boundary = _outermostBoundary(context);
  if (boundary != null) {
    final NavigatorState? outer = Navigator.maybeOf(boundary);
    if (outer != null) return outer;
  }
  return Navigator.maybeOf(context);
}
