import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/motion/motion.dart';
import 'package:morph/src/motion/spring.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/haptics.dart';
import 'package:morph/src/motion/spring_state.dart';
import 'package:morph/src/motion/timeline.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/theme/theme.dart';

/// The look of a [MorphPageControl].
@immutable
class MorphPageControlAppearance implements MorphAppearance {
  /// Creates an appearance; the defaults are UIKit's page indicator colors,
  /// meant for content behind the control.
  const MorphPageControlAppearance({
    this.pageIndicatorColor = const Color(0x73FFFFFF),
    this.currentPageIndicatorColor = const Color(0xFFFFFFFF),
    this.platterColor = const Color(0xFFF0F0F2),
    this.platterIndicatorColor = const Color(0x40000000),
  });

  /// The color of the other pages' dots: white at 45 percent (UIKit
  /// `pageIndicatorTintColor`).
  final Color pageIndicatorColor;

  /// The color of the current page's dot (UIKit
  /// `currentPageIndicatorTintColor`).
  final Color currentPageIndicatorColor;

  /// The flat stand-in for the prominent background's platter.
  final Color platterColor;

  /// The color of the other pages' dots on the platter.
  final Color platterIndicatorColor;

  /// The light appearance, as the simulator renders it.
  static const light = MorphPageControlAppearance();

  /// The dark appearance, as the simulator renders it.
  static const dark = MorphPageControlAppearance(
    platterColor: Color(0xFF1F1F1F),
    platterIndicatorColor: Color(0x4DFFFFFF),
  );

  /// The light appearance under Increase Contrast: the other pages' dots
  /// turn from 45 to 55 percent white and, on the platter, from 25 to 45
  /// percent black (read from UIKit's color tables, notes private).
  static const lightHighContrast = MorphPageControlAppearance(
    pageIndicatorColor: Color(0x8CFFFFFF),
    platterIndicatorColor: Color(0x73000000),
  );

