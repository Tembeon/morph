import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A render object whose properties follow a live source.
///
/// [bindLive] installs the source and the callback that writes the
/// source's current values into the render object's setters; the callback
/// runs at once, on every notification of the source while the render
/// object is attached, and again when it attaches. The setters decide what
/// a change costs (a paint, a layout, nothing when the value is equal), so
/// a source that notifies every frame never rebuilds a widget.
///
/// Sources notify during the build phase only, where a render object may
/// mark itself dirty.
@internal
mixin GlassLiveBinding on RenderObject {
  Listenable? _liveSource;
  VoidCallback? _liveApply;

  /// Follows [source], writing its values through [apply], at once unless
  /// [now] is false.
  void bindLive(Listenable? source, VoidCallback apply, {bool now = true}) {
    if (!identical(source, _liveSource)) {
      if (attached) {
        _liveSource?.removeListener(_onLive);
        source?.addListener(_onLive);
      }
      _liveSource = source;
    }
    _liveApply = apply;
    if (now) apply();
  }

  void _onLive() => _liveApply?.call();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _liveSource?.addListener(_onLive);
    _liveApply?.call();
  }

  @override
  void detach() {
    _liveSource?.removeListener(_onLive);
    super.detach();
  }
}

/// A value that never changes and never notifies.
@internal
class GlassFixed<T> implements ValueListenable<T> {
  /// Holds [value].
  const GlassFixed(this.value);

  @override
  final T value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Notifies its listeners when the key [of] reads from [source] changes.
///
/// It listens to [source] only while it has listeners itself, so a
/// clipper or painter holding it costs nothing once its render object
/// detaches.
@internal
class GlassChanges<K> implements Listenable {
  /// Watches [of] over the notifications of [source].
  GlassChanges(this.source, this.of);

  /// The source that may change the key.
  final Listenable source;

  /// The key; a notification whose key equals the last one is dropped.
  final K Function() of;

  final List<VoidCallback> _listeners = [];
  K? _last;

  void _changed() {
    final key = of();
    if (key == _last) return;
    _last = key;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.isEmpty) {
      _last = of();
      source.addListener(_changed);
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) source.removeListener(_changed);
  }
}

/// An [Opacity] whose opacity follows a live source.
@internal
class GlassLiveOpacity extends SingleChildRenderObjectWidget {
  /// Fades [child] by [opacity], read again on every notification of
  /// [live].
  const GlassLiveOpacity({
    required this.live,
    required this.opacityOf,
    super.child,
    super.key,
  });

  /// The source of the opacity, or null for a fixed one.
  final Listenable? live;

  /// The opacity now, 0 to 1.
  final double Function() opacityOf;

  /// The opacity now.
  double get opacity => opacityOf();

  @override
  RenderOpacity createRenderObject(BuildContext context) {
    final opacity = _RenderLiveOpacity(opacity: opacityOf());
    opacity.bindLive(live, () => opacity.opacity = opacityOf());
    return opacity;
  }

  @override
  void updateRenderObject(BuildContext context, RenderOpacity renderObject) {
    (renderObject as _RenderLiveOpacity).bindLive(
      live,
      () => renderObject.opacity = opacityOf(),
    );
  }
}

class _RenderLiveOpacity extends RenderOpacity with GlassLiveBinding {
  _RenderLiveOpacity({super.opacity});
}

/// A [Transform] whose matrix follows a live source.
@internal
class GlassLiveTransform extends SingleChildRenderObjectWidget {
  /// Transforms [child] about its center by the matrix [writeInto] fills,
  /// read again on every notification of [live].
  const GlassLiveTransform({
    required this.live,
    required void Function(Matrix4 into) this.writeInto,
    super.child,
    super.key,
  }) : writeSizedInto = null;

  /// Transforms [child] about its center by the matrix [writeSizedInto]
  /// fills from the child's laid-out size, read again on every
  /// notification of [live] and whenever that size changes.
  const GlassLiveTransform.sized({
    required this.live,
    required void Function(Matrix4 into, Size size) this.writeSizedInto,
    super.child,
    super.key,
  }) : writeInto = null;

  /// The source of the matrix, or null for a fixed one.
  final Listenable? live;

  /// Writes the current matrix into the identity matrix it is given.
  final void Function(Matrix4 into)? writeInto;

  /// Writes the current matrix for a child of the given size into the
  /// identity matrix it is given.
  final void Function(Matrix4 into, Size size)? writeSizedInto;

  @override
  RenderTransform createRenderObject(BuildContext context) {
    final render = _RenderLiveTransform();
    render.bind(live, writeInto, writeSizedInto);
    return render;
  }

  @override
  void updateRenderObject(BuildContext context, RenderTransform renderObject) {
    (renderObject as _RenderLiveTransform).bind(
      live,
      writeInto,
      writeSizedInto,
    );
  }
}

class _RenderLiveTransform extends RenderTransform with GlassLiveBinding {
  _RenderLiveTransform()
    : super(transform: Matrix4.identity(), alignment: Alignment.center);

  final Matrix4 _scratch = Matrix4.identity();
  void Function(Matrix4 into, Size size)? _sized;
  Size? _writtenFor;

  void bind(
    Listenable? live,
    void Function(Matrix4 into)? writeInto,
    void Function(Matrix4 into, Size size)? writeSizedInto,
  ) {
    _sized = writeSizedInto;
    bindLive(live, () {
      _scratch.setIdentity();
      if (writeSizedInto != null) {
        final size = hasSize ? this.size : Size.zero;
        _writtenFor = size;
        writeSizedInto(_scratch, size);
      } else {
        writeInto?.call(_scratch);
      }
      transform = _scratch;
    });
  }

