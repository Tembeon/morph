import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/plane/render_glass_plane.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';

/// Where one glass layer reads its backdrop.
@internal
enum GlassRead {
  /// The read of the nearest plane ([GlassPlaneScope], or an app's
  /// [BackdropGroup]): one copy taken where the plane's first glass paints.
  /// Glass painted later in the plane does not see what is painted between.
  plane,

  /// A read of its own, at its own place in paint order: chrome that floats
  /// over content (a bar, a menu, a sheet).
  own,

  /// A read of its own around its glass, for a small frost that animates (a
  /// lifted lens, knob or thumb): the blur reads a copy of its surroundings
  /// instead of the whole pass.
  lifted,
}

/// What glass with a read of its own reads.
@internal
sealed class GlassBackdrop {
  const GlassBackdrop();

  /// The backdrop as it stands where the glass paints.
  const factory GlassBackdrop.live() = LiveGlassBackdrop;

  /// A copy of the route below, re-taken when what the glass samples
  /// changes, never older than the frame ([GlassBackdropCache]).
  const factory GlassBackdrop.cached(GlassBackdropCache cache) =
      CachedGlassBackdrop;
}

/// The backdrop as it stands where the glass paints.
@internal
final class LiveGlassBackdrop extends GlassBackdrop {
  /// The live backdrop.
  const LiveGlassBackdrop();
}

/// A cached copy of the route below.
@internal
final class CachedGlassBackdrop extends GlassBackdrop {
  /// The copy [cache] holds.
  const CachedGlassBackdrop(this.cache);

  /// The cache.
  final GlassBackdropCache cache;

  @override
  bool operator ==(Object other) =>
      other is CachedGlassBackdrop && identical(other.cache, cache);

  @override
  int get hashCode => identityHashCode(cache);
}

/// What the owner of a plane ([GlassPlaneScope.owned]) guarantees about
/// painting between the plane and its glass.
@internal
enum GlassPaintOrder {
  /// Nothing paints between the plane and its members' glass: everything
  /// in the plane is content over its glass.
  owned,

  /// Content paints between the plane and its members' glass, never inside
  /// a member's outline: glass that reads only inside its outline (no
  /// frost) looks the same drawn at the plane.
  outsideGlass,
}

/// Declares glass planes: which glass shares one backdrop read, and what
/// glass with a read of its own reads.
///
/// - [plane]: a plane for the glass in its child that reads its plane
///   ([GlassRead.plane]), on a key of its own. Its read is taken where its
///   first glass paints, so only glass whose backdrop is complete before
///   then may share it.
/// - [chrome]: a plane for chrome that floats over a page (a bar's items,
///   a sheet's content): it joins the read a [shareRead] above hands down
///   (a screen's bars), else reads on a key of its own.
/// - [shareRead]: hands one read down to the [chrome] planes below,
///   without being a plane itself.
/// - [backdrop]: what glass with a read of its own ([GlassRead.own],
///   [GlassRead.lifted]) in its child reads: the live backdrop, or a cached
///   copy of the route below.
///
/// - [owned]: a plane whose owner declares what paints between it and its
///   glass ([GlassPaintOrder]): one pass at the plane draws the resting
///   glass below it that would look the same there ([RenderGlassPlane]),
///   with one geometry pass and one backdrop filter for all of it.
/// - [planeBreak]: keeps the glass in its child out of such a pass while
///   active, for an owner that sometimes paints between.
///
/// An app's [BackdropGroup] is a plane too: glass that reads its plane
/// reads the nearest group's key.
@internal
abstract final class GlassPlaneScope {
  /// A plane for the glass in [child].
  static Widget plane({required Widget child}) => BackdropGroup(child: child);

  /// A plane for the chrome in [child], joining a shared read above.
  static Widget chrome({required Widget child}) => _ChromePlane(child: child);

  /// Hands [read] down to the [chrome] planes in [child].
  static Widget shareRead({required BackdropKey read, required Widget child}) =>
      _SharedRead(read: read, child: child);

