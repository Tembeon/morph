import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/highlight_motion.dart';
import 'package:morph/src/widgets/lens_driver.dart';
import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// A segmented control whose selection lens moves exactly like
/// UISegmentedControl's on iOS 27.
///
/// The selection changes when the finger lifts within [releaseSlop] of
/// the control; pressing the selected segment lifts the lens and lets the
/// finger drag it, with a rubber band past the ends. A finger that lifts
/// farther away changes nothing. The lens's travel, lift and deformation come from
/// [MorphLensTuning.segmented].
///
/// The control is focusable and the arrow keys move the selection; screen
/// readers see one selectable button per segment. In a right-to-left
/// context the first segment is on the right. Labels follow the text
/// scale up to [maxTextScale]. With the platform's reduced motion on,
/// the lens travels without lifting or deforming.
class MorphSegmentedControl extends StatefulWidget {
  /// Creates a segmented control.
  const MorphSegmentedControl({
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.proportionalWidth = false,
    this.appearance,
    super.key,
  });

  /// The segments, left to right; an empty list draws an inert empty
  /// control.
  final List<MorphSegment> segments;

  /// The index of the selected segment, clamped to the available segments
  /// (UIKit `selectedSegmentIndex`), or null for none
  /// (`UISegmentedControl.noSegment`).
  ///
  /// With none selected the lens is hidden and every label plain. A tap
  /// selects on release, as on a control with a selection, and the lens
  /// appears at rest on the chosen segment, without travel or lift: how
  /// UIKit shows the first selection is not yet measured.
  final int? selectedIndex;

  /// Called with the new index when the user selects a segment; null
  /// disables the control.
  final ValueChanged<int>? onChanged;

  /// Whether segments are as wide as their labels instead of equal (UIKit
  /// `apportionsSegmentWidthsByContent`).
  final bool proportionalWidth;

  /// The colors and metrics of the control; null resolves them from the
  /// theme.
  final MorphSegmentedControlAppearance? appearance;

  /// The largest text scale the labels follow.
  static const double maxTextScale = 1.4;

  /// How far outside the control a finger may lift and still select: a
  /// release beyond it changes nothing and the lens settles back as after
  /// a cancelled touch.
  ///
  /// UISegmentedControl selects on a release 60 pt below its bottom edge
  /// but not 70 pt below (iPhone 16 Pro, iOS 27.0.1, fixture
  /// `tracking/release-outside.jsonl`). 70 with the bottom and right edges
  /// excluded, the way `CGRectContainsPoint` and [Rect.contains] test a
  /// point, also gives the glass button's measured edges (in 70 above,
  /// out 80 above; in 60 beside, out 70 beside): one UIKit bound fits all
  /// six points.
  static const double releaseSlop = 70;

  @override
  State<MorphSegmentedControl> createState() => _MorphSegmentedControlState();
}

/// One segment of a [MorphSegmentedControl]: UIKit's segment title
/// (`insertSegment(withTitle:at:animated:)`).
@immutable
class MorphSegment {
  /// Creates a segment labelled [title].
  const MorphSegment(this.title, {this.enabled = true, this.width});

  /// The label of the segment.
  final String title;

  /// Whether the segment can be selected (UIKit
  /// `setEnabled(_:forSegmentAt:)`). A disabled segment draws its label at
  /// the appearance's disabled opacity (not yet measured on a device); a
  /// touch on it selects nothing and the arrow keys skip it.
  final bool enabled;

  /// The width of the segment in points, or null to share the room with
  /// the other segments (UIKit `setWidth(_:forSegmentAt:)`, 0 there).
  final double? width;

  @override
  bool operator ==(Object other) =>
      other is MorphSegment &&
      other.title == title &&
      other.enabled == enabled &&
      other.width == width;

  @override
  int get hashCode => Object.hash(title, enabled, width);
}

