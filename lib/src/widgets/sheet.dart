import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/sheet_motion.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// The look of a sheet presented with [presentMorphSheet].
@immutable
class MorphSheetStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphSheetStyle({
    this.dockedColor = const Color(0xFFFFFFFF),
    this.floatingColor = const Color(0xF2F9F9F9),
    this.grabberColor = const Color(0x4D3C3C43),
    this.dimmingColor = const Color(0xFF000000),
  });

  /// The opaque fill of a sheet docked at the large detent:
  /// systemBackground, as rendered.
  final Color dockedColor;

  /// The flat stand-in for the glass of a floating sheet when no
  /// [MorphGlassPainter] is installed; a painter receives it as the tint.
  final Color floatingColor;

  /// The color of the grabber: tertiaryLabel, as rendered.
  final Color grabberColor;

  /// The hue of the dimming behind the sheet; its opacity is
  /// [MorphSheetTuning.dimmingOpacity] times this color's own.
  final Color dimmingColor;

  /// The light appearance.
  static const light = MorphSheetStyle();

  /// The dark appearance: the docked fill as the simulator renders it.
  static const dark = MorphSheetStyle(
    dockedColor: Color(0xFF2C2C2E),
    floatingColor: Color(0xF2232325),
    grabberColor: Color(0x4DEBEBF5),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphSheetStyle resolve(
    BuildContext context,
    MorphSheetStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.sheet ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

/// Presents [builder]'s content in a sheet that moves like an iOS 27
/// UISheetPresentationController, and completes with the value the sheet
/// is popped with.
///
/// The sheet slides up from the bottom of the screen to [initialDetent]
/// (the first of [detents] when null) and rests at one of [detents]. Below
/// the large detent it floats as glass, inset from the screen edges; at
/// [MorphSheetDetent.large] it docks edge to edge and turns opaque. See
/// [MorphSheetMotion] for the measured motion. Dragging the sheet moves
/// it between detents and, when [dismissible], down and away; a tap on
/// the dimming outside dismisses it too. The detents up to
/// [largestUndimmedDetent] do not dim and leave the page behind them
/// interactive.
///
/// Inside the sheet, [MorphSheet.of] changes the detent, and
/// [MorphSheet.scrollControllerOf] hands a scrollable the controller
/// that passes its drags to the sheet the way UIKit's sheets do: a drag
/// down on content scrolled to its top moves the sheet, and a drag up
/// expands the sheet before the content scrolls. `Navigator.pop` closes
/// the sheet with a result.
Future<T?> presentMorphSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  List<MorphSheetDetent> detents = const [MorphSheetDetent.large],
  MorphSheetDetent? initialDetent,
  MorphSheetDetent? largestUndimmedDetent,
  bool grabberVisible = false,
  bool dismissible = true,
  MorphSheetStyle? style,
  String? semanticLabel,
  bool useRootNavigator = false,
}) {
  assert(detents.isNotEmpty, 'A sheet needs at least one detent.');
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    MorphSheetRoute<T>(
      builder: builder,
      detents: detents,
      initialDetent: initialDetent,
      largestUndimmedDetent: largestUndimmedDetent,
      grabberVisible: grabberVisible,
      dismissible: dismissible,
      style: style,
      semanticLabel: semanticLabel,
    ),
  );
}

/// The route [presentMorphSheet] pushes: the sheet as a real navigator
/// route, so the back button, `Navigator.pop` and pop scopes work as on
/// any route.
class MorphSheetRoute<T> extends PopupRoute<T> {
  /// Creates the route.
  MorphSheetRoute({
    required this.builder,
    required this.detents,
    this.initialDetent,
    this.largestUndimmedDetent,
    this.grabberVisible = false,
    this.dismissible = true,
    this.style,
    this.semanticLabel,
    super.settings,
  });

  /// Builds the sheet's content.
  final WidgetBuilder builder;

  /// The heights the sheet rests at.
  final List<MorphSheetDetent> detents;

  /// The detent the sheet presents at; null for the first of [detents].
  final MorphSheetDetent? initialDetent;

  /// The largest detent that does not dim the page; null dims at every
  /// detent.
  final MorphSheetDetent? largestUndimmedDetent;

  /// Whether the grabber shows at the top of the sheet.
  final bool grabberVisible;

  /// Whether a drag down or a tap outside dismisses the sheet.
  final bool dismissible;

  /// The look of the sheet; null resolves it from the theme.
  final MorphSheetStyle? style;

  /// The label screen readers announce for the sheet.
  final String? semanticLabel;

