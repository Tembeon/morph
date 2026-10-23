import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Controls one menu source or context-menu region without exposing its flight.
///
/// Attach to exactly one live source. [isOpen] covers the visible
/// presentation, including its close animation; [closed] completes only
/// when that presentation has left the overlay. A row's selection callback
/// runs before this completion, so await [closed] before navigating from
/// an action that must wait for dismissal. The controller owns no widget
/// state.
class MorphMenuPresentationController extends ChangeNotifier {
  /// Creates an unattached controller.
  MorphMenuPresentationController();

  Object? _owner;
  VoidCallback? _open;
  VoidCallback? _close;
  Future<void> _closed = Future<void>.value();
  bool _isOpen = false;
  bool _disposed = false;
  bool _pending = false;
  int _session = 0;

  /// Whether a presentation is in the overlay, including while it closes.
  bool get isOpen => _isOpen;

  /// Completes after the current presentation leaves; already complete idle.
  Future<void> get closed => _closed;

  /// Opens the enabled attached source; an open or detached source is inert.
  void open() {
    if (!_isOpen) _open?.call();
  }

  /// Starts dismissal; await [closed] to observe its completed animation.
  void close() => _close?.call();

  /// Attaches the input doors of one live source.
  @internal
  void attach(
    Object owner, {
    required VoidCallback open,
    required VoidCallback close,
  }) {
    assert(
      _owner == null || identical(_owner, owner),
      'A menu controller has one live source.',
    );
    _owner = owner;
    _open = open;
    _close = close;
  }

  /// Forgets a removed source; its in-flight completion remains observable.
  @internal
  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _open = null;
    _close = null;
  }

  /// Follows one presentation through source removal and completed dismissal.
  @internal
  void presented(Future<Object?> completion) {
    final session = ++_session;
    _isOpen = true;
    _closed = completion.then<void>((_) {
      if (_disposed || session != _session) return;
      _isOpen = false;
      _changed();
    });
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _open = null;
    _close = null;
    super.dispose();
  }
}