/// The look of a [MorphSegmentedControl].
@immutable
class MorphSegmentedControlAppearance {
  /// Creates an appearance; the defaults are the iOS 27 light appearance.
  const MorphSegmentedControlAppearance({
    this.height = 32,
    this.inset = 2,
    this.trackColor = const Color(0x1F767680),
    this.lensColor = const Color(0xFFFFFFFF),
    this.liftedLensColor = const Color(0x40FFFFFF),
    this.lensBorderColor = const Color(0x33000000),
    this.shadowColor = const Color(0x1F000000),
    this.textStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFF000000),
    ),
    this.selectedTextStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFF000000),
    ),
    this.contentPadding = 16,
    this.disabledOpacity = 0.5,
  });

  /// The height of the control.
  final double height;

  /// The gap between the track and the resting lens.
  final double inset;

  /// The fill of the track: tertiarySystemFill.
  final Color trackColor;

  /// The fill of the resting lens.
  final Color lensColor;

  /// The fill of the fully lifted lens.
  final Color liftedLensColor;

  /// The outline the lens gains while lifted.
  final Color lensBorderColor;

  /// The shadow under the lens.
  final Color shadowColor;

  /// The label style of unselected segments, painted through
  /// [MorphTypography.resolve]; UIKit's is [MorphTypography.segment].
  final TextStyle textStyle;

  /// The label style of the selected segment, painted through
  /// [MorphTypography.resolve]; UIKit's is
  /// [MorphTypography.segmentSelected].
  final TextStyle selectedTextStyle;

  /// The horizontal padding around a label when sizing by content.
  final double contentPadding;

  /// The opacity of a disabled control, applied to the whole control as
  /// one layer: UIKit sets the segmented control's alpha to 0.5 (iPhone 16
  /// Pro, light and dark).
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphSegmentedControlAppearance();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphSegmentedControlAppearance(
    trackColor: Color(0x3D767680),
    lensColor: Color(0xFF636366),
    liftedLensColor: Color(0x33FFFFFF),
    lensBorderColor: Color(0x40FFFFFF),
    shadowColor: Color(0x33000000),
    textStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFFFFFFFF),
    ),
    selectedTextStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFFFFFFFF),
    ),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphSegmentedControlAppearance resolve(
    BuildContext context,
    MorphSegmentedControlAppearance? explicit,
  ) => morphResolveAppearance(
    context,
    explicit,
    themed: (theme) => theme.segmentedControl,
    light: light,
    dark: dark,
  );
}

