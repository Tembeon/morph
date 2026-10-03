import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/bar_motion.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// One button of a glass bar: a label or an icon.
///
/// Its [id] keeps its identity when the bar's items change: an item with
/// the same id travels to its new place, a new id grows in, a missing one
/// leaves.
@immutable
class MorphBarButton {
  /// Creates a button showing [label] or [icon].
  const MorphBarButton({
    required this.id,
    this.label,
    this.icon,
    this.onPressed,
    this.semanticLabel,
  }) : assert(label != null || icon != null, 'a label or an icon'),
       back = false;

  /// Creates the back button of a navigation bar: a chevron followed by
  /// [label], usually the previous screen's title.
  const MorphBarButton.back({
    this.label,
    this.onPressed,
    this.semanticLabel,
    this.id = 'morph.back',
  }) : icon = null,
       back = true;

  /// The identity of the button across item changes.
  final Object id;

  /// The text of the button.
  final String? label;

  /// The icon of the button, drawn [MorphBarMetrics.iconSize] large; used
  /// when there is no [label].
  final Widget? icon;

  /// Called when the button is tapped; null disables the button.
  final VoidCallback? onPressed;

  /// The label screen readers announce; defaults to [label].
  final String? semanticLabel;

  /// Whether this is a back button.
  final bool back;

  /// Whether the button accepts taps.
  bool get enabled => onPressed != null;
}

/// Buttons that share one glass capsule.
///
/// UIKit groups adjacent bar items into one piece of glass; separate
/// groups (a fixed space between items) get capsules of their own, 12
/// points apart. A [prominent] group is tinted, like
/// `UIBarButtonItem.Style.prominent`.
@immutable
class MorphBarButtonGroup {
  /// Creates a group of [buttons].
  const MorphBarButtonGroup(this.buttons, {this.id, this.prominent = false});

  /// The buttons, in reading order.
  final List<MorphBarButton> buttons;

  /// The identity of the capsule across item changes; null keeps the
  /// capsule by its position on its side of the bar, counted from the
  /// bar's edge (UIKit morphs the outermost capsule into the outermost
  /// one).
  final Object? id;

  /// Whether the capsule is tinted with the style's prominent color.
  final bool prominent;
}

/// The measured geometry of the glass buttons of a bar.
///
/// Values read from the view frames UIKit lays out on iOS 27 (iPhone 16
/// Pro, 402 points wide, and the simulator's iPhone 18 Pro Max at 440).
@immutable
class MorphBarMetrics {
  /// Creates metrics from explicit values.
  const MorphBarMetrics({
    required this.capsuleHeight,
    required this.buttonHeight,
    required this.capsulePadding,
    required this.buttonGap,
    required this.labelPadding,
    required this.iconPadding,
    required this.minButtonWidth,
    this.groupGap = 12,
    this.iconSize = 24,
    this.fontSize = 17,
    this.backChevronInset = 12,
    this.backChevronWidth = 16.33,
    this.backChevronGap = 6,
    this.backTrailingPadding = 17,
  });

  /// The height of a capsule.
  final double capsuleHeight;

  /// The height of a button inside its capsule.
  final double buttonHeight;

  /// The space between a capsule's edge and its first and last buttons.
  final double capsulePadding;

  /// The space between two buttons of one capsule.
  final double buttonGap;

  /// The space between two capsules on one side of the bar.
  final double groupGap;

  /// The space on each side of a button's label.
  final double labelPadding;

  /// The space on each side of a button's icon.
  final double iconPadding;

  /// The narrowest a button gets.
  final double minButtonWidth;

  /// The size icons are drawn at.
  final double iconSize;

  /// The size of button labels.
  final double fontSize;

  /// The space between a back button's leading edge and its chevron.
  final double backChevronInset;

  /// The width of the back chevron.
  final double backChevronWidth;

  /// The space between the back chevron and its label.
  final double backChevronGap;

  /// The space after the back button's label.
  final double backTrailingPadding;

