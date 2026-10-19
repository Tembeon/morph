import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/chrome_group.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/haptics.dart';
import 'package:morph/src/widgets/menu_content.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/menu_host.dart';
import 'package:morph/src/widgets/menu_motion.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/scrim.dart';
import 'package:morph/src/show.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/presentation.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/spring.dart';

/// A block standing above a context menu's preview, as UIKit's
/// accessory views do - a reactions capsule over a message bubble -
/// built when the menu opens, so it reads the state of that moment.
///
/// It rides the preview: it stands [MorphContextMenuRegion.measuredMenuGap]
/// above it, centered on it inside the safe area, and unfolds out of the
/// preview's top edge as the menu opens and folds back into it as the
/// menu closes. It is sized by its content, at most the overlay's width
/// minus the menu's margins; a [height] reserves that much room above the
/// preview when the menu is placed, so a preview near the top edge moves
/// down to make room for it.
class MorphSatellite {
  /// Creates an accessory.
  const MorphSatellite({this.height, required this.builder})
    : assert(
        height == null || height > 0,
        'an accessory needs a positive height.',
      );

  /// The room reserved above the preview, in points; null reserves the
  /// height the content had when the menu last showed.
  final double? height;

  /// Builds the content; a reaction closes the menu with
  /// [MorphContextMenuRegion.close] after its action.
  final WidgetBuilder builder;
}

/// A surface that becomes its own context menu when HELD, as a view
/// with a `UIContextMenuInteraction` does: the thing under a resting
/// finger grows as UIKit's preview grows ([measuredHoldGrowth]), and on
/// the hold its preview lifts ([measuredPreviewScale] about its center)
/// while the [menu] grows out of a blob at its center
/// ([MorphMenuAttachment]) and the page dims.
///
/// The menu IS the button menu, as in UIKit: the card, rows, sections,
/// submenus, highlight, flex, scrolling, keyboard and haptics of
/// [MorphMenuButton], on the context menu's measured morph. It stands
/// [measuredMenuGap] below the lifted preview, above it (its entries
/// reversed unless [order] is [MorphMenuOrder.fixed]) when it does not
/// fit below, and when it fits
/// on neither side the preview moves with it until it fits. The finger
/// that held the preview may slide onto a row and choose it on release,
/// with a selection haptic on each row; let go on the preview, it leaves
/// the menu open. A touch outside the menu, Esc, a chosen row or [close]
/// sends the preview home and the menu back into its blob.
///
/// A finger let go past [measuredCommitDuration] opens the menu too, a
/// plain tap passes through to the child untouched, and inside a
/// scrollable the lift waits for the platform's touch deadline so a
/// scroll never flashes it; a hold that wins the arena takes the gesture
/// away from the scrollable and from the child's own tap. Three doors
/// open the same menu: the hold, a secondary (right) click, and [open]
/// from any context inside [child].
///
/// The preview is the [child] itself, drawing its own surface (or
/// [replica] in the overlay); an [accessory] rides above it.
class MorphContextMenuRegion extends StatefulWidget {
  /// Creates a region around the held [child].
  const MorphContextMenuRegion({
    super.key,
    required this.child,
    this.menu = const <MorphMenuEntry>[],
    this.accessory,
    this.order = MorphMenuOrder.automatic,
    this.dismissOnSelect,
    this.appearance,
    this.replica,
    this.preview,
    this.previewSize,
    this.onPreviewTap,
    this.holdDuration = measuredHoldDuration,
    this.lifts = true,
    this.enabled = true,
    this.opensOnSecondaryTap = true,
    @internal this.tagId,
    this.maxScrimOpacity,
    this.scrimColor,
    @internal this.scrimMotion,
    @internal this.overlay,
    this.semanticLabel,
    this.onHold,
    @internal this.onOpen,
    this.onClose,
  });

  /// The held view: the surface that lifts into the preview and returns.
  /// Draws its own surface.
  final Widget child;

  /// The rows of the menu (`UIMenu` children, SwiftUI's `menuItems`):
  /// rows, sections, submenus, dividers, deferred groups and free-form
  /// [MorphMenuWidget] rows. An empty menu shows the preview and the
  /// [accessory] alone.
  ///
  /// The open menu follows the widget: a rebuild with other entries
  /// updates it in place and resizes it on the measured springs.
  final List<MorphMenuEntry> menu;

  /// A block above the preview, such as a reactions capsule, or null.
  final MorphSatellite? accessory;

  /// The order of [menu] relative to the preview: a menu standing above
  /// the preview reverses its entries unless this is
  /// [MorphMenuOrder.fixed] (`preferredMenuElementOrder`).
  final MorphMenuOrder order;

