import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/theme/theme.dart';

/// The measured look and timing of UIKit's vertical scroll indicator.
///
/// Read from a simulator film (iPhone 17 Pro, iOS 27.0, 2026-10-14, the
/// sweep's large-title table scrolled by XCUITest drags; light mode):
/// the indicator is 3 points thick with round ends, 3 points from the
/// trailing edge of the screen, 3 points below the navigation bar; it
/// shows at full strength on the first frame the content moves, stays
/// while it moves and [hideDelay] after the content comes to rest (the
/// finger lifted and any deceleration or bounce over: 1.06 and 1.08 s in
/// two captures), then fades out over [fadeDuration]. Over a cyan row it
/// darkened the color to 0.645 of itself: black at 0.35. A pull past the
/// top shortens it, pinned to its end (99 -> 18 points at the deepest pull
/// filmed).
abstract final class MorphScrollIndicatorTuning {
  /// The thickness of the indicator.
  static const double thickness = 3;

  /// The space between the indicator and the trailing edge of the scroll
  /// view.
  static const double edgeInset = 3;

  /// The space between the ends of the track and the bars over the
  /// content (UIKit's indicator insets follow the content insets; the
  /// track starts 3 points below the navigation bar).
  static const double endInset = 3;

  /// The color in light mode: black at 0.35 (measured).
  static const Color lightColor = Color(0x59000000);

  /// The color in dark mode: white at 0.35. NOT measured (UIKit's default
  /// indicator style flips to white on a dark background); pending a dark
  /// capture.
  static const Color darkColor = Color(0x59FFFFFF);

  /// How long the indicator stays after the content comes to rest
  /// (measured 1.06 - 1.08 s).
  static const double hideDelay = 1.07;

  /// How long the indicator fades out (measured ~0.2 s, about linear).
  static const double fadeDuration = 0.2;

  /// The shortest the indicator gets for a long content. NOT measured
  /// (Flutter's CupertinoScrollbar value); pending a device capture.
  static const double minLength = 36;

  /// The shortest the indicator gets while the content is pulled past an
  /// end. NOT measured (18 points were seen at the deepest pull filmed;
  /// Flutter's CupertinoScrollbar value); pending a device capture.
  static const double minOverscrollLength = 8;
}

/// UIKit's vertical scroll indicator over a scroll view driven by
/// [controller]: a thin bar along the trailing edge that shows while the
/// content moves and fades out once it rests (see
/// [MorphScrollIndicatorTuning] for the measured look and timing).
///
/// Place it over the scroll view, the same size. [padding] keeps the track
/// clear of the bars over the content; [contentPadding] is the part of
/// the scroll view's extent that is padding under those bars rather than
/// content (the top and bottom sliver paddings of a
/// `MorphNavigationScaffold`), so the indicator measures only the content
/// as UIKit measures its content size. The indicator only paints: a
/// scroll repaints it alone, and it takes no touches.
class MorphScrollIndicator extends StatefulWidget {
  /// Creates an indicator following [controller].
  const MorphScrollIndicator({
    required this.controller,
    this.padding = EdgeInsets.zero,
    this.contentPadding = EdgeInsets.zero,
    this.color,
    super.key,
  });

  /// The controller of the scroll view the indicator follows.
  final ScrollController controller;

  /// The space between the scroll view's edges and the track, before the
  /// [MorphScrollIndicatorTuning.endInset].
  final EdgeInsets padding;

  /// The scroll view's padding at its top and bottom that is not content.
  final EdgeInsets contentPadding;

  /// The color; null takes [MorphScrollIndicatorTuning.lightColor] or
  /// [MorphScrollIndicatorTuning.darkColor] by the ambient brightness.
  final Color? color;

  @override
  State<MorphScrollIndicator> createState() => _MorphScrollIndicatorState();
}

