import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_cache.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/presentation.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/themes.dart';
import 'package:morph/src/widgets/chrome_group.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/src/widgets/motion_route.dart';
import 'package:morph/src/widgets/sheet_motion.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/widgets/zoom_motion.dart';
import 'package:morph/src/widgets/zoom_source.dart';

/// The look of a sheet presented with [showMorphSheet].
@immutable
class MorphSheetAppearance implements MorphAppearance {
  /// Creates an appearance; the defaults are the iOS light appearance.
  const MorphSheetAppearance({
    this.dockedColor = const Color(0xFFFFFFFF),
    this.floatingColor = const Color(0xF2F9F9F9),
    this.grabberColor = const Color(0x4D3C3C43),
    this.dimmingColor = const Color(0xFF000000),
    this.textColor = const Color(0xFF000000),
  });

  /// The opaque fill of a sheet docked at the large detent:
  /// systemBackground, as rendered (simulator capture: white in light,
  /// 28, 28, 30 in dark).
  final Color dockedColor;

  /// The flat stand-in for the glass of a floating sheet when no
  /// [MorphGlassPainter] is installed; a painter receives it as the tint.
  final Color floatingColor;

  /// The color of the grabber: tertiaryLabel, as rendered.
  final Color grabberColor;

  /// The hue of the dimming behind the sheet; its opacity is
  /// [MorphSheetTuning.dimmingOpacity] times this color's own.
  final Color dimmingColor;

  /// The color of the content's default text (body style): label.
  final Color textColor;

  /// The light appearance.
  static const light = MorphSheetAppearance();

  /// The dark appearance: the docked fill as the simulator renders it.
  static const dark = MorphSheetAppearance(
    dockedColor: Color(0xFF1C1C1E),
    floatingColor: Color(0xF2232325),
    grabberColor: Color(0x4DEBEBF5),
    textColor: Color(0xFFFFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness.
  static MorphSheetAppearance resolve(
    BuildContext context,
    MorphSheetAppearance? explicit,
  ) =>
      explicit ??
      MorphTheme.maybeOf(context)?.appearance<MorphSheetAppearance>() ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };

  /// Copies this appearance with the given fields replaced.
  MorphSheetAppearance copyWith({
    Color? dockedColor,
    Color? floatingColor,
    Color? grabberColor,
    Color? dimmingColor,
    Color? textColor,
  }) => MorphSheetAppearance(
    dockedColor: dockedColor ?? this.dockedColor,
    floatingColor: floatingColor ?? this.floatingColor,
    grabberColor: grabberColor ?? this.grabberColor,
    dimmingColor: dimmingColor ?? this.dimmingColor,
    textColor: textColor ?? this.textColor,
  );

  @override
  bool operator ==(Object other) =>
      other is MorphSheetAppearance &&
      other.dockedColor == dockedColor &&
      other.floatingColor == floatingColor &&
      other.grabberColor == grabberColor &&
      other.dimmingColor == dimmingColor &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(
    dockedColor,
    floatingColor,
    grabberColor,
    dimmingColor,
    textColor,
  );
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
/// While a keyboard shows, the sheet rises as UIKit's does: every detent
/// grows by the keyboard's height, up to the maximum, and the sheet moves
/// to its largest detent (a medium and large sheet docks; a medium-only
/// sheet keeps its visible height above the keyboard), returning to its
/// detent when the keyboard hides. The content's bottom padding is the
/// keyboard's height, so it lays out above it. Neither move counts as a
/// detent change. [scrollingExpandsSheet] false lets a scrollable from
/// [MorphSheet.scrollControllerOf] scroll at once instead of expanding
/// the sheet first.
///
/// Inside the sheet, [MorphSheet.of] changes the detent, and
/// [MorphSheet.scrollControllerOf] hands a scrollable the controller
/// that passes its drags to the sheet the way UIKit's sheets do: a drag
/// down on content scrolled to its top moves the sheet, and a drag up
/// expands the sheet before the content scrolls. `Navigator.pop` closes
/// the sheet with a result.
///
/// With [from], the id of a [MorphTag] under the [MorphScope] around
/// [context], the sheet zooms out of that source instead of sliding up,
/// as a UIKit sheet presented with `preferredTransition = .zoom`: the
/// source hides, a container grows from its frame into the sheet's while
/// the source's look crossfades into the sheet's content, and every
/// dismissal - a pop, a tap on the dimming, a drag down from the smallest
/// detent, which UIKit commits at once - zooms the sheet back into the
/// source, which shows again when the zoom has come to rest. See
/// [MorphZoomMotion] for the measured motion; [zoom] tunes it.
///
/// An absent or unlaid-out source presents a sliding sheet. If the source
/// disappears while the sheet is open, its content stays usable and its
/// dismissal dissolves instead of landing on the old source frame.
///
/// The sheet is pushed on [morphPresentationNavigatorOf] when
/// [useRootNavigator] is null: from a page of a navigation stack it
/// covers the stack's bars, as a UIKit sheet covers the navigation bar of
/// the controller that presents it. True pushes on the root navigator,
/// false on the nearest one.
Future<T?> showMorphSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Object? from,
  MorphZoomTuning zoom = MorphZoomTuning.standard,
  List<MorphSheetDetent> detents = const [MorphSheetDetent.large],
  MorphSheetDetent? initialDetent,
  MorphSheetDetent? largestUndimmedDetent,
  bool grabberVisible = false,
  bool dismissible = true,
  bool scrollingExpandsSheet = true,
  MorphSheetAppearance? appearance,
  String? semanticLabel,
  bool? useRootNavigator,
  ValueChanged<MorphSheetDetent>? onDetentChanged,
  VoidCallback? onDismissAttempt,
}) {
  assert(detents.isNotEmpty, 'A sheet needs at least one detent.');
  final route = MorphSheetRoute<T>(
    onDetentChanged: onDetentChanged,
    onDismissAttempt: onDismissAttempt,
    builder: builder,
    from: from,
    zoom: zoom,
    detents: detents,
    initialDetent: initialDetent,
    largestUndimmedDetent: largestUndimmedDetent,
    grabberVisible: grabberVisible,
    dismissible: dismissible,
    scrollingExpandsSheet: scrollingExpandsSheet,
    appearance: appearance,
    semanticLabel: semanticLabel,
  );
  route._zoomSource = MorphZoomSource.resolve(context, from);
  final navigator = switch (useRootNavigator) {
    null => morphPresentationNavigatorOf(context) ?? Navigator.of(context),
    final bool root => Navigator.of(context, rootNavigator: root),
  };
  route._themes = MorphThemeCarrier(context, to: navigator.context);
  return navigator.push<T>(route);
}