  final ValueNotifier<int> _popRequests = ValueNotifier<int>(0);
  _SheetViewState? _view;

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
  ) => _SheetView(route: this);

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    controller?.stop();
    final view = _view;
    if (view == null || !view.mounted) {
      controller?.value = 0;
    } else {
      view._leave();
    }
    return popped;
  }

  void _finished() {
    final c = controller;
    if (c != null && !isActive && c.value != 0) c.value = 0;
  }

  @override
  void dispose() {
    _popRequests.dispose();
    super.dispose();
  }
}

/// What the content of a sheet presented with [presentMorphSheet] can do
/// with its sheet.
abstract class MorphSheet {
  /// The detent the sheet rests at or is heading to.
  MorphSheetDetent get detent;

  /// The sheet's detents.
  List<MorphSheetDetent> get detents;

  /// Moves the sheet to [detent] on the sheet spring.
  void animateTo(MorphSheetDetent detent);

  /// The sheet around [context].
  static MorphSheet of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SheetScope>();
    assert(scope != null, 'MorphSheet.of called outside a MorphSheetRoute.');
    return scope!.state;
  }

  /// The sheet around [context], or null outside one.
  static MorphSheet? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetScope>()?.state;

  /// A scroll controller for the sheet's main scrollable that hands its
  /// drags to the sheet as UIKit does.
  static ScrollController scrollControllerOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SheetScope>();
    assert(scope != null, 'MorphSheet.scrollControllerOf outside a sheet.');
    return scope!.state._scroll;
  }
}

class _SheetScope extends InheritedWidget {
  const _SheetScope({required this.state, required super.child});

  final _SheetViewState state;

  @override
  bool updateShouldNotify(_SheetScope oldWidget) => false;
}

class _SheetView extends StatefulWidget {
  const _SheetView({required this.route});

  final MorphSheetRoute<Object?> route;

  @override
  State<_SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<_SheetView>
    with SingleTickerProviderStateMixin<_SheetView>, MorphClock<_SheetView>
    implements MorphSheet {
  MorphSheetMotion? _motion;
  late final _SheetScrollController _scroll = _SheetScrollController(this);
  double _dragY = 0;
  double _stamp = 0;
  bool _leaving = false;
  int _index = 0;
  Size _size = Size.zero;
  EdgeInsets _padding = EdgeInsets.zero;

  MorphSheetRoute<Object?> get _route => widget.route;

  @override
  List<MorphSheetDetent> get detents => _route.detents;

  @override
  MorphSheetDetent get detent => detents[_motion?.index ?? _index];

  @override
  void initState() {
    super.initState();
    _route._view = this;
    final initial = _route.initialDetent;
    final i = initial == null ? 0 : detents.indexOf(initial);
    _index = i < 0 ? 0 : i;
  }

  @override
  void dispose() {
    if (_route._view == this) _route._view = null;
    _scroll.dispose();
    super.dispose();
  }

  @override
  void advanceMotion(double t) {
    final motion = _motion;
    if (motion == null) return;
    motion.advance(t);
    if (_leaving && motion.isDismissed) _route._finished();
  }

  @override
  bool get motionSettled {
    final motion = _motion;
    return motion == null || motion.isSettled;
  }

  @override
  void animateTo(MorphSheetDetent detent) {
    final i = detents.indexOf(detent);
    final motion = _motion;
    if (i < 0 || motion == null) return;
    motion.animateTo(clock, _sortedIndex(i));
    wake();
  }

  List<int> _order = const [];

  int _sortedIndex(int detentIndex) => _order.indexOf(detentIndex);

  void _leave() {
    final motion = _motion;
    _leaving = true;
    if (motion == null) {
      _route._finished();
      return;
    }
    if (!motion.isDismissing) motion.dismiss(clock);
    wake();
  }

  void _requestDismiss() {
    if (!_route.dismissible || _leaving) return;
    Navigator.of(context).maybePop();
  }

  double _maximum(Size size, EdgeInsets padding) =>
      math.max(0, size.height - padding.top - padding.bottom);

  void _layout(Size size, EdgeInsets padding) {
    if (size == _size && padding == _padding && _motion != null) return;
    _size = size;
    _padding = padding;
    final maximum = _maximum(size, padding);
    final values = [
      for (final d in detents) d.resolve(maximum) + padding.bottom,
    ];
    final order = List<int>.generate(detents.length, (int i) => i);
    order.sort((int a, int b) => values[a].compareTo(values[b]));
    _order = order;
    final heights = [for (final i in order) values[i]];
    final dockedAt = order.indexWhere((int i) => detents[i].isLarge);
    final undimmed = _route.largestUndimmedDetent;
    final undimmedAt = undimmed == null
        ? null
        : order.indexWhere((int i) => detents[i] == undimmed);
    final motion = _motion;
    if (motion == null) {
      final created = MorphSheetMotion(
        heights: heights,
        width: size.width,
        initial: order.indexOf(_index),
        dockedIndex: dockedAt < 0 ? null : dockedAt,
        undimmedIndex: undimmedAt == null || undimmedAt < 0 ? null : undimmedAt,
        dismissible: _route.dismissible,
      );
      created.onDetentChanged = (int sorted) => _index = _order[sorted];
      created.onDismiss = () {
        if (mounted && !_leaving) Navigator.of(context).maybePop();
      };
      created.present(clock);
      _motion = created;
      wake();
    } else {
      motion.relayout(clock, heights, size.width);
      wake();
    }
  }

  void _stampEvent(PointerEvent event) => _stamp = stamp(event);

  int? _touch;
  Offset _touchFrom = Offset.zero;
  bool _touchDragged = false;

  void _down(PointerDownEvent event) {
    _stampEvent(event);
    final motion = _motion;
    if (motion == null || _leaving || _touch != null) return;
    _touch = event.pointer;
    _touchFrom = event.localPosition;
    _touchDragged = false;
    motion.press(_stamp);
    wake();
  }

  void _move(PointerMoveEvent event) {
    _stampEvent(event);
    if (event.pointer != _touch) return;
    if ((event.localPosition - _touchFrom).distance > kTouchSlop) {
      _touchDragged = true;
    }
  }

  void _up(PointerEvent event) {
    _stampEvent(event);
    if (event.pointer != _touch) return;
    _touch = null;
    final motion = _motion;
    if (motion == null) return;
    if (!motion.isDragging) motion.unpress(_stamp);
    if (event is PointerUpEvent &&
        !_touchDragged &&
        !motion.isDragging &&
        _touchFrom.dy < MorphSheetTuning.grabberHitHeight) {
      motion.tapGrabber(_stamp);
    }
    wake();
  }

  void _dragStart(DragStartDetails details) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    _dragY = details.globalPosition.dy;
    motion.dragStart(_stamp, _dragY);
    wake();
  }

