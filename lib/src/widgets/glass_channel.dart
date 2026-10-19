import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/theme/glass.dart';

/// Everything a control hands the glass painter in one frame.
@internal
class MorphGlassFrame {
  /// Describes one frame of [surfaces].
  MorphGlassFrame(
    this.surfaces, {
    this.outline,
    this.contentSlots = const [],
    this.spacing = 0,
    this.still = false,
    this.slotted = false,
  });

  /// Whether nothing of the control moves in this frame: no surface and
  /// no transform between the surfaces and an enclosing glass container.
  final bool still;

  /// Whether the frame belongs to a change that keeps one glass tree
  /// while its surfaces fuse, part, appear and vanish, as UIKit updates
  /// the elements of one SDF layer through a bar's item change.
  ///
  /// A layer host given slotted frames ([morphGlassLayerSlots]) builds a
  /// slot for every surface - a separate shape, or a member of any body the
  /// surfaces can fuse into - and fills the slots from each frame, so its
  /// tree holds while [surfaces] keeps its length. Pad [surfaces] with
  /// invisible ones to hold the length. The pixels are those of the same
  /// frame unslotted; a frame whose surfaces float, glow or frost builds
  /// as an unslotted one.
  final bool slotted;

  /// The surfaces, back to front.
  final List<MorphGlassSurface> surfaces;

  /// The silhouette the control fused its glass surfaces into, if any.
  final MorphGlassOutline? outline;

  /// The boxes of the content's items.
  final List<Rect> contentSlots;

  /// The glass container spacing.
  final double spacing;

  /// The surfaces sorted by how a tier draws them, computed once per frame.
  late final MorphGlassLayerParts parts = MorphGlassLayerParts.of(
    surfaces,
    spacing: spacing,
    outline: outline,
  );

  late final MorphGlassLayerParts _silhouetteParts = MorphGlassLayerParts.of(
    surfaces,
    spacing: spacing,
    outline: outline,
    withField: false,
  );

  late final MorphGlassLayerParts _boxParts = MorphGlassLayerParts.of(
    surfaces,
    spacing: spacing,
    outline: outline,
    boxes: true,
  );

  /// The same bodies with optical samples only when [tier] uses them; on
  /// the liquid tier with analytic geometry, small fused bodies carry their
  /// boxes instead of a fused field.
  MorphGlassLayerParts partsFor(MorphGlassTier tier) => switch (tier) {
    MorphGlassTier.flat => _silhouetteParts,
    MorphGlassTier.liquid when RenderLiquidGlassLayer.analyticGeometryEnabled =>
      _boxParts,
    _ => parts,
  };
}

/// Where a glass tree reads its values: one fixed frame, or a channel
/// whose frame changes every animation tick.
///
/// A tree built from a channel binds its render objects to [live]: every
/// [MorphGlassChannel.push] writes the new values into them, without a
/// widget rebuild. [pick] hands a render object the part of the frame it
/// shows; [keep] lets the builder of the tree return the same widget
/// instance for a slot as long as the tree's structure holds, so a rebuild
/// of the tree around new content leaves the glass untouched.
@internal
abstract class MorphGlassSource {
  /// The frame now.
  MorphGlassFrame get frame;

  /// The notifications of a live source, or null for a fixed frame.
  Listenable? get live;

  /// The value [select] reads from the frame now, recomputed once per
  /// frame.
  ValueListenable<T> pick<T>(T Function(MorphGlassFrame frame) select);

  /// The value built for [slot] while the structure holds.
  T keep<T extends Object>(Object slot, T Function() build);
}

/// A source of one fixed frame: the tree is rebuilt for every new frame,
/// as a painter's per-frame widget path is.
@internal
class MorphMorphFixedSource implements MorphGlassSource {
  /// Holds [frame].
  MorphMorphFixedSource(this.frame);

  @override
  final MorphGlassFrame frame;

  @override
  Listenable? get live => null;

  @override
  ValueListenable<T> pick<T>(T Function(MorphGlassFrame frame) select) =>
      MorphFixed<T>(select(frame));

  @override
  T keep<T extends Object>(Object slot, T Function() build) => build();
}

/// The live source of a glass host: a frame that changes every tick.
@internal
class MorphGlassChannel extends ChangeNotifier implements MorphGlassSource {
  /// Starts with [frame].
  MorphGlassChannel(this._frame);

  MorphGlassFrame _frame;
  int _generation = 0;
  Map<Object, Object> _kept = {};

  @override
  MorphGlassFrame get frame => _frame;

  @override
  Listenable get live => this;

  /// Hands [frame] to every render object bound to the channel.
  void push(MorphGlassFrame frame) {
    _frame = frame;
    _generation++;
    notifyListeners();
  }

  /// Takes [frame] for a tree about to be rebuilt in a new structure: no
  /// notification (the rebuilt tree reads its values while it updates)
  /// and nothing kept from the old structure.
  void reseed(MorphGlassFrame frame) {
    _frame = frame;
    _generation++;
    _kept = {};
  }

  @override
  ValueListenable<T> pick<T>(T Function(MorphGlassFrame frame) select) =>
      _ChannelPick<T>(this, select);

