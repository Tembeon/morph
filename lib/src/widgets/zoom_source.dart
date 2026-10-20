import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/themes.dart';
import 'package:morph/src/widgets/glass.dart' show MorphGlassSurface;

/// The glass a source draws itself, which a zoom out of the source grows
/// from.
///
/// A glass control that is a [MorphSource]'s whole child hands its tag
/// one ([MorphTagState.attachFace]). A sheet zooming out of that source
/// then morphs the source's glass into its own, as UIKit's liquid zoom
/// does out of a glass view, instead of stretching a copy of the source
/// over its container.
@internal
abstract interface class MorphSourceGlass implements MorphSourceFace {
  /// The source's glass in [shape], in the coordinates of the drawing.
  MorphGlassSurface surface(RRect shape);

  /// The fill the source's glass draws without a glass painter.
  Color get fill;

  /// What the source shows on its glass, without the glass, at the
  /// source's own size.
  Widget get look;
}

/// The source geometry and lifetime of a sheet or page zoom.
@internal
class MorphZoomSource {
  /// Tracks [tag] for one presentation.
  MorphZoomSource(this.tag)
    : _themes = tag != null && tag.mounted
          ? MorphThemeCarrier(tag.context)
          : null;

  /// Resolves [id] in the scope around [context], tolerating an absent tag.
  factory MorphZoomSource.resolve(
    BuildContext context,
    MorphSourceLink? from,
  ) => MorphZoomSource(from?.tag);

  /// The source tag, or null when no source is available.
  final MorphTagState? tag;

  final MorphThemeCarrier? _themes;
  Rect? _rect;
  bool _hidden = false;
  bool _lost = false;
  double? _dissolveStart;
  ShapeBorder? _shape;
  TextDirection _direction = TextDirection.ltr;

  MorphSourceGlass? _glass;
  bool _glassRead = false;

  /// The glass the source draws itself when it is one glass control, read
  /// once for the zoom: a zoom out of it is the liquid one.
  MorphSourceGlass? get glass {
    if (!_glassRead) {
      _glassRead = true;
      final source = tag;
      final face = source != null && source.mounted ? source.sourceFace : null;
      _glass = face is MorphSourceGlass ? face : null;
    }
    return _glass;
  }

  /// [look] in the theme of the subtree the source sits in.
  Widget themed(Widget look) => _themes?.wrap(look) ?? look;

  /// Whether the source is gone or has never supplied geometry.
  bool get isLost {
    if (tag == null || !tag!.mounted) _lost = true;
    return _lost || _rect == null;
  }

  /// The most recent source frame, frozen when its tag goes away.
  Rect? capture(BuildContext context) {
    final source = tag;
    if (source == null || !source.mounted) {
      _lost = true;
      return _rect;
    }
    final own = context.findRenderObject();
    final box = own is RenderBox && own.hasSize
        ? own
        : Overlay.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return _rect;
    final rect = source.tryCaptureRect(box);
    if (rect != null && !rect.isEmpty) {
      _rect = rect;
      _shape = source.shape;
      _direction = Directionality.maybeOf(source.context) ?? TextDirection.ltr;
    }
    return _rect;
  }

