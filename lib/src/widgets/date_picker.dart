import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/date_picker_motion.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// What a [MorphDatePicker] picks.
enum MorphDatePickerMode {
  /// A day: one label that opens a month calendar.
  date,

  /// A time of day: one label that opens the hour and minute wheels.
  time,

  /// A day and a time: a date label and a time label side by side.
  dateAndTime,
}

/// The look of a [MorphDatePicker] and its overlay.
@immutable
class MorphDatePickerStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphDatePickerStyle({
    this.labelFillColor = const Color(0x1F767680),
    this.labelColor = const Color(0xFF000000),
    this.accentColor = const Color(0xFF0088FF),
    this.platterColor = const Color(0xF2F9F9FB),
    this.shadowColor = const Color(0x24000000),
    this.titleColor = const Color(0xFF000000),
    this.weekdayColor = const Color(0x993C3C43),
    this.dayColor = const Color(0xFF000000),
    this.todayFillColor = const Color(0x1F0088FF),
    this.selectedDayColor = const Color(0xFFFFFFFF),
    this.selectedDayFillColor = const Color(0xFF000000),
    this.selectedDayTextColor = const Color(0xFFFFFFFF),
    this.chevronColor = const Color(0xFF000000),
    this.wheelBandColor = const Color(0x1F767680),
    this.wheelColor = const Color(0xFF000000),
    this.wheelFadedOpacity = 0.4,
    this.disabledOpacity = 0.35,
  });

  /// The fill of a compact label: tertiarySystemFill.
  final Color labelFillColor;

  /// The color of a compact label's text: label.
  final Color labelColor;

  /// The accent: the text of an open label, the month title's chevron,
  /// today's number and, when today is the chosen day, its disc.
  final Color accentColor;

  /// The flat stand-in for the overlay's material when no
  /// [MorphGlassPainter] is installed; a painter receives it as the tint.
  final Color platterColor;

  /// The shadow of the flat overlay.
  final Color shadowColor;

  /// The color of the month title.
  final Color titleColor;

  /// The color of the weekday initials: secondaryLabel.
  final Color weekdayColor;

  /// The color of a day.
  final Color dayColor;

  /// The fill behind today when it is not selected.
  final Color todayFillColor;

  /// The color of the chosen day's number when the chosen day is today,
  /// on an [accentColor] disc.
  final Color selectedDayColor;

  /// The disc behind the chosen day when it is not today: label.
  final Color selectedDayFillColor;

  /// The color of the chosen day's number on [selectedDayFillColor].
  final Color selectedDayTextColor;

  /// The color of the previous and next month chevrons: label.
  final Color chevronColor;

  /// The band behind the wheels' selected row.
  final Color wheelBandColor;

  /// The color of the wheels' rows: full inside the band, at
  /// [wheelFadedOpacity] outside it.
  final Color wheelColor;

  /// The opacity of the wheels' rows outside the band, drawn in
  /// [wheelColor] at the smaller size (21 points against the band's 23.5),
  /// before they darken toward the cylinder's edges. UIKit's labels report
  /// 0.447; 0.4 matches the screen (the rows next to the band read 0.36 of
  /// black on an iPhone 16 Pro).
  final double wheelFadedOpacity;

  /// The opacity of a disabled picker (not measured on a device).
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphDatePickerStyle();

  /// The dark appearance.
  static const dark = MorphDatePickerStyle(
    labelFillColor: Color(0x3D767680),
    labelColor: Color(0xFFFFFFFF),
    accentColor: Color(0xFF0091FF),
    platterColor: Color(0xF22C2C2E),
    shadowColor: Color(0x4D000000),
    titleColor: Color(0xFFFFFFFF),
    weekdayColor: Color(0x99EBEBF5),
    dayColor: Color(0xFFFFFFFF),
    todayFillColor: Color(0x330091FF),
    selectedDayFillColor: Color(0xFFFFFFFF),
    selectedDayTextColor: Color(0xFF000000),
    chevronColor: Color(0xFFFFFFFF),
    wheelBandColor: Color(0x3D767680),
    wheelColor: Color(0xFFFFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphDatePickerStyle resolve(
    BuildContext context,
    MorphDatePickerStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.datePicker ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdays = [
  'SUN',
  'MON',
  'TUE',
  'WED',
  'THU',
  'FRI',
  'SAT',
];

String _two(int v) => v.toString().padLeft(2, '0');

int _daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The English medium date UIKit shows in an en_US compact label, such as
/// "Oct 3, 2026".
String _defaultDate(DateTime d) =>
    '${_months[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

String _defaultTime(DateTime d, {required bool twentyFour}) {
  if (twentyFour) return '${_two(d.hour)}:${_two(d.minute)}';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// The iOS 27 compact date picker: a label that opens its picker in an
/// overlay.
///
/// The label is a tinted capsule showing [value]; a touch dims its text,
/// and a tap opens the overlay out of it: a month calendar for a date, the
/// hour and minute wheels for a time. The overlay grows out of the label's
/// center on a spring while it fades in and reveals its content from the
/// label's side, hangs below the label (above it when there is no room),
/// and extends toward the leading side; see [MorphDatePickerMotion] and
/// [morphPlaceDatePicker]. While it is open the label's text takes the
/// accent color. Choosing a day or turning a wheel calls [onChanged] at
/// once and the overlay stays open; a tap outside or Escape closes it.
///
/// The calendar shows one month with the chosen day filled and today
/// tinted; the chevrons turn the month with a slide. The labels are
/// formatted in English by default ([dateFormatter] and [timeFormatter]
/// localize them). The label is a focusable button; Space and Enter open
/// it.
class MorphDatePicker extends StatefulWidget {
  /// Creates a picker.
  const MorphDatePicker({
    required this.value,
    required this.onChanged,
    this.mode = MorphDatePickerMode.date,
    this.firstDate,
    this.lastDate,
    this.dateFormatter,
    this.timeFormatter,
    this.use24HourFormat,
    this.firstDayOfWeek = DateTime.sunday,
    this.today,
    this.style,
    this.semanticLabel,
    super.key,
  });

  /// The picked moment.
  final DateTime value;

  /// Called with the new moment when the user picks one; null disables
  /// the picker.
  final ValueChanged<DateTime>? onChanged;

  /// What the picker picks.
  final MorphDatePickerMode mode;

  /// The earliest day that can be picked; null for no limit.
  final DateTime? firstDate;

  /// The latest day that can be picked; null for no limit.
  final DateTime? lastDate;

  /// Formats the date label; null for English, such as "Oct 3, 2026".
  final String Function(DateTime)? dateFormatter;

  /// Formats the time label; null for "09:41" or "9:41 AM".
  final String Function(DateTime)? timeFormatter;

  /// Whether times use 24 hours; null follows the platform's
  /// [MediaQueryData.alwaysUse24HourFormat].
  final bool? use24HourFormat;

  /// The first column of the calendar, as a [DateTime] weekday.
  final int firstDayOfWeek;

  /// The day to tint as today; null for the current day.
  final DateTime? today;

  /// The look; null resolves it from the theme.
  final MorphDatePickerStyle? style;

  /// The label screen readers announce before the value.
  final String? semanticLabel;

  @override
  State<MorphDatePicker> createState() => _MorphDatePickerState();
}

enum _Part { date, time }

class _MorphDatePickerState extends State<MorphDatePicker> {
  _Part? _open;
  final Map<_Part, GlobalKey> _labels = {
    _Part.date: GlobalKey(debugLabel: 'date'),
    _Part.time: GlobalKey(debugLabel: 'time'),
  };

  Rect? _labelRect(_Part part) {
    final box = _labels[part]!.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _switched(_Part part) {
    if (mounted) setState(() => _open = part);
  }

  bool get _enabled => widget.onChanged != null;

  bool get _twentyFour =>
      widget.use24HourFormat ??
      MediaQuery.maybeAlwaysUse24HourFormatOf(context) ??
      false;

  Future<void> _show(_Part part, BuildContext anchor) async {
    if (!_enabled || _open != null) return;
    final box = anchor.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _open = part);
    await Navigator.of(context, rootNavigator: true).push(
      _DatePickerRoute(
        picker: this,
        part: part,
        label: rect,
        style: widget.style,
      ),
    );
    if (mounted) setState(() => _open = null);
  }

  void _changed(DateTime value) => widget.onChanged?.call(value);

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final date = widget.dateFormatter?.call(value) ?? _defaultDate(value);
    final time =
        widget.timeFormatter?.call(value) ??
        _defaultTime(value, twentyFour: _twentyFour);
    final parts = switch (widget.mode) {
      MorphDatePickerMode.date => [(_Part.date, date)],
      MorphDatePickerMode.time => [(_Part.time, time)],
      MorphDatePickerMode.dateAndTime => [
        (_Part.date, date),
        (_Part.time, time),
      ],
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: MorphDatePickerTuning.labelGap),
          _CompactLabel(
            key: _labels[parts[i].$1],
            text: parts[i].$2,
            height: parts[i].$1 == _Part.date
                ? MorphDatePickerTuning.dateLabelHeight
                : MorphDatePickerTuning.timeLabelHeight,
            open: _open == parts[i].$1,
            enabled: _enabled,
            style: widget.style,
            semanticLabel: widget.semanticLabel,
            onOpen: (BuildContext anchor) => _show(parts[i].$1, anchor),
          ),
        ],
      ],
    );
  }
}