  /// A navigation bar's buttons: capsules 44 tall, buttons 36 tall
  /// inset by 4, 16 between buttons, labels padded by 12, icons by 7.
  static const navigation = MorphBarMetrics(
    capsuleHeight: 44,
    buttonHeight: 36,
    capsulePadding: 4,
    buttonGap: 16,
    labelPadding: 12,
    iconPadding: 7,
    minButtonWidth: 36,
  );

  /// A toolbar's buttons: capsules 48 tall, buttons 38 tall inset by 5,
  /// 14 between buttons, labels padded by 11, icons by 8, never
  /// narrower than 38.
  static const toolbar = MorphBarMetrics(
    capsuleHeight: 48,
    buttonHeight: 38,
    capsulePadding: 5,
    buttonGap: 14,
    labelPadding: 11,
    iconPadding: 8,
    minButtonWidth: 38,
  );
}

/// The look of a glass bar: its capsules, buttons and titles.
@immutable
class MorphBarStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphBarStyle({
    this.capsuleColor = const Color(0xD9FFFFFF),
    this.rimColor = const Color(0x1F000000),
    this.shadowColor = const Color(0x1A000000),
    this.foregroundColor = const Color(0xFF000000),
    this.prominentColor = const Color(0xFF007AFF),
    this.prominentForegroundColor = const Color(0xFFFFFFFF),
    this.titleColor = const Color(0xFF000000),
    this.disabledOpacity = 0.35,
  });

  /// The fill of a clear capsule.
  final Color capsuleColor;

  /// The outline of a capsule.
  final Color rimColor;

  /// The shadow under a capsule.
  final Color shadowColor;

  /// The color of button labels and icons.
  final Color foregroundColor;

  /// The fill of a prominent capsule: systemBlue.
  final Color prominentColor;

  /// The color of labels and icons on a prominent capsule.
  final Color prominentForegroundColor;

  /// The color of the bar's titles.
  final Color titleColor;

  /// The opacity of a disabled button (not measured on a device).
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphBarStyle();

  /// The dark appearance.
  static const dark = MorphBarStyle(
    capsuleColor: Color(0xB82C2C2E),
    rimColor: Color(0x33FFFFFF),
    shadowColor: Color(0x40000000),
    foregroundColor: Color(0xFFFFFFFF),
    prominentColor: Color(0xFF0A84FF),
    titleColor: Color(0xFFFFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphBarStyle resolve(BuildContext context, MorphBarStyle? explicit) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.bar ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

/// Where a group of a [MorphBarItems] row sits.
@internal
enum MorphBarSide {
  /// From the leading edge.
  leading,

  /// From the trailing edge.
  trailing,
}

/// A group placed on one side of a [MorphBarItems] row.
@internal
@immutable
class MorphPlacedGroup {
  /// Places [group] on [side].
  const MorphPlacedGroup(this.group, this.side);

  /// The group.
  final MorphBarButtonGroup group;

  /// The side it sits on.
  final MorphBarSide side;
}

/// The label style of bar buttons.
@internal
TextStyle morphBarLabelStyle(MorphBarMetrics metrics, {bool bold = false}) =>
    TextStyle(
      fontSize: metrics.fontSize,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      height: 1.2,
      letterSpacing: -0.43,
    );

/// The width of the content of [button].
@internal
double morphBarContentWidth(
  MorphBarButton button,
  MorphBarMetrics metrics,
  TextScaler scaler,
  TextDirection direction, {
  bool bold = false,
}) {
  final label = button.label;
  var width = 0.0;
  if (label != null) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: morphBarLabelStyle(metrics, bold: bold),
      ),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    );
    painter.layout();
    width = painter.width;
    painter.dispose();
  }
  if (button.back) {
    return metrics.backChevronInset +
        metrics.backChevronWidth +
        (label == null || label.isEmpty
            ? metrics.backChevronInset
            : metrics.backChevronGap + width + metrics.backTrailingPadding);
  }
  if (label != null) return width + 2 * metrics.labelPadding;
  return metrics.iconSize + 2 * metrics.iconPadding;
}