class _MorphScrollIndicatorState extends State<MorphScrollIndicator>
    with SingleTickerProviderStateMixin<MorphScrollIndicator> {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: Duration(
      microseconds: (MorphScrollIndicatorTuning.fadeDuration * 1e6).round(),
    ),
  );
  ScrollPosition? _position;
  Timer? _hide;
  late Listenable _repaint = Listenable.merge([widget.controller, _fade]);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_moved);
  }

  @override
  void didUpdateWidget(MorphScrollIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_moved);
      widget.controller.addListener(_moved);
      _follow(null);
      _repaint = Listenable.merge([widget.controller, _fade]);
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _follow(null);
    widget.controller.removeListener(_moved);
    _fade.dispose();
    super.dispose();
  }

  void _follow(ScrollPosition? position) {
    if (identical(position, _position)) return;
    _position?.isScrollingNotifier.removeListener(_scrollingChanged);
    _position = position;
    position?.isScrollingNotifier.addListener(_scrollingChanged);
  }

  void _moved() {
    final controller = widget.controller;
    if (controller.positions.length != 1) return;
    final position = controller.position;
    _follow(position);
    if (!position.isScrollingNotifier.value) return;
    _hide?.cancel();
    _hide = null;
    _fade.value = 1;
  }

  void _scrollingChanged() {
    final position = _position;
    if (position == null || position.isScrollingNotifier.value) return;
    if (_fade.value == 0) return;
    _hide?.cancel();
    _hide = Timer(
      Duration(
        microseconds: (MorphScrollIndicatorTuning.hideDelay * 1e6).round(),
      ),
      () {
        _hide = null;
        if (!mounted) return;
        if (_position?.isScrollingNotifier.value ?? false) return;
        // A frame may be due already: start the fade from it.
        SchedulerBinding.instance.scheduleFrame();
        _fade.reverse(from: 1);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        (morphBrightnessOf(context) == Brightness.dark
            ? MorphScrollIndicatorTuning.darkColor
            : MorphScrollIndicatorTuning.lightColor);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _IndicatorPainter(
            controller: widget.controller,
            fade: _fade,
            repaint: _repaint,
            padding: widget.padding,
            contentPadding: widget.contentPadding,
            color: color,
            rtl: Directionality.maybeOf(context) == TextDirection.rtl,
          ),
        ),
      ),
    );
  }
}

/// Where the indicator of a scroll view stands: its top and length along
/// a track [track] long, or null when the content fits.
///
/// [visible] is the content's visible extent and [content] its whole
/// extent (both without the padding under the bars); [offset] runs from 0
/// to `content - visible`, beyond on a pull. Past an end the indicator
/// shortens by the overscroll, pinned to that end.
@internal
({double top, double length})? morphScrollIndicatorFrame({
  required double track,
  required double visible,
  required double content,
  required double offset,
}) {
  if (track <= 0 || content <= visible + 0.5 || visible <= 0) return null;
  final range = content - visible;
  var length = math.max(
    math.min(track, MorphScrollIndicatorTuning.minLength),
    track * visible / content,
  );
  final over = offset < 0
      ? -offset
      : offset > range
      ? offset - range
      : 0.0;
  if (over > 0) {
    length = math.max(
      math.min(length, MorphScrollIndicatorTuning.minOverscrollLength),
      length - over,
    );
  }
  final f = (offset / range).clamp(0.0, 1.0);
  return (top: f * (track - length), length: length);
}

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({
    required this.controller,
    required this.fade,
    required Listenable repaint,
    required this.padding,
    required this.contentPadding,
    required this.color,
    required this.rtl,
  }) : super(repaint: repaint);

  final ScrollController controller;
  final Animation<double> fade;
  final EdgeInsets padding;
  final EdgeInsets contentPadding;
  final Color color;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = fade.value;
    if (alpha <= 0 || controller.positions.length != 1) return;
    final position = controller.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) {
      return;
    }
    const inset = MorphScrollIndicatorTuning.endInset;
    final top = padding.top + inset;
    final track = size.height - padding.bottom - inset - top;
    final pads = contentPadding.top + contentPadding.bottom;
    final visible = position.viewportDimension - pads;
    final content =
        position.maxScrollExtent -
        position.minScrollExtent +
        position.viewportDimension -
        pads;
    final frame = morphScrollIndicatorFrame(
      track: track,
      visible: visible,
      content: content,
      offset: position.pixels - position.minScrollExtent,
    );
    if (frame == null) return;
    const thickness = MorphScrollIndicatorTuning.thickness;
    final x = rtl
        ? MorphScrollIndicatorTuning.edgeInset
        : size.width - MorphScrollIndicatorTuning.edgeInset - thickness;
    final rect = Rect.fromLTWH(x, top + frame.top, thickness, frame.length);
    final paint = Paint();
    paint.color = color.withValues(alpha: color.a * alpha);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(thickness / 2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) =>
      !identical(old.controller, controller) ||
      old.padding != padding ||
      old.contentPadding != contentPadding ||
      old.color != color ||
      old.rtl != rtl;
}
