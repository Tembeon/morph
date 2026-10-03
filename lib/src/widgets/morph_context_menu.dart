import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

import 'package:morph/foundation.dart';
import 'package:morph/src/measure.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/touch_listener.dart';

/// One block of a context menu beside its hero: a slot above or below
/// the held surface, built when the menu opens (so its rows read the
/// state of that moment) and fading in with the menu. The slot spans the menu's full width; the content aligns itself inside.
///
/// A slot without a [height] is sized by its content: measured under
/// the menu's width, seeded at the menu's launch, and springing to
/// every later change on the flight's open motion - a capsule that
/// grows when a reaction is picked pushes the column out while the
/// hero stays put. A slot with a [height] is a fixed box.
class MorphSatellite {
  /// Creates a satellite slot.
  const MorphSatellite({this.height, required this.builder})
    : assert(
        height == null || height > 0,
        'a satellite needs a positive height.',
      );

  /// The slot's extent along the menu's column, in px; null sizes the
  /// slot by its content, live.
  final double? height;

  /// Builds the slot's content; receives the flight, so a row closes
  /// the menu with `flight.close()` after its action.
  final MorphContentBuilder builder;
}

/// A surface that becomes its own context menu when HELD - the
/// message-bubble pattern. The thing under a resting finger grows as
/// UIKit's preview does ([measuredHoldGrowth]), and on the hold
/// threshold it flies to where its satellites fit: a reactions capsule
/// above, the actions below, both arriving on the flight's own spring.
/// The open menu shows the hero lifted, as UIKit shows its preview
/// ([measuredPreviewScale] about the hero's center), and the flight home
/// lands it at its natural size.
/// A finger let go past [measuredCommitDuration] opens the menu too. The
/// hero keeps its identity for the whole journey (a shared element,
/// never a copy fading in over a copy); the scrim is modal and a tap on
/// it flies everything home; the finger may let go any time once the
/// menu is up.
///
/// The region owns the gesture and the physics, the app owns every
/// pixel: the hero is [child] itself, drawing its own surface - the
/// flight's container is a transparent vessel with no mass of its own,
/// so `MorphTag.specOf` inside the child reports a transparent spec and
/// the child must not render its surface from it - and the satellites
/// are the app's rows, capsules and light in slots ([MorphSatellite]).
///
/// Three doors into the same menu: the hold, a secondary (right)
/// click, and [open] from any context inside [child] - a visible
/// "more" glyph on a card opens what the hold would. A plain tap
/// passes through to the child untouched.
///
/// Geometry: the menu is a column `[above, gap, hero, gap, below]` of
/// at least [width], the hero placed by [alignment] - an outgoing bubble
/// aligns its satellites to its trailing edge. The hero prefers to stay
/// where it stands; when the satellites would leave the overlay (or
/// its safe area, or the keyboard's edge) the whole column shifts to
/// fit, and the hero visibly travels with it. The column rides the hero
/// for the whole flight: the vessel's content alignment is chosen so
/// the hero slot coincides with the flying hero at every spring value,
/// and each satellite unfolds out of a blob at the hero's center
/// ([measuredRetractScale]) on the way out and retracts into it on the
/// way home, as UIKit's menu does.
///
/// The column is live: the hero's slot and every content-sized
/// satellite are measured and spring to what their content becomes
/// while the menu is open (a badge appearing on the hero, a note field
/// unfolding in the capsule), and the placement follows - the hero
/// stays put unless the column must shift. A change to [child] or the
/// satellites while the menu is open rebuilds the menu.
///
/// Inside a scrollable the lift waits for the platform's touch
/// deadline, so a scroll never flashes it; a hold that wins the arena
/// takes the gesture away from the scrollable and from the child's
/// own tap.
class MorphContextMenuRegion extends StatefulWidget {
  /// Creates a region around the hero [child].
  const MorphContextMenuRegion({
    super.key,
    required this.child,
    this.above,
    this.below,
    this.replica,
    this.width = 250,
    this.gap = measuredMenuGap,
    this.margin = 12,
    this.alignment = AlignmentDirectional.centerStart,
    this.holdDuration = measuredHoldDuration,
    this.lifts = true,
    this.enabled = true,
    this.opensOnSecondaryTap = true,
    this.tagId,
    this.motion,
    this.maxScrimOpacity,
    this.scrimColor,
    this.shadowColor,
    this.overlay,
    this.semanticLabel,
    this.onHold,
    this.onOpen,
  }) : assert(width > 0, 'width must be positive.'),
       assert(gap >= 0, 'gap cannot be negative.'),
       assert(margin >= 0, 'margin cannot be negative.');

  /// The hero: the surface that lifts, flies and returns. Draws its
  /// own surface.
  final Widget child;

  /// The slot above the hero (a reactions capsule), or null.
  final MorphSatellite? above;

  /// The slot below the hero (the actions), or null.
  final MorphSatellite? below;

  /// The in-flight presentation of the hero ([MorphTag.replica]
  /// semantics): a lighter, state-independent widget of the same size.
  /// It is used both by the source ghost and by the open menu's hero slot,
  /// so a [child] with an external FocusNode, controller, GlobalKey or other
  /// single-owner state stays mounted exactly once in its original place.
  /// Keep the replica visual and disposable; it must not reuse those owners.
  final Widget? replica;