/// Lays out [groups] in a row [width] wide: leading groups from
/// [leadingInset], trailing groups from [trailingInset], capsules
/// [MorphBarMetrics.groupGap] apart, [top] the capsules' top edge.
@internal
List<MorphBarCapsuleLayout> morphLayoutBarGroups({
  required List<MorphPlacedGroup> groups,
  required double width,
  required double top,
  required double leadingInset,
  required double trailingInset,
  required MorphBarMetrics metrics,
  required TextScaler scaler,
  required TextDirection direction,
}) {
  final rtl = direction == TextDirection.rtl;
  final out = <MorphBarCapsuleLayout>[];
  final leading = [
    for (final g in groups)
      if (g.side == MorphBarSide.leading) g.group,
  ];
  final trailing = [
    for (final g in groups)
      if (g.side == MorphBarSide.trailing) g.group,
  ];
  MorphBarCapsuleLayout capsule(
    MorphBarButtonGroup group,
    double start,
    Object id,
  ) {
    final widths = [
      for (final b in group.buttons)
        math.max(
          metrics.minButtonWidth,
          morphBarContentWidth(
            b,
            metrics,
            scaler,
            direction,
            bold: group.prominent,
          ),
        ),
    ];
    final single = group.buttons.length == 1 && group.buttons.first.back;
    final inner =
        widths.fold<double>(0, (a, w) => a + w) +
        metrics.buttonGap * math.max(0, widths.length - 1);
    final total = single ? widths.first : inner + 2 * metrics.capsulePadding;
    final rect = Rect.fromLTWH(start, top, total, metrics.capsuleHeight);
    final items = <MorphBarItemLayout>[];
    var x = single ? start : start + metrics.capsulePadding;
    final buttonTop = top + (metrics.capsuleHeight - metrics.buttonHeight) / 2;
    for (var i = 0; i < widths.length; i++) {
      final itemHeight = single ? metrics.capsuleHeight : metrics.buttonHeight;
      final itemTop = single ? top : buttonTop;
      items.add(
        MorphBarItemLayout(
          group.buttons[i].id,
          Rect.fromLTWH(x, itemTop, widths[i], itemHeight),
        ),
      );
      x += widths[i] + metrics.buttonGap;
    }
    return MorphBarCapsuleLayout(id, rect, items);
  }

  var x = leadingInset;
  for (var i = 0; i < leading.length; i++) {
    final c = capsule(leading[i], x, leading[i].id ?? ('leading', i));
    out.add(c);
    x = c.rect.right + metrics.groupGap;
  }
  var right = width - trailingInset;
  for (var i = 0; i < trailing.length; i++) {
    final g = trailing[trailing.length - 1 - i];
    final probe = capsule(g, 0, '');
    final c = capsule(g, right - probe.rect.width, g.id ?? ('trailing', i));
    out.add(c);
    right = c.rect.left - metrics.groupGap;
  }
  if (!rtl) return out;
  return [
    for (final c in out)
      MorphBarCapsuleLayout(c.id, _mirror(c.rect, width), [
        for (final i in c.items)
          MorphBarItemLayout(i.id, _mirror(i.rect, width)),
      ]),
  ];
}

Rect _mirror(Rect r, double width) =>
    Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom);

/// A row of glass bar buttons that animates every change of its groups
/// with [MorphBarMotion].
///
/// A touch on a button lifts its whole capsule like a
/// [MorphGlassButton].
@internal
class MorphBarItems extends StatefulWidget {
  /// Creates the row.
  const MorphBarItems({
    required this.groups,
    required this.metrics,
    required this.top,
    required this.leadingInset,
    required this.trailingInset,
    this.style,
    this.onLayout,
    this.driftGroups,
    this.driftProgress,
    this.driftFactor = 1,
    super.key,
  });

  /// The groups and their sides.
  final List<MorphPlacedGroup> groups;

  /// The geometry of the buttons.
  final MorphBarMetrics metrics;

  /// The top of the capsules in the row.
  final double top;

  /// The space before the first leading capsule.
  final double leadingInset;

  /// The space after the last trailing capsule.
  final double trailingInset;

  /// The look; null resolves it from the theme.
  final MorphBarStyle? style;

  /// Called with the laid-out capsules whenever the layout changes.
  final ValueChanged<List<MorphBarCapsuleLayout>>? onLayout;