  @override
  T keep<T extends Object>(Object slot, T Function() build) =>
      _kept.putIfAbsent(slot, build) as T;
}

class _ChannelPick<T> implements ValueListenable<T> {
  _ChannelPick(this._channel, this._select);

  final MorphGlassChannel _channel;
  final T Function(MorphGlassFrame frame) _select;
  int _generation = -1;
  late T _value;

  @override
  T get value {
    if (_generation != _channel._generation) {
      _value = _select(_channel._frame);
      _generation = _channel._generation;
    }
    return _value;
  }

  @override
  void addListener(VoidCallback listener) => _channel.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _channel.removeListener(listener);
}

/// A list compared by its elements, for repaint keys.
@internal
@immutable
class MorphListKey<T> {
  /// Wraps [list].
  const MorphListKey(this.list);

  /// The compared list.
  final List<T> list;

  @override
  bool operator ==(Object other) =>
      other is MorphListKey<T> && listEquals(other.list, list);

  @override
  int get hashCode => Object.hashAll(list);
}

/// The repaint notifier of a painter over [data]: null for a fixed value,
/// else a notification whenever the value changes.
@internal
Listenable? morphRepaintOn<T>(
  ValueListenable<T> data, [
  Object? Function()? key,
]) => data is MorphFixed<T>
    ? null
    : MorphChanges<Object?>(data, key ?? () => data.value);

/// Turns the per-frame values of a glass host into widget builds only
/// when the structure of its glass changes.
///
/// While the structure holds (the same surfaces in the same roles, the
/// same lenses lifted, the same tier), a new frame is pushed into a
/// [MorphGlassChannel] and the host keeps the tree it built before; the
/// render objects of that tree follow the channel. A host its parent
/// rebuilds with a new frame pushes it without building at all, and so
/// does a host driven by [frames]. A painter other than
/// [GlassBuiltInPainter] itself is called every frame, as before.
@internal
class MorphGlassHost extends Widget {
  /// Hosts the glass of [mode] for the frames [frame] returns.
  const MorphGlassHost({
    required this.painter,
    required this.mode,
    required this.frame,
    this.frames,
    this.content,
    super.key,
  });

  /// The installed painter.
  final MorphGlassPainter painter;

  /// Which painter entry the host stands for.
  final MorphGlassMode mode;

  /// Returns the frame now; read whenever the host updates.
  final MorphGlassFrame Function() frame;

  /// Notifies when the frame changes; null for a host its parent rebuilds.
  final Listenable? frames;

  /// The control's content over the glass, for [MorphGlassMode.layer].
  final Widget? content;

  @override
  Element createElement() => _MorphGlassHostElement(this);
}

/// Whether every glass host rebuilds its whole tree from the painter on
/// every frame instead of pushing frames into its render objects; the
/// reference the channel is tested against.
@visibleForTesting
@internal
bool debugMorphGlassRebuildEveryFrame = false;

class _MorphGlassHostElement extends ComponentElement {
  _MorphGlassHostElement(MorphGlassHost super.widget);

  MorphGlassHost get _host => widget as MorphGlassHost;

  MorphGlassChannel? _channel;
  Object? _structure;
  GlassBuiltInPainter? _renderer;
  Widget? _tree;
  Widget? _content;
  MorphGlassContainerLink? _container;
  bool? _clearPath;

  // Only a debug override or a build with analytic geometry ever flips
  // which parts the liquid tier draws.
  static const bool _followsAnalytic =
      !kReleaseMode || ShaderKeys.analyticGeometry;

  @override
  void mount(Element? parent, Object? newSlot) {
    _host.frames?.addListener(_framed);
    // A renderer asking for liquid draws flat until the capability
    // resolves, and its == does not see that; a resting host would keep
    // the flat tree until its next frame.
    if (!morphLiquidGlassCapability.value) {
      morphLiquidGlassCapability.addListener(_capabilityResolved);
    }
    if (_followsAnalytic) {
      RenderLiquidGlassLayer.analyticGeometryChanges.addListener(
        markNeedsBuild,
      );
    }
    super.mount(parent, newSlot);
  }

  bool _syncing = false;
  bool _active = true;

  // A frame from a ticker syncs once after every ticker ran, before the
  // frame builds; a frame told in the mid-frame microtasks, where every
  // ticker already ran, syncs at once. Anything else builds, so the frame
  // is read after every listener of the notification ran. An ancestor
  // about to build may hand this host a new frame function, so the host
  // then builds with it instead of reading twice.
  void _framed() {
    if (_syncing || dirty) return;
    switch (SchedulerBinding.instance.schedulerPhase) {
      case SchedulerPhase.transientCallbacks:
        _syncing = true;
        scheduleMicrotask(_sync);
      case SchedulerPhase.midFrameMicrotasks:
        _sync();
      case _:
        markNeedsBuild();
    }
  }

  void _sync() {
    _syncing = false;
    if (!_active || dirty) return;
    var settled = true;
    visitAncestorElements((Element element) => settled = !element.dirty);
    if (!settled || !_push()) markNeedsBuild();
  }