/// The route [showMorphSheet] pushes: the sheet as a real navigator
/// route, so the back button, `Navigator.pop` and pop scopes work as on
/// any route.
class MorphSheetRoute<T> extends PopupRoute<T>
    with MorphMotionRouteMixin<T>, GlassBackdropCacheRoute<T> {
  /// Creates the route.
  MorphSheetRoute({
    required this.builder,
    required this.detents,
    this.from,
    this.zoom = MorphZoomTuning.standard,
    this.initialDetent,
    this.largestUndimmedDetent,
    this.grabberVisible = false,
    this.dismissible = true,
    this.scrollingExpandsSheet = true,
    this.appearance,
    this.semanticLabel,
    this.onDetentChanged,
    this.onDismissAttempt,
    super.settings,
  });

  /// Called with the detent the sheet settles toward when it changes:
  /// by a drag, a tap on the grabber or [MorphSheet.animateTo] (UIKit's
  /// `sheetPresentationControllerDidChangeSelectedDetentIdentifier`).
  final ValueChanged<MorphSheetDetent>? onDetentChanged;

  /// Called when the user tries to dismiss a sheet that may not be
  /// dismissed - [dismissible] is false or a [PopScope] in the sheet
  /// cannot pop - by dragging it down past where it would leave or by
  /// tapping the dimming (UIKit's
  /// `presentationControllerDidAttemptToDismiss`). The sheet stays; the
  /// app may ask, as UIKit apps do, whether to discard changes. A
  /// blocking [PopScope] also hears the attempt through its
  /// `onPopInvokedWithResult` (didPop false). When during the drag UIKit
  /// reports it is not measured: here it is on release.
  final VoidCallback? onDismissAttempt;

  /// Builds the sheet's content.
  final WidgetBuilder builder;

  /// The source tag's id, or null for a sheet that slides up from below.
  ///
  /// An absent or unlaid-out tag presents a sliding sheet.
  final Object? from;

  MorphZoomSource? _zoomSource;
  MorphThemeCarrier? _themes;

  /// The measured zoom used when there is a [from].
  final MorphZoomTuning zoom;

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
  ///
  /// A [PopScope] in the sheet that cannot pop turns both off as well
  /// (UIKit's `isModalInPresentation`): the drag down stretches and
  /// returns, as a sheet that is not dismissible does.
  final bool dismissible;

  /// Whether a drag up on content scrolled to its top expands the sheet
  /// toward its largest detent before the content scrolls (UIKit's
  /// `prefersScrollingExpandsWhenScrolledToEdge`, SwiftUI
  /// `presentationContentInteraction(.resizes)`). False scrolls the
  /// content at once and leaves the sheet at its detent (simulator
  /// capture: a 250 point drag on a scroll view at the medium detent
  /// scrolled it 250 points); a drag down on content at its top still
  /// moves the sheet. Applies to a scrollable driven by
  /// [MorphSheet.scrollControllerOf].
  final bool scrollingExpandsSheet;

  /// The look of the sheet; null resolves it from the theme.
  final MorphSheetAppearance? appearance;

  /// The label screen readers announce for the sheet.
  final String? semanticLabel;

  _SheetViewState? _view;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => dismissible;

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
  ) {
    _zoomSource ??= MorphZoomSource.resolve(context, from);
    final view = _SheetView(route: this);
    return _themes?.install(view) ?? view;
  }

  @override
  bool leaveMotionRoute() {
    final view = _view;
    if (view == null || !view.mounted) return false;
    view._leave();
    return true;
  }
}