  /// The groups the capsules lean toward while [driftProgress] is set
  /// (see [MorphBarMotion.setDrift]).
  final List<MorphPlacedGroup>? driftGroups;

  /// The progress the lean follows: the capsules lean [driftFactor] times
  /// its value of the way toward [driftGroups]; null ends the lean.
  final ValueListenable<double>? driftProgress;

  /// The share of [driftProgress] the capsules lean by.
  final double driftFactor;

  @override
  State<MorphBarItems> createState() => _MorphBarItemsState();
}

class _MorphBarItemsState extends State<MorphBarItems>
    with
        SingleTickerProviderStateMixin<MorphBarItems>,
        MorphClock<MorphBarItems> {
  final MorphBarMotion _motion = MorphBarMotion();
  final Map<Object, MorphGlassButtonMotion> _presses = {};
  final Map<Object, MorphBarButton> _buttons = {};
  final Map<Object, bool> _prominent = {};
  final Map<Object, Object> _capsuleOf = {};
  List<MorphBarCapsuleLayout> _layout = const [];
  List<MorphBarCapsuleLayout>? _driftLayout;
  String _signature = '';
  Object? _pressedCapsule;
  Object? _pressedButton;

  @override
  void advanceMotion(double t) {
    _motion.advance(t);
    for (final p in _presses.values) {
      p.advance(t);
    }
  }

  @override
  bool get motionSettled =>
      _motion.isSettled && _presses.values.every((p) => p.isSettled);

  void _relayout(double width) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final scaler =
        MediaQuery.maybeTextScalerOf(context)?.clamp(maxScaleFactor: 1.25) ??
        TextScaler.noScaling;
    List<MorphBarCapsuleLayout> lay(List<MorphPlacedGroup> groups) =>
        morphLayoutBarGroups(
          groups: groups,
          width: width,
          top: widget.top,
          leadingInset: widget.leadingInset,
          trailingInset: widget.trailingInset,
          metrics: widget.metrics,
          scaler: scaler,
          direction: direction,
        );
    final layout = lay(widget.groups);
    final driftGroups = widget.driftGroups;
    _driftLayout = driftGroups == null || widget.driftProgress == null
        ? null
        : lay(driftGroups);
    final signature = [
      width,
      for (final c in layout) ...[
        c.id,
        c.rect,
        for (final i in c.items) i.id,
        for (final i in c.items) i.rect,
      ],
    ].join('|');
    for (final g in widget.groups) {
      for (final b in g.group.buttons) {
        _buttons[b.id] = b;
      }
    }
    for (final c in layout) {
      _prominent[c.id] = widget.groups.any(
        (g) =>
            g.group.prominent &&
            c.items.any((i) => g.group.buttons.any((b) => b.id == i.id)),
      );
      for (final i in c.items) {
        _capsuleOf[i.id] = c.id;
      }
    }
    if (signature == _signature) return;
    final first = _signature.isEmpty;
    _signature = signature;
    _layout = layout;
    _motion.reducedMotion = morphReducedMotionOf(context);
    _motion.setLayout(clock, layout, animated: !first);
    if (!first) wake();
    widget.onLayout?.call(layout);
  }

  MorphGlassButtonMotion _press(Object capsule, Size size) {
    final motion = _presses.putIfAbsent(
      capsule,
      () => MorphGlassButtonMotion(size: size),
    );
    motion.size = size;
    motion.reducedMotion = morphReducedMotionOf(context);
    return motion;
  }

  MorphBarCapsuleLayout? _capsuleLayout(Object id) {
    for (final c in _layout) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _down(MorphBarButton button, PointerDownEvent event) {
    if (!button.enabled || event.buttons != kPrimaryButton) return;
    final capsuleId = _capsuleOf[button.id];
    final capsule = capsuleId == null ? null : _capsuleLayout(capsuleId);
    if (capsule == null) return;
    _pressedCapsule = capsuleId;
    _pressedButton = button.id;
    final press = _press(capsuleId!, capsule.rect.size);
    press.pointerDown(stamp(event), event.localPosition - capsule.rect.topLeft);
  }

  Offset _local(Object capsuleId, Offset global) {
    final box = context.findRenderObject();
    final capsule = _capsuleLayout(capsuleId);
    if (box is! RenderBox || capsule == null) return Offset.zero;
    return box.globalToLocal(global) - capsule.rect.topLeft;
  }

  void _move(PointerMoveEvent event) {
    final id = _pressedCapsule;
    if (id == null) return;
    _presses[id]?.pointerMove(stamp(event), _local(id, event.position));
  }

  void _up(PointerUpEvent event) {
    final id = _pressedCapsule;
    final buttonId = _pressedButton;
    if (id == null) return;
    _pressedCapsule = null;
    _pressedButton = null;
    final activated =
        _presses[id]?.pointerUp(stamp(event), _local(id, event.position)) ??
        false;
    if (activated && buttonId != null) _buttons[buttonId]?.onPressed?.call();
  }

  void _cancel(PointerCancelEvent event) {
    final id = _pressedCapsule;
    if (id == null) return;
    _pressedCapsule = null;
    _pressedButton = null;
    _presses[id]?.pointerCancel(stamp(event));
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphBarStyle.resolve(context, widget.style);
    final glass = MorphGlass.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _relayout(constraints.maxWidth);
        final progress = widget.driftProgress;
        if (progress == null && _motion.isDrifting) {
          _motion.endDrift(clock);
          wake();
        }
        return ListenableBuilder(
          listenable: progress == null
              ? frames
              : Listenable.merge([frames, progress]),
          builder: (BuildContext context, Widget? _) {
            if (progress != null) {
              _motion.setDrift(
                _driftLayout,
                widget.driftFactor * progress.value.clamp(0.0, 1.0),
              );
            }
            final capsules = _motion.capsules;
            final items = _motion.items;
            Rect lifted(Object id, Rect rect) {
              final press = _presses[id];
              if (press == null) return rect;
              final lean = press.lean;
              return Rect.fromCenter(
                center: rect.center + lean,
                width: rect.width * press.scaleX,
                height: rect.height * press.scaleY,
              );
            }

            final surfaces = [
              for (final c in capsules)
                MorphGlassSurface(
                  kind: MorphGlassKind.button,
                  shape: RRect.fromRectAndRadius(
                    lifted(c.id, c.rect),
                    Radius.circular(math.min(c.rect.width, c.rect.height) / 2),
                  ),
                  color: (_prominent[c.id] ?? false)
                      ? style.prominentColor
                      : style.capsuleColor,
                  brightness: brightness,
                ),
            ];
            final content = Stack(
              clipBehavior: Clip.none,
              children: [
                for (final f in items)
                  if (_buttons[f.id] case final button?)
                    _buildItem(
                      button,
                      f,
                      style,
                      direction,
                      capsuleId: _capsuleOf[f.id],
                    ),
              ],
            );
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: glass == null
                  ? CustomPaint(
                      painter: _CapsulePainter(surfaces, style),
                      child: content,
                    )
                  : glass.buildLayer(
                      context,
                      surfaces,
                      content: content,
                      contentSlots: [
                        for (final f in items)
                          Rect.fromCenter(
                            center: f.center,
                            width: f.size.width,
                            height: f.size.height,
                          ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildItem(
    MorphBarButton button,
    MorphBarItemFrame frame,
    MorphBarStyle style,
    TextDirection direction, {
    required Object? capsuleId,
  }) {
    final prominent = capsuleId != null && (_prominent[capsuleId] ?? false);
    final color = prominent
        ? style.prominentForegroundColor
        : style.foregroundColor;
    final press = capsuleId == null ? null : _presses[capsuleId];
    final capsule = capsuleId == null ? null : _capsuleLayout(capsuleId);
    var center = frame.center;
    var scale = frame.scale;
    if (press != null && capsule != null) {
      final c = capsule.rect.center;
      center = c + (center - c) * press.scaleX + press.lean;
      scale *= press.scale;
    }
    final metrics = widget.metrics;
    Widget content = _ButtonContent(
      button: button,
      metrics: metrics,
      color: color,
      bold: prominent,
      direction: direction,
    );
    if (frame.blur > 0.05) {
      content = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: frame.blur,
          sigmaY: frame.blur,
          tileMode: TileMode.decal,
        ),
        child: content,
      );
    }
    content = Opacity(
      opacity: (frame.presence * (button.enabled ? 1 : style.disabledOpacity))
          .clamp(0.0, 1.0),
      child: Transform.scale(scale: scale, child: content),
    );
    if (!frame.leaving) {
      content = Semantics(
        button: true,
        enabled: button.enabled,
        label: button.semanticLabel ?? button.label,
        onTap: button.onPressed,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) => _down(button, e),
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _cancel,
          child: ExcludeSemantics(child: content),
        ),
      );
    } else {
      content = IgnorePointer(child: ExcludeSemantics(child: content));
    }
    return Positioned(
      key: ValueKey<Object>(button.id),
      left: center.dx - frame.size.width / 2,
      top: center.dy - frame.size.height / 2,
      width: frame.size.width,
      height: frame.size.height,
      child: content,
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.button,
    required this.metrics,
    required this.color,
    required this.bold,
    required this.direction,
  });

  final MorphBarButton button;
  final MorphBarMetrics metrics;
  final Color color;
  final bool bold;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    final label = button.label;
    final text = label == null
        ? null
        : Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: morphBarLabelStyle(
              metrics,
              bold: bold,
            ).copyWith(color: color),
          );
    if (button.back) {
      return Padding(
        padding: EdgeInsetsDirectional.only(start: metrics.backChevronInset),
        child: Row(
          children: [
            SizedBox(
              width: metrics.backChevronWidth,
              height: 23,
              child: CustomPaint(
                painter: MorphBackChevronPainter(
                  color: color,
                  mirrored: direction == TextDirection.rtl,
                ),
              ),
            ),
            if (text != null) ...[
              SizedBox(width: metrics.backChevronGap),
              Flexible(child: text),
            ],
          ],
        ),
      );
    }
    return Center(
      child:
          text ??
          IconTheme.merge(
            data: IconThemeData(color: color, size: metrics.iconSize),
            child: SizedBox.square(
              dimension: metrics.iconSize,
              child: Center(child: button.icon),
            ),
          ),
    );
  }
}