class _CompactLabel extends StatefulWidget {
  const _CompactLabel({
    required this.text,
    required this.height,
    required this.open,
    required this.enabled,
    required this.style,
    required this.semanticLabel,
    required this.onOpen,
    super.key,
  });

  final String text;
  final double height;
  final bool open;
  final bool enabled;
  final MorphDatePickerStyle? style;
  final String? semanticLabel;
  final void Function(BuildContext anchor) onOpen;

  @override
  State<_CompactLabel> createState() => _CompactLabelState();
}

class _CompactLabelState extends State<_CompactLabel>
    with
        SingleTickerProviderStateMixin<_CompactLabel>,
        MorphClock<_CompactLabel> {
  final MorphDatePickerMotion _motion = MorphDatePickerMotion();
  bool _focused = false;
  int? _pointer;

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  void _down(PointerDownEvent event) {
    if (!widget.enabled ||
        _pointer != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    _motion.reducedMotion = morphReducedMotionOf(context);
    _motion.press(stamp(event));
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _motion.release(stamp(event));
    final box = context.findRenderObject();
    if (event is PointerUpEvent && box is RenderBox && box.hasSize) {
      final local = box.globalToLocal(event.position);
      if ((Offset.zero & box.size).contains(local)) widget.onOpen(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphDatePickerStyle.resolve(context, widget.style);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2);
    final label = widget.semanticLabel;
    return MorphDisabled(
      enabled: widget.enabled,
      opacity: style.disabledOpacity,
      child: MorphControlFocus(
        enabled: widget.enabled,
        onHighlight: (bool focused) => setState(() => _focused = focused),
        onActivate: () => widget.onOpen(context),
        child: Semantics(
          button: true,
          enabled: widget.enabled,
          expanded: widget.open,
          label: label == null ? widget.text : '$label, ${widget.text}',
          onTap: widget.enabled ? () => widget.onOpen(context) : null,
          child: ExcludeSemantics(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: MorphFocusRing(
                visible: _focused,
                child: Container(
                  constraints: BoxConstraints(minHeight: widget.height),
                  padding: const EdgeInsets.symmetric(
                    horizontal: MorphDatePickerTuning.labelPadding,
                  ),
                  decoration: ShapeDecoration(
                    color: style.labelFillColor,
                    shape: const StadiumBorder(),
                  ),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: ListenableBuilder(
                      listenable: frames,
                      builder: (BuildContext context, Widget? child) => Opacity(
                        opacity: _motion.highlight(_motion.time),
                        child: child,
                      ),
                      child: Text(
                        widget.text,
                        maxLines: 1,
                        textScaler: scaler,
                        style: MorphTypography.resolve(
                          MorphTypography.datePickerCompact.copyWith(
                            height: 20.33 / 17,
                            color: widget.open
                                ? style.accentColor
                                : style.labelColor,
                          ),
                        ),
                      ),
                    ),
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

class _DatePickerRoute extends PopupRoute<void> {
  _DatePickerRoute({
    required this.picker,
    required this.part,
    required this.label,
    required this.style,
  });

  final _MorphDatePickerState picker;
  final _Part part;
  final Rect label;
  final MorphDatePickerStyle? style;
  _OverlayViewState? _view;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(seconds: 1);

  @override
  Widget buildModalBarrier() => const IgnorePointer(child: SizedBox.expand());

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _OverlayView(route: this);

  @override
  bool didPop(void result) {
    final popped = super.didPop(result);
    controller?.stop();
    final view = _view;
    if (view == null || !view.mounted) {
      _finished();
    } else {
      view._leave();
    }
    return popped;
  }

  void _finished() {
    final c = controller;
    if (c != null && !isActive && c.value != 0) c.value = 0;
  }
}

/// The largest text scale the overlay's fixed-size calendar follows.
const double _overlayMaxTextScale = 1.2;

class _OverlayView extends StatefulWidget {
  const _OverlayView({required this.route});

  final _DatePickerRoute route;

  @override
  State<_OverlayView> createState() => _OverlayViewState();
}

class _OverlayViewState extends State<_OverlayView>
    with
        SingleTickerProviderStateMixin<_OverlayView>,
        MorphClock<_OverlayView> {
  final MorphDatePickerMotion _motion = MorphDatePickerMotion();
  bool _leaving = false;
  late DateTime _value = widget.route.picker.widget.value;
  late DateTime _month = DateTime(_value.year, _value.month);
  DateTime? _previousMonth;
  int? _outside;
  late _Part _part = widget.route.part;
  late Rect _label = widget.route.label;
  _Part? _fromPart;
  Rect? _fromLabel;
  final MorphSpringState _swap = MorphSpringState(
    MorphDatePickerTuning.switchSpring,
    1,
  );

  _DatePickerRoute get _route => widget.route;

  MorphDatePicker get _picker => _route.picker.widget;

  @override
  void initState() {
    super.initState();
    _route._view = this;
    _motion.open(clock);
    wake();
  }

  @override
  void dispose() {
    if (_route._view == this) _route._view = null;
    super.dispose();
  }

  @override
  void advanceMotion(double t) {
    _motion.advance(t);
    if (_fromPart != null && _swap.isAtRest(t, 0.001)) {
      setState(() => _fromPart = null);
    }
    if (_leaving && _motion.isClosed) _route._finished();
  }

  @override
  bool get motionSettled =>
      _motion.isSettled && _swap.isAtRest(_motion.time, 0.001);

  _Part? _otherLabelAt(Offset position) {
    for (final part in _Part.values) {
      if (part == _part) continue;
      final rect = _route.picker._labelRect(part);
      if (rect != null && rect.contains(position)) return part;
    }
    return null;
  }

  void _switchTo(_Part part) {
    final label = _route.picker._labelRect(part);
    if (label == null || _leaving) return;
    final t = clock;
    final q = _swap.value(t);
    final v = _swap.velocity(t);
    setState(() {
      final start = t + MorphDatePickerTuning.switchDelay;
      if (part == _fromPart && q < 1) {
        _swap.setState(start, 1 - q, -v);
      } else {
        _swap.setState(start, 0, 0);
      }
      _fromPart = _part;
      _fromLabel = _label;
      _part = part;
      _label = label;
    });
    _swap.retarget(t + MorphDatePickerTuning.switchDelay, 1);
    _route.picker._switched(part);
    wake();
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    _motion.close(clock);
    wake();
  }

  void _close() {
    if (_leaving) return;
    Navigator.of(context).pop();
  }

  void _pick(DateTime value) {
    setState(() => _value = value);
    if (_route.picker.mounted) _route.picker._changed(value);
  }

  void _turn(int direction) {
    setState(() {
      _previousMonth = _month;
      _month = DateTime(_month.year, _month.month + direction);
    });
    _motion.turnPage(clock, direction);
    wake();
  }

  int _weeks(DateTime month) {
    final first = DateTime(month.year, month.month);
    final lead = (first.weekday - _picker.firstDayOfWeek) % 7;
    final days = _daysIn(month);
    return ((lead + days) / 7).ceil();
  }

  Size _sizeFor(_Part part) {
    if (part == _Part.time) return MorphDatePickerTuning.timeSize;
    final weeks = math.max(_weeks(_month), _weeks(_previousMonth ?? _month));
    return Size(
      MorphDatePickerTuning.calendarSize.width,
      MorphDatePickerTuning.calendarSize.height +
          (weeks - 5) * MorphDatePickerTuning.weekHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphDatePickerStyle.resolve(context, _route.style);
    final media = MediaQuery.of(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final glass = MorphGlass.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final origin = _origin(context);
    final padding = EdgeInsets.only(
      top: media.padding.top,
      bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    Widget contentFor(_Part part) => part == _Part.time
        ? _TimeWheels(
            value: _value,
            twentyFour: _route.picker._twentyFour,
            style: style,
            onChanged: _pick,
          )
        : _Calendar(
            value: _value,
            month: _month,
            previousMonth: _previousMonth,
            motion: _motion,
            frames: frames,
            firstDayOfWeek: _picker.firstDayOfWeek,
            firstDate: _picker.firstDate,
            lastDate: _picker.lastDate,
            today: _picker.today ?? _dateOnly(DateTime.now()),
            style: style,
            onPick: _pick,
            onTurn: _turn,
          );
    final size = _sizeFor(_part);
    final from = _fromPart;
    final fromSize = from == null ? size : _sizeFor(from);
    Widget overlayFor({required bool below}) => Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: MediaQuery(
        data: media.copyWith(
          textScaler: media.textScaler.clamp(
            maxScaleFactor: _overlayMaxTextScale,
          ),
        ),
        child: DefaultTextStyle(
          style: MorphTypography.resolve(
            TextStyle(fontSize: 17, color: style.dayColor),
          ),
          child: _Crossfade(
            alignment: below
                ? AlignmentDirectional.topStart
                : AlignmentDirectional.bottomStart,
            frames: frames,
            fade: () => _swap.value(_motion.time),
            from: from == null
                ? null
                : ExcludeSemantics(
                    child: SizedBox.fromSize(
                      size: fromSize,
                      child: contentFor(from),
                    ),
                  ),
            to: SizedBox.fromSize(
              key: ValueKey<_Part>(_part),
              size: size,
              child: contentFor(_part),
            ),
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: FocusScope(
        autofocus: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            MorphDatePickerPlacement place(Size size, Rect label) =>
                morphPlaceDatePicker(
                  size: size,
                  label: label.shift(-origin),
                  screen: constraints.biggest,
                  padding: padding,
                  textDirection: direction,
                );
            final target = place(size, _label);
            final fromLabel = _fromLabel;
            final source = from == null || fromLabel == null
                ? null
                : place(fromSize, fromLabel);
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (PointerDownEvent e) => _outside = e.pointer,
                    onPointerUp: (PointerUpEvent e) {
                      if (e.pointer == _outside) {
                        final other = _otherLabelAt(e.position);
                        if (other == null) {
                          _close();
                        } else {
                          _switchTo(other);
                        }
                      }
                      _outside = null;
                    },
                    onPointerCancel: (PointerCancelEvent e) => _outside = null,
                  ),
                ),
                ListenableBuilder(
                  listenable: frames,
                  child: overlayFor(below: target.below),
                  builder: (BuildContext context, Widget? child) {
                    final q = _swap.value(_motion.time);
                    final placement = source == null
                        ? target
                        : MorphDatePickerPlacement(
                            rect: Rect.lerp(source.rect, target.rect, q)!,
                            anchor: Offset.lerp(
                              source.anchor,
                              target.anchor,
                              q,
                            )!,
                          );
                    return _frame(
                      context,
                      placement,
                      placement.rect.size,
                      target.below,
                      style,
                      glass,
                      brightness,
                      child!,
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _frame(
    BuildContext context,
    MorphDatePickerPlacement placement,
    Size size,
    bool below,
    MorphDatePickerStyle style,
    MorphGlassPainter? glass,
    Brightness brightness,
    Widget child,
  ) {
    final rect = placement.rect;
    final anchor = placement.anchor;
    final t = _motion.time;
    final s = _motion.scale(t);
    final h = math.min(size.height, _motion.height(t, size.height));
    final box = Rect.fromLTWH(
      rect.left,
      below ? rect.top : rect.bottom - h,
      rect.width,
      math.max(0, h),
    );
    final transform = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
    transform.multiply(Matrix4.diagonal3Values(s, s, 1));
    transform.multiply(Matrix4.translationValues(-anchor.dx, -anchor.dy, 0));
    final shape = RRect.fromRectAndRadius(
      Offset.zero & box.size,
      const Radius.circular(MorphDatePickerTuning.cornerRadius),
    );
    final opacity = _motion.opacity(t);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: _leaving,
        child: Transform(
          transform: transform,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: box,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (glass != null)
                      glass.buildSurface(
                        context,
                        MorphGlassSurface(
                          kind: MorphGlassKind.menu,
                          shape: shape,
                          color: style.platterColor,
                          brightness: brightness,
                          opacity: opacity,
                        ),
                      )
                    else
                      CustomPaint(
                        painter: _OverlayPainter(
                          shape: shape,
                          style: style,
                          opacity: opacity,
                        ),
                      ),
                    Opacity(
                      opacity: opacity,
                      child: ClipRRect(
                        clipper: _OverlayClipper(shape),
                        child: OverflowBox(
                          alignment: below
                              ? AlignmentDirectional.topStart
                              : AlignmentDirectional.bottomStart,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Offset _origin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.localToGlobal(Offset.zero);
    return Offset.zero;
  }
}

class _Crossfade extends StatelessWidget {
  const _Crossfade({
    required this.frames,
    required this.fade,
    required this.from,
    required this.to,
    required this.alignment,
  });

  final AlignmentDirectional alignment;
  final Listenable frames;
  final double Function() fade;
  final Widget? from;
  final Widget to;

  @override
  Widget build(BuildContext context) {
    final old = from;
    if (old == null) return to;
    return ListenableBuilder(
      listenable: frames,
      builder: (BuildContext context, Widget? _) {
        final q = fade().clamp(0.0, 1.0);
        return Stack(
          alignment: alignment,
          clipBehavior: Clip.none,
          children: [
            IgnorePointer(
              child: Opacity(opacity: 1 - q, child: old),
            ),
            Opacity(opacity: q, child: to),
          ],
        );
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  const _OverlayPainter({
    required this.shape,
    required this.style,
    required this.opacity,
  });

  final RRect shape;
  final MorphDatePickerStyle style;
  final double opacity;

  Color _faded(Color c) => c.withValues(alpha: c.a * opacity.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint();
    shadow.color = _faded(style.shadowColor);
    shadow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawRRect(shape.shift(const Offset(0, 6)), shadow);
    final fill = Paint();
    fill.color = _faded(style.platterColor);
    canvas.drawRRect(shape, fill);
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.style != style ||
      oldDelegate.opacity != opacity;
}

class _OverlayClipper extends CustomClipper<RRect> {
  _OverlayClipper(this.shape);

  final RRect shape;

  @override
  RRect getClip(Size size) => shape;

  @override
  bool shouldReclip(_OverlayClipper oldClipper) => oldClipper.shape != shape;
}

/// The layout of the calendar, read from UIKit's views at 320 points wide.
abstract final class _CalendarMetrics {
  static const double top = 16;
  static const double headerHeight = 37.67;
  static const double titleInset = 20.33;
  static const double titleChevronGap = 7.67;
  static const Size titleChevron = Size(6.33, 11.67);
  static const double titleChevronStroke = 2.1;
  static const Size chevron = Size(10, 17.33);
  static const double chevronStroke = 2.6;
  static const double chevronShiftForward = 1;
  static const double chevronShiftBack = -1.33;
  static const double weekdayTop = 16;
  static const double weekdayHeight = 15.67;
  static const double gridInset = 10.33;
  static const double cell = 42.67;
  static const double row = 45.67;
  static const double chevronButton = 43.33;
  static const double chevronEnd = 2;
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.value,
    required this.month,
    required this.previousMonth,
    required this.motion,
    required this.frames,
    required this.firstDayOfWeek,
    required this.firstDate,
    required this.lastDate,
    required this.today,
    required this.style,
    required this.onPick,
    required this.onTurn,
  });

  final DateTime value;
  final DateTime month;
  final DateTime? previousMonth;
  final MorphDatePickerMotion motion;
  final Listenable frames;
  final int firstDayOfWeek;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime today;
  final MorphDatePickerStyle style;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<int> onTurn;

  bool _canTurn(int direction) {
    final next = DateTime(month.year, month.month + direction);
    if (direction < 0) {
      final first = firstDate;
      return first == null ||
          !DateTime(
            next.year,
            next.month + 1,
          ).isBefore(DateTime(first.year, first.month, 2));
    }
    final last = lastDate;
    return last == null || !next.isAfter(last);
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    const grid = 7 * _CalendarMetrics.cell;
    final title = MorphTypography.resolve(
      MorphTypography.datePickerTitle.copyWith(
        height: 1.2,
        color: style.titleColor,
      ),
    );
    final weekday = MorphTypography.resolve(
      MorphTypography.datePickerWeekday.copyWith(
        height: 15.67 / 13,
        color: style.weekdayColor,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: _CalendarMetrics.top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _CalendarMetrics.headerHeight,
            child: Row(
              children: [
                const SizedBox(width: _CalendarMetrics.titleInset),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Semantics(
                          header: true,
                          liveRegion: true,
                          child: Text(
                            '${_months[month.month - 1]} ${month.year}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: title,
                          ),
                        ),
                      ),
                      const SizedBox(width: _CalendarMetrics.titleChevronGap),
                      CustomPaint(
                        size: _CalendarMetrics.titleChevron,
                        painter: _ChevronPainter(
                          color: style.accentColor,
                          forward: !rtl,
                          stroke: _CalendarMetrics.titleChevronStroke,
                        ),
                      ),
                    ],
                  ),
                ),
                _ChevronButton(
                  label: 'Previous month',
                  forward: false,
                  color: style.chevronColor,
                  onTap: _canTurn(-1) ? () => onTurn(-1) : null,
                ),
                _ChevronButton(
                  label: 'Next month',
                  forward: true,
                  color: style.chevronColor,
                  onTap: _canTurn(1) ? () => onTurn(1) : null,
                ),
                const SizedBox(width: _CalendarMetrics.chevronEnd),
              ],
            ),
          ),
          const SizedBox(height: _CalendarMetrics.weekdayTop),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _CalendarMetrics.gridInset,
            ),
            child: SizedBox(
              height: _CalendarMetrics.weekdayHeight,
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      SizedBox(
                        width: _CalendarMetrics.cell,
                        child: Text(
                          _weekdays[(firstDayOfWeek + i) % 7],
                          textAlign: TextAlign.center,
                          style: weekday,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _CalendarMetrics.gridInset,
              ),
              child: ClipRect(
                child: ListenableBuilder(
                  listenable: frames,
                  builder: (BuildContext context, Widget? _) {
                    final p = motion.page(motion.time);
                    final dir = motion.pageDirection * (rtl ? -1 : 1);
                    final previous = previousMonth;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (previous != null && p < 1)
                          Positioned(
                            left: -dir * grid * p,
                            top: 0,
                            width: grid,
                            child: ExcludeSemantics(child: _month(previous)),
                          ),
                        Positioned(
                          left: previous != null && p < 1
                              ? dir * grid * (1 - p)
                              : 0,
                          top: 0,
                          width: grid,
                          child: _month(month),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _month(DateTime month) {
    final first = DateTime(month.year, month.month);
    final lead = (first.weekday - firstDayOfWeek) % 7;
    final days = _daysIn(month);
    final weeks = ((lead + days) / 7).ceil();
    return Column(
      children: [
        for (var w = 0; w < weeks; w++)
          SizedBox(
            height: _CalendarMetrics.row,
            child: Row(
              children: [
                for (var d = 0; d < 7; d++)
                  SizedBox(
                    width: _CalendarMetrics.cell,
                    child: () {
                      final day = w * 7 + d - lead + 1;
                      if (day < 1 || day > days) return const SizedBox();
                      final date = DateTime(month.year, month.month, day);
                      return _Day(
                        date: date,
                        selected: _sameDay(date, value),
                        today: _sameDay(date, today),
                        enabled:
                            !(firstDate != null &&
                                date.isBefore(_dateOnly(firstDate!))) &&
                            !(lastDate != null &&
                                date.isAfter(_dateOnly(lastDate!))),
                        style: style,
                        onTap: () => onPick(
                          DateTime(
                            date.year,
                            date.month,
                            date.day,
                            value.hour,
                            value.minute,
                          ),
                        ),
                      );
                    }(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.selected,
    required this.today,
    required this.enabled,
    required this.style,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool enabled;
  final MorphDatePickerStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch ((selected, today)) {
      (true, true) => style.selectedDayColor,
      (true, false) => style.selectedDayTextColor,
      (false, true) => style.accentColor,
      (false, false) => style.dayColor,
    };
    final fill = switch ((selected, today)) {
      (true, true) => style.accentColor,
      (true, false) => style.selectedDayFillColor,
      (false, true) => style.todayFillColor,
      (false, false) => null,
    };
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${date.day} ${_months[date.month - 1]} ${date.year}',
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : style.disabledOpacity,
          child: Center(
            child: Container(
              width: _CalendarMetrics.cell,
              height: _CalendarMetrics.cell,
              alignment: Alignment.center,
              decoration: fill == null
                  ? null
                  : BoxDecoration(color: fill, shape: BoxShape.circle),
              child: Text(
                '${date.day}',
                textScaler: TextScaler.noScaling,
                style: MorphTypography.resolve(
                  (selected
                          ? MorphTypography.datePickerDaySelected
                          : MorphTypography.datePickerDay)
                      .copyWith(height: 1.2, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChevronButton extends StatelessWidget {
  const _ChevronButton({
    required this.label,
    required this.forward,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool forward;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _CalendarMetrics.chevronButton,
          height: _CalendarMetrics.headerHeight,
          child: Center(
            child: Transform.translate(
              offset: Offset(
                forward != rtl
                    ? _CalendarMetrics.chevronShiftForward
                    : _CalendarMetrics.chevronShiftBack,
                0,
              ),
              child: Opacity(
                opacity: onTap == null ? 0.35 : 1,
                child: CustomPaint(
                  size: _CalendarMetrics.chevron,
                  painter: _ChevronPainter(
                    color: color,
                    forward: forward != rtl,
                    stroke: _CalendarMetrics.chevronStroke,
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

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({
    required this.color,
    required this.forward,
    required this.stroke,
  });

  final Color color;
  final bool forward;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final inset = stroke / 2;
    final path = Path();
    if (forward) {
      path.moveTo(inset, inset);
      path.lineTo(size.width - inset, size.height / 2);
      path.lineTo(inset, size.height - inset);
    } else {
      path.moveTo(size.width - inset, inset);
      path.lineTo(inset, size.height / 2);
      path.lineTo(size.width - inset, size.height - inset);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.forward != forward ||
      oldDelegate.stroke != stroke;
}

class _TimeWheels extends StatefulWidget {
  const _TimeWheels({
    required this.value,
    required this.twentyFour,
    required this.style,
    required this.onChanged,
  });

  final DateTime value;
  final bool twentyFour;
  final MorphDatePickerStyle style;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_TimeWheels> createState() => _TimeWheelsState();
}

class _TimeWheelsState extends State<_TimeWheels> {
  static const int _loops = 100;
  late final FixedExtentScrollController _hours = FixedExtentScrollController(
    initialItem: 24 * (_loops ~/ 2) + widget.value.hour,
  );
  late final FixedExtentScrollController _minutes = FixedExtentScrollController(
    initialItem: 60 * (_loops ~/ 2) + widget.value.minute,
  );
  late int _hour = widget.value.hour;
  late int _minute = widget.value.minute;

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _emit() {
    final v = widget.value;
    widget.onChanged(DateTime(v.year, v.month, v.day, _hour, _minute));
  }

  String _hourText(int h) {
    if (widget.twentyFour) return _two(h);
    final twelve = h % 12 == 0 ? 12 : h % 12;
    return '$twelve';
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) text,
    required int selected,
    required ValueChanged<int> onSelected,
    required String label,
  }) {
    final style = widget.style;
    final row = MorphTypography.resolve(
      TextStyle(fontSize: _WheelMetrics.fontSize, color: style.wheelColor),
    );
    return Semantics(
      label: label,
      value: text(selected),
      increasedValue: text((selected + 1) % count),
      decreasedValue: text((selected - 1) % count),
      onIncrease: () => controller.animateToItem(
        controller.selectedItem + 1,
        duration: const Duration(milliseconds: 200),
        curve: const Cubic(0.25, 0.1, 0.25, 1),
      ),
      onDecrease: () => controller.animateToItem(
        controller.selectedItem - 1,
        duration: const Duration(milliseconds: 200),
        curve: const Cubic(0.25, 0.1, 0.25, 1),
      ),
      child: ExcludeSemantics(
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: _WheelMetrics.row,
          diameterRatio: _WheelMetrics.diameterRatio,
          perspective: _WheelMetrics.perspective,
          squeeze: _WheelMetrics.squeeze,
          useMagnifier: true,
          magnification: _WheelMetrics.magnification,
          overAndUnderCenterOpacity: style.wheelFadedOpacity,
          physics: const FixedExtentScrollPhysics(
            parent: BouncingScrollPhysics(
              decelerationRate: ScrollDecelerationRate.fast,
            ),
          ),
          onSelectedItemChanged: (int i) => onSelected(i % count),
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: count * _loops,
            builder: (BuildContext context, int i) => Center(
              child: Text(
                text(i % count),
                textScaler: TextScaler.noScaling,
                style: row,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _WheelMetrics.inset,
        vertical: _WheelMetrics.top,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: _WheelMetrics.bandInset,
            right: _WheelMetrics.bandInset,
            height: _WheelMetrics.band,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: style.wheelBandColor,
                shape: const StadiumBorder(),
              ),
            ),
          ),
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: _WheelMetrics.shade,
            child: Row(
              children: [
                const SizedBox(width: _WheelMetrics.lead),
                SizedBox(
                  width: _WheelMetrics.column,
                  child: _wheel(
                    controller: _hours,
                    count: 24,
                    text: _hourText,
                    selected: _hour,
                    label: 'Hour',
                    onSelected: (int h) {
                      setState(() => _hour = h);
                      _emit();
                    },
                  ),
                ),
                const SizedBox(width: _WheelMetrics.gap),
                SizedBox(
                  width: _WheelMetrics.column,
                  child: _wheel(
                    controller: _minutes,
                    count: 60,
                    text: _two,
                    selected: _minute,
                    label: 'Minute',
                    onSelected: (int m) {
                      setState(() => _minute = m);
                      _emit();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The layout of the time wheels, read from UIKit's views on an iPhone 16
/// Pro (232 x 204 platter): the column view 218 x 172 inside, the band 200
/// x 32 centered, the hour and minute labels centered 73.5 and 148.5 points
/// from the platter's leading edge, the rows on a cylinder of radius 73.5
/// whose neighbours sit 31.3, 56.7 and 71.9 points from the center.
abstract final class _WheelMetrics {
  static const double inset = 7;
  static const double top = 16;
  static const double row = 32.4;
  static const double band = 32;
  static const double bandInset = 9;
  static const double column = 72;
  static const double lead = 73.5 - inset - column / 2;
  static const double gap = 148.5 - 73.5 - column;
  static const double diameterRatio = 2 * 73.5 / 172;
  static const double perspective = 0.0001;
  static const double squeeze = row * math.pi / (172 * 0.4405);
  static const double fontSize = 21;
  static const double magnification = 23.5 / 21;

  /// The radius of the cylinder the rows sit on.
  static const double radius = 73.5;

  /// How fast the rows outside the band darken toward the cylinder's
  /// edges: their opacity falls as the cosine of their angle to this
  /// power (screen recording: 0.36, 0.25 and 0.06 of black on the platter
  /// at 31, 57 and 72 points out, where the labels report 0.447).
  static const double shadePower = 1.4;

  /// The mask that darkens the rows toward the cylinder's edges, over the
  /// wheels' box: opaque inside the band.
  static Shader shade(Rect rect) {
    final half = rect.height / 2;
    const steps = 24;
    double cosAt(double y) {
      final s = (y / radius).clamp(-1.0, 1.0);
      return math.sqrt(1 - s * s);
    }

    final edge = cosAt(band / 2);
    final stops = <double>[];
    final colors = <Color>[];
    for (var i = 0; i <= steps; i++) {
      final f = i / steps;
      final y = (f * 2 - 1) * half;
      final a = y.abs() <= band / 2
          ? 1.0
          : math.pow(cosAt(y) / edge, shadePower).toDouble().clamp(0.0, 1.0);
      stops.add(f);
      colors.add(Color.fromRGBO(0, 0, 0, a));
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(rect);
  }
}