/// What the content of a sheet presented with [showMorphSheet] can do
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
    final scope = InheritedModel.inheritFrom<_SheetScope>(
      context,
      aspect: _SheetAspect.sheet,
    );
    if (scope == null) {
      throw FlutterError('MorphSheet.of called outside a MorphSheetRoute.');
    }
    return scope.state;
  }

  /// The sheet around [context], or null outside one.
  static MorphSheet? maybeOf(BuildContext context) =>
      InheritedModel.inheritFrom<_SheetScope>(
        context,
        aspect: _SheetAspect.sheet,
      )?.state;

  /// A scroll controller for the sheet's main scrollable that hands its
  /// drags to the sheet as UIKit does.
  ///
  /// Unlike [of], it does not rebuild [context] when the detent changes.
  static ScrollController scrollControllerOf(BuildContext context) {
    final scope = InheritedModel.inheritFrom<_SheetScope>(
      context,
      aspect: _SheetAspect.controller,
    );
    if (scope == null) {
      throw FlutterError(
        'MorphSheet.scrollControllerOf called outside a MorphSheetRoute.',
      );
    }
    return scope.state._scroll;
  }
}

/// The docked fill of the sheet around [context] as a live source: the
/// sheet's frame notifier and a read of the fill's opacity, 0 floating to
/// 1 docked; null outside a sheet. A detent change does not rebuild
/// [context].
({Listenable frames, double Function() fill})? morphSheetFillOf(
  BuildContext context,
) {
  final scope = InheritedModel.inheritFrom<_SheetScope>(
    context,
    aspect: _SheetAspect.controller,
  );
  if (scope == null) return null;
  final state = scope.state;
  return (frames: state.frames, fill: state._fillNow);
}

/// What a dependent of a [_SheetScope] reads: the sheet with its detent,
/// or only its scroll controller, which a detent change leaves alone.
enum _SheetAspect { sheet, controller }

class _SheetScope extends InheritedModel<_SheetAspect> {
  const _SheetScope({
    required this.state,
    required this.detent,
    required super.child,
  });

  final _SheetViewState state;
  final MorphSheetDetent detent;

  @override
  bool updateShouldNotify(_SheetScope oldWidget) =>
      oldWidget.detent != detent || oldWidget.state != state;

  @override
  bool updateShouldNotifyDependent(
    _SheetScope oldWidget,
    Set<_SheetAspect> dependencies,
  ) =>
      oldWidget.state != state ||
      (oldWidget.detent != detent && dependencies.contains(_SheetAspect.sheet));
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
  MorphZoomMotion? _zoom;
  Rect? _zoomTarget;
  Size? _zoomContent;
  _ZoomFrame? _zoomFrame;
  late final MorphZoomSource _source = _route._zoomSource!;
  final GlobalKey _contentKey = GlobalKey();
  late final _SheetScrollController _scroll = _SheetScrollController(this);
  double _dragY = 0;
  double _stamp = 0;
  double? _scrubFrom;
  double _scrubTravel = 0;
  MorphSpringState? _scrubBack;
  bool _leaving = false;
  int _index = 0;
  Size _size = Size.zero;
  EdgeInsets _padding = EdgeInsets.zero;
  MorphSheetAppearance _style = MorphSheetAppearance.light;
  double _floatingRadius = 0;
  double _dockedRadius = 0;

  // The sheet's tree rebuilds only when this changes; every other frame
  // reads its geometry through frame boxes.
  final ValueNotifier<_SheetStructure> _structure = ValueNotifier((
    zooming: false,
    zoomOpening: false,
    gateOpen: false,
    opaque: false,
    filling: false,
    dimmed: false,
  ));

  // Synced where a build would read the motion, after every ticker ran.
  late final MorphFrameSync<_SheetStructure?> _sync =
      MorphFrameSync<_SheetStructure?>(
        structure: _readStructure,
        rebuild: _show,
      );

  void _show(_SheetStructure? structure) {
    if (structure != null) _structure.value = structure;
  }

  _SheetStructure? _readStructure() {
    if (_motion == null) return null;
    final frame = _frame(_size);
    final structure = (
      zooming: _zooming,
      zoomOpening: _zoom?.isOpening ?? false,
      gateOpen: frame.gateOpen,
      opaque: frame.opaque,
      filling: frame.filling,
      dimmed: frame.dimmed,
    );
    _route.backdropCache.overlay = _style.dimmingColor.withValues(
      alpha: frame.dimmed ? frame.dimOpacity : 0,
    );
    return structure;
  }

  MorphSheetRoute<Object?> get _route => widget.route;

  @override
  List<MorphSheetDetent> get detents => _route.detents;

  @override
  MorphSheetDetent get detent => detents[_index];