  void _dragUpdate(DragUpdateDetails details) {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    _dragY = details.globalPosition.dy;
    motion.dragUpdate(_stamp, _dragY);
  }

  void _dragEnd(DragEndDetails details) =>
      _release(details.velocity.pixelsPerSecond.dy);

  void _release(double velocity) {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragEnd(_stamp, velocity);
    wake();
  }

  void _scrollDragStart() {
    final motion = _motion;
    if (motion == null || _leaving || motion.isDragging) return;
    _stamp = math.max(_stamp, clock);
    _dragY = 0;
    motion.dragStart(_stamp, 0);
    wake();
  }

  void _scrollDragBy(double delta) {
    final motion = _motion;
    if (motion == null) return;
    if (!motion.isDragging) _scrollDragStart();
    _dragY += delta;
    motion.dragUpdate(math.max(_stamp, clock), _dragY);
  }

  bool get _canExpand {
    final motion = _motion;
    if (motion == null) return false;
    return motion.height(motion.time) < motion.heights.last - 0.5;
  }

  bool get _scrollDragging => _motion?.isDragging ?? false;

  @override
  Widget build(BuildContext context) {
    final style = MorphSheetStyle.resolve(context, _route.style);
    final media = MediaQuery.of(context);
    final glass = MorphGlass.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final reported = MediaQuery.maybeDisplayCornerRadiiOf(
      context,
    )?.bottomLeft.x;
    final floatingRadius =
        (reported ?? MorphSheetTuning.fallbackDisplayRadius) -
        MorphSheetTuning.floatingInset;
    final dockedRadius = reported ?? 0;
    final content = _SheetScope(
      state: this,
      child: Builder(builder: _route.builder),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = constraints.biggest;
        final padding = EdgeInsets.only(
          top: media.padding.top,
          bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
        );
        _layout(size, padding);
        final motion = _motion!;
        return ListenableBuilder(
          listenable: frames,
          child: MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(
                top: 0,
                bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
              ),
              viewPadding: media.viewPadding.copyWith(top: 0),
              viewInsets: EdgeInsets.zero,
            ),
            child: content,
          ),
          builder: (BuildContext context, Widget? child) {
            final t = motion.time;
            final h = motion.height(t);
            final dock = motion.dock(t);
            final s = motion.scale(t);
            final dim = motion.dimming(t);
            final bottomRadius =
                floatingRadius + (dockedRadius - floatingRadius) * dock;
            final shape = RRect.fromLTRBAndCorners(
              0,
              0,
              size.width,
              h,
              topLeft: const Radius.circular(MorphSheetTuning.topRadius),
              topRight: const Radius.circular(MorphSheetTuning.topRadius),
              bottomLeft: Radius.circular(math.max(0, bottomRadius)),
              bottomRight: Radius.circular(math.max(0, bottomRadius)),
            );
            final dimOpacity =
                style.dimmingColor.a * MorphSheetTuning.dimmingOpacity * dim;
            final sheet = _SheetBody(
              shape: shape,
              dock: dock,
              style: style,
              glass: glass,
              brightness: brightness,
              grabber: _route.grabberVisible,
              child: child!,
            );
            final transform = Matrix4.translationValues(
              0,
              motion.shift(t) + motion.offset(t),
              0,
            );
            transform.multiply(Matrix4.diagonal3Values(s, s, 1));
            return Stack(
              children: [
                if (dim > 0)
                  Positioned.fill(
                    child: Semantics(
                      onTap: _route.dismissible ? _requestDismiss : null,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _requestDismiss,
                        child: ColoredBox(
                          color: style.dimmingColor.withValues(
                            alpha: dimOpacity,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  top: size.height - h,
                  width: size.width,
                  height: h,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: transform,
                    child: Semantics(
                      scopesRoute: true,
                      namesRoute: _route.semanticLabel != null,
                      explicitChildNodes: true,
                      label: _route.semanticLabel,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _down,
                        onPointerMove: _move,
                        onPointerUp: _up,
                        onPointerCancel: _up,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: _dragStart,
                          onVerticalDragUpdate: _dragUpdate,
                          onVerticalDragEnd: _dragEnd,
                          onVerticalDragCancel: () {
                            _motion?.dragCancel(clock);
                            wake();
                          },
                          child: sheet,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.shape,
    required this.dock,
    required this.style,
    required this.glass,
    required this.brightness,
    required this.grabber,
    required this.child,
  });

  final RRect shape;
  final double dock;
  final MorphSheetStyle style;
  final MorphGlassPainter? glass;
  final Brightness brightness;
  final bool grabber;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final painter = glass;
    final docked = style.dockedColor.withValues(
      alpha: style.dockedColor.a * dock,
    );
    return ClipRRect(
      clipper: _ShapeClipper(shape),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (painter != null && dock < 1)
            painter.buildSurface(
              context,
              MorphGlassSurface(
                kind: MorphGlassKind.menu,
                shape: shape,
                color: style.floatingColor,
                brightness: brightness,
              ),
            )
          else if (dock < 1)
            ColoredBox(color: style.floatingColor),
          if (dock > 0) ColoredBox(color: docked),
          child,
          if (grabber)
            Positioned(
              top:
                  MorphSheetTuning.grabberOffset -
                  MorphSheetTuning.grabberSize.height / 2,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: MorphSheetTuning.grabberSize.width,
                  height: MorphSheetTuning.grabberSize.height,
                  decoration: BoxDecoration(
                    color: style.grabberColor,
                    borderRadius: BorderRadius.circular(
                      MorphSheetTuning.grabberSize.height / 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShapeClipper extends CustomClipper<RRect> {
  _ShapeClipper(this.shape);

  final RRect shape;

  @override
  RRect getClip(Size size) => shape;

  @override
  bool shouldReclip(_ShapeClipper oldClipper) => oldClipper.shape != shape;
}

class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.sheet);

  final _SheetViewState sheet;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    sheet: sheet,
    physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
    context: context,
    oldPosition: oldPosition,
  );
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.sheet,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _SheetViewState sheet;
  bool _owns = false;

  @override
  void applyUserOffset(double delta) {
    if (_owns && delta < 0 && !sheet._canExpand) {
      _owns = false;
      sheet._release(0);
      super.applyUserOffset(delta);
      return;
    }
    final atTop = pixels <= minScrollExtent;
    if (_owns || (delta > 0 && atTop) || (delta < 0 && sheet._canExpand)) {
      _owns = true;
      sheet._scrollDragBy(delta);
      if (!sheet._scrollDragging) _owns = false;
      return;
    }
    super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    if (_owns) {
      _owns = false;
      sheet._release(-velocity);
      super.goBallistic(0);
      return;
    }
    super.goBallistic(velocity);
  }

  @override
  void dispose() {
    if (_owns) sheet._release(0);
    super.dispose();
  }
}