class _MorphSegmentedControlState
    extends MorphControlHost<MorphSegmentedControl>
    with MorphLensDriver<MorphSegmentedControl> {
  MorphLensMotion? _motion;
  List<MorphLensSlot> _slots = const [];
  MorphSegmentedControlAppearance _style =
      MorphSegmentedControlAppearance.light;
  Brightness _brightness = Brightness.light;
  TextScaler _scaler = TextScaler.noScaling;
  bool _rtl = false;
  double _width = 0;

  @override
  MorphLensMotion get motion => _motion!;

  @override
  double trackPosition(Offset local) => _rtl ? _width - local.dx : local.dx;

  bool get _enabled => widget.onChanged != null;

  final MorphSegmentHighlightMotion _highlight = MorphSegmentHighlightMotion();
  final ValueNotifier<(int?, double)> _dim = ValueNotifier((null, 1));

  @override
  void advanceMotion(double t) {
    super.advanceMotion(t);
    _highlight.advance(t);
    _syncDim(t);
  }

  @override
  bool get motionSettled => super.motionSettled && _highlight.isSettled(clock);

  @override
  void dispose() {
    _dim.dispose();
    super.dispose();
  }

  void _syncDim(double t) {
    final index = _highlight.index;
    final value = (index, index == null ? 1.0 : _highlight.opacity(t, index));
    if (_dim.value != value) _dim.value = value;
  }

  void _pressTitle(double t, Offset local) {
    if (_motion == null || _slots.isEmpty) return;
    final index = motion.slotAt(trackPosition(local));
    if (!_selectable(index) || (!_none && index == motion.selected)) return;
    _highlight.press(t, index);
    _syncDim(t);
    wake();
  }

  void _releaseTitle(double t) {
    if (_highlight.index == null) return;
    _highlight.release(t);
    _syncDim(t);
    wake();
  }

  final MorphLabelWidths _labelWidths = MorphLabelWidths();

  List<double> _labelSpans() => _labelWidths.of(
    [for (final segment in widget.segments) segment.title],
    [_style.textStyle, _style.selectedTextStyle],
    _scaler,
  );

  List<MorphLensSlot> _layout(double width) {
    final style = _style;
    final segments = widget.segments;
    final count = segments.length;
    final fixed = segments.fold<double>(0, (a, s) => a + (s.width ?? 0));
    final free = count - segments.where((s) => s.width != null).length;
    final room = width - fixed;
    final List<double> widths;
    if (widget.proportionalWidth) {
      final natural = [
        for (final w in _labelSpans()) w + 2 * style.contentPadding,
      ];
      var total = 0.0;
      for (var i = 0; i < count; i++) {
        if (segments[i].width == null) total += natural[i];
      }
      widths = [
        for (var i = 0; i < count; i++)
          segments[i].width ?? natural[i] * room / total,
      ];
    } else if (free == count) {
      widths = List.filled(count, width / count);
    } else {
      widths = [for (final s in segments) s.width ?? room / free];
    }
    final slots = <MorphLensSlot>[];
    var left = 0.0;
    for (final w in widths) {
      slots.add((center: left + w / 2, width: w - 2 * style.inset));
      left += w;
    }
    return slots;
  }

  double _naturalWidth() => _labelSpans().fold<double>(
    0,
    (total, w) => total + w + 2 * _style.contentPadding,
  );

  void _sync(double width) {
    _width = width;
    final slots = _layout(width);
    final current = _motion;
    if (current == null) {
      final created = MorphLensMotion(
        tuning: MorphLensTuning.segmented,
        slots: slots,
        selected: widget.selectedIndex ?? 0,
        height: _style.height - 2 * _style.inset,
        frameRate: motionFrameRate,
      );
      created.onSelect = _selected;
      created.isSelectable = _selectable;
      _motion = created;
    } else if (!_sameSlots(slots, _slots)) {
      current.slots = slots;
    }
    _slots = slots;
    final index = widget.selectedIndex;
    final wasNone = _shownNone;
    _shownNone = index == null;
    if (index == null || slots.isEmpty) return;
    final selected = index.clamp(0, slots.length - 1);
    if (wasNone) {
      motion.place(clock, selected);
      wake();
    } else if (motion.selected != selected) {
      motion.select(clock, selected, notify: false);
      wake();
    }
  }

  bool _shownNone = false;

  bool get _none => widget.selectedIndex == null;

  bool _selectable(int index) =>
      index >= 0 &&
      index < widget.segments.length &&
      widget.segments[index].enabled;

  void _selected(int index) {
    if (index != widget.selectedIndex) widget.onChanged?.call(index);
    reconcileSelection(() {
      final selected = widget.selectedIndex;
      if (widget.segments.isEmpty) return -1;
      if (selected == null) return motion.selected;
      return selected.clamp(0, widget.segments.length - 1);
    });
  }

  void _select(int index) {
    if (!_enabled || _motion == null || !_selectable(index)) return;
    if (_none) {
      motion.place(clock, index);
      setState(() {});
      widget.onChanged?.call(index);
      wake();
      return;
    }
    motion.select(clock, index);
    wake();
  }

  void _step(int delta) {
    final current = _motion;
    if (current == null || _slots.isEmpty) return;
    final direction = (_rtl ? -delta : delta).sign;
    var next = _none
        ? (direction > 0 ? 0 : _slots.length - 1)
        : current.selected + direction;
    while (next >= 0 && next < _slots.length && !_selectable(next)) {
      next += direction;
    }
    if (next < 0 || next >= _slots.length) return;
    if (_none || next != current.selected) _select(next);
  }

  int? _noneDown;

  @override
  void onControlDown(double t, PointerDownEvent event) {
    _pressTitle(t, event.localPosition);
    if (!_none) {
      super.onControlDown(t, event);
      return;
    }
    _noneDown = motion.slotAt(trackPosition(event.localPosition));
  }

  @override
  void onControlMove(double t, PointerMoveEvent event) {
    if (_noneDown == null) super.onControlMove(t, event);
  }

  @override
  void onControlUp(double t, PointerUpEvent event) {
    _releaseTitle(t);
    if (_noneDown == null) {
      super.onControlUp(t, event);
      return;
    }
    _noneDown = null;
    _select(motion.slotAt(trackPosition(event.localPosition)));
  }

  @override
  void onControlCancel(double t) {
    _releaseTitle(t);
    if (_noneDown == null) {
      super.onControlCancel(t);
      return;
    }
    _noneDown = null;
  }

  static bool _sameSlots(List<MorphLensSlot> a, List<MorphLensSlot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  ({RRect track, RRect lens, double lift}) _frame(Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final lens = morphLensShape(motion, size, rtl: _rtl);
    return (track: track, lens: lens, lift: motion.lift.clamp(0.0, 1.0));
  }

  List<Rect> _contentSlots(double width) => [
    for (final slot in _slots)
      Rect.fromCenter(
        center: Offset(
          _rtl ? width - slot.center : slot.center,
          _style.height / 2,
        ),
        width: slot.width + 2 * _style.inset,
        height: _style.height,
      ),
  ];

  List<MorphGlassSurface> _surfaces() {
    final frame = _frame(Size(_width, _style.height));
    final style = _style;
    return [
      MorphGlassSurface(
        kind: MorphGlassKind.track,
        shape: frame.track,
        color: style.trackColor,
        brightness: _brightness,
        enabled: _enabled,
        glass: false,
      ),
      if (!_none)
        MorphGlassSurface(
          kind: MorphGlassKind.lens,
          shape: frame.lens,
          color: Color.lerp(
            style.lensColor,
            style.liftedLensColor,
            frame.lift,
          )!,
          brightness: _brightness,
          lift: frame.lift,
          scaleX: motion.scaleX,
          scaleY: motion.scaleY,
          optics: MorphGlassOptics.large,
          enabled: _enabled,
        ),
    ];
  }

  @override
  bool get controlEnabled => _enabled;

  @override
  double get pressSlop => MorphSegmentedControl.releaseSlop;

  @override
  void onControlUpOutside(double t, PointerUpEvent event) => onControlCancel(t);

  @override
  bool buildsLike(MorphSegmentedControl oldWidget) =>
      listEquals(oldWidget.segments, widget.segments) &&
      oldWidget.selectedIndex == widget.selectedIndex &&
      (oldWidget.onChanged == null) == (widget.onChanged == null) &&
      oldWidget.proportionalWidth == widget.proportionalWidth &&
      oldWidget.appearance == widget.appearance;

  // The labels read whether a selection shows besides the motion's.
  @override
  Object? get buildInputs => (_motion?.selected, _none);

  @override
  Widget buildControl(BuildContext context) {
    _style = MorphSegmentedControlAppearance.resolve(
      context,
      widget.appearance,
    );
    _brightness = morphBrightnessOf(context);
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: MorphSegmentedControl.maxTextScale);
    final glass = MorphGlassScope.maybeOf(context);
    final style = _style;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _naturalWidth();
        _sync(width);
        if (widget.segments.isEmpty) {
          return SizedBox(width: width, height: style.height);
        }
        motion.reducedMotion = morphReducedMotionOf(context);
        final selected = _none ? -1 : motion.selected;
        final labels = Row(
          children: [
            for (var i = 0; i < widget.segments.length; i++)
              SizedBox(
                width: _slots[i].width + 2 * style.inset,
                child: Semantics(
                  container: true,
                  button: true,
                  inMutuallyExclusiveGroup: true,
                  selected: i == selected,
                  enabled: _enabled && _selectable(i),
                  label: widget.segments[i].title,
                  onTap: _enabled && _selectable(i) ? () => _select(i) : null,
                  child: ExcludeSemantics(
                    child: Center(
                      child: _PressedTitle(
                        dim: _dim,
                        index: i,
                        child: _dimmed(
                          !widget.segments[i].enabled,
                          style.disabledOpacity,
                          Text(
                            widget.segments[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: _scaler,
                            style: MorphTypography.resolve(
                              i == selected
                                  ? style.selectedTextStyle
                                  : style.textStyle,
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
        // The labels repaint only when the selection changes them, not
        // with every frame of the lens, unless the painter records them
        // to copy into a lifted lens.
        final content = morphGlassKeepsContentLive(glass)
            ? RepaintBoundary(child: labels)
            : labels;
        return RepaintBoundary(
          child: MorphDisabled(
            enabled: _enabled,
            opacity: style.disabledOpacity,
            child: MorphPress(
              target: this,
              enabled: _enabled,
              onHighlight: highlightControlFocus,
              onStep: _step,
              dragAxis: .horizontal,
              child: MorphFocusRing(
                visible: controlFocused,
                child: SizedBox(
                  height: style.height,
                  width: width,
                  child: glass == null
                      ? CustomPaint(
                          painter: _SegmentedPainter(this),
                          child: content,
                        )
                      : MorphGlassLayer(
                          painter: glass,
                          frames: frames,
                          surfaces: _surfaces,
                          content: content,
                          contentSlots: _contentSlots(width),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SegmentedPainter extends CustomPainter {
  _SegmentedPainter(this.state) : super(repaint: state.frames);

  final _MorphSegmentedControlState state;

  @override
  void paint(Canvas canvas, Size size) {
    final style = state._style;
    final frame = state._frame(size);
    final trackPaint = Paint();
    trackPaint.color = style.trackColor;
    canvas.drawRRect(frame.track, trackPaint);
    if (state._none) return;
    final lift = frame.lift;
    final lens = frame.lens;
    final shadow = Paint();
    shadow.color = style.shadowColor;
    shadow.maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 5 * lift);
    canvas.drawRRect(lens.shift(const Offset(0, 1.5)), shadow);
    final fill = Paint();
    fill.color = Color.lerp(style.lensColor, style.liftedLensColor, lift)!;
    canvas.drawRRect(lens, fill);
    if (lift > 0.01) {
      final border = Paint();
      border.style = PaintingStyle.stroke;
      border.strokeWidth = 0.5;
      border.color = style.lensBorderColor.withValues(
        alpha: style.lensBorderColor.a * lift,
      );
      canvas.drawRRect(lens.deflate(0.25), border);
    }
  }

  @override
  bool shouldRepaint(_SegmentedPainter oldDelegate) => true;
}

/// A segment's title, dimmed while a finger presses its segment: the
/// dimming changes the alpha of the title's own layer, without building or
/// repainting it.
class _PressedTitle extends SingleChildRenderObjectWidget {
  const _PressedTitle({
    required this.dim,
    required this.index,
    required super.child,
  });

  final ValueListenable<(int?, double)> dim;
  final int index;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPressedTitle(dim, index);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPressedTitle renderObject,
  ) {
    renderObject.dim = dim;
    renderObject.index = index;
  }
}

class _RenderPressedTitle extends RenderProxyBox {
  _RenderPressedTitle(this._dim, this._index);

  ValueListenable<(int?, double)> _dim;
  int _index;

  ValueListenable<(int?, double)> get dim => _dim;

  set dim(ValueListenable<(int?, double)> value) {
    if (identical(value, _dim)) return;
    if (attached) _dim.removeListener(_changed);
    _dim = value;
    if (attached) _dim.addListener(_changed);
    _changed();
  }

  int get index => _index;

  set index(int value) {
    if (value == _index) return;
    _index = value;
    _changed();
  }

  double get _opacity {
    final (pressed, opacity) = _dim.value;
    return pressed == _index ? opacity : 1;
  }

  bool _dimmed = false;

  void _changed() {
    final dimmed = _opacity < 1;
    if (dimmed != _dimmed) {
      _dimmed = dimmed;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsCompositedLayerUpdate();
  }

  @override
  bool get isRepaintBoundary => child != null && _dimmed;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant OpacityLayer? oldLayer,
  }) {
    final layer = oldLayer ?? OpacityLayer();
    layer.alpha = Color.getAlphaFromOpacity(_opacity);
    return layer;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _dim.addListener(_changed);
    _dimmed = _opacity < 1;
  }

  @override
  void detach() {
    _dim.removeListener(_changed);
    super.detach();
  }
}

Widget _dimmed(bool dimmed, double opacity, Widget child) =>
    dimmed ? Opacity(opacity: opacity, child: child) : child;
