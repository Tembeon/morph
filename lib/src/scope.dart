import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/flight.dart';

/// The registry of tags and flights. Installed once near the top of the
/// tree (not necessarily above the Navigator, but inside MaterialApp).
/// A flight's shuttle renders in the NEAREST enclosing [Overlay], so a
/// nested navigator keeps its flights inside itself; in a
/// single-navigator app that is the root overlay anyway. Also serves as
/// the TickerProvider for all flights.
class MorphScope extends StatefulWidget {
  /// Creates the scope; place it once, inside MaterialApp.builder.
  const MorphScope({super.key, required this.child});

  /// The subtree served by this scope.
  final Widget child;

  /// The nearest scope above [context]; asserts when absent.
  static MorphScopeState of(BuildContext context) {
    final MorphScopeState? state = maybeOf(context);
    assert(
      state != null,
      'No MorphScope found above this context. Wrap the app once, above '
      'the Navigator: MaterialApp(builder: (context, child) => '
      'MorphScope(child: child!)).',
    );
    return state!;
  }

  /// null outside a scope - for consumers that can live without the
  /// morph engine (e.g. MorphSkin as pure fusion).
  static MorphScopeState? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<_MorphScopeMarker>()?.state;
  }

  @override
  State<MorphScope> createState() => MorphScopeState();
}

/// The registry behind [MorphScope]: tags by id, live flights by id,
/// and the ticker provider all flights share.
class MorphScopeState extends State<MorphScope> with TickerProviderStateMixin {
  final Map<Object, MorphTagState> _tags = <Object, MorphTagState>{};
  final Map<Object, MorphFlight> _flights = <Object, MorphFlight>{};
  final List<MorphFlight> _retired = <MorphFlight>[];

  /// The most recently launched flight - the subscription point for
  /// debug HUDs and telemetry.
  final ValueNotifier<MorphFlight?> lastFlight = ValueNotifier<MorphFlight?>(
    null,
  );

  /// The registered tag for [id]; asserts when the tag is not mounted.
  @internal
  MorphTagState tagOf(Object id) {
    final MorphTagState? tag = _tags[id];
    assert(
      tag != null,
      'No MorphTag(id: $id) is mounted in this MorphScope. Check that '
      'the id matches the tag exactly (type included: "2" != 2), that '
      'the tag is built before the morph launches, and that the tag '
      'sits under the SAME MorphScope as the launching context.',
    );
    return tag!;
  }

  /// The live flight of the tag with [id], or null.
  MorphFlight? flightOf(Object id) => _flights[id];

  /// A snapshot of every live flight in this scope, one per tag.
  Iterable<MorphFlight> get liveFlights =>
      List<MorphFlight>.unmodifiable(_flights.values);

  /// Closes every live flight - the app-level "nothing stays open"
  /// path (logout, deep link, tab switch, test teardown). [animate]
  /// false tears them down instantly via [MorphFlight.abort].
  void closeAll({bool animate = true}) {
    for (final MorphFlight flight in _flights.values.toList()) {
      if (animate) {
        flight.close();
      } else {
        flight.abort();
      }
    }
  }

  /// Like [flightOf], but null when the flight's source tag has left
  /// the active tree. A flight can outlive its tag (a screen torn down
  /// mid-flight: the scope owns flights, a disposing tag only
  /// unregisters) - such a stray stays visible to observers through
  /// [flightOf], but engine consumers that would touch the tag (the
  /// skin's neck, a retarget) must treat it as absent.
  @internal
  MorphFlight? liveFlightOf(Object id) {
    final MorphFlight? flight = _flights[id];
    if (flight == null || !flight.tag.isTreeActive) {
      return null;
    }
    return flight;
  }

  /// Registers a mounted tag; ids must be unique within the scope.
  @internal
  void registerTag(Object id, MorphTagState tag) {
    assert(
      _tags[id] == null || _tags[id] == tag,
      'Duplicate MorphTag(id: $id): ids must be unique within a scope.',
    );
    _tags[id] = tag;
  }

  /// Removes a tag registration if [tag] still owns it.
  @internal
  void unregisterTag(Object id, MorphTagState tag) {
    if (_tags[id] == tag) {
      _tags.remove(id);
    }
  }