  @override
  void performLayout() {
    super.performLayout();
    final sized = _sized;
    if (sized == null || size == _writtenFor) return;
    _writtenFor = size;
    _scratch.setIdentity();
    sized(_scratch, size);
    transform = _scratch;
  }
}

/// A clipper computed from a live source, reclipping only when its key
/// changes.
@internal
class GlassLiveClipper<T> extends CustomClipper<T> {
  /// Clips to [clipOf], reclipping when [keyOf] over [live] changes.
  GlassLiveClipper({
    required Listenable live,
    required Object? Function() keyOf,
    required this.clipOf,
  }) : super(reclip: GlassChanges<Object?>(live, keyOf));

  /// The clip for a box of the given size.
  final T Function(Size size) clipOf;

  @override
  T getClip(Size size) => clipOf(size);

  @override
  bool shouldReclip(GlassLiveClipper<T> oldClipper) =>
      !identical(oldClipper, this);
}

/// A [BackdropFilter] whose filter follows a live source.
@internal
class GlassLiveBackdropFilter extends BackdropFilter {
  /// Filters the backdrop by [filterOf], read again on every notification
  /// of [live].
  GlassLiveBackdropFilter({
    required this.live,
    required this.filterOf,
    super.backdropGroupKey,
    super.child,
    super.key,
  }) : super(filter: filterOf());

  /// The source of the filter.
  final Listenable? live;

  /// The filter now.
  final ui.ImageFilter Function() filterOf;

  @override
  ui.ImageFilter get filter => filterOf();

  @override
  RenderBackdropFilter createRenderObject(BuildContext context) {
    final filter = _RenderLiveBackdropFilter(
      filterConfig: ImageFilterConfig(filterOf()),
      backdropKey: backdropGroupKey,
    );
    filter.bindLive(live, () => filter.filter = filterOf());
    return filter;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBackdropFilter renderObject,
  ) {
    renderObject.enabled = enabled;
    renderObject.blendMode = blendMode;
    renderObject.backdropKey = backdropGroupKey;
    (renderObject as _RenderLiveBackdropFilter).bindLive(
      live,
      () => renderObject.filter = filterOf(),
    );
  }
}

class _RenderLiveBackdropFilter extends RenderBackdropFilter
    with GlassLiveBinding {
  _RenderLiveBackdropFilter({required super.filterConfig, super.backdropKey});
}

/// A [ClipRRect] whose border radius follows a live source.
@internal
class GlassLiveClipRRect extends SingleChildRenderObjectWidget {
  /// Clips [child] to [borderRadiusOf], read again on every notification
  /// of [live].
  const GlassLiveClipRRect({
    required this.live,
    required this.borderRadiusOf,
    this.clipBehavior = Clip.antiAlias,
    super.child,
    super.key,
  });

  /// The source of the radius.
  final Listenable? live;

  /// The border radius now.
  final BorderRadiusGeometry Function() borderRadiusOf;

  /// How the clip is antialiased.
  final Clip clipBehavior;

  @override
  RenderClipRRect createRenderObject(BuildContext context) {
    final clip = _RenderLiveClipRRect(
      borderRadius: borderRadiusOf(),
      clipBehavior: clipBehavior,
      textDirection: Directionality.maybeOf(context),
    );
    clip.bindLive(live, () => clip.borderRadius = borderRadiusOf());
    return clip;
  }

  @override
  void updateRenderObject(BuildContext context, RenderClipRRect renderObject) {
    renderObject.clipBehavior = clipBehavior;
    renderObject.textDirection = Directionality.maybeOf(context);
    (renderObject as _RenderLiveClipRRect).bindLive(
      live,
      () => renderObject.borderRadius = borderRadiusOf(),
    );
  }
}

class _RenderLiveClipRRect extends RenderClipRRect with GlassLiveBinding {
  _RenderLiveClipRRect({
    super.borderRadius,
    super.clipBehavior,
    super.textDirection,
  });
}

/// A [ClipRSuperellipse] whose border radius follows a live source.
@internal
class GlassLiveClipRSuperellipse extends SingleChildRenderObjectWidget {
  /// Clips [child] to [borderRadiusOf], read again on every notification
  /// of [live].
  const GlassLiveClipRSuperellipse({
    required this.live,
    required this.borderRadiusOf,
    this.clipBehavior = Clip.antiAlias,
    super.child,
    super.key,
  });

  /// The source of the radius.
  final Listenable? live;

  /// The border radius now.
  final BorderRadiusGeometry Function() borderRadiusOf;

  /// How the clip is antialiased.
  final Clip clipBehavior;

  @override
  RenderClipRSuperellipse createRenderObject(BuildContext context) {
    final clip = _RenderLiveClipRSuperellipse(
      borderRadius: borderRadiusOf(),
      clipBehavior: clipBehavior,
      textDirection: Directionality.maybeOf(context),
    );
    clip.bindLive(live, () => clip.borderRadius = borderRadiusOf());
    return clip;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderClipRSuperellipse renderObject,
  ) {
    renderObject.clipBehavior = clipBehavior;
    renderObject.textDirection = Directionality.maybeOf(context);
    (renderObject as _RenderLiveClipRSuperellipse).bindLive(
      live,
      () => renderObject.borderRadius = borderRadiusOf(),
    );
  }
}

class _RenderLiveClipRSuperellipse extends RenderClipRSuperellipse
    with GlassLiveBinding {
  _RenderLiveClipRSuperellipse({
    super.borderRadius,
    super.clipBehavior,
    super.textDirection,
  });
}