  /// Hides a laid-out source: in the frame that first draws the zoom when
  /// called from the push, after the current frame when called while the
  /// tree builds.
  void hide() {
    final source = tag;
    if (_hidden || _lost || source == null || !source.mounted) return;
    final box = source.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _hidden = true;
    // A hide one frame late draws the source under the zoom's copy of it.
    if (_rebuildsNow) {
      source.hideForFlight();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (_hidden && source.mounted) source.hideForFlight();
    });
  }

  /// Reveals a source: in the frame that drops the zoom when called from a
  /// tick, after the current frame when called while the tree builds or
  /// tears down, as on route removal.
  void reveal() {
    if (!_hidden) return;
    _hidden = false;
    final source = tag;
    if (source == null) return;
    // A reveal one frame late shows neither the zoom nor its source.
    if (_rebuildsNow) {
      if (source.mounted) source.reveal();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (source.mounted) source.reveal();
    });
  }

  static bool get _rebuildsNow =>
      SchedulerBinding.instance.schedulerPhase !=
      SchedulerPhase.persistentCallbacks;

  /// The source's resolved top-left radius, bounded by [size].
  double radius(Size size) {
    final half = size.shortestSide / 2;
    return switch (_shape ?? tag?.shape) {
      StadiumBorder() || CircleBorder() => half,
      RoundedRectangleBorder(:final borderRadius) ||
      ContinuousRectangleBorder(:final borderRadius) ||
      RoundedSuperellipseBorder(
        :final borderRadius,
      ) => math.min(half, borderRadius.resolve(_direction).topLeft.x),
      _ => 0,
    };
  }

  /// The container's opacity during a close with no live source.
  ///
  /// Dissolves over the first half of the remaining progress, continuously
  /// from the frame at which source loss is observed.
  double opacity(double progress, {required bool closing}) {
    if (!closing) return 1;
    if (_dissolveStart == null && isLost) _dissolveStart = progress;
    final start = _dissolveStart;
    if (start == null) return 1;
    if (start <= 0) return 0;
    return ((progress / start - 0.5) * 2).clamp(0.0, 1.0);
  }

  /// Whether [crossfade] shows the source's look at [fade] in a container
  /// of [size].
  ///
  /// A caller rebuilds the crossfade when this flips; between flips the
  /// look's opacity follows the motion without a build.
  bool showsLook(double fade, Size size) =>
      !isLost && tag != null && fade < 1 && !size.isEmpty;

  /// What [crossfade] builds at [fade] in a container of [size]: whether
  /// the look shows and, while it does, the source widget it replicates.
  ///
  /// A caller rebuilds the crossfade when this changes, including when the
  /// source tag takes a new widget mid-zoom.
  Object? look(double fade, Size size) {
    final shows = showsLook(fade, size);
    return (shows, shows ? tag?.widget : null);
  }

  /// Notifies when the source tag takes a new widget, or null without a
  /// mounted source.
  Listenable? get revisions {
    final source = tag;
    return source != null && source.mounted ? source.revisions : null;
  }

  /// Crossfades the source's look over [content].
  ///
  /// The look fills a container of [size] and fades by `1 - fadeOf()`,
  /// read again on every notification of [live], so the result builds
  /// again only when [look] or [size] changes.
  Widget crossfade({
    required Listenable? live,
    required double Function() fadeOf,
    required Size size,
    required Widget content,
  }) {
    final source = tag;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        if (source != null && showsLook(fadeOf(), size))
          Positioned.fill(
            child: IgnorePointer(
              child: MorphLiveOpacity(
                live: live,
                opacityOf: () => (1 - fadeOf()).clamp(0.0, 1.0),
                child: ExcludeFocus(
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.fill,
                      alignment: Alignment.topLeft,
                      child: SizedBox.fromSize(
                        size: size,
                        child: _themes?.wrap(source.replica) ?? source.replica,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Clips a zoom container to its current shape.
@internal
class MorphZoomShapeClipper extends CustomClipper<RRect> {
  /// Creates a clipper for [shape].
  const MorphZoomShapeClipper(this.shape);

  /// The current container shape.
  final RRect shape;

  @override
  RRect getClip(Size size) => shape;

  @override
  bool shouldReclip(MorphZoomShapeClipper oldClipper) =>
      oldClipper.shape != shape;
}

/// Clips a zoom container to its current shape with continuous corners:
/// the rounded superellipse of the shape's radii, as UIKit's sheet draws
/// them.
@internal
class MorphZoomContinuousClipper extends CustomClipper<RSuperellipse> {
  /// Creates a clipper for [shape].
  const MorphZoomContinuousClipper(this.shape);

  /// The current container shape.
  final RRect shape;

  @override
  RSuperellipse getClip(Size size) => RSuperellipse.fromLTRBAndCorners(
    shape.left,
    shape.top,
    shape.right,
    shape.bottom,
    topLeft: shape.tlRadius,
    topRight: shape.trRadius,
    bottomLeft: shape.blRadius,
    bottomRight: shape.brRadius,
  );

  @override
  bool shouldReclip(MorphZoomContinuousClipper oldClipper) =>
      oldClipper.shape != shape;
}
