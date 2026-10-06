import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

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
  });

  /// Whether nothing of the control moves in this frame: no surface and
  /// no transform between the surfaces and an enclosing glass container.
  final bool still;

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
class MorphGlassFixedSource implements MorphGlassSource {
  /// Holds [frame].
  MorphGlassFixedSource(this.frame);

  @override
  final MorphGlassFrame frame;

  @override
  Listenable? get live => null;

  @override
  ValueListenable<T> pick<T>(T Function(MorphGlassFrame frame) select) =>
      GlassFixed<T>(select(frame));

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
]) => data is GlassFixed<T>
    ? null
    : GlassChanges<Object?>(data, key ?? () => data.value);

/// A [Stack] whose [MorphLivePositioned] children follow a live source.
///
/// Every notification of [live] reads the boxes of the live children
/// again and lays the stack out when one moved, as a rebuild with new
/// `Positioned.fromRect` children would; no widget rebuilds.
@internal
class MorphLiveStack extends Stack {
  /// Stacks [children], without clipping them.
  const MorphLiveStack({
    required this.live,
    super.children,
    super.clipBehavior = Clip.none,
    super.key,
  });

  /// The source the live children's boxes follow, or null for fixed boxes.
  final Listenable? live;

  @override
  RenderStack createRenderObject(BuildContext context) {
    final stack = _RenderLiveStack(
      alignment: alignment,
      textDirection: textDirection ?? Directionality.maybeOf(context),
      fit: fit,
      clipBehavior: clipBehavior,
    );
    stack.bindLive(live, stack.follow, now: false);
    return stack;
  }

  @override
  void updateRenderObject(BuildContext context, RenderStack renderObject) {
    super.updateRenderObject(context, renderObject);
    final stack = renderObject as _RenderLiveStack;
    stack.bindLive(live, stack.follow, now: false);
  }
}

/// Places a child of a [MorphLiveStack] at a box that follows the stack's
/// source, as `Positioned.fromRect` places it at a fixed one.
@internal
class MorphLivePositioned extends ParentDataWidget<StackParentData> {
  /// Places [child] at [rect].
  const MorphLivePositioned({
    required this.rect,
    required super.child,
    super.key,
  });

  /// The box of the child in the stack's coordinates.
  final ValueListenable<Rect> rect;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _LiveStackParentData;
    data.live = rect;
    if (data.place(rect.value)) {
      final stack = renderObject.parent;
      if (stack is RenderObject) stack.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => MorphLiveStack;
}

class _LiveStackParentData extends StackParentData {
  ValueListenable<Rect>? live;

  bool place(Rect value) {
    if (left == value.left &&
        top == value.top &&
        width == value.width &&
        height == value.height &&
        right == null &&
        bottom == null) {
      return false;
    }
    left = value.left;
    top = value.top;
    width = value.width;
    height = value.height;
    right = null;
    bottom = null;
    return true;
  }
}

class _RenderLiveStack extends RenderStack with GlassLiveBinding {
  _RenderLiveStack({
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
  });

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LiveStackParentData) {
      child.parentData = _LiveStackParentData();
    }
  }

  void follow() {
    var moved = false;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _LiveStackParentData;
      final rect = data.live;
      if (rect != null && data.place(rect.value)) moved = true;
      child = data.nextSibling;
    }
    if (moved) markNeedsLayout();
  }
}

/// A [DecoratedBox] whose decoration follows a live source.
@internal
class MorphLiveDecoratedBox extends DecoratedBox {
  /// Paints [live]'s decoration behind [child].
  MorphLiveDecoratedBox({required this.live, super.child, super.key})
    : super(decoration: live.value);

  /// The decoration now.
  final ValueListenable<Decoration> live;

  @override
  Decoration get decoration => live.value;

  @override
  RenderDecoratedBox createRenderObject(BuildContext context) {
    final box = _RenderLiveDecoratedBox(
      decoration: live.value,
      configuration: createLocalImageConfiguration(context),
    );
    box.bindLive(
      live is GlassFixed<Decoration> ? null : live,
      () => box.decoration = live.value,
    );
    return box;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderDecoratedBox renderObject,
  ) {
    renderObject.configuration = createLocalImageConfiguration(context);
    renderObject.position = position;
    (renderObject as _RenderLiveDecoratedBox).bindLive(
      live is GlassFixed<Decoration> ? null : live,
      () => renderObject.decoration = live.value,
    );
  }
}

class _RenderLiveDecoratedBox extends RenderDecoratedBox with GlassLiveBinding {
  _RenderLiveDecoratedBox({required super.decoration, super.configuration});
}

/// A [ColoredBox] whose color follows a live source.
@internal
class MorphLiveColoredBox extends SingleChildRenderObjectWidget {
  /// Fills its box with [color].
  const MorphLiveColoredBox({required this.color, super.child, super.key});

  /// The color now.
  final ValueListenable<Color> color;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveColoredBox(color.value);
    box.bindLive(
      color is GlassFixed<Color> ? null : color,
      () => box.color = color.value,
    );
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveColoredBox;
    box.bindLive(
      color is GlassFixed<Color> ? null : color,
      () => box.color = color.value,
    );
  }
}

class _RenderLiveColoredBox extends RenderProxyBoxWithHitTestBehavior
    with GlassLiveBinding {
  _RenderLiveColoredBox(this._color) : super(behavior: HitTestBehavior.opaque);

  Color _color;

  Color get color => _color;

  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size > Size.zero) {
      final paint = Paint();
      paint.isAntiAlias = true;
      paint.color = _color;
      context.canvas.drawRect(offset & size, paint);
    }
    final child = this.child;
    if (child != null) context.paintChild(child, offset);
  }
}

/// Turns the per-frame values of a glass host into widget builds only
/// when the structure of its glass changes.
///
/// While the structure holds (the same surfaces in the same roles, the
/// same lenses lifted, the same tier), a new frame is pushed into a
/// [MorphGlassChannel] and the host keeps the tree it built before; the
/// render objects of that tree follow the channel. A host its parent
/// rebuilds with a new frame pushes it without building at all; a host
/// driven by [frames] builds once per frame, as a `ListenableBuilder`
/// does, and returns the same tree. A painter other than
/// [MorphGlassRenderer] itself is called every frame, as before.
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
  MorphGlassRenderer? _renderer;
  Widget? _tree;
  Widget? _content;
  MorphGlassContainerLink? _container;
  bool? _clearPath;

  @override
  void mount(Element? parent, Object? newSlot) {
    _host.frames?.addListener(markNeedsBuild);
    super.mount(parent, newSlot);
  }

  @override
  void unmount() {
    _host.frames?.removeListener(markNeedsBuild);
    _container?.release(this);
    super.unmount();
  }

  @override
  void activate() {
    super.activate();
    _clearPath = null;
    _structure = null;
  }

  /// The structure of [frame] drawn by [renderer], with whether the
  /// nearest glass container shades it.
  Object _structureOf(MorphGlassRenderer renderer, MorphGlassFrame frame) {
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
      old.frames?.removeListener(markNeedsBuild);
      newWidget.frames?.addListener(markNeedsBuild);
    }
    if (old.mode != newWidget.mode) _structure = null;
    if (!_push()) rebuild(force: true);
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
        _host.painter.runtimeType != MorphGlassRenderer ||
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
    if (painter.runtimeType != MorphGlassRenderer ||
        debugMorphGlassRebuildEveryFrame) {
      _container?.release(this);
      _container = null;
      _channel = null;
      _renderer = null;
      _structure = null;
      return _painted(frame);
    }
    final renderer = painter as MorphGlassRenderer;
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