  /// The menu's minimum width; a wider hero widens the menu to itself.
  final double width;

  /// Space between the hero and each satellite; UIKit's
  /// [measuredMenuGap] by default.
  final double gap;

  /// The menu's distance from the overlay's edges (past the safe area).
  final double margin;

  /// Where the hero sits across the menu's width when the menu is
  /// wider than the hero - and which edge the satellites should align
  /// their content to.
  final AlignmentGeometry alignment;

  /// How long the finger must rest before the menu opens; a finger let
  /// go past [measuredCommitDuration] opens it at the release.
  final Duration holdDuration;

  /// UIKit's hold before a context menu shows: 0.755 - 0.80 s from the
  /// touch to `willDisplayMenu` in four simulator recordings of
  /// UIContextMenuInteraction (iOS 27), 0.768 - 0.797 s in four on an
  /// iPhone 16 Pro.
  static const Duration measuredHoldDuration = Duration(milliseconds: 780);

  /// Whether the hero grows under a resting finger and shows lifted in
  /// the open menu. Held, it scales by `1 + growth / longest side`, the
  /// growth [measuredHoldGrowth] of the time held - the same number of
  /// points for every size, as UIKit's preview grows; a finger that lets
  /// go or scrolls before the commit point drops it back at once. Open,
  /// the menu's hero is [measuredPreviewScale] of its natural size about
  /// its natural center, and the satellites stand off the lifted hero:
  /// the flight carries the hero from the grown size to the lifted one
  /// (a small hero shrinks a little, a large one keeps growing) and back
  /// to its natural size on the way home. Off, the hero keeps its
  /// natural size throughout.
  final bool lifts;

  /// UIKit's growth of a held context menu preview before its menu opens,
  /// in points along the preview's longest side, after [held] time since
  /// the touch: nothing for 0.184 s, then 32 points per second to 8
  /// points at 0.434 s, then 20 points per second to 15 points at
  /// 0.784 s, where it stays.
  ///
  /// Fitted to iPhone 16 Pro recordings (iOS 27, 120 Hz) of previews of
  /// 60 x 40, 120 x 80, 80 x 160 and 300 x 200 points, within 0.21
  /// points of every frame. A pure function of the hold time.
  static double measuredHoldGrowth(Duration held) {
    final double t = held.inMicroseconds / Duration.microsecondsPerSecond;
    if (t <= _growthStart) {
      return 0;
    }
    if (t <= _growthKnee) {
      return _growthFastRate * (t - _growthStart);
    }
    return math.min(
      _growthKneePoints + _growthSlowRate * (t - _growthKnee),
      measuredHoldGrowthPoints,
    );
  }

  /// UIKit's commit point of a held preview: let go after it and the
  /// menu opens anyway (0.400 s cancelled and 0.433 s opened on an
  /// iPhone 16 Pro, with the growth's knee at 0.434 s). Past it the press
  /// belongs to the region - the child's own tap no longer fires. A
  /// [holdDuration] shorter than this commits at the hold itself.
  static const Duration measuredCommitDuration = Duration(milliseconds: 420);

  /// The most a held preview grows before its menu opens, in points.
  static const double measuredHoldGrowthPoints = 15;

  static const double _growthStart = 0.184;
  static const double _growthKnee = 0.434;
  static const double _growthFastRate = 32;
  static const double _growthSlowRate = 20;
  static const double _growthKneePoints =
      _growthFastRate * (_growthKnee - _growthStart);

  /// The most UIKit's open preview has grown over its natural size, in
  /// points along its longest side (26 measured on a 300 x 200 preview);
  /// a smaller preview grows by [measuredLiftScale] instead.
  static const double measuredLiftPoints = 26;

  /// The largest scale of UIKit's open preview (1.15 measured on 60 x 40,
  /// 120 x 80 and 80 x 160 previews).
  static const double measuredLiftScale = 1.15;

  /// The scale of UIKit's open preview over a preview of natural [size]:
  /// [measuredLiftScale] while that adds at most [measuredLiftPoints]
  /// along the longest side, those points beyond (the knee is at 173.3
  /// points). A 60 x 40 preview opens at 69 x 46, a 300 x 200 one at
  /// 326 x 217.3 (iPhone 16 Pro, iOS 27).
  ///
  /// UIKit keeps the preview at this size for as long as the menu is
  /// open; the preview's center stays on the held view's center.
  static double measuredPreviewScale(Size size) {
    final double longest = size.longestSide;
    if (longest <= 0) {
      return 1;
    }
    return 1 +
        math.min((measuredLiftScale - 1) * longest, measuredLiftPoints) /
            longest;
  }

  /// Space UIKit leaves between an open preview and its menu, in points.
  static const double measuredMenuGap = 16;

  /// The size of the blob a UIKit menu grows out of and retracts into, as
  /// a share of the preview, at the preview's center (48 x 32 for a
  /// 120 x 80 preview).
  static const double measuredRetractScale = 0.4;

  /// Whether the region listens for gestures; a disabled region is a
  /// plain wrapper that [open] can still drive.
  final bool enabled;

  /// Whether a secondary (right) click opens the menu. Off, the click
  /// is left to the child - a pointer app that wants its own cursor
  /// popover there.
  final bool opensOnSecondaryTap;

