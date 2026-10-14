import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
/// Sources notify outside layout and paint (from a ticker, the mid-frame
/// microtasks or a build), where a render object may mark itself dirty.
@internal
mixin MorphLiveBinding on RenderObject {
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

/// Syncs a widget with its motion once per frame, after every ticker of
/// the frame ran, and builds the widget only when the structure its tree
/// is built from changes.
///
/// A notification of the source it [follow]s reads [structure] in the
/// frame's mid-frame microtasks, where every ticker has advanced its
/// motion and nothing has built yet: a notification from a ticker, a
/// gesture or a build queues the read as one microtask, a notification
/// during the mid-frame microtasks (another sync, a flight handing back
/// its source) reads at once. A notification between frames also asks
/// for a frame, as a setState does. A structure that differs from the
/// built one goes to [rebuild]; otherwise this notifies its listeners,
/// the live render objects that follow the motion without a build. With
/// [notifiesOnRebuild] it notifies them on a rebuilding frame too, for
/// listeners that sit outside the subtree the rebuild builds.
///
/// The build reads its structure through [read], which records it as
/// the built one. Before the first build the built structure counts as
/// null.
@internal
class MorphFrameSync<S> extends ChangeNotifier {
  /// Reads [structure] on every frame and hands a changed one to
  /// [rebuild].
  MorphFrameSync({
    required this.structure,
    required this.rebuild,
    this.same,
    this.notifiesOnRebuild = false,
  });

  /// Reads the motion's frame and returns the structure it shows.
  final S Function() structure;

  /// Builds the widget for a structure that differs from the built one.
  final void Function(S structure) rebuild;

  /// Whether two structures build the same tree; `==` when null.
  final bool Function(S a, S b)? same;

  /// Whether the listeners hear a frame that rebuilds as well.
  final bool notifiesOnRebuild;

  Listenable? _source;
  bool _queued = false;
  bool _disposed = false;
  S? _built;

  /// Reads the structure now and records it as the built one.
  S read() => _built = structure();

  /// Follows [source] instead of the source followed before.
  void follow(Listenable? source) {
    if (identical(source, _source)) return;
    _source?.removeListener(_framed);
    _source = source;
    source?.addListener(_framed);
  }

  void _framed() {
    if (_queued || _disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.midFrameMicrotasks) {
      _sync();
      return;
    }
    _queued = true;
    // Outside a frame the read asks for the frame that shows it right
    // away, as a setState would, so that frame is already due when the
    // read runs.
    SchedulerBinding.instance.ensureVisualUpdate();
    scheduleMicrotask(() {
      _queued = false;
      if (!_disposed) _sync();
    });
  }

  void _sync() {
    final now = structure();
    final built = _built;
    final kept = built is S && (same?.call(now, built) ?? now == built);
    if (!kept) {
      _built = now;
      rebuild(now);
      if (!notifiesOnRebuild) return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _source?.removeListener(_framed);
    _source = null;
    super.dispose();
  }
}

/// A value that never changes and never notifies.
@internal
class MorphFixed<T> implements ValueListenable<T> {
  /// Holds [value].
  const MorphFixed(this.value);

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
class MorphChanges<K> implements Listenable {
  /// Watches [of] over the notifications of [source].
  MorphChanges(this.source, this.of);

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
class MorphLiveOpacity extends SingleChildRenderObjectWidget {
  /// Fades [child] by [opacity], read again on every notification of
  /// [live].
  const MorphLiveOpacity({
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

class _RenderLiveOpacity extends RenderOpacity with MorphLiveBinding {
  _RenderLiveOpacity({super.opacity});
}

/// A [Text] faded by an opacity that follows a live source.
///
/// The fade is the alpha of the text's color, so a fading text draws in
/// the pass it belongs to instead of an opacity layer of its own (NEAR:
/// one rounding instead of two, at most 1 of 255 per channel), and it
/// repaints only itself: the text is a repaint boundary. A text whose
/// style the fade cannot reach (no color, a foreground paint, children or
/// a semantics label) fades through a [MorphLiveOpacity] instead.
@internal
class MorphLiveFadedText extends Text {
  /// Shows [data] faded to [opacityOf], read again on every notification
  /// of [live].
  const MorphLiveFadedText(
    super.data, {
    required this.live,
    required this.opacityOf,
    super.style,
    super.maxLines,
    super.textScaler,
    super.key,
  });

  /// The source of the opacity.
  final Listenable live;

  /// The opacity now, 0 to 1.
  final double Function() opacityOf;

  @override
  Widget build(BuildContext context) {
    final built = super.build(context);
    if (built is RichText && _LiveFadedParagraph.fades(built.text)) {
      return _LiveFadedRichText(built, live: live, opacityOf: opacityOf);
    }
    return MorphLiveOpacity(live: live, opacityOf: opacityOf, child: built);
  }
}

class _LiveFadedRichText extends RichText {
  _LiveFadedRichText(
    RichText from, {
    required this.live,
    required this.opacityOf,
  }) : super(
         key: from.key,
         text: from.text,
         textAlign: from.textAlign,
         textDirection: from.textDirection,
         softWrap: from.softWrap,
         overflow: from.overflow,
         textScaler: from.textScaler,
         maxLines: from.maxLines,
         locale: from.locale,
         strutStyle: from.strutStyle,
         textWidthBasis: from.textWidthBasis,
         textHeightBehavior: from.textHeightBehavior,
         selectionRegistrar: from.selectionRegistrar,
         selectionColor: from.selectionColor,
       );

  final Listenable live;
  final double Function() opacityOf;

  @override
  RenderParagraph createRenderObject(BuildContext context) {
    final paragraph = _LiveFadedParagraph(
      text,
      textAlign: textAlign,
      textDirection: textDirection ?? Directionality.of(context),
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      registrar: selectionRegistrar,
      selectionColor: selectionColor,
      devicePixelRatio:
          MediaQuery.maybeDevicePixelRatioOf(context) ??
          View.maybeOf(context)?.devicePixelRatio ??
          1.0,
    );
    paragraph.bindLive(live, () => paragraph.opacity = opacityOf());
    return paragraph;
  }

  @override
  void updateRenderObject(BuildContext context, RenderParagraph renderObject) {
    super.updateRenderObject(context, renderObject);
    final paragraph = renderObject as _LiveFadedParagraph;
    paragraph.bindLive(live, () => paragraph.opacity = opacityOf());
  }
}

class _LiveFadedParagraph extends RenderParagraph with MorphLiveBinding {
  _LiveFadedParagraph(
    super.text, {
    required super.textDirection,
    super.textAlign,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.registrar,
    super.selectionColor,
    super.devicePixelRatio,
  }) : _base = text;

  /// Whether [span] is a plain run of text whose color can carry a fade.
  static bool fades(InlineSpan span) =>
      span is TextSpan &&
      span.children == null &&
      span.recognizer == null &&
      span.semanticsLabel == null &&
      span.style?.color != null &&
      span.style?.foreground == null;

  InlineSpan _base;
  int _alpha = 255;

  @override
  bool get isRepaintBoundary => true;

  @override
  set text(InlineSpan value) {
    _base = value;
    super.text = _faded();
  }

  double get opacity => _alpha / 255;

  set opacity(double value) {
    final alpha = ui.Color.getAlphaFromOpacity(value.clamp(0.0, 1.0));
    if (alpha == _alpha) return;
    _alpha = alpha;
    super.text = _faded();
  }

  InlineSpan _faded() {
    final base = _base;
    if (_alpha == 255 || base is! TextSpan || !fades(base)) return base;
    final style = base.style!;
    final color = style.color!;
    return TextSpan(
      text: base.text,
      style: style.copyWith(
        color: color.withValues(alpha: color.a * _alpha / 255),
      ),
      locale: base.locale,
      spellOut: base.spellOut,
      mouseCursor: base.mouseCursor,
      onEnter: base.onEnter,
      onExit: base.onExit,
    );
  }
}

/// A [Semantics] annotation whose properties follow a live source: a
/// flag that changes with a motion, such as a menu's expanded state or a
/// slider's value, reaches the semantics tree without a build.
@internal
class MorphLiveSemantics extends SingleChildRenderObjectWidget {
  /// Annotates [child] with [propertiesOf], read again on every
  /// notification of [live].
  const MorphLiveSemantics({
    required this.live,
    required this.propertiesOf,
    this.container = false,
    super.child,
    super.key,
  });

  /// The source of the properties, or null for fixed ones.
  final Listenable? live;

  /// The properties now.
  final SemanticsProperties Function() propertiesOf;

  /// Whether the annotation forms a node of its own.
  final bool container;

  @override
  RenderSemanticsAnnotations createRenderObject(BuildContext context) {
    final semantics = _RenderLiveSemantics(
      properties: propertiesOf(),
      container: container,
      textDirection: Directionality.maybeOf(context),
    );
    semantics.bindLive(live, () => semantics.properties = propertiesOf());
    return semantics;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSemanticsAnnotations renderObject,
  ) {
    renderObject.container = container;
    renderObject.textDirection = Directionality.maybeOf(context);
    (renderObject as _RenderLiveSemantics).bindLive(
      live,
      () => renderObject.properties = propertiesOf(),
    );
  }
}

class _RenderLiveSemantics extends RenderSemanticsAnnotations
    with MorphLiveBinding {
  _RenderLiveSemantics({
    required super.properties,
    super.container,
    super.textDirection,
  });
}

/// A [Transform] whose matrix follows a live source.
@internal
class MorphLiveTransform extends SingleChildRenderObjectWidget {
  /// Transforms [child] about its center by the matrix [writeInto] fills,
  /// read again on every notification of [live].
  const MorphLiveTransform({
    required this.live,
    required void Function(Matrix4 into) this.writeInto,
    super.child,
    super.key,
  }) : writeSizedInto = null,
       matrixOf = null,
       alignment = Alignment.center;

  /// Transforms [child] about [alignment] by [matrixOf], read again on
  /// every notification of [live]; null [alignment] transforms about the
  /// child's origin.
  const MorphLiveTransform.matrix({
    required this.live,
    required Matrix4 Function() this.matrixOf,
    this.alignment = Alignment.center,
    super.child,
    super.key,
  }) : writeInto = null,
       writeSizedInto = null;

  /// Transforms [child] about its center by the matrix [writeSizedInto]
  /// fills from the child's laid-out size, read again on every
  /// notification of [live] and whenever that size changes.
  const MorphLiveTransform.sized({
    required this.live,
    required void Function(Matrix4 into, Size size) this.writeSizedInto,
    super.child,
    super.key,
  }) : writeInto = null,
       matrixOf = null,
       alignment = Alignment.center;

  /// The source of the matrix, or null for a fixed one.
  final Listenable? live;

  /// Writes the current matrix into the identity matrix it is given.
  final void Function(Matrix4 into)? writeInto;

  /// Writes the current matrix for a child of the given size into the
  /// identity matrix it is given.
  final void Function(Matrix4 into, Size size)? writeSizedInto;

  /// Returns the current matrix.
  final Matrix4 Function()? matrixOf;

  /// The point the matrix is applied about.
  final AlignmentGeometry? alignment;

  @override
  RenderTransform createRenderObject(BuildContext context) {
    final render = _RenderLiveTransform(
      alignment: alignment,
      textDirection: Directionality.maybeOf(context),
    );
    render.bind(live, writeInto, writeSizedInto, matrixOf);
    return render;
  }

  @override
  void updateRenderObject(BuildContext context, RenderTransform renderObject) {
    renderObject.alignment = alignment;
    renderObject.textDirection = Directionality.maybeOf(context);
    (renderObject as _RenderLiveTransform).bind(
      live,
      writeInto,
      writeSizedInto,
      matrixOf,
    );
  }
}

class _RenderLiveTransform extends RenderTransform with MorphLiveBinding {
  _RenderLiveTransform({super.alignment, super.textDirection})
    : super(transform: Matrix4.identity());

  final Matrix4 _scratch = Matrix4.identity();
  void Function(Matrix4 into, Size size)? _sized;
  Size? _writtenFor;

  void bind(
    Listenable? live,
    void Function(Matrix4 into)? writeInto,
    void Function(Matrix4 into, Size size)? writeSizedInto,
    Matrix4 Function()? matrixOf,
  ) {
    _sized = writeSizedInto;
    if (matrixOf != null) {
      bindLive(live, () => transform = matrixOf());
      return;
    }
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

/// A repaint boundary of its own while [apartOf] reads true, read again on
/// every notification of [live]: a child that moves for a while (a press
/// growth, a landing) repaints alone during those frames, not with what is
/// painted around it, and adds no layer at rest.
@internal
class MorphLiveApart extends SingleChildRenderObjectWidget {
  /// Sets [child] apart while [apartOf] reads true.
  const MorphLiveApart({
    required this.live,
    required this.apartOf,
    super.child,
    super.key,
  });

  /// The source of [apartOf].
  final Listenable live;

  /// Whether the child is apart now.
  final bool Function() apartOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveApart(apart: apartOf());
    box.bindLive(live, () => box.apart = apartOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveApart;
    box.bindLive(live, () => box.apart = apartOf());
  }
}

class _RenderLiveApart extends RenderProxyBox with MorphLiveBinding {
  _RenderLiveApart({required this._apart});

  bool _apart;

  bool get apart => _apart;

  set apart(bool value) {
    if (value == _apart) return;
    _apart = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => _apart;
}

/// A clipper computed from a live source, reclipping only when its key
/// changes.
@internal
class MorphLiveClipper<T> extends CustomClipper<T> {
  /// Clips to [clipOf], reclipping when [keyOf] over [live] changes.
  MorphLiveClipper({
    required Listenable live,
    required Object? Function() keyOf,
    required this.clipOf,
  }) : super(reclip: MorphChanges<Object?>(live, keyOf));

  /// The clip for a box of the given size.
  final T Function(Size size) clipOf;

  @override
  T getClip(Size size) => clipOf(size);

  @override
  bool shouldReclip(MorphLiveClipper<T> oldClipper) =>
      !identical(oldClipper, this);
}

/// A [BackdropFilter] whose filter follows a live source.
@internal
class MorphLiveBackdropFilter extends BackdropFilter {
  /// Filters the backdrop by [filterOf], read again on every notification
  /// of [live].
  MorphLiveBackdropFilter({
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
    with MorphLiveBinding {
  _RenderLiveBackdropFilter({required super.filterConfig, super.backdropKey});
}

/// A [ClipRRect] whose border radius follows a live source.
@internal
class MorphLiveClipRRect extends SingleChildRenderObjectWidget {
  /// Clips [child] to [borderRadiusOf], read again on every notification
  /// of [live].
  const MorphLiveClipRRect({
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

class _RenderLiveClipRRect extends RenderClipRRect with MorphLiveBinding {
  _RenderLiveClipRRect({
    super.borderRadius,
    super.clipBehavior,
    super.textDirection,
  });
}

/// A [ClipRSuperellipse] whose border radius follows a live source.
@internal
class MorphLiveClipRSuperellipse extends SingleChildRenderObjectWidget {
  /// Clips [child] to [borderRadiusOf], read again on every notification
  /// of [live].
  const MorphLiveClipRSuperellipse({
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
    with MorphLiveBinding {
  _RenderLiveClipRSuperellipse({
    super.borderRadius,
    super.clipBehavior,
    super.textDirection,
  });
}

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

class _RenderLiveStack extends RenderStack with MorphLiveBinding {
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
      live is MorphFixed<Decoration> ? null : live,
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
      live is MorphFixed<Decoration> ? null : live,
      () => renderObject.decoration = live.value,
    );
  }
}

class _RenderLiveDecoratedBox extends RenderDecoratedBox with MorphLiveBinding {
  _RenderLiveDecoratedBox({required super.decoration, super.configuration});
}

/// A [ColoredBox] whose color follows a live source; it takes every hit
/// in its box.
@internal
class MorphLiveColoredBox extends SingleChildRenderObjectWidget {
  /// Fills its box with [colorOf], read again on every notification of
  /// [live].
  const MorphLiveColoredBox({
    required this.live,
    required this.colorOf,
    super.child,
    super.key,
  });

  /// The source of the color, or null for a fixed one.
  final Listenable? live;

  /// The color now.
  final Color Function() colorOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveColoredBox(colorOf());
    box.bindLive(live, () => box.color = colorOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveColoredBox;
    box.bindLive(live, () => box.color = colorOf());
  }
}

class _RenderLiveColoredBox extends RenderProxyBoxWithHitTestBehavior
    with MorphLiveBinding {
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
    if (size > Size.zero && _color.a > 0) {
      final paint = Paint();
      paint.isAntiAlias = true;
      paint.color = _color;
      context.canvas.drawRect(offset & size, paint);
    }
    final child = this.child;
    if (child != null) context.paintChild(child, offset);
  }
}

/// A child placed, transformed, faded and clipped from state a motion holds,
/// read again on every notification of [live] without a rebuild.
///
/// The child is built once and sits in a repaint boundary of its own: a
/// notification re-records only this box's layers (opacity, transform, clip) and
/// keeps the child's pictures. A frame whose [size] changed lays the child
/// out again; every other one only repaints.
///
/// Each callback is read during layout or paint, so it must be a pure
/// read of the source's current state.
@internal
class MorphLiveBox extends SingleChildRenderObjectWidget {
  /// Creates a box driven by [live].
  MorphLiveBox({
    required this.live,
    this.size,
    this.offset,
    this.transform,
    this.opacity,
    this.clip,
    this.continuous = false,
    Widget? child,
    super.key,
  }) : super(child: child == null ? null : RepaintBoundary(child: child));

  /// Notifies whenever what the callbacks read changed.
  final Listenable live;

  /// The child's size; null gives the child this box's constraints.
  final Size Function()? size;

  /// Where the child's top-left corner sits in this box; null for the
  /// origin.
  final Offset Function()? offset;

  /// A transform applied about the child's top-left corner after [offset];
  /// null for none.
  final Matrix4 Function()? transform;

  /// The child's opacity, 0 to 1; at 0 the child neither paints nor takes
  /// hits. Null for 1.
  final double Function()? opacity;

  /// A rounded rect the child is clipped to, in the child's coordinates;
  /// null for no clip.
  final RRect Function()? clip;

  /// Whether [clip]'s corners are continuous: the rounded superellipse with
  /// the same radii, as UIKit's `cornerCurve = .continuous`, instead of
  /// circular arcs.
  final bool continuous;

  @override
  RenderMorphLiveBox createRenderObject(BuildContext context) =>
      RenderMorphLiveBox(
        live: live,
        size: size,
        offset: offset,
        transform: transform,
        opacity: opacity,
        clip: clip,
        continuous: continuous,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMorphLiveBox renderObject,
  ) {
    renderObject.bindLive(live, renderObject._tick, now: false);
    renderObject.sizeOf = size;
    renderObject.offsetOf = offset;
    renderObject.transformOf = transform;
    renderObject.opacityOf = opacity;
    renderObject.clipOf = clip;
    renderObject.continuous = continuous;
  }
}

/// The render object of [MorphLiveBox].
@internal
class RenderMorphLiveBox extends RenderProxyBox with MorphLiveBinding {
  /// Creates the box.
  RenderMorphLiveBox({
    required Listenable live,
    Size Function()? size,
    Offset Function()? offset,
    Matrix4 Function()? transform,
    double Function()? opacity,
    RRect Function()? clip,
    this._continuous = false,
  }) : _sizeOf = size,
       _offsetOf = offset,
       _transformOf = transform,
       _opacityOf = opacity,
       _clipOf = clip {
    bindLive(live, _tick, now: false);
  }

  Size Function()? _sizeOf;

  /// See [MorphLiveBox.size].
  Size Function()? get sizeOf => _sizeOf;
  set sizeOf(Size Function()? value) {
    if (identical(value, _sizeOf)) return;
    _sizeOf = value;
    markNeedsLayout();
  }

  Offset Function()? _offsetOf;

  /// See [MorphLiveBox.offset].
  Offset Function()? get offsetOf => _offsetOf;
  set offsetOf(Offset Function()? value) {
    if (identical(value, _offsetOf)) return;
    _offsetOf = value;
    markNeedsPaint();
  }

  Matrix4 Function()? _transformOf;

  /// See [MorphLiveBox.transform].
  Matrix4 Function()? get transformOf => _transformOf;
  set transformOf(Matrix4 Function()? value) {
    if (identical(value, _transformOf)) return;
    _transformOf = value;
    markNeedsPaint();
  }

  double Function()? _opacityOf;

  /// See [MorphLiveBox.opacity].
  double Function()? get opacityOf => _opacityOf;
  set opacityOf(double Function()? value) {
    if (identical(value, _opacityOf)) return;
    _opacityOf = value;
    markNeedsPaint();
  }

  RRect Function()? _clipOf;

  /// See [MorphLiveBox.clip].
  RRect Function()? get clipOf => _clipOf;
  set clipOf(RRect Function()? value) {
    if (identical(value, _clipOf)) return;
    _clipOf = value;
    markNeedsPaint();
  }

  bool _continuous;

  /// See [MorphLiveBox.continuous].
  bool get continuous => _continuous;
  set continuous(bool value) {
    if (value == _continuous) return;
    _continuous = value;
    _clipLayer.layer = null;
    _continuousLayer.layer = null;
    markNeedsPaint();
  }

  Size? _laidOut;
  bool? _shown;

  void _tick() {
    final size = _sizeOf?.call();
    if (size != null && size != _laidOut) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
    final shown = _opacity > 0;
    if (shown != _shown) {
      _shown = shown;
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_opacity > 0) super.visitChildrenForSemantics(visitor);
  }

  @override
  void dispose() {
    _opacityLayer.layer = null;
    _transformLayer.layer = null;
    _clipLayer.layer = null;
    _continuousLayer.layer = null;
    super.dispose();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void performLayout() {
    final child = this.child;
    final size = _sizeOf?.call();
    _laidOut = size;
    if (child != null) {
      child.layout(
        size == null ? constraints : BoxConstraints.tight(size),
        parentUsesSize: size == null,
      );
    }
    this.size = size == null && child != null
        ? constraints.constrain(child.size)
        : constraints.biggest;
  }

  // This box's coordinates to the child's: offset, then transform.
  Matrix4 _childTransform() {
    final offset = _offsetOf?.call() ?? Offset.zero;
    final matrix = Matrix4.translationValues(offset.dx, offset.dy, 0);
    final transform = _transformOf?.call();
    if (transform != null) matrix.multiply(transform);
    return matrix;
  }

  double get _opacity => (_opacityOf?.call() ?? 1).clamp(0.0, 1.0);

  final _opacityLayer = LayerHandle<OpacityLayer>();
  final _transformLayer = LayerHandle<TransformLayer>();
  final _clipLayer = LayerHandle<ClipRRectLayer>();
  final _continuousLayer = LayerHandle<ClipRSuperellipseLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final alpha = Color.getAlphaFromOpacity(_opacity);
    if (alpha == 0) {
      _opacityLayer.layer = null;
      _transformLayer.layer = null;
      _clipLayer.layer = null;
      _continuousLayer.layer = null;
      return;
    }
    void clipped(PaintingContext context, Offset offset) {
      final clip = _clipOf?.call();
      if (clip == null) {
        _clipLayer.layer = null;
        _continuousLayer.layer = null;
        context.paintChild(child, offset);
        return;
      }
      if (_continuous) {
        _continuousLayer.layer = context.pushClipRSuperellipse(
          true,
          offset,
          clip.outerRect,
          RSuperellipse.fromLTRBAndCorners(
            clip.left,
            clip.top,
            clip.right,
            clip.bottom,
            topLeft: clip.tlRadius,
            topRight: clip.trRadius,
            bottomLeft: clip.blRadius,
            bottomRight: clip.brRadius,
          ),
          (PaintingContext context, Offset offset) =>
              context.paintChild(child, offset),
          oldLayer: _continuousLayer.layer,
        );
        return;
      }
      _clipLayer.layer = context.pushClipRRect(
        true,
        offset,
        clip.outerRect,
        clip,
        (PaintingContext context, Offset offset) =>
            context.paintChild(child, offset),
        oldLayer: _clipLayer.layer,
      );
    }

    void transformed(PaintingContext context, Offset offset) {
      _transformLayer.layer = context.pushTransform(
        true,
        offset,
        _childTransform(),
        clipped,
        oldLayer: _transformLayer.layer,
      );
    }

    if (alpha == 255) {
      _opacityLayer.layer = null;
      transformed(context, offset);
      return;
    }
    _opacityLayer.layer = context.pushOpacity(
      offset,
      alpha,
      transformed,
      oldLayer: _opacityLayer.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_childTransform());
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_opacity == 0) return false;
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _childTransform(),
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) {
        final clip = _clipOf?.call();
        if (clip != null && !clip.contains(position)) return false;
        return child.hitTest(result, position: position);
      },
    );
  }

  // The clip applies in the child's coordinates, inside the transform;
  // callers read it in this box's own, where glass bounds its backdrop
  // samples by it.
  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    final clip = _clipOf?.call();
    if (clip == null) return null;
    return MatrixUtils.transformRect(_childTransform(), clip.outerRect);
  }
}

/// Paints its child shifted by [offsetOf], read again on every
/// notification of [live], without a layout.
///
/// The child takes hits where it paints, also outside this box's bounds.
@internal
class MorphLiveShift extends SingleChildRenderObjectWidget {
  /// Shifts [child] by [offsetOf].
  const MorphLiveShift({
    required this.live,
    required this.offsetOf,
    super.child,
    super.key,
  });

  /// The source of the offset.
  final Listenable? live;

  /// The offset now.
  final Offset Function() offsetOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveShift(offsetOf());
    box.bindLive(live, () => box.shift = offsetOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveShift;
    box.bindLive(live, () => box.shift = offsetOf());
  }
}

class _RenderLiveShift extends RenderProxyBox with MorphLiveBinding {
  _RenderLiveShift(this._shift);

  Offset _shift;

  Offset get shift => _shift;

  set shift(Offset value) {
    if (value == _shift) return;
    _shift = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _shift);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) =>
          child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
  }
}

/// Lays its child out at the size of [rectOf] and paints it at its
/// offset, as `Positioned.fromRect` in a [Stack] does, reading [rectOf]
/// again on every notification of [live].
///
/// A move only repaints; a resize lays the child out again. A box out of
/// this one's bounds is clipped to them, as a [Stack] clips its overflow.
@internal
class MorphLivePlacement extends SingleChildRenderObjectWidget {
  /// Places [child] at [rectOf].
  const MorphLivePlacement({
    required this.live,
    required this.rectOf,
    super.child,
    super.key,
  });

  /// The source of the box.
  final Listenable? live;

  /// The child's box in this one's coordinates now.
  final Rect Function() rectOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLivePlacement(rectOf());
    box.bindLive(live, () => box.rect = rectOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLivePlacement;
    box.bindLive(live, () => box.rect = rectOf());
  }
}

class _RenderLivePlacement extends RenderProxyBox with MorphLiveBinding {
  _RenderLivePlacement(this._rect);

  Rect _rect;

  Rect get rect => _rect;

  set rect(Rect value) {
    if (value == _rect) return;
    final resized = value.size != _rect.size;
    _rect = value;
    if (resized) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
    markNeedsSemanticsUpdate();
  }

  @override
  void performLayout() {
    child?.layout(
      BoxConstraints.tightFor(width: _rect.width, height: _rect.height),
      parentUsesSize: true,
    );
    size = constraints.biggest;
  }

  bool get _overflows =>
      _rect.left < 0 ||
      _rect.left + _rect.width > size.width ||
      _rect.top < 0 ||
      _rect.top + _rect.height > size.height;

  final _clip = LayerHandle<ClipRectLayer>();

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_overflows) {
      _clip.layer = null;
      context.paintChild(child, _rect.topLeft + offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (PaintingContext context, Offset offset) =>
          context.paintChild(child, _rect.topLeft + offset),
      oldLayer: _clip.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _overflows ? Offset.zero & size : null;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _rect.topLeft,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) =>
          child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_rect.left, _rect.top, 0, 1);
  }
}

/// Centers its child on the center of [rectOf], as a `Positioned.fromRect`
/// over a [Center] places it, reading [rectOf] again on every notification
/// of [live].
///
/// The child is laid out loosely within the size of [rectOf], as the
/// [Center] would, but only when that can change the layout:
///
/// - a child of [fixedSize] (a box of that size in any box at least as
///   large, such as a `SizedBox`) is laid out again only while [rectOf] is
///   smaller than it;
/// - while [hiddenOf] says the child shows nowhere (an opacity at zero
///   above it), it keeps the layout it has, and takes the one of the
///   current box once it shows again.
///
/// A frame that needs no new layout only repaints: the child lands
/// exactly where the [Center] would put it.
///
/// This box takes its constraints' biggest size; it takes no hits outside
/// the child, and none at all while [ignoring], as an [IgnorePointer]
/// around the child would.
@internal
class MorphLiveCenter extends SingleChildRenderObjectWidget {
  /// Centers [child] on [rectOf].
  const MorphLiveCenter({
    required this.live,
    required this.rectOf,
    this.fixedSize,
    this.hiddenOf,
    this.ignoring = false,
    super.child,
    super.key,
  });

  /// The source of the box.
  final Listenable? live;

  /// The box the child is centered in, in this one's coordinates, now.
  final Rect Function() rectOf;

  /// The size of a child whose size does not depend on a box at least
  /// this large, or null for any child.
  final Size? fixedSize;

  /// Whether the child shows nowhere now; null for always shown.
  final bool Function()? hiddenOf;

  /// Whether the child is invisible to hit testing.
  final bool ignoring;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveCenter(
      rectOf(),
      fixedSize: fixedSize,
      hiddenOf: hiddenOf,
      ignoring: ignoring,
    );
    box.bindLive(live, () => box.rect = rectOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveCenter;
    box.fixedSize = fixedSize;
    box.hiddenOf = hiddenOf;
    box.ignoring = ignoring;
    box.bindLive(live, () => box.rect = rectOf());
  }
}

class _RenderLiveCenter extends RenderIgnorePointer with MorphLiveBinding {
  _RenderLiveCenter(
    this._rect, {
    required this._fixedSize,
    required this.hiddenOf,
    required super.ignoring,
  });

  Rect _rect;

  Rect get rect => _rect;

  set rect(Rect value) {
    if (value == _rect) return;
    _rect = value;
    if (_childConstraints != _laidOutWith && !(hiddenOf?.call() ?? false)) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
    markNeedsSemanticsUpdate();
  }

  Size? _fixedSize;

  Size? get fixedSize => _fixedSize;

  set fixedSize(Size? value) {
    if (value == _fixedSize) return;
    _fixedSize = value;
    markNeedsLayout();
  }

  bool Function()? hiddenOf;

  BoxConstraints? _laidOutWith;

  BoxConstraints get _childConstraints {
    final fixed = _fixedSize;
    final box = _rect.size;
    if (fixed != null &&
        box.width >= fixed.width &&
        box.height >= fixed.height) {
      return BoxConstraints.loose(fixed);
    }
    return BoxConstraints.loose(box);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      final constraints = _laidOutWith == null || !(hiddenOf?.call() ?? false)
          ? _childConstraints
          : _laidOutWith!;
      _laidOutWith = constraints;
      child.layout(constraints, parentUsesSize: true);
    }
    size = constraints.biggest;
  }

  Offset get _centering {
    final child = this.child;
    if (child == null) return Offset.zero;
    return Alignment.center.alongOffset((_rect.size - child.size) as Offset);
  }

  Offset get _shift => _rect.topLeft + _centering;

  // Summed in the order a stack and a center would, so the child lands on
  // the same doubles.
  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset + _rect.topLeft + _centering);
    }
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) =>
          child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}

/// Shows its child through a window that follows a live source: the
/// child is laid out once at this box's constraints and painted shifted to
/// the window's top-left, clipped to the window's rounded rect, and takes
/// hits only inside it, reading [windowOf] again on every notification of
/// [live].
///
/// It stands for a `Positioned.fromRect` over a [ClipRRect] whose child
/// does not depend on the window's size (a [Stack] of fixed boxes): a
/// moving or resizing window only repaints.
@internal
class MorphLiveWindow extends SingleChildRenderObjectWidget {
  /// Shows [child] through [windowOf].
  const MorphLiveWindow({
    required this.live,
    required this.windowOf,
    required this.clipsOf,
    super.child,
    super.key,
  });

  /// The source of the window.
  final Listenable? live;

  /// The window in this box's coordinates now.
  final RRect Function() windowOf;

  /// Whether the window clips the child's painting now; it always bounds
  /// the hits.
  final bool Function() clipsOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = RenderMorphLiveWindow(windowOf(), clips: clipsOf());
    box.bindLive(live, () => box.follow(windowOf(), clips: clipsOf()));
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as RenderMorphLiveWindow;
    box.bindLive(live, () => box.follow(windowOf(), clips: clipsOf()));
  }
}

/// The render object of [MorphLiveWindow].
@internal
class RenderMorphLiveWindow extends RenderProxyBox with MorphLiveBinding {
  /// Creates the window.
  RenderMorphLiveWindow(this._window, {required this._clips});

  RRect _window;
  bool _clips;

  /// The window now, in this box's coordinates.
  RRect get window => _window;

  /// Moves the window to [window] and lets it clip or not.
  void follow(RRect window, {required bool clips}) {
    if (window == _window && clips == _clips) return;
    final moved = window.left != _window.left || window.top != _window.top;
    _window = window;
    _clips = clips;
    markNeedsPaint();
    if (moved) markNeedsSemanticsUpdate();
  }

  @override
  void performLayout() {
    child?.layout(constraints, parentUsesSize: true);
    size = constraints.biggest;
  }

  Offset get _shift => Offset(_window.left, _window.top);

  final _clip = LayerHandle<ClipRRectLayer>();

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final shift = _shift;
    if (!_clips) {
      _clip.layer = null;
      context.paintChild(child, offset + shift);
      return;
    }
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset + shift,
      Offset.zero & _window.outerRect.size,
      _window.shift(-shift),
      (PaintingContext context, Offset offset) =>
          context.paintChild(child, offset),
      oldLayer: _clip.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clips ? _window.outerRect : null;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_window.outerRect.contains(position)) return false;
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) =>
          child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}

/// The render object [template] makes, configured again from a fresh
/// [template] on every notification of [live] without a build.
///
/// The template is a render object widget whose own child is ignored;
/// [child] is this widget's. Each notification applies what its
/// `updateRenderObject` would, so the render object marks itself for
/// paint, layout or compositing exactly as a rebuild with the same values
/// would. A template must make the same render object type every time.
///
/// It fits any stock render object without a live twin, at the price of
/// one template widget per notification.
@internal
class MorphLiveTemplate extends SingleChildRenderObjectWidget {
  /// Drives the render object of [template].
  const MorphLiveTemplate({
    required this.template,
    this.live,
    super.child,
    super.key,
  });

  /// The source the template follows, or null for a fixed one.
  final Listenable? live;

  /// Returns the render object widget for the source's current state.
  final RenderObjectWidget Function() template;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      template().createRenderObject(context);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      template().updateRenderObject(context, renderObject);

  @override
  SingleChildRenderObjectElement createElement() => _LiveDrivenElement(
    this,
    (Widget widget) => (widget as MorphLiveTemplate).live,
    (Widget widget, BuildContext context, RenderObject renderObject) =>
        (widget as MorphLiveTemplate).updateRenderObject(context, renderObject),
  );
}

/// An [ImageFiltered] whose filter follows a live source.
///
/// It stays an [ImageFiltered], so whatever looks for one above a widget
/// (a glass container deciding whether it reaches its members) still
/// finds it.
///
/// With [enabledOf] the filter also turns on and off with the source: a
/// disabled filter adds no layer and paints its child as if it were not
/// there, so a filter that applies only part of the time costs no build
/// when it starts or stops.
@internal
class MorphLiveImageFiltered extends ImageFiltered {
  /// Filters [child] by [filterOf], read again on every notification of
  /// [live].
  MorphLiveImageFiltered({
    required this.live,
    required this.filterOf,
    this.enabledOf,
    super.enabled,
    super.child,
    super.key,
  }) : super(imageFilter: filterOf());

  /// The source of the filter, or null for a fixed one.
  final Listenable? live;

  /// The filter now.
  final ui.ImageFilter Function() filterOf;

  /// Whether the filter applies now; null applies it while [enabled].
  final bool Function()? enabledOf;

  @override
  ui.ImageFilter get imageFilter => filterOf();

  @override
  bool get enabled => enabledOf?.call() ?? super.enabled;

  @override
  SingleChildRenderObjectElement createElement() => _LiveDrivenElement(
    this,
    (Widget widget) => (widget as MorphLiveImageFiltered).live,
    (Widget widget, BuildContext context, RenderObject renderObject) =>
        (widget as MorphLiveImageFiltered).updateRenderObject(
          context,
          renderObject,
        ),
  );
}

/// Applies its widget's `updateRenderObject` again on every notification
/// of the source its widget names.
class _LiveDrivenElement extends SingleChildRenderObjectElement {
  _LiveDrivenElement(super.widget, this._liveOf, this._update);

  final Listenable? Function(Widget widget) _liveOf;
  final void Function(
    Widget widget,
    BuildContext context,
    RenderObject renderObject,
  )
  _update;

  Listenable? get _live => _liveOf(widget);

  void _drive() => _update(widget, this, renderObject);

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _live?.addListener(_drive);
  }

  @override
  void update(SingleChildRenderObjectWidget newWidget) {
    final old = _live;
    super.update(newWidget);
    if (!identical(old, _live)) {
      old?.removeListener(_drive);
      _live?.addListener(_drive);
    }
  }

  @override
  void activate() {
    super.activate();
    _live?.addListener(_drive);
  }

  @override
  void deactivate() {
    _live?.removeListener(_drive);
    super.deactivate();
  }
}