  void _capabilityResolved() {
    if (!morphLiquidGlassCapability.value) return;
    morphLiquidGlassCapability.removeListener(_capabilityResolved);
    markNeedsBuild();
  }

  @override
  void unmount() {
    _active = false;
    _host.frames?.removeListener(_framed);
    morphLiquidGlassCapability.removeListener(_capabilityResolved);
    if (_followsAnalytic) {
      RenderLiquidGlassLayer.analyticGeometryChanges.removeListener(
        markNeedsBuild,
      );
    }
    _container?.release(this);
    super.unmount();
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _clearPath = null;
    _structure = null;
  }

  /// The structure of [frame] drawn by [renderer], with whether the
  /// nearest glass container shades it.
  Object _structureOf(GlassBuiltInPainter renderer, MorphGlassFrame frame) {
    final container = MorphGlassContainerScope.maybeOf(this);
    if (!identical(container, _container)) {
      _container?.release(this);
      _clearPath = null;
    }
    _container = container;
    final joined =
        _host.mode == MorphGlassMode.layer &&
        container != null &&
        (_clearPath ??= morphGlassContainerReaches(this)) &&
        container.admit(this, renderer, frame);
    if (!joined) container?.release(this);
    return (
      renderer.structureOf(_host.mode, frame, content: _host.content != null),
      joined,
    );
  }

  @override
  void update(MorphGlassHost newWidget) {
    final old = _host;
    super.update(newWidget);
    if (!identical(old.frames, newWidget.frames)) {
      old.frames?.removeListener(_framed);
      newWidget.frames?.addListener(_framed);
    }
    if (old.mode != newWidget.mode) _structure = null;
    // A host its frames already marked builds once; a push here would read
    // and push the frame again in the build that follows.
    if (dirty || !_push()) rebuild(force: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _structure = null;
    _clearPath = null;
  }

  /// Pushes the frame into the tree built before when its structure still
  /// holds; false when the tree has to be built.
  bool _push() {
    final channel = _channel;
    final renderer = _renderer;
    if (channel == null ||
        renderer == null ||
        !identical(_host.content, _content) ||
        debugMorphGlassRebuildEveryFrame ||
        _host.painter.runtimeType != GlassBuiltInPainter ||
        renderer != _host.painter) {
      return false;
    }
    final frame = _host.frame();
    if (_structureOf(renderer, frame) != _structure) return false;
    channel.push(frame);
    return true;
  }

  Widget _painted(MorphGlassFrame frame) {
    final painter = _host.painter;
    return switch (_host.mode) {
      MorphGlassMode.layer => painter.buildLayer(
        this,
        frame.surfaces,
        content: _host.content,
        contentSlots: frame.contentSlots,
        spacing: frame.spacing,
        outline: frame.outline,
      ),
      MorphGlassMode.surface => painter.buildSurface(
        this,
        frame.surfaces.single,
      ),
      MorphGlassMode.fill => painter.buildFill(this, frame.surfaces.single),
      MorphGlassMode.body => painter.buildBody(
        this,
        frame.outline!,
        frame.surfaces,
      ),
    };
  }

  @override
  Widget build() {
    final frame = _host.frame();
    final painter = _host.painter;
    if (painter.runtimeType != GlassBuiltInPainter ||
        debugMorphGlassRebuildEveryFrame) {
      _container?.release(this);
      _container = null;
      _channel = null;
      _renderer = null;
      _structure = null;
      return _painted(frame);
    }
    final renderer = painter as GlassBuiltInPainter;
    final content = _host.content;
    final structure = _structureOf(renderer, frame);
    final channel = _channel;
    if (channel == null || renderer != _renderer || structure != _structure) {
      final source = channel ?? MorphGlassChannel(frame);
      if (channel != null) source.reseed(frame);
      _channel = source;
      _renderer = renderer;
      _structure = structure;
      _content = content;
      return _tree = renderer.buildFrom(
        this,
        _host.mode,
        source,
        content: content,
      );
    }
    channel.push(frame);
    if (!identical(content, _content)) {
      _content = content;
      _tree = renderer.buildFrom(this, _host.mode, channel, content: content);
    }
    return _tree!;
  }
}

/// What a glass host draws now, for a debug inspector: null unless
/// [element] is the element of a [MorphGlassHost].
@internal
({
  MorphGlassMode mode,
  MorphGlassPainter painter,
  MorphGlassFrame frame,
  bool joined,
})?
debugMorphGlassHostOf(Element element) {
  if (element is! _MorphGlassHostElement || !element.mounted) return null;
  final host = element._host;
  return (
    mode: host.mode,
    painter: host.painter,
    frame: host.frame(),
    joined: element._container?.holds(element) ?? false,
  );
}

/// The painter entry a [MorphGlassHost] stands for.
@internal
enum MorphGlassMode {
  /// [MorphGlassPainter.buildLayer].
  layer,

  /// [MorphGlassPainter.buildSurface].
  surface,

  /// [MorphGlassPainter.buildFill].
  fill,

  /// [MorphGlassPainter.buildBody].
  body,
}