  @override
  void initState() {
    super.initState();
    _route._view = this;
    _sync.follow(frames);
    final initial = _route.initialDetent;
    final i = initial == null ? 0 : detents.indexOf(initial);
    _index = i < 0 ? 0 : i;
  }

  @override
  void dispose() {
    _sync.dispose();
    _structure.dispose();
    if (_route._view == this) _route._view = null;
    _source.reveal();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void advanceMotion(double t) {
    final motion = _motion;
    if (motion == null) return;
    _zoomFrame = null;
    motion.advance(t);
    final back = _scrubBack;
    if (back != null && back.isAtRest(t, 0.05)) _scrubBack = null;
    final zoom = _zoom;
    if (zoom != null) {
      zoom.advance(t);
      if (_leaving && zoom.isClosed) {
        _source.reveal();
        _route.finishMotionRoute();
      }
      return;
    }
    if (_leaving && motion.isDismissed) _route.finishMotionRoute();
  }

  @override
  bool get motionSettled {
    final motion = _motion;
    final zoom = _zoom;
    return (motion == null || motion.isSettled) &&
        (zoom == null || zoom.isSettled) &&
        _scrubBack == null;
  }

  /// How far a finger scrubbing the sheet before a zoom dismissal has
  /// travelled down at time [t], or null when nothing scrubs it.
  double? _scrubAt(double t) {
    if (_scrubFrom != null) return _scrubTravel;
    return _scrubBack?.value(t);
  }

  MorphGlassContainerGate? _gated;

  MorphGlassContainerGate _gate({required bool open, required Widget child}) {
    final gated = _gated;
    if (gated != null && gated.open == open && identical(gated.child, child)) {
      return gated;
    }
    return _gated = MorphGlassContainerGate(open: open, child: child);
  }

  bool get _zooming {
    final zoom = _zoom;
    return zoom != null && !(zoom.isOpening && zoom.isSettled);
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
      _route.finishMotionRoute();
      return;
    }
    final zoom = _zoom;
    if (zoom != null) {
      final natural = motion.visibleRect(clock, _size.height);
      final scrub = _scrubAt(clock);
      _zoomContent ??= natural.size;
      _zoomTarget ??= scrub == null
          ? natural
          : _route.zoom.scrubFrame(natural, scrub);
      _scrubFrom = null;
      _scrubBack = null;
      motion.dragCancel(clock);
      zoom.close(clock);
      _zoomFrame = null;
      wake();
      return;
    }
    if (!motion.isDismissing) motion.dismiss(clock);
    wake();
  }

  bool get _dismissAllowed =>
      _route.dismissible &&
      _route.popDisposition != RoutePopDisposition.doNotPop;

  void _requestDismiss() {
    if (_leaving) return;
    if (!_dismissAllowed) {
      _attempted();
      return;
    }
    _route.popMotionRoute();
  }

  // A pop scope that blocks the dismissal still hears the attempt through
  // its own callback, as a blocked back gesture reports it.
  void _attempted() {
    _route.onDismissAttempt?.call();
    if (_route.dismissible) _route.popMotionRoute();
  }

  double? _fitted;

  void _fittedHeight(double height) {
    if (!mounted || _fitted == height) return;
    setState(() => _fitted = height);
  }

  double _maximum(Size size, EdgeInsets padding) =>
      math.max(0, size.height - padding.top - padding.bottom);

  double _keyboard = 0;