/// Paints the back chevron of a navigation bar, pointing to the leading
/// edge; [mirrored] flips it for right-to-left text.
@internal
class MorphBackChevronPainter extends CustomPainter {
  /// Creates the painter.
  const MorphBackChevronPainter({required this.color, this.mirrored = false});

  /// The stroke color.
  final Color color;

  /// Whether the chevron points right.
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.19;
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final left = stroke / 2 + size.width * 0.12;
    final right = size.width - stroke / 2 - size.width * 0.12;
    final path = Path();
    if (mirrored) {
      path.moveTo(left, stroke / 2);
      path.lineTo(right, size.height / 2);
      path.lineTo(left, size.height - stroke / 2);
    } else {
      path.moveTo(right, stroke / 2);
      path.lineTo(left, size.height / 2);
      path.lineTo(right, size.height - stroke / 2);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MorphBackChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mirrored != mirrored;
}

class _CapsulePainter extends CustomPainter {
  _CapsulePainter(this.surfaces, this.style);

  final List<MorphGlassSurface> surfaces;
  final MorphBarStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in surfaces) {
      if (s.bounds.isEmpty) continue;
      final shadow = Paint();
      shadow.color = style.shadowColor;
      shadow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(s.shape.shift(const Offset(0, 2)), shadow);
    }
    for (final s in surfaces) {
      if (s.bounds.isEmpty) continue;
      final fill = Paint();
      fill.color = s.color;
      canvas.drawRRect(s.shape, fill);
      final rim = Paint();
      rim.style = PaintingStyle.stroke;
      rim.strokeWidth = 0.5;
      rim.color = style.rimColor;
      canvas.drawRRect(s.shape.deflate(0.25), rim);
    }
  }

  @override
  bool shouldRepaint(_CapsulePainter oldDelegate) => true;
}