  /// An explicit tag id instead of identity-by-State, for consumers
  /// that must find the flight by name. Stable for the region's life.
  final Object? tagId;

  /// Motion profile of the flight; null resolves MorphTheme, then
  /// [measuredMotion].
  final MorphMotion? motion;

  /// UIKit's context-menu morph, measured on an iPhone 16 Pro (iOS 27):
  /// the preview's resize and the menu growing out of its blob and
  /// retracting into it ride one spring both ways, response 0.284 s and
  /// damping ratio 0.81. The open overshoots and the close dips below
  /// its rest by 1.3 percent, so the handoff latch fires on the close's
  /// zero crossing and the hero lands with UIKit's own undershoot.
  static const MorphMotion measuredMotion = MorphMotion.springs(
    name: 'contextMenu',
    open: measuredSpring,
    close: measuredSpring,
  );

  /// The spring of [measuredMotion].
  static const MorphSpring measuredSpring = MorphSpring(0.284, 0.81);

  /// Scrim ceiling; null resolves MorphTheme, then 0.35 - an inkier
  /// dim than a dialog's, the menu is the only thing that matters.
  final double? maxScrimOpacity;

  /// Scrim hue; null resolves MorphTheme, then black.
  final Color? scrimColor;

  /// Shadow color of the flying vessel (which casts none by itself).
  final Color? shadowColor;

  /// The overlay the menu renders in; null is the nearest enclosing
  /// one ([showMorph]'s `overlay:` semantics). A floating bar layered
  /// over a nested navigator wants the navigator's owner's overlay.
  final OverlayState? overlay;

  /// Accessibility name of the open menu.
  final String? semanticLabel;

  /// The hold threshold was crossed and the menu is about to fly: the
  /// moment for a haptic. Not called for [open] or a secondary click.
  final VoidCallback? onHold;

  /// A new flight took off, whichever door opened it - subscribe to
  /// [MorphFlight.events] here for the landing haptic.
  final void Function(MorphFlight flight)? onOpen;

  /// Opens the menu of the nearest enclosing region - the visible door:
  /// a "more" glyph inside the hero calls this with its own context.
  /// Inside the open menu's hero copy it retargets the live flight.
  static MorphFlight open(BuildContext context) {
    final _RegionScope? scope = context
        .getInheritedWidgetOfExactType<_RegionScope>();
    assert(
      scope != null && scope.state.mounted,
      'MorphContextMenuRegion.open: no live MorphContextMenuRegion above '
      'this context. Call it from inside the region\'s child.',
    );
    return scope!.state._open();
  }

  @override
  State<MorphContextMenuRegion> createState() => _MorphContextMenuRegionState();
}

/// The hero's shared-element id: the same on the source and the target
/// side of every region flight, one flight owning its own registry.
const String _heroId = 'morph-context-menu-hero';

/// The flying container of a context menu: no mass of its own. The
/// hero and the satellites draw their surfaces; the vessel only lays
/// them out and dims the page.
const MorphSurfaceSpec _vessel = MorphSurfaceSpec(
  shape: RoundedRectangleBorder(),
  color: Color(0x00000000),
  elevation: 0,
);

