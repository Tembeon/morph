import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_cache.dart';

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
