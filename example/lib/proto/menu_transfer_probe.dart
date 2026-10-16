import 'package:flutter/painting.dart';
import 'package:flutter/gestures.dart';
import 'package:morph/motion.dart';
import 'package:morph/glass_painter.dart';

/// The widget responsible for sampling the menu model.
enum ProbeMenuOwnerKind {
  /// The source paints the landing tail.
  source,

  /// A presentation route paints the menu.
  route,
}

/// A unique sampling lease, including distinct instances of the same route role.
final class ProbeMenuLease {
  /// Creates a new owner's identity.
  ProbeMenuLease(this.kind);

  /// The owner's presentation role.
  final ProbeMenuOwnerKind kind;
}

/// The sampled geometry and driven channels used for transfer comparisons.
typedef ProbeMenuFrame = ({
  double time,
  double progress,
  RRect button,
  RRect menu,
  double buttonKick,
  double menuKick,
  double contentOpacity,
  double buttonOpacity,
  double fusionRadius,
});

/// Transfers one complete model by translating each owner's local clock.
class ProbeMenuTransfer {
  /// Adopts [motion] at the source's current local time.
  ProbeMenuTransfer({
    required MorphMenuMotion motion,
    required ProbeMenuLease source,
    required double sourceTime,
  }) : _motion = motion,
       _owner = source,
       _offset = motion.time - sourceTime;

  final MorphMenuMotion _motion;
  ProbeMenuLease _owner;
  double _offset;

  /// The only lease allowed to sample or command the model.
  ProbeMenuLease get owner => _owner;

  /// Cancels the held interaction without removing committed release work.
  bool cancelPointer(ProbeMenuLease lease) {
    if (!identical(lease, _owner)) return false;
    _motion.pointerCancel(_motion.time);
    return true;
  }

  /// Whether this closing frame may pass the landing tail to the source.
  bool get readyToHandBack =>
      _owner.kind == .route && _motion.isClosing && _motion.progress <= 0;

  /// Whether the complete measured model has no remaining work.
  bool get isSettled => _motion.isSettled;

  /// Whether the measured opening has started.
  bool get isOpen => _motion.isOpen;

  /// Whether the model has begun its measured closing.
  bool get isClosing => _motion.isClosing;

  /// Whether an early touch belongs to a pending menu.
  bool get isOpenPending => _motion.isOpenPending;

  /// Whether a source press or delayed opening is still armed.
  bool get isArming => _motion.isArming;

  /// Whether a visible morph, including its closing tail, still exists.
  bool get isPresented => _motion.isPresented;

  /// The carried menu edge under its own fusion law, including the landing tail.
  MorphGlassOutline? get flatOutline => _motion.silhouetteFor(withField: false);

  /// Applies raw input on the active owner's local clock.
  double? pointer(ProbeMenuLease lease, double localTime, PointerEvent event) {
    if (!identical(lease, _owner)) return null;
    final time = localTime + _offset;
    switch (event) {
      case PointerDownEvent():
        _motion.pointerDown(time, event.position);
      case PointerMoveEvent():
        _motion.pointerMove(time, event.position);
      case PointerUpEvent():
        _motion.pointerUp(time, event.position);
      case PointerCancelEvent():
        _motion.pointerCancel(time);
      default:
        return null;
    }
    return time;
  }

  /// A value snapshot; no writable motion reference is exposed.
  ProbeMenuFrame get frame => (
    time: _motion.time,
    progress: _motion.progress,
    button: _motion.buttonBlob.rrect,
    menu: _motion.menuBlob.rrect,
    buttonKick: _motion.buttonKick,
    menuKick: _motion.menuKick,
    contentOpacity: _motion.contentOpacity,
    buttonOpacity: _motion.buttonLookOpacity,
    fusionRadius: _motion.fusionRadius,
  );

  /// Samples the active owner; a callback from an old lease has no effect.
  bool advance(ProbeMenuLease lease, double localTime) {
    if (!identical(lease, _owner)) return false;
    _motion.advance(localTime + _offset);
    return true;
  }

  /// Opens or reverses the current model on its owner's event time.
  bool open(ProbeMenuLease lease, double localTime) {
    if (!identical(lease, _owner)) return false;
    _motion.open(localTime + _offset);
    return true;
  }

  /// Begins closing without replacing any model state.
  bool close(ProbeMenuLease lease, double localTime) {
    if (!identical(lease, _owner)) return false;
    _motion.close(localTime + _offset);
    return true;
  }

  /// Continues the same sampled frame on the next owner's local clock.
  bool transfer(
    ProbeMenuLease from, {
    required double fromTime,
    required ProbeMenuLease to,
    required double toTime,
  }) {
    if (!advance(from, fromTime)) return false;
    if (to.kind == .source && !readyToHandBack) {
      throw StateError('The menu has not reached its landing hand-back');
    }
    _offset = _motion.time - toTime;
    _owner = to;
    return true;
  }
}