  /// Whether choosing a row closes the menu: null leaves it to each row's
  /// [MorphMenuItem.keepsMenuOpen], true closes after every row, false
  /// keeps the menu open after every row (`menuActionDismissBehavior`).
  final bool? dismissOnSelect;

  /// The look of [menu]; null resolves it through
  /// [MorphMenuAppearance.resolve].
  final MorphMenuAppearance? appearance;

  /// The preview's stand-in in the overlay ([MorphTag.replica]
  /// semantics): a lighter, state-independent widget of the same size, so
  /// a [child] with an external FocusNode, controller, GlobalKey or other
  /// single-owner state stays mounted exactly once in its original place.
  /// Keep the replica visual and disposable; it must not reuse those
  /// owners.
  final Widget? replica;

  /// Builds a different view to preview instead of the held [child]
  /// (`previewProvider`, SwiftUI's `contextMenu(menuItems:preview:)`): a
  /// photo larger than its thumbnail, a page behind a link. The held view
  /// morphs into it, crossfading as it grows into [previewSize] about the
  /// held view's center, and back into the held view on the close. Null
  /// previews the held view itself, lifted.
  ///
  /// Fidelity: approximation - the crossfade from the held view to the
  /// preview is not measured.
  final WidgetBuilder? preview;

  /// The size of the [preview] (`preferredContentSize`); null gives it the
  /// held view's lifted size.
  final Size? previewSize;

  /// Called when the open preview is tapped (`willPerformPreviewAction`,
  /// the dismiss commit style): the menu closes and the preview flies
  /// home, and the app runs its action, such as opening the previewed
  /// page. Null leaves a tap on the preview to close the menu.
  final VoidCallback? onPreviewTap;

  /// How long the finger must rest before the menu opens; a finger let
  /// go past [measuredCommitDuration] opens it at the release.
  final Duration holdDuration;

  /// UIKit's hold before a context menu shows: 0.755 - 0.80 s from the
  /// touch to `willDisplayMenu` in four simulator recordings of
  /// UIContextMenuInteraction (iOS 27), 0.768 - 0.797 s in four on an
  /// iPhone 16 Pro.
  static const Duration measuredHoldDuration = Duration(milliseconds: 780);

  /// Whether the held view grows under a resting finger and shows lifted
  /// in the open menu. Held, it scales by `1 + growth / longest side`, the
  /// growth [measuredHoldGrowth] of the time held - the same number of
  /// points for every size, as UIKit's preview grows; a finger that lets
  /// go or scrolls before the commit point drops it back at once. Open,
  /// the preview is [measuredPreviewScale] of its natural size about its
  /// natural center, and the menu stands off the lifted preview: the
  /// preview goes from the grown size to the lifted one (a small view
  /// shrinks a little, a large one keeps growing) and back to its natural
  /// size on the way home. Off, the preview keeps its natural size
  /// throughout.
  ///
  /// Under Reduce Motion the held view keeps its natural size, as UIKit
  /// holds its preview at scale 1 then (read from UIKit, notes private).
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
  /// a share of the held view, at its center (48 x 32 for a 120 x 80
  /// view; [MorphMenuAttachment.blobSize] has the measured law).
  static const double measuredRetractScale =
      MorphMenuAttachment.measuredBlobScale;

  /// Whether the region listens for gestures; a disabled region is a
  /// plain wrapper that [open] can still drive.
  final bool enabled;

  /// Whether a secondary (right) click opens the menu. Off, the click
  /// is left to the child - a pointer app that wants its own cursor
  /// popover there.
  final bool opensOnSecondaryTap;

  /// An explicit tag id instead of identity-by-State, for consumers
  /// that must find the flight by name. Stable for the region's life.
  @internal
  final Object? tagId;

  /// UIKit's context-menu morph, measured on an iPhone 16 Pro (iOS 27):
  /// the preview's resize and the menu growing out of its blob and
  /// retracting into it ride one spring both ways, response 0.284 s and
  /// damping ratio 0.81 ([MorphMenuMorphSpec.context]). The open
  /// overshoots and the close dips below its rest by 1.3 percent, so the
  /// handoff latch fires on the close's zero crossing and the held view
  /// lands with UIKit's own undershoot.
  @internal
  static const MorphMotion measuredMotion = MorphMotion(
    name: 'contextMenu',
    openSpring: measuredSpring,
    closeSpring: measuredSpring,
  );

  /// The spring of [measuredMotion].
  @internal
  static const MorphSpring measuredSpring = MorphSpring(0.284, 0.81);

  /// Scrim ceiling; null resolves MorphTheme, then
  /// [measuredDimOpacity] for the ambient brightness.
  final double? maxScrimOpacity;

  /// Scrim hue; null resolves MorphTheme, then black.
  final Color? scrimColor;