  // A keyboard raises the sheet as UIKit's does (simulator capture): each
  // detent grows by the keyboard's height up to the maximum, and the sheet
  // moves to its largest detent while the keyboard shows, back to the
  // selected one when it hides, neither reported as a detent change.
  void _layout(Size size, EdgeInsets padding, double keyboard) {
    if (size == _size &&
        padding == _padding &&
        keyboard == _keyboard &&
        _motion != null) {
      return;
    }
    final raised = keyboard > 0;
    final wasRaised = _keyboard > 0;
    _size = size;
    _padding = padding;
    _keyboard = keyboard;
    final maximum = _maximum(size, padding);
    final full = maximum + padding.bottom;
    final values = [
      for (final d in detents)
        math.min(
              d.resolve(maximum, fittedHeight: _fitted) + keyboard,
              maximum,
            ) +
            padding.bottom,
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
        initial: raised ? order.length - 1 : order.indexOf(_index),
        fullHeight: full,
        dockedIndex: dockedAt < 0 ? null : dockedAt,
        undimmedIndex: undimmedAt == null || undimmedAt < 0 ? null : undimmedAt,
        dismissible: _route.dismissible,
      );
      created.onDetentChanged = (int sorted) {
        if (!mounted) return;
        setState(() => _index = _order[sorted]);
        _route.onDetentChanged?.call(detent);
      };
      created.onDismissAttempt = _attempted;
      created.onDismiss = () {
        if (mounted && !_leaving) _route.popMotionRoute();
      };
      if (_source.capture(context) != null && !_source.isLost) {
        created.presentInPlace(clock);
        final zoom = MorphZoomMotion(tuning: _route.zoom);
        zoom.open(clock);
        _zoom = zoom;
        _source.hide();
      } else {
        created.present(clock);
      }
      _motion = created;
      wake();
    } else {
      motion.relayout(
        clock,
        heights,
        size.width,
        fullHeight: full,
        index: raised == wasRaised
            ? null
            : raised
            ? order.length - 1
            : order.indexOf(_index),
      );
      wake();
    }
  }

  void _stampEvent(PointerEvent event) {
    _unstampedMove = null;
    _stamp = stamp(event);
  }

  // A move wakes the clock only when a drag consumes it, within the same
  // event dispatch, so a finger moving over a resting sheet (a list
  // scrolling inside it) costs no motion frames.
  PointerMoveEvent? _unstampedMove;

  void _stampMove() {
    final move = _unstampedMove;
    if (move != null) _stampEvent(move);
  }

  int? _touch;
  Offset _touchFrom = Offset.zero;
  bool _touchDragged = false;

  void _down(PointerDownEvent event) {
    _stampEvent(event);
    final motion = _motion;
    if (motion == null ||
        _leaving ||
        _touch != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    _touch = event.pointer;
    _touchFrom = event.localPosition;
    _touchDragged = false;
    motion.press(_stamp);
    wake();
  }

  void _move(PointerMoveEvent event) {
    _unstampedMove = event;
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
        _touchFrom.dy < MorphSheetTuning.grabberHitHeight) {
      if (motion.isDragging) motion.dragCancel(_stamp);
      motion.tapGrabber(_stamp);
    }
    wake();
  }

  void _dragStart(DragStartDetails details) {
    _stampMove();
    final motion = _motion;
    if (motion == null || _leaving) return;
    motion.dismissible = _dismissAllowed;
    _dragY = details.globalPosition.dy;
    motion.dragStart(_stamp, _dragY);
    wake();
  }

  void _dragUpdate(DragUpdateDetails details) {
    _stampMove();
    final y = details.globalPosition.dy;
    final from = _scrubFrom;
    if (from != null) {
      _scrubTravel = y - from;
      wake();
      return;
    }
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    if (_zoom != null &&
        _dismissAllowed &&
        y > _dragY &&
        motion.height(_stamp) <= motion.heights.first + 0.5) {
      motion.dragCancel(_stamp);
      _scrubFrom = _dragY;
      _scrubTravel = y - _dragY;
      wake();
      return;
    }
    _dragY = y;
    motion.dragUpdate(_stamp, _dragY);
  }

  void _dragEnd(DragEndDetails details) =>
      _release(details.velocity.pixelsPerSecond.dy);

  void _release(double velocity) {
    _stampMove();
    if (_scrubFrom != null) {
      _endScrub(velocity);
      return;
    }
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragEnd(_stamp, velocity);
    wake();
  }

  /// The finger left a scrubbed sheet moving down at [velocity] points
  /// per second: far enough or fast enough it zooms back into the source,
  /// otherwise it returns to its detent.
  void _endScrub(double velocity) {
    final travel = _scrubTravel;
    final tuning = _route.zoom;
    if (travel > tuning.scrubDismissTravel ||
        velocity > tuning.scrubDismissVelocity) {
      _requestDismiss();
      return;
    }
    _scrubFrom = null;
    final back = MorphSpringState(
      tuning.scrubReturnSpring,
      math.max(travel, -tuning.scrubStretch),
    );
    back.retarget(_stamp, 0);
    _scrubBack = back;
    wake();
  }

  void _scrollDragStart() {
    _stampMove();
    final motion = _motion;
    if (motion == null || _leaving || motion.isDragging) return;
    _stamp = math.max(_stamp, clock);
    _dragY = 0;
    motion.dragStart(_stamp, 0);
    wake();
  }

  void _scrollDragBy(double delta) {
    _stampMove();
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

  double _fillNow() {
    final motion = _motion;
    return motion == null ? 0 : motion.fill(motion.time);
  }

  // The content widget is reused while its inputs hold, so a rebuild of
  // the chrome (each keyboard-inset frame) leaves the app's builder alone;
  // content that reads the MediaQuery still rebuilds through its own
  // dependency. A detent change hands the scope a new detent over the same
  // content: only what reads the sheet through [MorphSheet.of] rebuilds.
  Widget? _builtContent;
  (Color, bool)? _builtFor;
  _SheetScope? _builtScope;

  Widget _contentFor(MorphSheetAppearance style) {
    final inputs = (style.textColor, MorphTypography.usesAppleSystemFont);
    var content = _builtContent;
    if (content == null || inputs != _builtFor) {
      _builtFor = inputs;
      _builtScope = null;
      content = _builtContent = DefaultTextStyle(
        style: MorphTypography.resolve(
          MorphTypography.body.copyWith(color: style.textColor),
        ),
        child: _route.detents.any((MorphSheetDetent d) => d.isFitted)
            ? _FitReport(
                onHeight: _fittedHeight,
                child: Builder(builder: _route.builder),
              )
            : Builder(builder: _route.builder),
      );
    }
    final scope = _builtScope;
    if (scope != null && scope.detent == detent) return scope;
    return _builtScope = _SheetScope(
      state: this,
      detent: detent,
      child: content,
    );
  }

  @override
  void didUpdateWidget(_SheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _builtContent = null;
    _builtScope = null;
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphSheetAppearance.resolve(context, _route.appearance);
    final media = MediaQuery.of(context);
    final glass = MorphGlassScope.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final reported = MediaQuery.maybeDisplayCornerRadiiOf(
      context,
    )?.bottomLeft.x;
    _style = style;
    _zoomFrame = null;
    _floatingRadius =
        (reported ?? MorphSheetTuning.fallbackDisplayRadius) -
        MorphSheetTuning.floatingInset;
    _dockedRadius = reported ?? 0;
    final content = _contentFor(style);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = constraints.biggest;
        final padding = EdgeInsets.only(
          top: media.padding.top,
          bottom: media.padding.bottom,
        );
        _layout(size, padding, media.viewInsets.bottom);
        final motion = _motion!;
        _show(_sync.read());
        return GlassBackdropCacheScope(
          cache: _route.backdropCache,
          child: ValueListenableBuilder<_SheetStructure>(
            valueListenable: _structure,
            child: GlassBackdropCacheScope(
              cache: null,
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    top: 0,
                    bottom: math.max(
                      media.padding.bottom,
                      media.viewInsets.bottom,
                    ),
                  ),
                  viewPadding: media.viewPadding.copyWith(top: 0),
                  viewInsets: EdgeInsets.zero,
                ),
                child: KeyedSubtree(
                  key: _contentKey,
                  child: MorphChromeBackdrop(child: content),
                ),
              ),
            ),
            builder:
                (
                  BuildContext context,
                  _SheetStructure structure,
                  Widget? child,
                ) {
                  final sheet = _SheetBody(
                    frames: frames,
                    fill: () => motion.fill(motion.time),
                    opaque: structure.opaque,
                    filling: structure.filling,
                    clipped: structure.zooming,
                    style: style,
                    glass: glass,
                    brightness: brightness,
                    grabber: _route.grabberVisible,
                    shape: () => _frame(size).bodyShape,
                    child: _gate(open: structure.gateOpen, child: child!),
                  );
                  if (structure.zooming) {
                    return _buildZoom(
                      size: size,
                      style: style,
                      sheet: sheet,
                      opening: structure.zoomOpening,
                    );
                  }
                  return Stack(
                    children: [
                      if (structure.dimmed)
                        Positioned.fill(
                          key: const ValueKey('dim'),
                          child: Semantics(
                            onTap: _route.dismissible ? _requestDismiss : null,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _requestDismiss,
                              child: RepaintBoundary(
                                child: MorphLiveColoredBox(
                                  live: frames,
                                  colorOf: () => style.dimmingColor.withValues(
                                    alpha: _frame(size).dimOpacity,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Keyed so the dimming appearing mid-drag does not
                      // re-inflate the sheet and dispose its drag recognizer.
                      Positioned.fill(
                        key: const ValueKey('sheet'),
                        child: MorphLiveBox(
                          live: frames,
                          size: () => Size(size.width, _frame(size).height),
                          transform: () => _frame(size).transform,
                          clip: () => _frame(size).bodyShape,
                          continuous: true,
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
                                  if (_scrubFrom != null) {
                                    _scrubTravel = 0;
                                    _endScrub(0);
                                    return;
                                  }
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
          ),
        );
      },
    );
  }

  // The sheet's geometry at the motion's current time in a view of [size],
  // computed once per frame: every frame-driven read in the tree asks here.
  _SheetFrame _frame(Size size) {
    final motion = _motion!;
    final t = motion.time;
    final h = motion.height(t);
    final s = motion.scale(t);
    final dim = motion.dimming(t);
    final fill = motion.fill(t);
    final floating = _floatingRadius;
    final bottomRadius = math.max(
      0.0,
      floating + (_dockedRadius - floating) * motion.cornerBlend(t),
    );
    final dimOpacity =
        _style.dimmingColor.a * MorphSheetTuning.dimmingOpacity * dim;
    final scrub = _zooming ? null : _scrubAt(t);
    final natural = motion.visibleRect(t, size.height);
    final drawn = scrub == null
        ? natural
        : _route.zoom.scrubFrame(natural, scrub);
    final k = size.width <= 0 ? 1.0 : drawn.width / size.width;
    final stretched = motion.stretch(t) != 1;
    final ky = scrub == null && stretched && h > 0 ? drawn.height / h : k;
    final transform = Matrix4.translationValues(drawn.left, drawn.top, 0);
    transform.multiply(Matrix4.diagonal3Values(k, ky, 1));
    final frame = _SheetFrame(
      height: h,
      scale: s,
      dimmed: dim > 0,
      dimOpacity: dimOpacity,
      bottomRadius: bottomRadius,
      transform: transform,
      bodyShape: RRect.fromLTRBAndCorners(
        0,
        0,
        size.width,
        scrub == null ? h : math.min(h, drawn.height / k),
        topLeft: const Radius.circular(MorphSheetTuning.topRadius),
        topRight: const Radius.circular(MorphSheetTuning.topRadius),
        bottomLeft: Radius.circular(bottomRadius),
        bottomRight: Radius.circular(bottomRadius),
      ),
      gateOpen: !_zooming && scrub == null && s == 1 && !stretched,
      opaque: fill >= 1,
      filling: fill > 0,
    );
    return frame;
  }
}

/// What the sheet's tree is built from; it rebuilds only when this changes.
typedef _SheetStructure = ({
  bool zooming,
  bool zoomOpening,
  bool gateOpen,
  bool opaque,
  bool filling,
  bool dimmed,
});

/// The sheet's geometry at one time.
class _SheetFrame {
  const _SheetFrame({
    required this.height,
    required this.scale,
    required this.dimmed,
    required this.dimOpacity,
    required this.bottomRadius,
    required this.transform,
    required this.bodyShape,
    required this.gateOpen,
    required this.opaque,
    required this.filling,
  });

  final double height;
  final double scale;
  final bool dimmed;
  final double dimOpacity;
  final double bottomRadius;
  final Matrix4 transform;
  final RRect bodyShape;
  final bool gateOpen;
  final bool opaque;
  final bool filling;
}

/// The zoom's geometry at one time.
class _ZoomFrame {
  const _ZoomFrame({
    required this.size,
    required this.rect,
    required this.shape,
    required this.fit,
    required this.dimOpacity,
    required this.opacity,
    required this.sourceSize,
    required this.height,
    required this.fade,
    required this.closing,
    required this.lost,
  });

  final Size size;
  final Rect rect;
  final RRect shape;
  final double fit;
  final double dimOpacity;
  final double opacity;
  final Size sourceSize;
  final double height;
  final double fade;
  final bool closing;
  final bool lost;
}

extension on _SheetViewState {
  // Computed once per frame of the motion: every live read of the zoom
  // asks here, so the source is captured and its dissolve sampled once.
  _ZoomFrame _zoomAt(Size size) {
    final cached = _zoomFrame;
    if (cached != null && cached.size == size) return cached;
    final zoom = _zoom!;
    final motion = _motion!;
    final t = motion.time;
    final frame = _frame(size);
    final natural = motion.visibleRect(t, size.height);
    final destination = _zoomTarget ?? natural;
    final source = _source.capture(context) ?? destination;
    final rect = zoom.rect(t, source, destination);
    final progress = zoom.sizeProgress(t);
    final p = progress.clamp(0.0, 1.0);
    final from = _source.radius(source.size);
    Radius corner(double to) =>
        Radius.circular(math.max(0, from + (to - from) * p));
    final top = corner(MorphSheetTuning.topRadius * frame.scale);
    final bottom = corner(frame.bottomRadius * frame.scale);
    final closing = !zoom.isOpening;
    final opacity = _source.opacity(progress, closing: closing);
    return _zoomFrame = _ZoomFrame(
      size: size,
      rect: rect,
      shape: RRect.fromRectAndCorners(
        Offset.zero & rect.size,
        topLeft: top,
        topRight: top,
        bottomLeft: bottom,
        bottomRight: bottom,
      ),
      fit:
          frame.scale *
          MorphZoomMotion.contentScale(rect, _zoomContent ?? natural.size),
      dimOpacity: frame.dimOpacity * zoom.dimming(t),
      opacity: opacity,
      sourceSize: source.size,
      height: frame.height,
      fade: zoom.fade(t),
      closing: closing,
      lost: _source.isLost,
    );
  }

  Widget _buildZoom({
    required Size size,
    required MorphSheetAppearance style,
    required Widget sheet,
    required bool opening,
  }) {
    _ZoomFrame now() => _zoomAt(size);
    return Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            onTap: _route.dismissible ? _requestDismiss : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: opening ? _requestDismiss : null,
              child: MorphLiveColoredBox(
                live: frames,
                colorOf: () =>
                    style.dimmingColor.withValues(alpha: now().dimOpacity),
              ),
            ),
          ),
        ),
        MorphLivePositionedTemplate(
          live: frames,
          template: () =>
              Positioned.fromRect(rect: now().rect, child: morphLiveSlot),
          child: IgnorePointer(
            child: MorphLiveTemplate(
              live: frames,
              template: () => ClipRSuperellipse(
                clipper: MorphZoomContinuousClipper(now().shape),
              ),
              child: MorphLiveOpacity(
                live: frames,
                opacityOf: () => now().opacity,
                child: _SheetZoomCrossfade(
                  frames: frames,
                  source: _source,
                  frame: now,
                  content: MorphLivePositionedTemplate(
                    live: frames,
                    template: () => Positioned(
                      left: 0,
                      top: 0,
                      width: size.width,
                      height: now().height,
                      child: morphLiveSlot,
                    ),
                    child: MorphLiveTransform.matrix(
                      live: frames,
                      alignment: Alignment.topLeft,
                      matrixOf: () {
                        final fit = now().fit;
                        return Matrix4.diagonal3Values(fit, fit, 1);
                      },
                      child: MorphLiveOpacity(
                        live: frames,
                        opacityOf: () {
                          final frame = now();
                          return frame.lost && frame.closing ? 1 : frame.fade;
                        },
                        child: sheet,
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

/// The sheet crossfaded with its source's look: the sheet and the look's
/// fade follow the zoom on live render objects, and the crossfade builds
/// again only when the look appears, leaves or changes size, or the source
/// tag takes a new widget while the look shows.
class _SheetZoomCrossfade extends StatefulWidget {
  const _SheetZoomCrossfade({
    required this.frames,
    required this.source,
    required this.frame,
    required this.content,
  });

  final Listenable frames;
  final MorphZoomSource source;
  final _ZoomFrame Function() frame;
  final Widget content;

  @override
  State<_SheetZoomCrossfade> createState() => _SheetZoomCrossfadeState();
}

class _SheetZoomCrossfadeState extends State<_SheetZoomCrossfade> {
  late final MorphFrameSync<Object?> _sync = MorphFrameSync<Object?>(
    structure: _inputsNow,
    rebuild: (Object? _) => setState(() {}),
  );

  late Listenable _ticks = _ticksOf(widget);

  // A tag rebuild notifies during build, so the sync hears it in a
  // microtask and the replica takes the new widget on the next frame.
  static Listenable _ticksOf(_SheetZoomCrossfade widget) {
    final revisions = widget.source.revisions;
    return revisions == null
        ? widget.frames
        : Listenable.merge(<Listenable>[widget.frames, revisions]);
  }

  @override
  void initState() {
    super.initState();
    _sync.follow(_ticks);
  }

  @override
  void didUpdateWidget(_SheetZoomCrossfade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frames, widget.frames) ||
        !identical(oldWidget.source, widget.source)) {
      _ticks = _ticksOf(widget);
      _sync.follow(_ticks);
    }
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  Object? _inputsNow() {
    final frame = widget.frame();
    return (frame.sourceSize, widget.source.look(frame.fade, frame.sourceSize));
  }

  @override
  Widget build(BuildContext context) {
    _sync.read();
    return widget.source.crossfade(
      live: widget.frames,
      fadeOf: () => widget.frame().fade,
      size: widget.frame().sourceSize,
      content: widget.content,
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.frames,
    required this.shape,
    required this.fill,
    required this.opaque,
    required this.filling,
    required this.clipped,
    required this.style,
    required this.glass,
    required this.brightness,
    required this.grabber,
    required this.child,
  });

  /// Notifies once per frame the sheet's motion advanced.
  final Listenable frames;

  /// The body's shape now, in its own coordinates.
  final RRect Function() shape;

  /// The opacity of the docked fill now, 0 to 1.
  final double Function() fill;

  /// Whether the docked fill is opaque: the glass under it is not drawn.
  final bool opaque;

  /// Whether the docked fill shows at all, over the glass.
  final bool filling;

  /// Whether the body clips itself to [shape]; a frame box above it clips
  /// otherwise.
  final bool clipped;

  final MorphSheetAppearance style;
  final MorphGlassPainter? glass;
  final Brightness brightness;
  final bool grabber;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final painter = glass;
    final body = Stack(
      fit: StackFit.expand,
      children: [
        if (painter != null && !opaque)
          MorphGlassHost(
            painter: painter,
            mode: MorphGlassMode.surface,
            frames: frames,
            frame: () => MorphGlassFrame([
              MorphGlassSurface(
                kind: MorphGlassKind.menu,
                shape: shape(),
                color: style.floatingColor,
                brightness: brightness,
              ),
            ]),
          )
        else if (!opaque)
          ColoredBox(color: style.floatingColor),
        if (opaque)
          ColoredBox(color: style.dockedColor)
        else if (filling)
          RepaintBoundary(
            child: MorphLiveColoredBox(
              live: frames,
              colorOf: () => style.dockedColor.withValues(
                alpha: style.dockedColor.a * fill(),
              ),
            ),
          ),
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
    );
    if (!clipped) return body;
    return ClipRSuperellipse(
      clipper: MorphZoomContinuousClipper(shape()),
      child: body,
    );
  }
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
    if (_owns ||
        (delta > 0 && atTop) ||
        (delta < 0 && sheet._route.scrollingExpandsSheet && sheet._canExpand)) {
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

/// Lays its child out with a loose height at its top and reports the
/// child's height after layout: the content height a fitted detent rests
/// at.
class _FitReport extends SingleChildRenderObjectWidget {
  const _FitReport({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  _RenderFitReport createRenderObject(BuildContext context) =>
      _RenderFitReport(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderFitReport renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderFitReport extends RenderProxyBox {
  _RenderFitReport(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      constraints.hasBoundedHeight
          ? Size(child.size.width, constraints.maxHeight)
          : child.size,
    );
    final height = child.size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
