import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// The look of a [MorphPageControl].
@immutable
class MorphPageControlStyle {
  /// Creates a style; the defaults are UIKit's page indicator colors,
  /// meant for content behind the control.
  const MorphPageControlStyle({
    this.indicatorColor = const Color(0x73FFFFFF),
    this.currentIndicatorColor = const Color(0xFFFFFFFF),
    this.platterColor = const Color(0xFFF0F0F2),
    this.platterIndicatorColor = const Color(0x40000000),
    this.disabledOpacity = 0.35,
  });

  /// The color of the other pages' dots: white at 45 percent.
  final Color indicatorColor;

  /// The color of the current page's dot.
  final Color currentIndicatorColor;

  /// The flat stand-in for the prominent background's platter.
  final Color platterColor;

  /// The color of the other pages' dots on the platter.
  final Color platterIndicatorColor;

  /// The opacity of a disabled page control.
  final double disabledOpacity;

  /// The light appearance, as the simulator renders it.
  static const light = MorphPageControlStyle();

  /// The dark appearance, as the simulator renders it.
  static const dark = MorphPageControlStyle(
    platterColor: Color(0xFF1F1F1F),
    platterIndicatorColor: Color(0x4DFFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphPageControlStyle resolve(
    BuildContext context,
    MorphPageControlStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.pageControl ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

/// When a [MorphPageControl] shows its platter, after
/// UIPageControl.BackgroundStyle.
enum MorphPageControlBackground {
  /// Only while the user interacts with the control.
  automatic,

  /// Always.
  prominent,

  /// Never.
  minimal,
}

/// The measured geometry and motion of iOS 27's UIPageControl.
abstract final class MorphPageControlTuning {
  /// The box of one page's indicator.
  static const double indicatorSize = 9.67;

  /// The diameter of a drawn dot.
  static const double dotSize = 7.67;

  /// The gap between two indicators.
  static const double spacing = 8;

  /// The width of the current indicator while it shows a progress.
  static const double progressIndicatorWidth = 27.33;

  /// The padding between the dots and the platter's ends.
  static const double padding = 14;

  /// The height of the control and its platter.
  static const double height = 25.67;

  /// The spring an indicator's width changes on when the current page of
  /// a control showing progress changes (fitted to the simulator's
  /// frames, 0.08 point rms).
  static const widthSpring = MorphSpring(0.398, 0.927);

  /// The spring the finished progress fades out on (0.002 rms).
  static const fadeSpring = MorphSpring(0.381, 0.963);

  /// Seconds a touch rests on the control before its platter shows (and
  /// the dots take the platter's colors) under
  /// [MorphPageControlBackground.automatic]: 0.19 - 0.2 s on an iPhone 16
  /// Pro at 120 Hz (the 60 Hz simulator read 0.2).
  static const double platterDelay = 0.193;

  /// The spring the platter fades in on (critically damped 0.100 s on the
  /// device, 0.001 rms; 0.106 / 0.973 on the simulator's coarser frames).
  static const platterInSpring = MorphSpring(0.100, 1);

  /// The spring the platter fades out on (0.001 rms).
  static const platterOutSpring = MorphSpring(0.100, 1);

  /// Seconds between the lift of the touch and the platter's fade out
  /// (0.03 - 0.035 s on the device; 0.02 on the simulator).
  static const double platterOutDelay = 0.032;

  /// How far a touch travels before it scrubs instead of tapping.
  static const double scrubSlop = 10;

  /// How far past the midpoint between two dots a scrubbing finger goes
  /// before the page changes, either way (1 - 2 points measured, a frame
  /// of latency included).
  static const double scrubHysteresis = 1.5;

  /// The distance between two dot centers.
  static const double pitch = indicatorSize + spacing;
}

/// The motion of an iOS 27 page control's indicators.
///
/// Without a progress every dot is [MorphPageControlTuning.indicatorSize]
/// wide and a page change is instant, as UIKit's is. With a progress the
/// current indicator is a capsule
/// [MorphPageControlTuning.progressIndicatorWidth] wide whose fill shows
/// the progress; when the
/// page changes, the old capsule shrinks to a dot and the new one grows on
/// [MorphPageControlTuning.widthSpring] while the old fill fades out on
/// [MorphPageControlTuning.fadeSpring]. Times are seconds.
class MorphPageControlMotion {
  /// Creates a motion of [count] pages showing [page].
  MorphPageControlMotion({
    required int count,
    required int page,
    this.showsProgress = false,
  }) : _page = page,
       _widths = [
         for (var i = 0; i < count; i++)
           MorphSpringState(
             MorphPageControlTuning.widthSpring,
             _restWidth(i == page, showsProgress),
           ),
       ];

  static double _restWidth(bool current, bool progress) => current && progress
      ? MorphPageControlTuning.progressIndicatorWidth
      : MorphPageControlTuning.indicatorSize;

  /// Whether the current indicator shows a progress.
  bool showsProgress;

  int _page;
  final List<MorphSpringState> _widths;
  final MorphSpringState _platter = MorphSpringState(
    MorphPageControlTuning.platterInSpring,
    0,
  );
  final MorphTimeline _timeline = MorphTimeline(now: 0);
  double? _downX;
  bool _scrubbing = false;
  bool _stepped = false;

  /// Called with the page a touch picks.
  ValueChanged<int>? onChanged;

  /// The opacity of the platter under a touch at time [t], 0 to 1.
  double platter(double t) => _platter.value(t).clamp(0.0, 1.0);

  /// Whether a touch is scrubbing through the pages.
  bool get isScrubbing => _scrubbing;
  MorphSpringState? _fade;
  int _fading = -1;
  double _now = 0;

  /// The number of pages.
  int get count => _widths.length;

  /// The current page.
  int get page => _page;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether nothing moves.
  bool get isSettled =>
      _downX == null &&
      _timeline.isEmpty &&
      _platter.isAtRest(_now, 0.002) &&
      _widths.every((MorphSpringState w) => w.isAtRest(_now, 0.01)) &&
      (_fade?.isAtRest(_now, 0.002) ?? true);

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t < _now) return;
    _timeline.runDue(t);
    _now = t;
  }

  /// A finger touched the control at [x], measured from the start of the
  /// dots.
  void pointerDown(double t, double x) {
    advance(t);
    _downX = x;
    _scrubbing = false;
    _stepped = false;
    _timeline.clear();
    _timeline.at(
      t + MorphPageControlTuning.platterDelay,
      (double s) => _platter.retarget(
        s,
        1,
        spring: MorphPageControlTuning.platterInSpring,
      ),
    );
  }

  /// The finger moved to [x].
  void pointerMove(double t, double x) {
    advance(t);
    final from = _downX;
    if (from == null) return;
    if (!_scrubbing && (x - from).abs() <= MorphPageControlTuning.scrubSlop) {
      return;
    }
    _scrubbing = true;
    const pitch = MorphPageControlTuning.pitch;
    const h = MorphPageControlTuning.scrubHysteresis;
    final ahead = x - center(_page, t);
    var next = _page;
    if (ahead > pitch / 2 + h) {
      next = _page + ((ahead - pitch / 2 - h) / pitch).floor() + 1;
    } else if (ahead < -pitch / 2 - h) {
      next = _page - ((-ahead - pitch / 2 - h) / pitch).floor() - 1;
    }
    next = next.clamp(0, count - 1);
    if (next != _page) {
      _stepped = true;
      setPage(t, next);
      onChanged?.call(next);
    }
  }

  /// The finger lifted at [x]; a tap on the trailing half of a control
  /// [width] wide (dots and padding) steps forward, on the leading half
  /// back, unless the touch scrubbed.
  void pointerUp(double t, double x, {required double width}) {
    advance(t);
    final from = _downX;
    _downX = null;
    _hidePlatter(t);
    if (from == null || _scrubbing || _stepped) {
      _scrubbing = false;
      return;
    }
    final mid = width / 2 - MorphPageControlTuning.padding;
    final next = (_page + (x > mid ? 1 : -1)).clamp(0, count - 1);
    if (next != _page) {
      setPage(t, next);
      onChanged?.call(next);
    }
  }

  /// The touch was cancelled.
  void pointerCancel(double t) {
    advance(t);
    _downX = null;
    _scrubbing = false;
    _hidePlatter(t);
  }

  void _hidePlatter(double t) {
    _timeline.clear();
    _timeline.at(
      t + MorphPageControlTuning.platterOutDelay,
      (double s) => _platter.retarget(
        s,
        0,
        spring: MorphPageControlTuning.platterOutSpring,
      ),
    );
  }

  /// Shows [page] from time [t]; animated only while showing progress.
  void setPage(double t, int page) {
    advance(t);
    final next = page.clamp(0, count - 1);
    if (next == _page) return;
    final previous = _page;
    _page = next;
    if (!showsProgress) {
      for (var i = 0; i < count; i++) {
        _widths[i].snap(t, MorphPageControlTuning.indicatorSize);
      }
      return;
    }
    _widths[previous].retarget(t, MorphPageControlTuning.indicatorSize);
    _widths[next].retarget(t, MorphPageControlTuning.progressIndicatorWidth);
    final fade = MorphSpringState(MorphPageControlTuning.fadeSpring, 1);
    fade.retarget(t, 0);
    _fade = fade;
    _fading = previous;
  }

  /// The width of indicator [index] at time [t].
  double width(int index, double t) => _widths[index].value(t);

  /// The opacity of the fill of indicator [index] at time [t]: 1 on the
  /// current page, fading on the page just left, 0 elsewhere.
  double fillOpacity(int index, double t) {
    if (index == _page) return 1;
    if (index == _fading) return (_fade?.value(t) ?? 0).clamp(0.0, 1.0);
    return 0;
  }

  /// The width of all indicators and the gaps between them at time [t].
  double contentWidth(double t) {
    var w = MorphPageControlTuning.spacing * (count - 1);
    for (var i = 0; i < count; i++) {
      w += width(i, t);
    }
    return w;
  }

  /// The center of indicator [index] from the start of the dots at
  /// time [t].
  double center(int index, double t) {
    var x = 0.0;
    for (var i = 0; i < index; i++) {
      x += width(i, t) + MorphPageControlTuning.spacing;
    }
    return x + width(index, t) / 2;
  }
}

/// A page control that looks and steps like iOS 27's UIPageControl.
///
/// Dots for [count] pages, the current one opaque. A tap on the trailing
/// half of the control moves to the next page and one on the leading half
/// to the previous page, as UIKit's does. With [progress] the current
/// indicator becomes a capsule whose fill shows how far the page has
/// progressed (UIPageControlProgress); see [MorphPageControlMotion]. The
/// platter behind the dots shows per [background].
///
/// The control is focusable: the arrows step through the pages; screen
/// readers see an adjustable value "page n of count". In a right-to-left
/// context the pages run from the right.
class MorphPageControl extends StatefulWidget {
  /// Creates a page control.
  const MorphPageControl({
    required this.count,
    required this.page,
    required this.onChanged,
    this.progress,
    this.background = MorphPageControlBackground.automatic,
    this.style,
    this.semanticLabel,
    super.key,
  });

  /// The number of pages.
  final int count;

  /// The current page.
  final int page;

  /// Called with the page the user picks; null disables the control.
  final ValueChanged<int>? onChanged;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// dots.
  final double? progress;

  /// When the platter shows.
  final MorphPageControlBackground background;

  /// The look of the control; null resolves it from the theme.
  final MorphPageControlStyle? style;

  /// The label screen readers announce for the control.
  final String? semanticLabel;

  @override
  State<MorphPageControl> createState() => _MorphPageControlState();
}

class _MorphPageControlState extends State<MorphPageControl>
    with
        SingleTickerProviderStateMixin<MorphPageControl>,
        MorphClock<MorphPageControl> {
  late MorphPageControlMotion _motion = _create();
  bool _focused = false;
  int? _pointer;

  double _dotsX(Offset local, bool rtl) {
    final x = rtl ? _size.width - local.dx : local.dx;
    return x - MorphPageControlTuning.padding;
  }

  void _picked(int page) {
    if (page != widget.page) widget.onChanged?.call(page);
  }

  MorphPageControlMotion _create() {
    final motion = MorphPageControlMotion(
      count: math.max(1, widget.count),
      page: widget.page.clamp(0, math.max(0, widget.count - 1)),
      showsProgress: widget.progress != null,
    );
    motion.onChanged = _picked;
    return motion;
  }

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void didUpdateWidget(MorphPageControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count ||
        (widget.progress == null) != (oldWidget.progress == null)) {
      _motion = _create();
      return;
    }
    if (widget.page != _motion.page) {
      _motion.setPage(clock, widget.page);
      wake();
    }
  }

  bool get _enabled => widget.onChanged != null;

  void _step(int delta) {
    final next = (widget.page + delta).clamp(0, widget.count - 1);
    if (next != widget.page) widget.onChanged?.call(next);
  }

  Size get _size {
    final dots = _motion.contentWidth(_motion.time);
    return Size(
      dots + 2 * MorphPageControlTuning.padding,
      MorphPageControlTuning.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphPageControlStyle.resolve(context, widget.style);
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final count = widget.count;
    return MorphDisabled(
      enabled: _enabled,
      opacity: style.disabledOpacity,
      child: MorphControlFocus(
        enabled: _enabled,
        onHighlight: (bool v) => setState(() => _focused = v),
        onStep: (int delta) => _step(rtl ? -delta : delta),
        child: MorphFocusRing(
          visible: _focused,
          child: Semantics(
            container: true,
            enabled: _enabled,
            label: widget.semanticLabel,
            value: 'page ${widget.page + 1} of $count',
            increasedValue: widget.page + 1 < count
                ? 'page ${widget.page + 2} of $count'
                : null,
            decreasedValue: widget.page > 0
                ? 'page ${widget.page} of $count'
                : null,
            onIncrease: _enabled && widget.page + 1 < count
                ? () => _step(1)
                : null,
            onDecrease: _enabled && widget.page > 0 ? () => _step(-1) : null,
            child: MorphTouchListener(
              enabled: _enabled,
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent e) {
                if (!_enabled || e.buttons != kPrimaryButton) return;
                _pointer = e.pointer;
                _motion.pointerDown(stamp(e), _dotsX(e.localPosition, rtl));
              },
              onPointerMove: (PointerMoveEvent e) {
                if (e.pointer != _pointer) return;
                _motion.pointerMove(stamp(e), _dotsX(e.localPosition, rtl));
              },
              onPointerUp: (PointerUpEvent e) {
                if (e.pointer != _pointer) return;
                _pointer = null;
                _motion.pointerUp(
                  stamp(e),
                  _dotsX(e.localPosition, rtl),
                  width: _size.width,
                );
              },
              onPointerCancel: (PointerCancelEvent e) {
                if (e.pointer != _pointer) return;
                _pointer = null;
                _motion.pointerCancel(stamp(e));
              },
              child: ListenableBuilder(
                listenable: frames,
                builder: (BuildContext context, Widget? _) => CustomPaint(
                  size: _size,
                  painter: _PageControlPainter(
                    motion: _motion,
                    style: style,
                    rtl: rtl,
                    platter: switch (widget.background) {
                      MorphPageControlBackground.prominent => true,
                      MorphPageControlBackground.minimal => false,
                      MorphPageControlBackground.automatic => null,
                    },
                    progress: widget.progress,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageControlPainter extends CustomPainter {
  _PageControlPainter({
    required this.motion,
    required this.style,
    required this.rtl,
    required this.platter,
    required this.progress,
  });

  final MorphPageControlMotion motion;
  final MorphPageControlStyle style;
  final bool rtl;
  final bool? platter;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = motion.time;
    final shown = switch (platter) {
      true => 1.0,
      false => 0.0,
      null => motion.platter(t),
    };
    if (shown > 0) {
      final p = Paint();
      p.color = style.platterColor.withValues(
        alpha: style.platterColor.a * shown,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
        p,
      );
    }
    final other = Color.lerp(
      style.indicatorColor,
      style.platterIndicatorColor,
      shown,
    )!;
    const dot = MorphPageControlTuning.dotSize;
    const inset = (MorphPageControlTuning.indicatorSize - dot) / 2;
    final cy = size.height / 2;
    for (var i = 0; i < motion.count; i++) {
      final w = motion.width(i, t);
      var cx = MorphPageControlTuning.padding + motion.center(i, t);
      if (rtl) cx = size.width - cx;
      final shape = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: w - 2 * inset,
          height: dot,
        ),
        const Radius.circular(dot / 2),
      );
      final fill = progress == null ? 0.0 : motion.fillOpacity(i, t);
      final base = Paint();
      base.color = progress == null && i == motion.page
          ? style.currentIndicatorColor
          : other;
      canvas.drawRRect(shape, base);
      if (fill > 0) {
        final fraction = i == motion.page ? (progress ?? 0) : 1.0;
        final fillWidth = dot + (shape.width - dot) * fraction.clamp(0, 1);
        final left = rtl ? shape.right - fillWidth : shape.left;
        final paint = Paint();
        paint.color = style.currentIndicatorColor.withValues(
          alpha: style.currentIndicatorColor.a * fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, shape.top, fillWidth, dot),
            const Radius.circular(dot / 2),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PageControlPainter oldDelegate) => true;
}