  /// The scrim's own springs; null is [measuredDim].
  @internal
  final MorphScrimMotion? scrimMotion;

  /// UIKit's context-menu dimming, measured on an iPhone 16 Pro (iOS
  /// 27): a full-screen black view without blur whose alpha alone
  /// animates, on its own springs beside the morph - open response
  /// 0.32 s damping 0.80, close 0.35 s / 0.85 (0.001 rms of alpha) -
  /// starting 14.5 ms after the preview on the way in and 12.5 ms on
  /// the way out, the same in both appearances.
  @internal
  static const MorphScrimMotion measuredDim = MorphScrimMotion(
    motion: MorphMotion(
      name: 'contextMenuDim',
      openSpring: MorphSpring(0.32, 0.80),
      closeSpring: MorphSpring(0.35, 0.85),
    ),
    openDelay: Duration(microseconds: 14500),
    closeDelay: Duration(microseconds: 12500),
  );

  /// The opacity of UIKit's context-menu dimming over black: 0.2 in
  /// the light appearance, 0.48 in the dark one (iPhone 16 Pro, iOS 27).
  static double measuredDimOpacity(Brightness brightness) =>
      switch (brightness) {
        Brightness.dark => 0.48,
        Brightness.light => 0.2,
      };

  /// The overlay the menu renders in; null is
  /// [morphPresentationOverlayOf] ([showMorph]'s `overlay:` semantics),
  /// above the bars of a navigation stack the region sits in. A floating
  /// bar layered over a nested navigator wants the navigator's owner's
  /// overlay.
  @internal
  final OverlayState? overlay;

  /// Accessibility name of the open menu.
  final String? semanticLabel;

  /// The hold threshold was crossed and the menu is about to open. Not
  /// called for [open] or a secondary click.
  ///
  /// The region itself plays UIKit's preview haptic at this moment
  /// ([MorphThemeData.haptics]): UIKit's context menu plays its
  /// full-strength preview pattern when the hold reaches its preview
  /// (read from UIKit, notes private).
  final VoidCallback? onHold;

  /// The menu opened, whichever door opened it (`willDisplayMenu`):
  /// receives the flight that carries the preview, the menu and the dim -
  /// subscribe to [MorphFlight.events] here for the landing haptic.
  @internal
  final void Function(MorphFlight flight)? onOpen;

  /// The menu started closing, however it closes (`willEndMenu`): a row
  /// chosen, a touch outside, Esc, [close] or the flight closed.
  final VoidCallback? onClose;

  /// Opens the menu of the nearest enclosing region - the visible door:
  /// a "more" glyph inside the held view calls this with its own context.
  /// Inside the open preview it retargets the live flight.
  @internal
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

  /// Closes the open menu of the region whose [child], [accessory] or
  /// menu row [context] is in (`dismissMenu`); nothing happens when it is
  /// not open.
  static void close(BuildContext context) {
    final _RegionScope? scope = context
        .getInheritedWidgetOfExactType<_RegionScope>();
    if (scope == null || !scope.state.mounted) return;
    scope.state._close();
  }

  @override
  State<MorphContextMenuRegion> createState() => _MorphContextMenuRegionState();
}