class _MorphContextMenuRegionState extends State<MorphContextMenuRegion>
    with TickerProviderStateMixin {
  late final SingleMotionController _press = SingleMotionController(
    motion: MorphFlexSpec.ultraSmall.scaleSpring.toMotion(),
    vsync: this,
    initialValue: 0,
  );
  MorphFlexSpec _flex = MorphFlexSpec.ultraSmall;
  // The hero's scale below its natural size while its flight lands: the
  // close spring's undershoot after the latch, which UIKit's preview
  // plays as a shrink below its natural size.
  final ValueNotifier<double> _landing = ValueNotifier<double>(0);
  late final Listenable _heroScale = Listenable.merge(<Listenable>[
    _press,
    _landing,
  ]);
  // The hold clock: started on the touch, its elapsed time is the hold
  // time the growth is a function of. The growth shows only once the
  // tap is down (past a scrollable's touch deadline).
  late final Ticker _holdClock = createTicker(_onHoldTick);
  bool _growing = false;
  int? _clockPointer;
  // Past the commit point the press is the region's: a release opens
  // the menu, and the timer opens it at the hold duration.
  bool _committed = false;
  Timer? _holdTimer;

  // The recognizers are owned here, not by a RawGestureDetector: the
  // hold duration is a constructor argument of the long-press
  // recognizer, and swapping the recognizer must not remount the
  // subtree (a MorphTag inside would re-register mid-frame).
  late final TapGestureRecognizer _tap = TapGestureRecognizer(debugOwner: this);
  late LongPressGestureRecognizer _hold = _makeHold();
  // The third arena member keeps a held press from a scrollable: a
  // finger that stayed still past the touch delay and then wanders is
  // claimed here, after the tap and the hold above gave it up, instead
  // of starting a scroll. A still press stays theirs and the child's.
  late final MorphTouchRecognizer _ownership = MorphTouchRecognizer(
    debugOwner: this,
    claimsOnDelay: false,
    allowedButtonsFilter: (int buttons) => buttons == kPrimaryButton,
  );

  Size _size = Size.zero;
  MorphFlight? _flight;
  MorphFlight? _pressOwner;
  StreamSubscription<MorphFlightEvent>? _pressWatch;
  _MenuGeometry? _geometry;

  Object get _tagId => widget.tagId ?? this;

  @override
  void initState() {
    super.initState();
    _tap.onTapDown = _lift;
    _tap.onTapUp = (TapUpDetails _) => _drop();
    _tap.onTapCancel = _drop;
    _syncSecondaryDoor();
  }

  void _syncSecondaryDoor() {
    _tap.onSecondaryTapUp = widget.opensOnSecondaryTap
        ? (TapUpDetails _) => _open()
        : null;
  }

  Duration get _commitDuration =>
      widget.holdDuration < MorphContextMenuRegion.measuredCommitDuration
      ? widget.holdDuration
      : MorphContextMenuRegion.measuredCommitDuration;

  LongPressGestureRecognizer _makeHold() {
    final LongPressGestureRecognizer hold = LongPressGestureRecognizer(
      debugOwner: this,
      duration: _commitDuration,
    );
    hold.onLongPressStart = _onCommit;
    hold.onLongPressEnd = _onCommittedRelease;
    return hold;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final DeviceGestureSettings? settings = MediaQuery.maybeGestureSettingsOf(
      context,
    );
    _tap.gestureSettings = settings;
    _hold.gestureSettings = settings;
    _ownership.gestureSettings = settings;
  }

  @override
  void didUpdateWidget(MorphContextMenuRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holdDuration != widget.holdDuration) {
      _hold.dispose();
      _hold = _makeHold();
      _hold.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    }
    if (oldWidget.opensOnSecondaryTap != widget.opensOnSecondaryTap) {
      _syncSecondaryDoor();
    }
    // The open menu shows this widget's child and satellites, and an
    // overlay entry does not follow its owner's build on its own: a
    // rebuild with new content rebuilds the menu too. Deferred - the
    // entry is no ancestor, so marking it during build is illegal.
    final MorphFlight? flight = _flight;
    final _MenuGeometry? geometry = _geometry;
    if (flight != null && !flight.isFinished) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted && !flight.isFinished && identical(geometry, _geometry)) {
          geometry?.reconfigure(
            above: widget.above,
            below: widget.below,
            minWidth: widget.width,
            gap: widget.gap,
            margin: widget.margin,
            alignment: widget.alignment.resolve(Directionality.of(context)),
            lifted: widget.lifts,
          );
          flight.markNeedsBuild();
        }
      });
    }
  }

  @override
  void dispose() {
    // The flight is the scope's, not the region's: a hero whose row
    // was archived from its own menu keeps flying and dissolves on its
    // way home (MorphFlight.isSourceLost). Its column's springs are
    // this State's tickers, though: they stop here, and the slots
    // freeze at their current extents for the dissolve.
    _geometry?.dispose();
    _geometry = null;
    unawaited(_pressWatch?.cancel());
    _tap.dispose();
    _hold.dispose();
    _ownership.dispose();
    _holdTimer?.cancel();
    _holdClock.dispose();
    _press.dispose();
    _landing.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) {
      return;
    }
    _tap.addPointer(event);
    _hold.addPointer(event);
    _ownership.addPointer(event);
    if (event.buttons == kPrimaryButton &&
        _pressOwner == null &&
        !_holdClock.isActive) {
      _growing = false;
      _clockPointer = event.pointer;
      _holdClock.start();
    }
  }

  void _lift(TapDownDetails details) {
    final RenderObject? box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _size = box.size;
    }
    if (!widget.lifts || _size.isEmpty || !_holdClock.isActive) {
      return;
    }
    _flex = MorphFlexSpec.forSize(_size);
    _growing = true;
  }

  void _onHoldTick(Duration held) {
    if (_growing) {
      _press.value = MorphContextMenuRegion.measuredHoldGrowth(held);
    }
  }

  void _stopGrowth() {
    _growing = false;
    if (_holdClock.isActive) {
      _holdClock.stop();
    }
  }

  void _settlePress() {
    _press.motion = _flex.scaleSpring.toMotion();
    _press.animateTo(0);
  }

  void _drop() {
    // Winning the long-press arena cancels the tap recognizer, and the
    // arena rejects the tap BEFORE it starts the winner: the verdict
    // waits a microtask. A committed press keeps growing, and a flight
    // which re-reads this tag's transformed rect every frame owns the
    // grown size through takeoff - the shuttle would chase a shrinking
    // source otherwise. Ordinary taps and canceled scroll attempts drop
    // at once, as UIKit drops a preview let go before its commit point.
    scheduleMicrotask(() {
      if (!mounted || _pressOwner != null || _committed) {
        return;
      }
      _stopGrowth();
      _press.value = 0;
    });
  }

  void _onCommit(LongPressStartDetails details) {
    final Duration rest = widget.holdDuration - _commitDuration;
    if (rest <= Duration.zero) {
      _onHold();
      return;
    }
    _committed = true;
    _holdTimer?.cancel();
    _holdTimer = Timer(rest, _onHold);
  }

  void _onCommittedRelease(LongPressEndDetails details) {
    if (_committed) {
      _onHold();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    // The tap reports its own end only once it went down: a swipe that
    // a scrollable took before the touch deadline stops the clock here.
    if (event.pointer == _clockPointer && !_committed) {
      _drop();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _clockPointer) {
      return;
    }
    if (!_committed) {
      _drop();
      return;
    }
    _committed = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    _stopGrowth();
    _press.value = 0;
  }

  void _onHold() {
    _committed = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    widget.onHold?.call();
    // The tap cancel may run immediately before or after this callback.
    // Freeze whichever press value is on screen and hand that one stable
    // rect to the flight. Source tracking itself stays live, so scrolling
    // and layout changes still move the return address normally.
    _stopGrowth();
    _press.stop(canceled: true);
    final MorphFlight flight = _open();
    _pressOwner = flight;
    late final StreamSubscription<MorphFlightEvent> pressWatch;
    pressWatch = flight.events.listen((MorphFlightEvent event) {
      if (event != MorphFlightEvent.settled) {
        return;
      }
      if (identical(_pressWatch, pressWatch)) {
        _pressWatch = null;
      }
      unawaited(pressWatch.cancel());
      _releasePress(flight);
    });
    unawaited(_pressWatch?.cancel());
    _pressWatch = pressWatch;
    unawaited(
      flight.closed.whenComplete(() {
        if (identical(_pressWatch, pressWatch)) {
          _pressWatch = null;
          unawaited(pressWatch.cancel());
        }
        _releasePress(flight);
      }),
    );
  }

  void _releasePress(MorphFlight flight) {
    if (!identical(_pressOwner, flight)) {
      return;
    }
    _pressOwner = null;
    if (mounted) {
      // The source is hidden once takeoff has settled, so returning its
      // endpoint to natural size cannot flicker. A later close now lands
      // on the actual resting pixels instead of growing into the held
      // size and shrinking for a second time.
      _settlePress();
    }
  }

  MorphFlight _open() {
    final OverlayState? overlay = widget.overlay;
    // The region's own box, ABOVE the press transform: the hero's
    // natural rect, grown or not - the size the hero lands at, and the
    // center the open menu lifts it about.
    final Rect hero = morphAnchorRect(context, overlay: overlay);
    final MorphFlight? active = _flight;
    final _MenuGeometry geometry;
    if (active != null && !active.isFinished && _geometry != null) {
      geometry = _geometry!;
      geometry.reconfigure(
        above: widget.above,
        below: widget.below,
        minWidth: widget.width,
        gap: widget.gap,
        margin: widget.margin,
        alignment: widget.alignment.resolve(Directionality.of(context)),
        lifted: widget.lifts,
      );
    } else {
      geometry = _MenuGeometry(
        hero: hero,
        above: widget.above,
        below: widget.below,
        minWidth: widget.width,
        gap: widget.gap,
        margin: widget.margin,
        alignment: widget.alignment.resolve(Directionality.of(context)),
        lifted: widget.lifts,
      );
    }
    final MorphTheme? theme = MorphTheme.maybeOf(context);
    final MorphFlight flight = showMorph(
      context,
      from: _tagId,
      motion:
          widget.motion ??
          theme?.motion ??
          MorphContextMenuRegion.measuredMotion,
      maxScrimOpacity: widget.maxScrimOpacity ?? theme?.maxScrimOpacity ?? 0.35,
      scrimColor: widget.scrimColor,
      shadowColor: widget.shadowColor,
      semanticLabel: widget.semanticLabel,
      overlay: overlay,
      target: _MenuTarget(geometry),
      builder: (BuildContext context, MorphFlight flight) =>
          _buildMenu(context, flight, geometry),
    );
    if (!identical(flight, _flight)) {
      _flight = flight;
      // A retarget reuses the live geometry above; only a fresh flight
      // adopts a new one. The springs are this State's tickers and die
      // with the flight, or with the State if that comes first.
      _geometry?.dispose();
      _geometry = geometry;
      geometry.attach(flight, vsync: this);
      _followLanding(flight, hero.size);
      unawaited(
        flight.closed.whenComplete(() {
          geometry.dispose();
          if (identical(_geometry, geometry)) {
            _geometry = null;
          }
        }),
      );
      widget.onOpen?.call(flight);
    }
    return flight;
  }

  /// Plays the close spring's undershoot past the latch on the source
  /// hero: the lifted size is a linear function of the flight value, so
  /// below zero the hero shrinks under its natural size by the same law.
  void _followLanding(MorphFlight flight, Size natural) {
    final double lift = widget.lifts
        ? MorphContextMenuRegion.measuredPreviewScale(natural) - 1
        : 0;
    void land() {
      if (mounted && identical(flight, _flight)) {
        _landing.value = flight.isLanding
            ? math.min(flight.controller.value, 0) * lift
            : 0;
      }
    }

    flight.frameTicks.addListener(land);
    unawaited(
      flight.closed.whenComplete(() {
        flight.frameTicks.removeListener(land);
        if (mounted && identical(flight, _flight)) {
          _landing.value = 0;
        }
      }),
    );
  }

  /// The source stays live in place. An explicit replica supplies every
  /// overlay copy, keeping single-owner state out of the duplicated tree.
  Widget _sourceHero() => _RegionScope(state: this, child: widget.child);

  Widget _flightHero() =>
      _RegionScope(state: this, child: widget.replica ?? widget.child);

  Widget _buildMenu(
    BuildContext context,
    MorphFlight flight,
    _MenuGeometry geometry,
  ) {
    final MorphSatellite? above = widget.above;
    final MorphSatellite? below = widget.below;
    // Built once per menu build; the geometry's ticks move only the
    // slots around them.
    final Widget? aboveContent = above?.builder(context, flight);
    final Widget? belowContent = below?.builder(context, flight);
    final Widget hero = _flightHero();
    return ListenableBuilder(
      listenable: geometry,
      builder: (BuildContext context, Widget? _) {
        return SizedBox(
          width: geometry.width,
          height: geometry.height,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              if (above != null) ...<Widget>[
                _Retract(
                  flight: flight,
                  geometry: geometry,
                  slot: Rect.fromLTWH(0, 0, geometry.width, geometry.above),
                  child: _slot(
                    extent: geometry.above,
                    fixed: above.height != null,
                    alignment: Alignment.bottomCenter,
                    width: geometry.width,
                    onSize: geometry.reportAbove,
                    child: aboveContent!,
                  ),
                ),
                SizedBox(height: geometry.gap),
              ],
              Align(
                alignment: Alignment(geometry.alignment.x, 0),
                child: SizedBox(
                  width: geometry.slotWidth,
                  height: geometry.slotHeight,
                  // The same content on both sides: the target copy
                  // flies alone at full opacity - a fade-through of
                  // identical pixels would read as a blink.
                  child: MorphSharedElement(
                    id: _heroId,
                    fade: .none,
                    // The copy lays out at its natural size and is
                    // painted lifted, as UIKit scales its preview: text
                    // never rewraps at the lifted size. The slot is
                    // seeded at the hero's launch size and springs to
                    // what the copy becomes; the copy is never narrower
                    // than at launch, never wider than the menu, and
                    // overflows the slot until it catches up.
                    child: Transform.scale(
                      scale: geometry.scale,
                      alignment: Alignment.topLeft,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: geometry.heroWidth,
                        maxWidth: geometry.heroWidth,
                        minHeight: geometry.heroHeight,
                        maxHeight: geometry.heroHeight,
                        child: MorphContentMeasure(
                          childConstraints: BoxConstraints(
                            minWidth: geometry.hero.width,
                            maxWidth: geometry.width / geometry.scale,
                          ),
                          alignment: AlignmentDirectional.topStart,
                          onSize: geometry.reportHero,
                          child: hero,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (below != null) ...<Widget>[
                SizedBox(height: geometry.gap),
                _Retract(
                  flight: flight,
                  geometry: geometry,
                  slot: Rect.fromLTWH(
                    0,
                    geometry.aboveExtent + geometry.slotHeight + geometry.gap,
                    geometry.width,
                    geometry.below,
                  ),
                  child: _slot(
                    extent: geometry.below,
                    fixed: below.height != null,
                    alignment: Alignment.topCenter,
                    width: geometry.width,
                    onSize: geometry.reportBelow,
                    child: belowContent!,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// A satellite slot: a fixed box, or a box of the live extent whose
  /// content lays out at its natural height under the menu's width,
  /// clipped while the extent catches up - the growth reveals from the
  /// hero's side outward.
  static Widget _slot({
    required double extent,
    required bool fixed,
    required Alignment alignment,
    required double width,
    required ValueChanged<Size> onSize,
    required Widget child,
  }) {
    if (fixed) {
      return SizedBox(height: extent, child: child);
    }
    return SizedBox(
      height: extent,
      child: ClipRect(
        child: MorphContentMeasure(
          childConstraints: BoxConstraints(minWidth: width, maxWidth: width),
          alignment: alignment,
          onSize: onSize,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget? replica = widget.replica;
    final Widget tagged = MorphTag(
      id: _tagId,
      spec: _vessel,
      replica: replica == null
          ? null
          : MorphSharedElement(
              id: _heroId,
              child: _RegionScope(state: this, child: replica),
            ),
      child: MorphSharedElement(id: _heroId, child: _sourceHero()),
    );
    // The press transform sits ABOVE the tag: the
    // tag's live rect is the lifted one, so the flight takes off from
    // exactly the pixels under the finger, and the wrapper chain is
    // identical at rest - no remount across the press.
    final Widget lifted = ListenableBuilder(
      listenable: _heroScale,
      child: tagged,
      builder: (BuildContext context, Widget? child) => Transform.scale(
        scale:
            (_size.isEmpty ? 1 : 1 + _press.value / _size.longestSide) +
            _landing.value,
        child: child,
      ),
    );
    return Semantics(
      onLongPress: widget.enabled ? _open : null,
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: lifted,
      ),
    );
  }
}

/// A satellite unfolding out of the hero: at flight value 0 the slot is
/// squeezed into a blob of [MorphContextMenuRegion.measuredRetractScale]
/// times the hero's natural size at the hero's center, at 1 it stands in
/// place - the
/// menu grows out of the held surface and retracts into it on the way
/// home, a pure function of the flight's value.
class _Retract extends StatelessWidget {
  const _Retract({
    required this.flight,
    required this.geometry,
    required this.slot,
    required this.child,
  });

  final MorphFlight flight;
  final _MenuGeometry geometry;

  /// The slot's rect in the column.
  final Rect slot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: flight.frameTicks,
      child: child,
      builder: (BuildContext context, Widget? child) {
        // The open's overshoot carries the satellites past their slots,
        // as UIKit's menu overshoots with its preview.
        final double value = math.max(flight.controller.value, 0);
        // One Transform on every frame, identity at rest: a tree that
        // changed shape at the boundary would remount the satellite.
        if (value == 1 || slot.width <= 0 || slot.height <= 0) {
          return Transform(transform: Matrix4.identity(), child: child);
        }
        final Offset heroCenter =
            geometry.heroOffset +
            Offset(geometry.slotWidth / 2, geometry.slotHeight / 2);
        final Rect blob = Rect.fromCenter(
          center: heroCenter,
          width:
              geometry.heroWidth * MorphContextMenuRegion.measuredRetractScale,
          height:
              geometry.heroHeight * MorphContextMenuRegion.measuredRetractScale,
        );
        final Rect now = Rect.lerp(blob, slot, value)!;
        final Matrix4 transform = Matrix4.translationValues(
          now.left - slot.left,
          now.top - slot.top,
          0,
        );
        transform.scaleByDouble(
          now.width / slot.width,
          now.height / slot.height,
          1,
          1,
        );
        return Transform(transform: transform, child: child);
      },
    );
  }
}

/// The identity transport behind [MorphContextMenuRegion.open]. Lives
/// INSIDE the tag's child, so the hero copies in the shuttle carry it
/// too: a "more" glyph in the open menu's hero retargets the live
/// flight instead of asserting.
class _RegionScope extends InheritedWidget {
  const _RegionScope({required this.state, required super.child});

  final _MorphContextMenuRegionState state;

  @override
  bool updateShouldNotify(_RegionScope oldWidget) => state != oldWidget.state;
}

/// The menu's target: the vessel, with the rect and the content
/// alignment read live from the column on every frame the column
/// notifies.
class _MenuTarget extends MorphTargetSpec {
  _MenuTarget(this.geometry)
    : super(
        rectFor: geometry.rectFor,
        surface: _vessel,
        clipBehavior: Clip.none,
        repaint: geometry,
      );

  final _MenuGeometry geometry;

  @override
  Alignment get contentAlignment => geometry.contentAlignment;
}

/// One live extent of the column: its current value, and the spring
/// that carries it to each new measurement once seeded.
class _LiveExtent {
  _LiveExtent(this.value, {required this.seeded});

  double value;
  bool seeded;
  SingleMotionController? spring;
}

/// The menu column around a hero: sizes, the hero's slot and the
/// placement rule. The slot holds the hero lifted
/// ([MorphContextMenuRegion.measuredPreviewScale] of its natural extents)
/// about the launch rect's center. The hero's rect is captured once at
/// launch; the
/// extents are live - seeded from the first measurement (the hero's
/// from its launch size) and springing to every later one on the
/// flight's open motion - and the column notifies on every change, so
/// the rect, the alignment and the slots move together in one frame.
class _MenuGeometry extends ChangeNotifier {
  _MenuGeometry({
    required this.hero,
    required MorphSatellite? above,
    required MorphSatellite? below,
    required this.minWidth,
    required this.gap,
    required this.margin,
    required this.alignment,
    required this.lifted,
  }) : _hasAbove = above != null,
       _hasBelow = below != null,
       _above = _LiveExtent(above?.height ?? 0, seeded: above?.height != null),
       _below = _LiveExtent(below?.height ?? 0, seeded: below?.height != null),
       _heroWidth = _LiveExtent(hero.width, seeded: true),
       _heroHeight = _LiveExtent(hero.height, seeded: true);

  /// The hero's natural rect at launch, in overlay coordinates.
  final Rect hero;

  /// The menu's minimum width.
  double minWidth;

  /// Space between the hero and each satellite.
  double gap;

  /// The menu's distance from the overlay edges.
  double margin;

  /// The resolved hero alignment across the width.
  Alignment alignment;

  /// Whether the slot holds the hero lifted.
  bool lifted;

  bool _hasAbove;
  bool _hasBelow;
  final _LiveExtent _above;
  final _LiveExtent _below;
  final _LiveExtent _heroWidth;
  final _LiveExtent _heroHeight;

  MorphFlight? _flight;
  TickerProvider? _vsync;
  bool _disposed = false;

  /// Binds the column to its flight: the springs ride the flight's
  /// motion on [vsync]'s tickers.
  void attach(MorphFlight flight, {required TickerProvider vsync}) {
    _flight = flight;
    _vsync = vsync;
  }

  /// Applies a rebuilt region to the already-open column. Structural
  /// changes and fixed extents are reflected before the overlay rebuilds,
  /// so layout never combines new children with stale slot geometry.
  void reconfigure({
    required MorphSatellite? above,
    required MorphSatellite? below,
    required double minWidth,
    required double gap,
    required double margin,
    required Alignment alignment,
    required bool lifted,
  }) {
    if (_disposed) {
      return;
    }
    final bool hadAbove = _hasAbove;
    final bool hadBelow = _hasBelow;
    bool changed =
        this.minWidth != minWidth ||
        this.gap != gap ||
        this.margin != margin ||
        this.alignment != alignment ||
        this.lifted != lifted ||
        hadAbove != (above != null) ||
        hadBelow != (below != null);
    this.minWidth = minWidth;
    this.gap = gap;
    this.margin = margin;
    this.alignment = alignment;
    this.lifted = lifted;
    _hasAbove = above != null;
    _hasBelow = below != null;
    changed = _reconfigureSatellite(_above, hadAbove, above) || changed;
    changed = _reconfigureSatellite(_below, hadBelow, below) || changed;
    if (changed) {
      notifyListeners();
    }
  }

  bool _reconfigureSatellite(
    _LiveExtent extent,
    bool existed,
    MorphSatellite? satellite,
  ) {
    if (satellite == null) {
      final bool changed = existed || extent.value != 0 || extent.seeded;
      extent.spring?.dispose();
      extent.spring = null;
      extent.value = 0;
      extent.seeded = false;
      return changed;
    }
    if (!existed) {
      extent.spring?.dispose();
      extent.spring = null;
      extent.value = 0;
      // This is a live insertion, not the invisible launch measurement:
      // its first content report should grow from zero on the spring.
      extent.seeded = true;
    }
    final double? fixed = satellite.height;
    if (fixed == null) {
      return !existed;
    }
    final bool changed = extent.value != fixed || !extent.seeded;
    _report(extent, fixed);
    return changed || !existed;
  }

  /// The above slot's current extent (without the gap).
  double get above => _above.value;

  /// The below slot's current extent (without the gap).
  double get below => _below.value;

  /// The hero's current natural width.
  double get heroWidth => _heroWidth.value;

  /// The hero's current natural height.
  double get heroHeight => _heroHeight.value;

  /// The hero's lift in the open menu: UIKit's preview scale of its
  /// current natural size, or 1 unlifted.
  double get scale => lifted
      ? MorphContextMenuRegion.measuredPreviewScale(Size(heroWidth, heroHeight))
      : 1;

  /// The hero slot's current width: the lifted hero.
  double get slotWidth => heroWidth * scale;

  /// The hero slot's current height: the lifted hero.
  double get slotHeight => heroHeight * scale;

  /// The column's width: the lifted hero's or the minimum, whichever is
  /// wider.
  double get width => math.max(minWidth, slotWidth);

  /// Rows above the hero plus their gap; 0 without a satellite.
  double get aboveExtent => _hasAbove ? above + gap : 0;

  /// Rows below the hero plus their gap; 0 without a satellite.
  double get belowExtent => _hasBelow ? below + gap : 0;

  /// The column's height.
  double get height => aboveExtent + slotHeight + belowExtent;

  /// The hero slot's offset inside the column.
  Offset get heroOffset =>
      Offset((alignment.x + 1) / 2 * (width - slotWidth), aboveExtent);

  /// Where the column sits inside the vessel for every spring value.
  /// The vessel lerps from the hero's rect to the column's; aligning
  /// the content by the hero slot's share of the extra size makes the
  /// slot coincide with the flying hero at EVERY value - the satellites
  /// ride the hero as one rigid body and only unfold.
  Alignment get contentAlignment {
    final double extra = aboveExtent + belowExtent;
    final double y = extra <= 0 ? 0 : aboveExtent / extra * 2 - 1;
    return Alignment(alignment.x, y);
  }

  /// The column's rect: the hero stays put - lifted about its launch
  /// center, as UIKit lifts its preview - unless the column would leave
  /// the overlay's safe area (or the keyboard's edge), then the whole
  /// column shifts.
  Rect rectFor(Size overlay, EdgeInsets padding) {
    final double leftMin = padding.left + margin;
    final double leftMax = overlay.width - padding.right - margin - width;
    final double topMin = padding.top + margin;
    final double topMax = overlay.height - padding.bottom - margin - height;
    final Offset slot =
        hero.topLeft - Offset(hero.width, hero.height) * ((scale - 1) / 2);
    final double left = (slot.dx - heroOffset.dx).clamp(
      leftMin,
      leftMax < leftMin ? leftMin : leftMax,
    );
    final double top = (slot.dy - heroOffset.dy).clamp(
      topMin,
      topMax < topMin ? topMin : topMax,
    );
    return Rect.fromLTWH(left, top, width, height);
  }

  /// The above slot's content was measured.
  void reportAbove(Size size) => _report(_above, size.height);

  /// The below slot's content was measured.
  void reportBelow(Size size) => _report(_below, size.height);

  /// The hero copy was measured.
  void reportHero(Size size) {
    _report(_heroWidth, size.width);
    _report(_heroHeight, size.height);
  }

  void _report(_LiveExtent extent, double target) {
    final MorphFlight? flight = _flight;
    final TickerProvider? vsync = _vsync;
    if (_disposed || flight == null || vsync == null) {
      return;
    }
    if (!extent.seeded) {
      extent.seeded = true;
      extent.value = target;
      notifyListeners();
      return;
    }
    if (target == extent.value && !(extent.spring?.isAnimating ?? false)) {
      return;
    }
    final Motion motion = flight.controller.effectiveMotion.openMotion;
    SingleMotionController? spring = extent.spring;
    if (spring == null) {
      spring = SingleMotionController(
        motion: motion,
        vsync: vsync,
        initialValue: extent.value,
      );
      spring.addListener(() {
        extent.value = spring!.value;
        notifyListeners();
      });
      extent.spring = spring;
    } else if (spring.motion != motion) {
      spring.motion = motion;
    }
    spring.animateTo(target);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final _LiveExtent extent in <_LiveExtent>[
      _above,
      _below,
      _heroWidth,
      _heroHeight,
    ]) {
      extent.spring?.dispose();
      extent.spring = null;
    }
    super.dispose();
  }
}