  /// Declares what glass with a read of its own in [child] reads.
  static Widget backdrop({
    required GlassBackdrop backdrop,
    required Widget child,
  }) => _GlassBackdropScope(backdrop: backdrop, child: child);

  /// A plane for the glass in [child] whose owner guarantees [paintOrder],
  /// with a pass of [settings] and [defaultAppearance] that reads the
  /// plane's backdrop, or paints over [solidBackdrop]
  /// ([LiquidGlassLayer.solidBackdrop]); it merges nothing while not
  /// [open].
  static Widget owned({
    required LiquidGlassSettings settings,
    required LiquidGlassAppearance defaultAppearance,
    required Widget child,
    bool open = true,
    GlassPaintOrder paintOrder = GlassPaintOrder.owned,
    Color? solidBackdrop,
  }) => LiquidGlassLayer(
    settings: settings,
    defaultAppearance: defaultAppearance,
    read: GlassRead.plane,
    solidBackdrop: solidBackdrop,
    planePass: true,
    child: _OwnedPlane(
      settings: settings,
      open: open,
      paintOrder: paintOrder,
      solid: solidBackdrop,
      child: child,
    ),
  );

  /// Keeps the glass in [child] out of the pass of an owned plane above
  /// while [active].
  static Widget planeBreak({required bool active, required Widget child}) =>
      _PlaneBreak(active: active, child: child);

  /// The cached copy glass with a read of its own above [context] paints
  /// over, or null for the live backdrop.
  static GlassBackdropCache? cacheOf(BuildContext context) => switch (context
      .dependOnInheritedWidgetOfExactType<_GlassBackdropScope>()
      ?.backdrop) {
    CachedGlassBackdrop(:final cache) => cache,
    _ => null,
  };
}

class _ChromePlane extends StatefulWidget {
  const _ChromePlane({required this.child});

  final Widget child;

  @override
  State<_ChromePlane> createState() => _ChromePlaneState();
}

class _ChromePlaneState extends State<_ChromePlane> {
  final BackdropKey _own = BackdropKey();

  @override
  Widget build(BuildContext context) => BackdropGroup(
    backdropKey:
        context.dependOnInheritedWidgetOfExactType<_SharedRead>()?.read ?? _own,
    child: widget.child,
  );
}

class _GlassBackdropScope extends InheritedWidget {
  const _GlassBackdropScope({required this.backdrop, required super.child});

  final GlassBackdrop backdrop;

  @override
  bool updateShouldNotify(_GlassBackdropScope oldWidget) =>
      oldWidget.backdrop != backdrop;
}

class _SharedRead extends InheritedWidget {
  const _SharedRead({required this.read, required super.child});

  final BackdropKey read;

  @override
  bool updateShouldNotify(_SharedRead oldWidget) => oldWidget.read != read;
}

class _OwnedPlane extends SingleChildRenderObjectWidget {
  const _OwnedPlane({
    required this.settings,
    required this.open,
    required this.paintOrder,
    required this.solid,
    required super.child,
  });

  final LiquidGlassSettings settings;
  final bool open;
  final GlassPaintOrder paintOrder;
  final Color? solid;

  @override
  RenderGlassPlane createRenderObject(BuildContext context) => RenderGlassPlane(
    settings: settings,
    open: open,
    paintOrder: paintOrder,
    pass: InheritedGeometryRenderLink.of(context)!,
    solid: solid,
    readKey: BackdropGroup.of(context)?.backdropKey,
  );

  @override
  void updateRenderObject(BuildContext context, RenderGlassPlane renderObject) {
    renderObject.settings = settings;
    renderObject.open = open;
    renderObject.paintOrder = paintOrder;
    renderObject.pass = InheritedGeometryRenderLink.of(context)!;
    renderObject.solid = solid;
    renderObject.readKey = BackdropGroup.of(context)?.backdropKey;
  }
}

class _PlaneBreak extends SingleChildRenderObjectWidget {
  const _PlaneBreak({required this.active, required super.child});

  final bool active;

  @override
  RenderGlassPlaneBreak createRenderObject(BuildContext context) =>
      RenderGlassPlaneBreak(active: active);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassPlaneBreak renderObject,
  ) => renderObject.active = active;
}
