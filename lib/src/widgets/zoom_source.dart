import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
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

  /// Crossfades source pixels with content laid out by [content].
  Widget crossfade({
    required Widget Function(double opacity) content,
    required double fade,
    required Size size,
    required bool closing,
  }) {
    final source = tag;
    final lost = isLost;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content(lost && closing ? 1 : fade),
        if (!lost && source != null && fade < 1 && !size.isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 1 - fade,
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