  /// The dark appearance under Increase Contrast: the platter's other
  /// dots take UIKit's 45 percent white (read from UIKit's color tables,
  /// notes private; UIKit's standard dark value is 25 percent where the
  /// simulator renders 30).
  static const darkHighContrast = MorphPageControlAppearance(
    pageIndicatorColor: Color(0x8CFFFFFF),
    platterColor: Color(0xFF1F1F1F),
    platterIndicatorColor: Color(0x73FFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness and contrast.
  static MorphPageControlAppearance resolve(
    BuildContext context,
    MorphPageControlAppearance? explicit,
  ) => morphResolveAppearance(
    context,
    explicit,
    light: light,
    dark: dark,
    lightHighContrast: lightHighContrast,
    darkHighContrast: darkHighContrast,
  );

  /// Copies this appearance with the given fields replaced.
  MorphPageControlAppearance copyWith({
    Color? pageIndicatorColor,
    Color? currentPageIndicatorColor,
    Color? platterColor,
    Color? platterIndicatorColor,
  }) => MorphPageControlAppearance(
    pageIndicatorColor: pageIndicatorColor ?? this.pageIndicatorColor,
    currentPageIndicatorColor:
        currentPageIndicatorColor ?? this.currentPageIndicatorColor,
    platterColor: platterColor ?? this.platterColor,
    platterIndicatorColor: platterIndicatorColor ?? this.platterIndicatorColor,
  );

  @override
  bool operator ==(Object other) =>
      other is MorphPageControlAppearance &&
      other.pageIndicatorColor == pageIndicatorColor &&
      other.currentPageIndicatorColor == currentPageIndicatorColor &&
      other.platterColor == platterColor &&
      other.platterIndicatorColor == platterIndicatorColor;

  @override
  int get hashCode => Object.hash(
    pageIndicatorColor,
    currentPageIndicatorColor,
    platterColor,
    platterIndicatorColor,
  );
}

/// When a [MorphPageControl] shows its platter, after
/// UIPageControl.BackgroundStyle.
enum MorphPageControlBackgroundStyle {
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
  /// [MorphPageControlBackgroundStyle.automatic]: 0.19 - 0.2 s on an iPhone 16
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
class MorphPageControlMotion
    with MorphMotionEvents<MorphPageControlEvent>
    implements MorphMotion<MorphPageControlEvent> {
  /// Creates a motion of [count] pages showing [page].
  MorphPageControlMotion({
    required int count,
    required int page,
    this.showsProgress = false,
  }) : _page = count > 0 ? page.clamp(0, count - 1) : 0,
       _widths = [
         for (var i = 0; i < count; i++)
           MorphSpringState(
             MorphPageControlTuning.widthSpring,
             _restWidth(i == page.clamp(0, count - 1), showsProgress),
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

  /// The opacity of the platter under a touch, 0 to 1.
  double get platter => _platter.value(_now).clamp(0.0, 1.0);

  /// Whether a touch is scrubbing through the pages.
  bool get isScrubbing => _scrubbing;

  MorphSpringState? _fade;
  int _fading = -1;
  double _now = 0;

  /// The number of pages.
  int get count => _widths.length;

  /// The current page.
  int get page => _page;

  @override
  double get time => _now;

  /// Whether nothing moves. A resting finger does not count: the
  /// control's moves and lift arrive as stamped pointer events, which wake
  /// the clock.
  @override
  bool get isSettled => _timeline.isEmpty && _still;

  @override
  void settle() {
    _platter.settle(_now);
    for (final w in _widths) {
      w.settle(_now);
    }
    _fade?.settle(_now);
  }

  /// Whether what remains is invisible ([MorphRest], NEAR): the platter
  /// and the old fill fade by less than [MorphRest.opacity], the widths
  /// swing less than [MorphRest.length].
  bool get _still =>
      _platter.isWithin(_now, MorphRest.opacity) &&
      _widths.every(
        (MorphSpringState w) => w.isWithin(_now, MorphRest.length),
      ) &&
      (_fade?.isWithin(_now, MorphRest.opacity) ?? true);

  /// The time before which nothing moves, or null while something does:
  /// a touch waiting out the platter's delay draws nothing new.
  @override
  double? get wakeTime => _still ? _timeline.nextDue : null;

  @override
  void advance(double t) {
    if (t < _now) return;
    _timeline.runDue(t);
    _now = t;
  }

  /// A finger touched the control at [x], measured from the start of the
  /// dots.
  void pointerDown(double t, double x) {
    advance(t);
    if (count == 0) return;
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
    if (from == null || count == 0) return;
    if (!_scrubbing && (x - from).abs() <= MorphPageControlTuning.scrubSlop) {
      return;
    }
    _scrubbing = true;
    const pitch = MorphPageControlTuning.pitch;
    const h = MorphPageControlTuning.scrubHysteresis;
    final ahead = x - center(_page);
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
      emit(MorphPageControlPicked(next, scrubbed: true));
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
    if (count == 0 || from == null || _scrubbing || _stepped) {
      _scrubbing = false;
      return;
    }
    final mid = width / 2 - MorphPageControlTuning.padding;
    final next = (_page + (x > mid ? 1 : -1)).clamp(0, count - 1);
    if (next != _page) {
      setPage(t, next);
      emit(MorphPageControlPicked(next, scrubbed: false));
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
    if (count == 0) return;
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

  /// The width of indicator [index].
  double width(int index) =>
      index >= 0 && index < count ? _widths[index].value(_now) : 0;

  /// The opacity of the fill of indicator [index]: 1 on the current page,
  /// fading on the page just left, 0 elsewhere.
  double fillOpacity(int index) {
    if (index == _page) return 1;
    if (index == _fading) return (_fade?.value(_now) ?? 0).clamp(0.0, 1.0);
    return 0;
  }

  /// The width of all indicators and the gaps between them.
  double get contentWidth {
    if (count == 0) return 0;
    var w = MorphPageControlTuning.spacing * (count - 1);
    for (var i = 0; i < count; i++) {
      w += width(i);
    }
    return w;
  }

  /// The center of indicator [index] from the start of the dots.
  double center(int index) {
    if (index < 0 || index >= count) return 0;
    var x = 0.0;
    for (var i = 0; i < index; i++) {
      x += width(i) + MorphPageControlTuning.spacing;
    }
    return x + width(index) / 2;
  }
}

/// A page control that looks and steps like iOS 27's UIPageControl.
///
/// Dots for [count] pages, the current one opaque. A tap on the trailing
/// half of the control moves to the next page and one on the leading half
/// to the previous page, as UIKit's does. With [progress] the current
/// indicator becomes a capsule whose fill shows how far the page has
/// progressed (UIPageControlProgress); see [MorphPageControlMotion]. The
/// platter behind the dots shows per [backgroundStyle].
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
    this.backgroundStyle = MorphPageControlBackgroundStyle.automatic,
    this.appearance,
    this.semanticLabel,
    this.semanticValueFormatter,
    super.key,
  });

  /// The number of pages.
  final int count;

  /// The current page.
  final int page;

  /// Called with the page the user picks; null disables the control.
  ///
  /// A disabled page control looks exactly like an enabled one and
  /// ignores input, as UIKit's does on iOS 27.
  final ValueChanged<int>? onChanged;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// dots.
  final double? progress;

  /// When the platter shows.
  final MorphPageControlBackgroundStyle backgroundStyle;

  /// The look of the control; null resolves it from the theme.
  final MorphPageControlAppearance? appearance;

  /// The label screen readers announce for the control.
  final String? semanticLabel;

  /// Formats the adjustable value from a one-based page and page count.
  /// Null uses the English "page n of count". Empty controls have no value.
  final String Function(int page, int count)? semanticValueFormatter;

  @override
  State<MorphPageControl> createState() => _MorphPageControlState();
}

class _MorphPageControlState extends MorphControlHost<MorphPageControl> {
  late MorphPageControlMotion _motion = _create();

  double _dotsX(Offset local, bool rtl) {
    final x = rtl ? _size.width - local.dx : local.dx;
    return x - MorphPageControlTuning.padding;
  }

  void _picked(int page) {
    if (page != _page) widget.onChanged?.call(page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _motion.page == _page) return;
      _motion.setPage(clock, _page);
      wake();
    });
  }

  MorphPageControlMotion _create() {
    final motion = MorphPageControlMotion(
      count: math.max(0, widget.count),
      page: widget.page.clamp(0, math.max(0, widget.count - 1)),
      showsProgress: widget.progress != null,
    );
    return motion;
  }

  @override
  void deliverMotionEvents() {
    for (final event in _motion.drainEvents()) {
      if (!mounted) return;
      switch (event) {
        case MorphPageControlPicked(:final page, :final scrubbed):
          _picked(page);
          // UIKit's page control plays its selection haptic when a
          // scrubbing finger moves it to another page (read from UIKit,
          // notes private).
          if (scrubbed) morphPlayHaptic(context, MorphHaptic.selection);
      }
    }
  }

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  double? get motionWakeTime => _motion.wakeTime;

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

  int get _count => math.max(0, widget.count);

  int get _page => _count == 0 ? 0 : widget.page.clamp(0, _count - 1);

  bool get _enabled => widget.onChanged != null && _count > 0;

  @override
  bool get controlEnabled => _enabled;

  bool get _rtl => Directionality.maybeOf(context) == TextDirection.rtl;

  @override
  void onControlDown(double t, PointerDownEvent event) =>
      _motion.pointerDown(t, _dotsX(event.localPosition, _rtl));

  @override
  void onControlMove(double t, PointerMoveEvent event) =>
      _motion.pointerMove(t, _dotsX(event.localPosition, _rtl));

  @override
  void onControlUp(double t, PointerUpEvent event) => _motion.pointerUp(
    t,
    _dotsX(event.localPosition, _rtl),
    width: _size.width,
  );

  @override
  void onControlCancel(double t) => _motion.pointerCancel(t);

  void _step(int delta) {
    if (!_enabled) return;
    final next = (_page + delta).clamp(0, _count - 1);
    if (next != _page) widget.onChanged?.call(next);
  }

  Size get _size {
    final dots = _motion.contentWidth;
    return Size(
      dots + 2 * MorphPageControlTuning.padding,
      MorphPageControlTuning.height,
    );
  }

  @override
  Widget buildControl(BuildContext context) {
    final style = MorphPageControlAppearance.resolve(
      context,
      widget.appearance,
    );
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final count = _count;
    final page = _page;
    String value(int page) =>
        widget.semanticValueFormatter?.call(page, count) ??
        'page $page of $count';
    return RepaintBoundary(
      child: MorphPress(
        target: this,
        enabled: _enabled,
        onHighlight: highlightControlFocus,
        onStep: (int delta) => _step(rtl ? -delta : delta),
        semantics: SemanticsProperties(
          enabled: _enabled,
          label: widget.semanticLabel,
          value: count == 0 ? null : value(page + 1),
          increasedValue: page + 1 < count ? value(page + 2) : null,
          decreasedValue: page > 0 ? value(page) : null,
          onIncrease: _enabled && page + 1 < count ? () => _step(1) : null,
          onDecrease: _enabled && page > 0 ? () => _step(-1) : null,
        ),
        semanticsContainer: true,
        behavior: HitTestBehavior.opaque,
        child: MorphFocusRing(
          visible: controlFocused,
          child: CustomPaint(
            size: _size,
            painter: _PageControlPainter(
              frames: frames,
              motion: _motion,
              style: style,
              rtl: rtl,
              platter: switch (widget.backgroundStyle) {
                MorphPageControlBackgroundStyle.prominent => true,
                MorphPageControlBackgroundStyle.minimal => false,
                MorphPageControlBackgroundStyle.automatic => null,
              },
              progress: widget.progress,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageControlPainter extends CustomPainter {
  _PageControlPainter({
    required Listenable frames,
    required this.motion,
    required this.style,
    required this.rtl,
    required this.platter,
    required this.progress,
  }) : super(repaint: frames);

  final MorphPageControlMotion motion;
  final MorphPageControlAppearance style;
  final bool rtl;
  final bool? platter;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final shown = switch (platter) {
      true => 1.0,
      false => 0.0,
      null => motion.platter,
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
      style.pageIndicatorColor,
      style.platterIndicatorColor,
      shown,
    )!;
    const dot = MorphPageControlTuning.dotSize;
    const inset = (MorphPageControlTuning.indicatorSize - dot) / 2;
    final cy = size.height / 2;
    var x = 0.0;
    for (var i = 0; i < motion.count; i++) {
      final w = motion.width(i);
      var cx = MorphPageControlTuning.padding + (x + w / 2);
      x += w + MorphPageControlTuning.spacing;
      if (rtl) cx = size.width - cx;
      final shape = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: w - 2 * inset,
          height: dot,
        ),
        const Radius.circular(dot / 2),
      );
      final fill = progress == null ? 0.0 : motion.fillOpacity(i);
      final base = Paint();
      base.color = progress == null && i == motion.page
          ? style.currentPageIndicatorColor
          : other;
      canvas.drawRRect(shape, base);
      if (fill > 0) {
        final fraction = i == motion.page ? (progress ?? 0) : 1.0;
        final fillWidth = dot + (shape.width - dot) * fraction.clamp(0, 1);
        final left = rtl ? shape.right - fillWidth : shape.left;
        final paint = Paint();
        paint.color = style.currentPageIndicatorColor.withValues(
          alpha: style.currentPageIndicatorColor.a * fill,
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
  bool shouldRepaint(_PageControlPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.style != style ||
      oldDelegate.rtl != rtl ||
      oldDelegate.platter != platter ||
      oldDelegate.progress != progress;
}

/// What a [MorphPageControlMotion] tells its host.
sealed class MorphPageControlEvent {
  const MorphPageControlEvent();
}

/// A touch picked [page]: a tap on either half, or a scrubbing finger
/// ([scrubbed]) that moved the control to another page.
final class MorphPageControlPicked extends MorphPageControlEvent {
  /// Creates the event.
  const MorphPageControlPicked(this.page, {required this.scrubbed});

  /// The page picked.
  final int page;

  /// Whether a scrubbing finger picked it.
  final bool scrubbed;
}