  /// Moves a live flight to the tag's new id when the tag re-keys
  /// mid-flight. [MorphFlight.tagId] reads the tag's CURRENT id, so an
  /// un-moved registry entry would be orphaned under the old key:
  /// retireFlight would probe the new key and remove nothing, and every
  /// later launch from the old id would retarget the dead flight
  /// forever.
  @internal
  void retagFlight(Object oldId, MorphTagState tag) {
    final MorphFlight? flight = _flights[oldId];
    if (flight != null && flight.tag == tag) {
      _flights.remove(oldId);
      _flights[flight.tagId] = flight;
    }
  }

  /// Records a newly launched flight and publishes it on [lastFlight].
  @internal
  void adoptFlight(MorphFlight flight) {
    _flights[flight.tagId] = flight;
    lastFlight.value = flight;
    for (final MorphFlight old in _retired) {
      old.disposeController();
    }
    _retired.clear();
  }

  /// Removes a finished flight; its controller is disposed after the
  /// frame so external listeners can detach first.
  @internal
  void retireFlight(MorphFlight flight) {
    if (_flights[flight.tagId] == flight) {
      _flights.remove(flight.tagId);
    }
    _retired.add(flight);
    // Finish retirement after the frame, but leave lastFlight alone:
    // HUDs and derived animations may still be subscribed to its
    // controller - it lives until replaced in adoptFlight.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) {
        return;
      }
      _retired.removeWhere((MorphFlight retired) {
        if (retired == lastFlight.value) {
          return false;
        }
        retired.disposeController();
        return true;
      });
    });
  }

  @override
  void dispose() {
    for (final MorphFlight flight in _flights.values.toList()) {
      flight.abort();
    }
    for (final MorphFlight old in _retired) {
      old.disposeController();
    }
    _retired.clear();
    lastFlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MorphScopeMarker(state: this, child: widget.child);
  }
}

class _MorphScopeMarker extends InheritedWidget {
  const _MorphScopeMarker({required this.state, required super.child});

  final MorphScopeState state;

  @override
  bool updateShouldNotify(_MorphScopeMarker oldWidget) =>
      state != oldWidget.state;
}

/// The morph's surface model as a value: everything the engine can
/// interpolate about a surface - (shape, color, elevation). Declared
/// once at a [MorphTag] (via [MorphTag.spec]) and readable by any
/// descendant through [MorphTag.specOf], so the visible surface is
/// BUILT FROM the declaration instead of duplicating it - drift between
/// "what the button looks like" and "what the morph believes" becomes
/// structurally impossible, whatever rendering stack draws it.
///
/// Being a plain value, specs compose with any storage the app already
/// has: its own ThemeExtension of named archetypes, constants, or
/// inline.
@immutable
class MorphSurfaceSpec {
  /// Creates a surface model.
  const MorphSurfaceSpec({
    this.shape = const RoundedRectangleBorder(),
    this.color,
    this.elevation = 0,
  });

  /// The surface outline.
  final ShapeBorder shape;

  /// The surface color; null lets the consumer pick a scheme default.
  final Color? color;

  /// The surface shadow.
  final double elevation;

  /// A copy with the given fields replaced.
  MorphSurfaceSpec copyWith({
    ShapeBorder? shape,
    Color? color,
    double? elevation,
  }) {
    return MorphSurfaceSpec(
      shape: shape ?? this.shape,
      color: color ?? this.color,
      elevation: elevation ?? this.elevation,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MorphSurfaceSpec &&
        other.shape == shape &&
        other.color == color &&
        other.elevation == elevation;
  }

  @override
  int get hashCode => Object.hash(shape, color, elevation);

  @override
  String toString() =>
      'MorphSurfaceSpec(shape: $shape, color: $color, elevation: $elevation)';
}

/// The transport behind [MorphTag.specOf]: installed by the tag around
/// its child and by the shuttle around flight content, so the surface
/// model is readable at both ends of a flight. Library-internal - not
/// exported.
class MorphSurfaceSpecScope extends InheritedWidget {
  /// Publishes [spec] to the subtree.
  const MorphSurfaceSpecScope({
    super.key,
    required this.spec,
    required super.child,
  });

  /// The surface model served to descendants.
  final MorphSurfaceSpec spec;

  @override
  bool updateShouldNotify(MorphSurfaceSpecScope oldWidget) =>
      spec != oldWidget.spec;
}

/// The identity marker: registers its RenderBox in the scope and hands
/// the engine a (rect, shape) pair. The shape is declared, never
/// inferred from decoration. Prefer declaring the whole surface once
/// via [spec] and rendering from [specOf]; the individual fields
/// remain for terse cases.
class MorphTag extends StatefulWidget {
  /// Creates an identity tag around [child].
  const MorphTag({
    super.key,
    required this.id,
    required this.child,
    this.spec,
    this.shape = const RoundedRectangleBorder(),
    this.surfaceColor,
    this.elevation = 0,
    this.replica,
    this.snapshotGhost = false,
  }) : assert(elevation >= 0, 'elevation cannot be negative.');

