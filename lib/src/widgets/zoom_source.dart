import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/themes.dart';

/// The source geometry and lifetime of a sheet or page zoom.
@internal
class MorphZoomSource {
  /// Tracks [tag] for one presentation.
  MorphZoomSource(this.tag)
    : _themes = tag != null && tag.mounted
          ? MorphThemeCarrier(tag.context)
          : null;

  /// Resolves [id] in the scope around [context], tolerating an absent tag.
  factory MorphZoomSource.resolve(BuildContext context, Object? id) =>
      MorphZoomSource(id == null ? null : MorphScope.of(context).tryTagOf(id));

  /// The source tag, or null when no source is available.
  final MorphTagState? tag;

  final MorphThemeCarrier? _themes;
  Rect? _rect;
  bool _hidden = false;
  bool _lost = false;
  double? _dissolveStart;
  ShapeBorder? _shape;
  TextDirection _direction = TextDirection.ltr;

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

  /// Hides a laid-out source after the current frame.
  void hide() {
    if (_hidden || isLost) return;
    _hidden = true;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      final source = tag;
      if (_hidden && source != null && source.mounted) source.hideForFlight();
    });
  }

  /// Reveals a source after the current frame, including on route removal.
  void reveal() {
    if (!_hidden) return;
    _hidden = false;
    final source = tag;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (source != null && source.mounted) source.reveal();
    });
  }

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
                        child: MorphSurfaceSpecScope(
                          spec: source.surfaceSpec,
                          child:
                              _themes?.wrap(source.replica) ?? source.replica,
                        ),
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
