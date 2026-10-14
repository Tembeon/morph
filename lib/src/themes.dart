import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The nearest [InheritedTheme] of each kind above [from], up to (not
/// including) [to], nearest first.
///
/// When [to] is not an ancestor of [from] the walk runs to the root.
@internal
List<InheritedTheme> morphCaptureThemes(BuildContext from, {BuildContext? to}) {
  final themes = <InheritedTheme>[];
  if (identical(from, to)) return themes;
  final kinds = <Type>{};
  from.visitAncestorElements((Element ancestor) {
    if (identical(ancestor, to)) return false;
    if (ancestor is InheritedElement) {
      final widget = ancestor.widget;
      if (widget is InheritedTheme && kinds.add(widget.runtimeType)) {
        themes.add(widget);
      }
    }
    return true;
  });
  return themes;
}

/// Makes [from] depend on the themes [morphCaptureThemes] captures for
/// the same arguments, so it is told when one of them changes.
@internal
void morphDependOnThemes(BuildContext from, {BuildContext? to}) {
  if (identical(from, to)) return;
  final kinds = <Type>{};
  from.visitAncestorElements((Element ancestor) {
    if (identical(ancestor, to)) return false;
    if (ancestor is InheritedElement) {
      final widget = ancestor.widget;
      if (widget is InheritedTheme && kinds.add(widget.runtimeType)) {
        from.dependOnInheritedElement(ancestor);
      }
    }
    return true;
  });
}

/// The inherited themes of a source context, carried into an overlay or
/// a route that does not sit below that context.
///
/// A surface presented from a source draws with the source's themes, the
/// way Flutter's popup routes draw with the themes of the context that
/// showed them. The kinds of themes carried are fixed when the carrier is
/// created: a later capture that finds other kinds is ignored, so the
/// subtree under [wrap] never changes shape and keeps its state. Once the
/// source is gone the last capture stays.
@internal
class MorphThemeCarrier extends ChangeNotifier {
  /// Captures the themes above [source], up to [to] when [to] is an
  /// ancestor of [source].
  MorphThemeCarrier(BuildContext source, {BuildContext? to})
    : _source = source,
      _to = to,
      _themes = morphCaptureThemes(source, to: to),
      _text = _textOf(source);

  static DefaultTextStyle _textOf(BuildContext source) =>
      source.getInheritedWidgetOfExactType<DefaultTextStyle>() ??
      const DefaultTextStyle.fallback();

  BuildContext _source;
  final BuildContext? _to;
  List<InheritedTheme> _themes;
  Widget? _child;
  Widget? _wrapped;
  DefaultTextStyle _text;

  /// The source's own default text style, wherever it is set: a copy of
  /// the source drawn under a Material, which sets the theme's body style,
  /// draws in it again through [wrapText].
  DefaultTextStyle get textStyle => _text;

  /// The themes carried, nearest to the source first.
  List<InheritedTheme> get themes => _themes;

  /// Captures again from [source], or from the last source when null,
  /// and reports whether the carried themes changed.
  ///
  /// The caller makes sure the source is in the active tree.
  bool recapture([BuildContext? source]) {
    final from = source ?? _source;
    final text = _textOf(from);
    final textChanged = !identical(text, _text);
    _text = text;
    final next = morphCaptureThemes(from, to: _to);
    if (next.length != _themes.length) return textChanged;
    var changed = false;
    for (var i = 0; i < next.length; i++) {
      if (next[i].runtimeType != _themes[i].runtimeType) return textChanged;
      if (!identical(next[i], _themes[i])) changed = true;
    }
    _source = from;
    if (!changed) return textChanged;
    _themes = next;
    _wrapped = null;
    return true;
  }

  /// [recapture]s and notifies the listeners when the themes changed.
  void refresh([BuildContext? source]) {
    if (recapture(source)) notifyListeners();
  }

  /// [child] below the carried themes.
  ///
  /// The same [child] under the same themes gives the same widget, so a
  /// per-frame caller does not rebuild the themes.
  Widget wrap(Widget child) {
    if (_themes.isEmpty) return child;
    final wrapped = _wrapped;
    if (wrapped != null && identical(child, _child)) return wrapped;
    _child = child;
    return _wrapped = _CarriedThemes(themes: _themes, child: child);
  }

  /// [child], a copy of the source, in the source's own default text
  /// style ([textStyle]), whatever sets another one above it.
  Widget wrapText(Widget child) {
    final text = _text;
    return DefaultTextStyle(
      style: text.style,
      textAlign: text.textAlign,
      softWrap: text.softWrap,
      overflow: text.overflow,
      maxLines: text.maxLines,
      textWidthBasis: text.textWidthBasis,
      textHeightBehavior: text.textHeightBehavior,
      child: child,
    );
  }

  /// [recapture]s from the source while it is mounted, then [wrap]s
  /// [child]: for a route that rebuilds its page now and then.
  Widget install(Widget child) {
    if (_source.mounted) recapture();
    return wrap(child);
  }
}

class _CarriedThemes extends StatelessWidget {
  const _CarriedThemes({required this.themes, required this.child});

  final List<InheritedTheme> themes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var wrapped = child;
    for (final theme in themes) {
      wrapped = theme.wrap(context, wrapped);
    }
    return wrapped;
  }
}