  /// Unique identity within the enclosing [MorphScope].
  final Object id;

  /// The tagged widget; replicated in the shuttle during flight.
  ///
  /// The replica is pixels-only: it takes no pointer and no focus. An
  /// explicit [FocusNode] inside the child is nevertheless attached to
  /// the replica for the duration of the flight (the copy shares this
  /// widget configuration), so the node may transiently report the
  /// shuttle as its context; focus itself cannot enter the replica,
  /// and requestFocus on such a node is ignored while the flight is
  /// up.
  final Widget child;

  /// The surface model declared as one value; when set it wins over
  /// [shape]/[surfaceColor]/[elevation]. Descendants read it back via
  /// [specOf] and render the visible surface from it - one source of
  /// truth for the eye and for the flight.
  final MorphSurfaceSpec? spec;

  /// The source outline the shuttle takes off from.
  final ShapeBorder shape;

  /// The source widget's surface color: the shuttle's surfaceColor
  /// starts from it so the container looks like the button at flight
  /// start. WITHOUT it the shuttle starts from the TARGET color and
  /// mismatches the button on the first frame - mandatory for opaque
  /// buttons.
  final Color? surfaceColor;

  /// The source widget's elevation: the shuttle's shadow starts from
  /// it. A button with its own shadow (a FAB) must declare it here,
  /// otherwise the shadow pops when the tag hides and at handoff.
  final double elevation;

  /// The "in-flight" version of the child for the shuttle. For buttons
  /// with their own decoration (background, shadow) put the flat
  /// content here: in flight the shuttle provides background and
  /// shadow, and a replicated decoration would be clipped at the edges.
  /// null - the [child] itself flies.
  final Widget? replica;

  /// The declared surface model of the nearest enclosing [MorphTag] -
  /// render the visible surface from it instead of repeating the
  /// values.
  static MorphSurfaceSpec specOf(BuildContext context) {
    final MorphSurfaceSpec? spec = maybeSpecOf(context);
    assert(
      spec != null,
      'MorphTag.specOf called outside of a MorphTag subtree.',
    );
    return spec!;
  }

  /// Like [specOf], but null outside a tag subtree.
  static MorphSurfaceSpec? maybeSpecOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MorphSurfaceSpecScope>()
        ?.spec;
  }

  /// The id of the nearest enclosing [MorphTag]. Lets a tap handler
  /// inside the tag's own subtree call showMorph* WITHOUT repeating the
  /// id - the morph flies from the surface the finger is already on.
  /// Content that launches a morph from elsewhere (a morphable skin
  /// piece, a list controller) still names its source explicitly.
  static Object idOf(BuildContext context) {
    final Object? id = maybeIdOf(context);
    assert(
      id != null,
      'No enclosing MorphTag: pass from: explicitly, or call from within '
      'the source tag\'s subtree.',
    );
    return id!;
  }

  /// Like [idOf], but null outside a tag subtree.
  static Object? maybeIdOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_MorphTagIdScope>()?.id;
  }

  /// The ghost in the shuttle as a pixel snapshot instead of a second
  /// build. Opt-in for heavy content: the snapshot freezes ephemeral
  /// state (e.g. a mid-ripple), which on ordinary buttons looks worse
  /// than a live widget replica.
  final bool snapshotGhost;

  @override
  State<MorphTag> createState() => MorphTagState();
}

/// The registration and flight-side machinery of a [MorphTag].
class MorphTagState extends State<MorphTag> {
  MorphScopeState? _scope;
  bool _hidden = false;
  final GlobalKey _boundaryKey = GlobalKey();

  /// mounted is not enough: in the dismantling frame the element is
  /// already deactivated (findRenderObject throws) but the State is not
  /// yet disposed.
  bool _treeActive = true;

  /// Whether the tag still lives in an active tree. False while
  /// deactivated or after dispose - a flight can outlive its tag (the
  /// scope owns flights, a disposing tag only unregisters), and
  /// consumers such as the skin must not touch a defunct tag's context
  /// or widget.
  @internal
  bool get isTreeActive => _treeActive && mounted;

  @override
  void activate() {
    super.activate();
    _treeActive = true;
  }

  @override
  void deactivate() {
    _treeActive = false;
    super.deactivate();
  }

  /// The tag's identity.
  Object get id => widget.id;

