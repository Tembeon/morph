import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The backdrop copy the bars below it share.
///
/// A screen's navigation bar and toolbar float over the same page, so one
/// copy taken when the first of them paints serves both.
@internal
class MorphChromeBackdropScope extends InheritedWidget {
  /// Shares [backdropKey] among the bars in [child].
  const MorphChromeBackdropScope({
    required this.backdropKey,
    required super.child,
    super.key,
  });

  /// The key of the bars' backdrop copy.
  final BackdropKey backdropKey;

  /// The key of the nearest scope above [context], or null.
  static BackdropKey? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MorphChromeBackdropScope>()
      ?.backdropKey;

  @override
  bool updateShouldNotify(MorphChromeBackdropScope oldWidget) =>
      oldWidget.backdropKey != backdropKey;
}

/// Puts the glass in [child], which floats over the page (a bar, a
/// sheet's content), in a backdrop group of its own: the key of the
/// nearest [MorphChromeBackdropScope], else one of its own.
///
/// Glass in one group does not read the backdrop at its own place in
/// paint order but a copy Impeller took earlier, so glass painted over
/// the page in the page's group misses what was painted after that copy.
@internal
class MorphChromeBackdrop extends StatefulWidget {
  /// Groups the glass in [child].
  const MorphChromeBackdrop({required this.child, super.key});

  /// The floating content.
  final Widget child;

  @override
  State<MorphChromeBackdrop> createState() => _MorphChromeBackdropState();
}

class _MorphChromeBackdropState extends State<MorphChromeBackdrop> {
  final BackdropKey _own = BackdropKey();

  @override
  Widget build(BuildContext context) => BackdropGroup(
    backdropKey: MorphChromeBackdropScope.maybeOf(context) ?? _own,
    child: widget.child,
  );
}