class _MorphContextMenuRegionState extends State<MorphContextMenuRegion>
    with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );
  MorphFlexSpec _flex = MorphFlexSpec.ultraSmall;
  // The held view's scale below its natural size while its flight lands:
  // the close spring's undershoot after the latch, which UIKit's preview
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
  // Under Reduce Motion the held view keeps its size.
  bool _still = false;
  int? _clockPointer;
  Duration _holdOrigin = Duration.zero;
  Duration? _holdOffset;
  bool _committed = false;

  late final TapGestureRecognizer _tap = TapGestureRecognizer(debugOwner: this);
  late _MotionHoldRecognizer _hold = _makeHold();
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
  final GlobalKey<_MenuDriverState> _driver = GlobalKey<_MenuDriverState>();
  int? _menuPointer;
  Offset _finger = Offset.zero;
  MorphFlight? _flight;
  MorphFlight? _pressOwner;
  StreamSubscription<MorphFlightEvent>? _pressWatch;
  _Placement? _placement;
  double _accessoryHeight = 0;

  Object? _sessionTag;
  Object get _tagId => _flight != null && !_flight!.isFinished
      ? _sessionTag ?? widget.tagId ?? this
      : widget.tagId ?? this;

  MorphMenuController? get _controller => _driver.currentState?.controller;

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

  _MotionHoldRecognizer _makeHold() {
    final hold = _MotionHoldRecognizer(debugOwner: this);
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
    if (oldWidget.enabled && !widget.enabled ||
        oldWidget.tagId != widget.tagId ||
        oldWidget.holdDuration != widget.holdDuration) {
      _committed = false;
      _stopGrowth();
      _clockPointer = null;
      _press.value = 0;
      _hold.dispose();
      _hold = _makeHold();
      _hold.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    }
    if (oldWidget.tagId != widget.tagId) {
      final flight = _flight;
      if (flight != null && !flight.isFinished) {
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          if (!flight.isFinished) flight.close();
        });
      }
    }
    if (oldWidget.opensOnSecondaryTap != widget.opensOnSecondaryTap) {
      _syncSecondaryDoor();
    }
    // The open preview and accessory show this widget's child, and an
    // overlay entry does not follow its owner's build on its own: a
    // rebuild rebuilds them too. Deferred - the entry is no ancestor, so
    // marking it during build is illegal. The menu rows follow through
    // their controller.
    final MorphFlight? flight = _flight;
    if (flight != null && !flight.isFinished) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted && !flight.isFinished) flight.markContentNeedsBuild();
      });
    }
  }

  @override
  void dispose() {
    // The flight is the scope's, not the region's: a held view archived
    // from its own menu keeps flying and dissolves on its way home
    // (MorphFlight.isSourceLost).
    unawaited(_pressWatch?.cancel());
    _tap.dispose();
    _hold.dispose();
    _ownership.dispose();
    _holdClock.dispose();
    _press.dispose();
    _landing.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) {
      return;
    }
    _finger = event.position;
    _tap.addPointer(event);
    _hold.addPointer(event);
    _ownership.addPointer(event);
    if (event.buttons == kPrimaryButton &&
        _pressOwner == null &&
        !_holdClock.isActive) {
      _growing = false;
      _clockPointer = event.pointer;
      _holdOrigin = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      _holdOffset = null;
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
    _still = morphReducedMotionOf(context);
  }

  void _onHoldTick(Duration elapsed) {
    _holdOffset ??= Duration(
      microseconds:
          ((SchedulerBinding.instance.currentSystemFrameTimeStamp - _holdOrigin)
                      .inMicroseconds /
                  timeDilation)
              .round(),
    );
    final held = elapsed + _holdOffset!;
    if (_growing) {
      _press.value = _still
          ? 0
          : MorphContextMenuRegion.measuredHoldGrowth(held);
    }
    if (!widget.enabled || _clockPointer == null) return;
    // A hold that lost the arena (a scroll took the touch before the tap
    // went down) can never commit, and nothing else ends the clock until
    // the finger lifts: stop it rather than tick an unchanged scene.
    if (!_committed &&
        !_growing &&
        _hold.state != GestureRecognizerState.possible) {
      _stopGrowth();
      return;
    }
    if (!_committed && held >= _commitDuration) _hold.commit();
    if (_committed && held >= widget.holdDuration) _onHold(held: true);
  }

  void _stopGrowth() {
    _growing = false;
    if (_holdClock.isActive) {
      _holdClock.stop();
    }
  }

  void _settlePress() {
    _press.animateWith(
      SpringSimulation(
        _flex.scaleSpring.description,
        _press.value,
        0,
        _press.velocity,
      ),
    );
  }

  void _drop() {
    // Winning the long-press arena cancels the tap recognizer, and the
    // arena rejects the tap BEFORE it starts the winner: the verdict
    // waits a microtask. A committed press keeps growing, and a flight
    // which re-reads this tag's transformed rect every frame owns the
    // grown size through takeoff - the preview would chase a shrinking
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
    if (!widget.enabled || !_holdClock.isActive) return;
    _committed = true;
  }

  void _onCommittedRelease(LongPressEndDetails details) {
    if (_committed) {
      _onHold();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _clockPointer) _finger = event.position;
    if (event.pointer == _menuPointer) _controller?.menuPointerMove(event);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer == _menuPointer) {
      _menuPointer = null;
      _controller?.menuPointerUp(event);
    }
    // The tap reports its own end only once it went down: a swipe that
    // a scrollable took before the touch deadline stops the clock here.
    if (event.pointer == _clockPointer && !_committed) {
      _drop();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _menuPointer) {
      _menuPointer = null;
      _controller?.menuPointerCancel(event);
    }
    if (event.pointer != _clockPointer) {
      return;
    }
    if (!_committed) {
      _drop();
      return;
    }
    _committed = false;
    _stopGrowth();
    _press.value = 0;
  }

  void _onHold({bool held = false}) {
    if (!mounted || !widget.enabled || !_holdClock.isActive) return;
    _committed = false;
    morphPlayHaptic(context, MorphHaptic.preview);
    widget.onHold?.call();
    // The tap cancel may run immediately before or after this callback.
    // Freeze whichever press value is on screen and hand that one stable
    // rect to the flight. Source tracking itself stays live, so scrolling
    // and layout changes still move the return address normally.
    _stopGrowth();
    _press.stop(canceled: true);
    final MorphFlight flight = _open(pointer: held ? _clockPointer : null);
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
      _releasePress(flight, hidden: true);
    });
    unawaited(_pressWatch?.cancel());
    _pressWatch = pressWatch;
    unawaited(
      flight.closed.whenComplete(() {
        if (identical(_pressWatch, pressWatch)) {
          _pressWatch = null;
          unawaited(pressWatch.cancel());
        }
        _releasePress(flight, hidden: false);
      }),
    );
  }

  void _releasePress(MorphFlight flight, {required bool hidden}) {
    if (!identical(_pressOwner, flight)) {
      return;
    }
    _pressOwner = null;
    if (!mounted) return;
    // The source is hidden once takeoff has settled, so its endpoint
    // returns to natural size at once: nothing shows it, and a spring
    // there would repaint the hidden source (and the page around it)
    // every frame for a second. A later close lands on the actual
    // resting pixels instead of growing into the held size and shrinking
    // for a second time. A flight closed before it settled hands back a
    // source that shows, which springs back.
    if (hidden) {
      _press.stop();
      _press.value = 0;
    } else {
      _settlePress();
    }
  }

  OverlayState get _overlay =>
      widget.overlay ??
      morphPresentationOverlayOf(context) ??
      Overlay.of(context);

  /// Opens the menu, or retargets the open one; [pointer] is the finger
  /// that held the preview, handed to the menu rows.
  MorphFlight _open({int? pointer}) {
    final OverlayState? explicit = widget.overlay;
    if (explicit != null) morphCheckOverlayAncestor(context, explicit);
    final MorphFlight? active = _flight;
    final bool fresh = active == null || active.isFinished;
    if (fresh) {
      _sessionTag = widget.tagId ?? this;
      _placement = _place();
    }
    final MorphMenuController? controller = _controller;
    final MorphMenuMotion? motion = controller?.menuMotion;
    if (controller != null &&
        widget.menu.isNotEmpty &&
        motion != null &&
        !motion.isOpen) {
      // The menu's opening launches the flight through the controller's
      // launcher (_launch), which carries the preview and the menu as one.
      if (pointer != null) {
        _menuPointer = pointer;
        controller.holdOpen(pointer, _finger);
      } else {
        controller.open();
      }
      final MorphFlight? launched = _flight;
      if (launched != null && !launched.isFinished) return launched;
    }
    return _launch();
  }

  /// Where the preview, the accessory and the menu stand: the held view's
  /// natural rect - the region's own box, ABOVE the press transform, grown
  /// or not - the lifted preview about its center, and the menu attached
  /// to it, which moves the preview when it fits on neither side.
  _Placement _place() {
    final Rect held = morphAnchorRect(context, overlay: widget.overlay);
    final double scale = widget.lifts
        ? MorphContextMenuRegion.measuredPreviewScale(held.size)
        : 1;
    final Size size = widget.preview == null
        ? held.size * scale
        : widget.previewSize ?? held.size * scale;
    final Rect lifted = Rect.fromCenter(
      center: held.center,
      width: size.width,
      height: size.height,
    );
    final MorphSatellite? accessory = widget.accessory;
    final double room = accessory == null
        ? 0
        : (accessory.height ?? _accessoryHeight) +
              MorphContextMenuRegion.measuredMenuGap;
    final OverlayState overlay = _overlay;
    final RenderBox overlayBox =
        overlay.context.findRenderObject()! as RenderBox;
    final EdgeInsets padding = morphTargetPaddingOf(
      context,
      overlayBox.size,
      overlayBox: overlayBox,
    );
    final _MenuDriverState? driver = _driver.currentState;
    final MorphMenuAttachment attachment = MorphMenuAttachment(
      held: held,
      preview: lifted,
      accessory: room,
    );
    Offset shift;
    if (driver != null && widget.menu.isNotEmpty) {
      shift = driver
          .prepare(
            held: held,
            attachment: attachment,
            overlay: overlay,
            bounds: overlayBox.size,
            padding: padding,
          )
          .previewShift;
    } else {
      shift = MorphMenuMotion.placeAttached(
        attachment: attachment,
        size: Size.zero,
        bounds: overlayBox.size,
        padding: padding,
      ).shift;
    }
    return _Placement(held: held, preview: lifted.shift(shift));
  }

  /// Launches the flight that carries the preview, the accessory and the
  /// menu, or retargets the live one.
  MorphFlight _launch() {
    final _Placement placement = _placement ??= _place();
    final MorphFlight flight = showMorph(
      _driver.currentContext ?? context,
      from: _tagId,
      motion: MorphContextMenuRegion.measuredMotion,
      maxScrimOpacity:
          widget.maxScrimOpacity ??
          MorphContextMenuRegion.measuredDimOpacity(morphBrightnessOf(context)),
      scrimColor: widget.scrimColor ?? const Color(0xFF000000),
      scrimMotion: widget.scrimMotion ?? MorphContextMenuRegion.measuredDim,
      semanticLabel: widget.semanticLabel,
      overlay: widget.overlay,
      onDismissRequested: _close,
      target: MorphTargetSpec.vessel(
        rectFor: (Size size, EdgeInsets padding) => placement.preview,
      ),
      builder: (BuildContext context, MorphFlight flight) =>
          _buildMenu(context, flight, placement),
    );
    if (!identical(flight, _flight)) {
      _flight = flight;
      _followLanding(flight, placement.held.size);
      late final StreamSubscription<MorphFlightEvent> closing;
      closing = flight.events.listen((MorphFlightEvent event) {
        if (event != MorphFlightEvent.closing) return;
        unawaited(closing.cancel());
        _menuPointer = null;
        widget.onClose?.call();
        _controller?.close();
      });
      unawaited(
        flight.closed.whenComplete(() {
          unawaited(closing.cancel());
          if (identical(_flight, flight)) {
            _placement = null;
            // The tag takes the region's id again once the session ends.
            if (mounted) setState(() {});
          }
        }),
      );
      widget.onOpen?.call(flight);
    }
    return flight;
  }

  /// Closes the open menu and sends the preview home.
  void _close() {
    final MorphMenuMotion? motion = _controller?.menuMotion;
    if (motion != null && motion.isOpen) {
      _controller!.close();
      return;
    }
    final MorphFlight? flight = _flight;
    if (flight != null && !flight.isFinished) flight.close();
  }

  void _previewTapped() {
    widget.onPreviewTap?.call();
    _close();
  }

  /// The menu rows started closing: the preview flies home with them.
  void _menuClosed() {
    _menuPointer = null;
    final MorphFlight? flight = _flight;
    if (flight == null || flight.isFinished) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!flight.isFinished) flight.close();
      });
    } else {
      flight.close();
    }
  }

  /// Plays the close spring's undershoot past the latch on the held view:
  /// the lifted size is a linear function of the flight value, so below
  /// zero the view shrinks under its natural size by the same law.
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

  Widget _buildMenu(
    BuildContext context,
    MorphFlight flight,
    _Placement placement,
  ) {
    final MorphMenuController? controller = _controller;
    final MorphSatellite? accessory = widget.accessory;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (controller != null && widget.menu.isNotEmpty)
          _RegionScope(
            state: this,
            child: MorphMenuLayer(host: controller, flight: flight),
          ),
        // A frame of the flight repaints the preview's transform alone.
        RepaintBoundary(
          child: _PreviewLayer(
            flight: flight,
            placement: placement,
            onTap: widget.onPreviewTap == null ? null : _previewTapped,
            preview: widget.preview == null
                ? null
                : _RegionScope(
                    state: this,
                    child: Builder(builder: widget.preview!),
                  ),
            child: _RegionScope(
              state: this,
              child: flight.sourceThemes.wrapText(
                widget.replica ?? widget.child,
              ),
            ),
          ),
        ),
        if (accessory != null)
          _AccessoryLayer(
            flight: flight,
            placement: placement,
            onHeight: (double height) => _accessoryHeight = height,
            child: _RegionScope(
              state: this,
              child: MorphChromeBackdrop(
                child: Builder(builder: accessory.builder),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget tagged = MorphTag(
      id: _tagId,
      child: _RegionScope(state: this, child: widget.child),
    );
    // The press transform sits ABOVE the tag: the tag's live rect is the
    // lifted one, so the flight takes off from exactly the pixels under
    // the finger, and the wrapper chain is identical at rest - no remount
    // across the press.
    final Widget lifted = MorphLiveApart(
      // Apart while it grows or lands, so those frames repaint the
      // source, not the page around it.
      live: _heroScale,
      apartOf: () => _press.value != 0 || _landing.value != 0,
      child: MorphLiveTransform(
        live: _heroScale,
        writeInto: (Matrix4 into) {
          final double scale =
              (_size.isEmpty ? 1 : 1 + _press.value / _size.longestSide) +
              _landing.value;
          into.scaleByDouble(scale, scale, 1, 1);
        },
        child: tagged,
      ),
    );
    final region = Semantics(
      onLongPress: widget.enabled ? _open : null,
      child: _MenuDriver(
        key: _driver,
        region: this,
        child: Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: lifted,
        ),
      ),
    );
    if (MorphScope.maybeOf(context) != null) return region;
    return MorphScope(child: region);
  }
}

/// Where an open context menu's parts stand, in the overlay's
/// coordinates: the held view at rest and its lifted preview, moved with
/// the menu when the menu fits on neither side of it.
class _Placement {
  const _Placement({required this.held, required this.preview});

  final Rect held;
  final Rect preview;
}

/// The rect the flight carries the preview on at its current value: from
/// the grown held view to the lifted preview on the open, home on the
/// close, a straight line on the value (overshoot included), as UIKit
/// resizes its preview about the held view's center.
Rect _previewNow(MorphFlight flight, _Placement placement) =>
    Rect.lerp(flight.sourceRect, placement.preview, flight.controller.value) ??
    placement.preview;

/// The preview in the open menu: a copy of the held view, laid out once at
/// its natural size and painted on the rect the flight carries it on by a
/// transform alone. A frame of the flight lays nothing out and paints only
/// the transform: the copy is a repaint boundary whose layer is moved and
/// scaled, as UIKit scales its preview's bitmaps. A custom [preview],
/// laid out once at the open preview's size, rides the same rect and
/// crossfades with the copy over the first half of the flight.
///
/// Fidelity: identical geometry to the copy laid out at the flight's rect
/// and scaled from its top left; text is resampled from one raster instead
/// of being painted again each frame (NEAR).
class _PreviewLayer extends StatelessWidget {
  const _PreviewLayer({
    required this.flight,
    required this.placement,
    required this.child,
    this.preview,
    this.onTap,
  });

  final MorphFlight flight;
  final _Placement placement;
  final Widget child;
  final Widget? preview;
  final VoidCallback? onTap;

  /// How far the custom preview has faded in over the held view's copy.
  double get _shown => (flight.controller.value * 2).clamp(0.0, 1.0);

  Widget _carried(Size natural, Widget child) => Positioned(
    left: 0,
    top: 0,
    width: natural.width,
    height: natural.height,
    child: MorphLiveTransform.matrix(
      live: flight.frameTicks,
      alignment: null,
      matrixOf: () {
        final Rect rect = _previewNow(flight, placement);
        final Matrix4 matrix = Matrix4.translationValues(
          rect.left,
          rect.top,
          0,
        );
        matrix.scaleByDouble(
          natural.width <= 0 ? 1 : rect.width / natural.width,
          natural.height <= 0 ? 1 : rect.height / natural.height,
          1,
          1,
        );
        return matrix;
      },
      child: RepaintBoundary(child: MorphChromeBackdrop(child: child)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Widget? preview = this.preview;
    final VoidCallback? onTap = this.onTap;
    final Widget copy = _carried(
      placement.held.size,
      preview == null
          ? child
          : MorphLiveTemplate(
              live: flight.frameTicks,
              template: () => Opacity(opacity: 1 - _shown),
              child: child,
            ),
    );
    final Widget? custom = preview == null
        ? null
        : _carried(
            placement.preview.size,
            MorphLiveTemplate(
              live: flight.frameTicks,
              template: () => Opacity(opacity: _shown),
              child: preview,
            ),
          );
    final Widget layer = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[copy, ?custom],
    );
    if (onTap == null) return IgnorePointer(child: layer);
    // Only the preview takes the tap; everywhere else the touch goes on to
    // the menu under it.
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        IgnorePointer(child: layer),
        Positioned.fromRect(
          rect: placement.preview,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

/// The accessory above the preview: laid out once, centered on the open
/// preview inside the overlay's margins with its bottom
/// [MorphContextMenuRegion.measuredMenuGap] above the preview's top, and
/// carried with the preview by a transform while it unfolds out of that
/// edge on the flight's value (opacity and scale about its bottom center).
///
/// Fidelity: approximation - UIKit's accessory views are not measured;
/// they ride the preview and fade with it.
class _AccessoryLayer extends StatelessWidget {
  const _AccessoryLayer({
    required this.flight,
    required this.placement,
    required this.onHeight,
    required this.child,
  });

  final MorphFlight flight;
  final _Placement placement;
  final ValueChanged<double> onHeight;
  final Widget child;

  double get _unfold => flight.controller.value.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _AccessoryLayout(
        preview: placement.preview,
        onHeight: onHeight,
      ),
      child: MorphLiveTemplate(
        live: flight.frameTicks,
        template: () => Opacity(opacity: _unfold),
        child: MorphLiveTransform.sized(
          live: flight.frameTicks,
          writeSizedInto: (Matrix4 into, Size size) {
            final Rect now = _previewNow(flight, placement);
            final Rect open = placement.preview;
            final double scale =
                MorphMenuAttachment.measuredBlobScale +
                (1 - MorphMenuAttachment.measuredBlobScale) * _unfold;
            // About the child's center (the transform's alignment): the
            // bottom center rides the preview's top edge, the box scales
            // about it.
            into.translateByDouble(
              now.center.dx - open.center.dx,
              now.top - open.top + size.height / 2 * (1 - scale),
              0,
              1,
            );
            into.scaleByDouble(scale, scale, 1, 1);
          },
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

class _AccessoryLayout extends SingleChildLayoutDelegate {
  _AccessoryLayout({required this.preview, required this.onHeight});

  final Rect preview;
  final ValueChanged<double> onHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
          0,
          constraints.maxWidth - 2 * MorphMenuTuning.contextMargin,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    onHeight(childSize.height);
    final double left = (preview.center.dx - childSize.width / 2).clamp(
      MorphMenuTuning.contextMargin,
      math.max(
        MorphMenuTuning.contextMargin,
        size.width - MorphMenuTuning.contextMargin - childSize.width,
      ),
    );
    return Offset(
      left,
      preview.top - MorphContextMenuRegion.measuredMenuGap - childSize.height,
    );
  }

  @override
  bool shouldRelayout(_AccessoryLayout oldDelegate) =>
      oldDelegate.preview != preview;
}

/// The identity transport behind [MorphContextMenuRegion.open] and
/// [MorphContextMenuRegion.close]. Lives INSIDE the tag's child and the
/// overlay copies too: a "more" glyph in the open preview retargets the
/// live flight instead of asserting.
class _RegionScope extends InheritedWidget {
  const _RegionScope({required this.state, required super.child});

  final _MorphContextMenuRegionState state;

  @override
  bool updateShouldNotify(_RegionScope oldWidget) => state != oldWidget.state;
}

/// The clock and the controller of a region's menu rows.
class _MenuDriver extends StatefulWidget {
  const _MenuDriver({super.key, required this.region, required this.child});

  final _MorphContextMenuRegionState region;
  final Widget child;

  @override
  State<_MenuDriver> createState() => _MenuDriverState();
}

class _MenuDriverState extends State<_MenuDriver>
    with SingleTickerProviderStateMixin<_MenuDriver>, MorphClock<_MenuDriver> {
  MorphMenuAppearance _style = MorphMenuAppearance.light;

  late final MorphMenuController controller = MorphMenuController(
    tagId: Object(),
    scopeContext: () => context,
    clock: () => clock,
    stamp: stamp,
    wake: wake,
    style: () => _style,
    glyph: () => const SizedBox.shrink(),
    semanticLabel: () => _region.semanticLabel,
    launch: () => widget.region._launch(),
    onClose: () => widget.region._menuClosed(),
  );

  MorphContextMenuRegion get _region => widget.region.widget;
  MorphMenuContent get _content => controller.menuContent;

  @override
  void initState() {
    super.initState();
    _content.entries = _region.menu;
    _content.order = _region.order;
  }

  @override
  void didUpdateWidget(_MenuDriver oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.updateEntries(
      _region.menu,
      order: _region.order,
      dismissOnSelect: _region.dismissOnSelect,
    );
  }

  @override
  void deactivate() {
    controller.sourceActive = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    controller.sourceActive = true;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Lays the menu out for the view [held] at rest, attached to its
  /// lifted preview, in [overlay]'s coordinates; an open menu stays as it
  /// is.
  MorphMenuMotion prepare({
    required Rect held,
    required MorphMenuAttachment attachment,
    required OverlayState overlay,
    required Size bounds,
    required EdgeInsets padding,
  }) {
    final MorphMenuMotion? current = controller.menuMotion;
    if (current != null && current.isPresented) {
      if (current.isClosing) controller.beginReopenSession();
      return current;
    }
    _content.rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _content.titleStyle = MorphTypography.resolve(_style.textStyle);
    _content.textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    _content.beginSession();
    return controller.prepare(
      button: held,
      bounds: bounds,
      padding: padding,
      tuning: MorphMenuTuning.context,
      overlay: overlay,
      dismissOnSelect: _region.dismissOnSelect,
      attachment: attachment,
    );
  }

  @override
  void advanceMotion(double t) =>
      controller.advance(t, framePeriod: framePeriod);

  @override
  bool get motionSettled => controller.menuMotion?.isSettled ?? true;

  @override
  double? get motionWakeTime => controller.wakeTime;

  @override
  Widget build(BuildContext context) {
    _style = MorphMenuAppearance.resolve(context, _region.appearance);
    return widget.child;
  }
}

/// A long press whose arena deadline is advanced by the hold ticker.
class _MotionHoldRecognizer extends LongPressGestureRecognizer {
  _MotionHoldRecognizer({super.debugOwner});

  @override
  Duration? get deadline => null;

  void commit() {
    if (state == GestureRecognizerState.possible && primaryPointer != null) {
      didExceedDeadline();
    }
  }
}