  /// The resolved source outline ([MorphTag.spec] wins over the field).
  ShapeBorder get shape => widget.spec?.shape ?? widget.shape;

  /// The resolved source color.
  Color? get surfaceColor => widget.spec?.color ?? widget.surfaceColor;

  /// The resolved source elevation.
  double get elevation => widget.spec?.elevation ?? widget.elevation;

  /// The widget the shuttle flies: [MorphTag.replica] or the child.
  @internal
  Widget get replica => widget.replica ?? widget.child;

  /// The resolved surface model of this tag - what specOf serves and
  /// what the shuttle republishes around the source replica.
  MorphSurfaceSpec get surfaceSpec => _effectiveSpec;

  MorphSurfaceSpec get _effectiveSpec =>
      widget.spec ??
      MorphSurfaceSpec(
        shape: widget.shape,
        color: widget.surfaceColor,
        elevation: widget.elevation,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final MorphScopeState scope = MorphScope.of(context);
    if (_scope != scope) {
      _scope?.unregisterTag(widget.id, this);
      _scope = scope;
      scope.registerTag(widget.id, this);
    }
  }

  @override
  void didUpdateWidget(MorphTag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _scope?.unregisterTag(oldWidget.id, this);
      _scope?.registerTag(widget.id, this);
      _scope?.retagFlight(oldWidget.id, this);
    }
  }

  @override
  void dispose() {
    _scope?.unregisterTag(widget.id, this);
    super.dispose();
  }

  /// The tag's global rect in the overlay RenderBox coordinates.
  @internal
  Rect captureRect(RenderBox overlayBox) => tryCaptureRect(overlayBox)!;

  /// null if the tag has not been laid out yet or is already
  /// deactivated (safe to call from the build phase: it reads the
  /// previous frame's result).
  @internal
  Rect? tryCaptureRect(RenderBox overlayBox) {
    if (!isTreeActive) {
      return null;
    }
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    // A tag may sit below a paint transform (the press lift of a held
    // surface is the important case). Transforming only local zero and
    // then pairing it with the untransformed layout size produces a rect
    // that is neither the painted rect nor the layout rect: a centered
    // scale moves its top-left but mysteriously keeps its old extent.
    // Capture the whole local bounds through the same transform so the
    // shuttle's first pixel is exactly the pixel the finger was holding.
    return MatrixUtils.transformRect(
      renderObject.getTransformTo(overlayBox),
      Offset.zero & renderObject.size,
    );
  }

  /// Hides the home widget while its content rides the shuttle.
  @internal
  void hideForFlight() {
    if (!_hidden) {
      setState(() => _hidden = true);
    }
  }

  /// Un-hides the widget: called by the handoff latch, and by every
  /// teardown that skips it (abort, a scrub-interrupted finalize) - a
  /// tag left hidden with no flight would stay invisible forever.
  @internal
  void reveal() {
    if (_hidden && mounted) {
      setState(() => _hidden = false);
    }
  }

  /// A pixel snapshot of the live button (including current ephemeral
  /// state such as a ripple) for the shuttle's ghost. null if the
  /// boundary has not painted yet - the caller falls back to the widget
  /// replica.
  @internal
  Future<ui.Image?> captureSnapshot(double pixelRatio) async {
    final RenderObject? boundary = _boundaryKey.currentContext
        ?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      return null;
    }
    try {
      return await boundary.toImage(pixelRatio: pixelRatio);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.child.key is! GlobalKey,
      'MorphTag(id: ${widget.id}): a child with a GlobalKey cannot be '
      'replicated in the shuttle - one GlobalKey cannot be mounted '
      'twice. Remove the key or move it deeper, outside the replicated '
      'part.',
    );
    final Widget child = RepaintBoundary(
      key: _boundaryKey,
      child: widget.child,
    );
    return IgnorePointer(
      ignoring: _hidden,
      child: Opacity(
        opacity: _hidden ? 0 : 1,
        child: _MorphTagIdScope(
          id: widget.id,
          child: MorphSurfaceSpecScope(spec: _effectiveSpec, child: child),
        ),
      ),
    );
  }
}

/// The identity transport behind [MorphTag.idOf]: installed by the tag
/// itself (and deliberately not republished by the shuttle - dialog
/// content must name its source explicitly).
class _MorphTagIdScope extends InheritedWidget {
  const _MorphTagIdScope({required this.id, required super.child});

  final Object id;

  @override
  bool updateShouldNotify(_MorphTagIdScope oldWidget) => id != oldWidget.id;
}