/// A child of a plain [Stack] placed by the [Positioned] [template]
/// returns, read again on every notification of [live] without a build.
///
/// The template's own child is ignored; pass [morphLiveSlot].
@internal
class MorphLivePositionedTemplate extends ParentDataWidget<StackParentData> {
  /// Places [child] where [template] says.
  const MorphLivePositionedTemplate({
    required this.template,
    required super.child,
    this.live,
    super.key,
  });

  /// The source the placement follows, or null for a fixed one.
  final Listenable? live;

  /// Returns the placement for the source's current state.
  final Positioned Function() template;

  @override
  void applyParentData(RenderObject renderObject) =>
      template().applyParentData(renderObject);

  @override
  Type get debugTypicalAncestorWidgetClass => Stack;

  @override
  ParentDataElement<StackParentData> createElement() =>
      _LivePositionedTemplateElement(this);
}

/// The child a [MorphLivePositionedTemplate]'s template carries; never
/// built.
@internal
const Widget morphLiveSlot = SizedBox.shrink();

class _LivePositionedTemplateElement
    extends ParentDataElement<StackParentData> {
  _LivePositionedTemplateElement(MorphLivePositionedTemplate super.widget);

  Listenable? get _live => (widget as MorphLivePositionedTemplate).live;

  void _drive() {
    var child = renderObjectAttachingChild;
    while (child != null && child is! RenderObjectElement) {
      child = child.renderObjectAttachingChild;
    }
    if (child is RenderObjectElement) {
      (widget as MorphLivePositionedTemplate).applyParentData(
        child.renderObject,
      );
    }
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _live?.addListener(_drive);
  }

  @override
  void update(MorphLivePositionedTemplate newWidget) {
    final old = _live;
    super.update(newWidget);
    if (!identical(old, _live)) {
      old?.removeListener(_drive);
      _live?.addListener(_drive);
    }
  }

  @override
  void activate() {
    super.activate();
    _live?.addListener(_drive);
  }

  @override
  void deactivate() {
    _live?.removeListener(_drive);
    super.deactivate();
  }
}
