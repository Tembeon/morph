import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// A page that previews its pop under the system back gesture, as Android
/// 14 predictive back drives it.
///
/// The gesture drives the page's own interactive pop: its progress stands
/// in for the finger's fraction of the page width that the iOS edge swipe
/// follows (an approximation: iOS has no predictive back to measure). A
/// commit pops the page from where the preview left it, a cancel returns
/// it on the same spring as a released swipe.
@internal
abstract interface class MorphBackPreview {
  /// A context inside the page, under the page's own navigator.
  BuildContext get context;

  /// Whether the page is the one a back gesture pops now: current in its
  /// navigator, poppable, not already being dragged.
  bool get acceptsBackPreview;

  /// The gesture started.
  void startBackPreview(PredictiveBackEvent event);

  /// The gesture moved.
  void updateBackPreview(PredictiveBackEvent event);

  /// The gesture ended past the system's threshold: pop.
  void commitBackPreview();

  /// The gesture ended short of it: stay.
  void cancelBackPreview();
}

/// Registers [page] while it is mounted; the one observer routes each
/// system back gesture to the page on top of every navigator.
@internal
void morphAddBackPreview(MorphBackPreview page) =>
    _MorphPredictiveBack.instance.add(page);

/// Removes [page] from the back gesture.
@internal
void morphRemoveBackPreview(MorphBackPreview page) =>
    _MorphPredictiveBack.instance.remove(page);

class _MorphPredictiveBack with WidgetsBindingObserver {
  _MorphPredictiveBack._();

  static final instance = _MorphPredictiveBack._();

  final List<MorphBackPreview> _pages = [];
  MorphBackPreview? _active;

  void add(MorphBackPreview page) {
    if (_pages.isEmpty) WidgetsBinding.instance.addObserver(this);
    _pages.add(page);
  }

  void remove(MorphBackPreview page) {
    _pages.remove(page);
    if (identical(_active, page)) _active = null;
    if (_pages.isEmpty) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    _active = null;
    if (backEvent.isButtonEvent) return false;
    for (final page in _pages.reversed) {
      if (!page.context.mounted || !page.acceptsBackPreview) continue;
      if (!_onTop(page.context)) continue;
      _active = page;
      page.startBackPreview(backEvent);
      return true;
    }
    return false;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) =>
      _active?.updateBackPreview(backEvent);

  @override
  void handleCommitBackGesture() {
    final page = _active;
    _active = null;
    page?.commitBackPreview();
  }

  @override
  void handleCancelBackGesture() {
    final page = _active;
    _active = null;
    page?.cancelBackPreview();
  }

  /// Whether every route around [context], up to the root navigator, is
  /// current: a page in a nested navigator under a sheet or a page of the
  /// root navigator is not the one back pops.
  static bool _onTop(BuildContext context) {
    BuildContext? inner = context;
    while (inner != null) {
      if (ModalRoute.isCurrentOf(inner) == false) return false;
      inner = inner.findAncestorStateOfType<NavigatorState>()?.context;
    }
    return true;
  }
}
