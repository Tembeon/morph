import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/show.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/widgets/activity_indicator.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_content.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/menu_layout.dart';
import 'package:morph/src/widgets/menu_motion.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// The look of a [MorphMenuButton] and its menu.
class MorphMenuStyle {
  /// Creates a style; the defaults are the iOS 27 light appearance.
  const MorphMenuStyle({
    this.buttonSize = 48,
    this.glassColor = const Color(0xF2F9F9FF),
    this.shadowColor = const Color(0x33000000),
    this.shadowElevation = 12,
    this.textStyle = const TextStyle(fontSize: 17, color: Color(0xF5000000)),
    this.iconColor = const Color(0xF5000000),
    this.disabledIconColor = const Color(0x4C3C3C43),
    this.iconSize = 20,
    this.destructiveColor = const Color(0xFFFF383C),
    this.highlightColor = const Color(0x1F000000),
    this.glowColor = const Color(0xFFFFFFFF),
    this.secondaryColor = const Color(0x993C3C43),
    this.disabledColor = const Color(0x4C3C3C43),
    this.separatorColor = const Color(0x14000000),
    this.submenuColor = const Color(0x66FFFFFF),
    this.submenuRimColor = const Color(0xFFFFFFFF),
    this.submenuShadowColor = const Color(0x14000000),
    this.paletteSelectionColor = const Color(0x10000000),
  });

  /// The diameter of the button.
  final double buttonSize;

  /// The fill of the button and of the menu.
  final Color glassColor;

  /// The color of the shadow under the button and the menu.
  final Color shadowColor;

  /// The elevation of the shadow under the button and the menu.
  final double shadowElevation;

  /// The style of row titles.
  ///
  /// The menu shows in an overlay, outside the text style of the screen
  /// the button sits on, so this is the whole style of its titles: it
  /// replaces the overlay's ambient text style instead of merging into it.
  final TextStyle textStyle;

  /// The color of the button's default glyph and of row glyphs.
  final Color iconColor;

  /// The color of a disabled button's glyph: tertiaryLabel. UIKit leaves
  /// the glass of a disabled menu button untouched (iPhone 16 Pro, iOS
  /// 27.0.1, light and dark).
  final Color disabledIconColor;

  /// The size of row glyphs.
  final double iconSize;

  /// The color of destructive rows.
  final Color destructiveColor;

  /// The fill of the pill under the highlighted row.
  final Color highlightColor;

  /// The color of the glow under a finger on the menu.
  final Color glowColor;

  /// The color of subtitles and section headers: secondaryLabel.
  final Color secondaryColor;

  /// The color of disabled rows and of the loading row: tertiaryLabel.
  final Color disabledColor;

  /// The color of the hairline between groups of rows (rendered 229 on
  /// the 249 light platter, 50 on the 32 dark one).
  final Color separatorColor;

  /// The tint a submenu card lays over the list under it.
  ///
  /// A card is a translucent platter that blurs what lies under it by
  /// [MorphMenuTuning.cardBlur]: where it covers the list it opened from
  /// it reads 252 on the 249 light menu and 57 on the 32 dark one; past
  /// that list's edge only the blur shows (device screenshots, iPhone 16
  /// Pro). Each further card under it adds half as much.
  final Color submenuColor;

  /// The highlight along the top edge of a submenu card, fading out over
  /// its first points (device: a one-pixel line at 251 - 255 over the 248
  /// light card, 65 - 83 over the 57 dark one).
  final Color submenuRimColor;

  /// The shadow a submenu card casts around itself (device: the light
  /// list darkens by 5 levels 4 points above a card's top).
  final Color submenuShadowColor;

  /// The platter under the selected palette cell (sampled: 233 on 249
  /// light, 53 on 32 dark).
  final Color paletteSelectionColor;

  /// The light appearance.
  static const light = MorphMenuStyle();

  /// The dark appearance, sampled from the iOS 27 dark menu.
  static const dark = MorphMenuStyle(
    glassColor: Color(0xF2222222),
    shadowColor: Color(0x66000000),
    textStyle: TextStyle(fontSize: 17, color: Color(0xF5FFFFFF)),
    iconColor: Color(0xF5FFFFFF),
    disabledIconColor: Color(0x4CEBEBF5),
    destructiveColor: Color(0xFFFF4245),
    highlightColor: Color(0x29FFFFFF),
    glowColor: Color(0xFFFFFFFF),
    secondaryColor: Color(0x99EBEBF5),
    disabledColor: Color(0x4CEBEBF5),
    separatorColor: Color(0x14FFFFFF),
    submenuColor: Color(0x1DFFFFFF),
    submenuRimColor: Color(0x33FFFFFF),
    submenuShadowColor: Color(0x33000000),
    paletteSelectionColor: Color(0x18FFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphMenuStyle resolve(
    BuildContext context,
    MorphMenuStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.menu ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };

  /// A copy of this style with the given fields replaced.
  MorphMenuStyle copyWith({
    double? buttonSize,
    Color? glassColor,
    Color? shadowColor,
    double? shadowElevation,
    TextStyle? textStyle,
    Color? iconColor,
    Color? disabledIconColor,
    double? iconSize,
    Color? destructiveColor,
    Color? highlightColor,
    Color? glowColor,
    Color? secondaryColor,
    Color? disabledColor,
    Color? separatorColor,
    Color? submenuColor,
    Color? submenuRimColor,
    Color? submenuShadowColor,
    Color? paletteSelectionColor,
  }) => MorphMenuStyle(
    buttonSize: buttonSize ?? this.buttonSize,
    glassColor: glassColor ?? this.glassColor,
    shadowColor: shadowColor ?? this.shadowColor,
    shadowElevation: shadowElevation ?? this.shadowElevation,
    textStyle: textStyle ?? this.textStyle,
    iconColor: iconColor ?? this.iconColor,
    disabledIconColor: disabledIconColor ?? this.disabledIconColor,
    iconSize: iconSize ?? this.iconSize,
    destructiveColor: destructiveColor ?? this.destructiveColor,
    highlightColor: highlightColor ?? this.highlightColor,
    glowColor: glowColor ?? this.glowColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    disabledColor: disabledColor ?? this.disabledColor,
    separatorColor: separatorColor ?? this.separatorColor,
    submenuColor: submenuColor ?? this.submenuColor,
    submenuRimColor: submenuRimColor ?? this.submenuRimColor,
    submenuShadowColor: submenuShadowColor ?? this.submenuShadowColor,
    paletteSelectionColor: paletteSelectionColor ?? this.paletteSelectionColor,
  );
}

/// A round glass button that turns into its menu exactly like an iOS 27
/// `UIButton` whose menu is its primary action.
///
/// A tap opens the menu on release; holding opens it after
/// [MorphMenuTuning.holdDuration] and lets the finger slide onto a
/// row and select it on release. A release outside the menu, Esc or the
/// system back gesture closes it. The menu shows in the nearest [Overlay]
/// unless [overlay] names another one, below the button when the button
/// sits in the upper half of the safe area and above it, with its entries
/// reversed (unless [order] is [MorphMenuOrder.fixed]), otherwise; the
/// keyboard counts as an obstructed edge.
///
/// The [items] are [MorphMenuEntry] values: rows, sections (with headers,
/// single selection, palettes and small or medium cells), submenus that
/// open as cards stacked over the menu, dividers, deferred groups and
/// free-form [MorphMenuWidget] rows. The open menu follows the widget: a
/// rebuild with other entries updates it in place and resizes it on the
/// measured springs, as a SwiftUI menu follows its state. Arrow keys move
/// the highlight, Enter or Space choose, Esc goes back out of a submenu
/// and then closes the menu.
///
/// The menu is a morph flight: the button is its source and the flight
/// runs UIKit's measured progress spring. The menu evaluates the same
/// spring on the clock its kicks run on and draws both shapes of
/// [MorphMenuMotion] inside a vessel target ([MorphTargetSpec.vessel]);
/// once the closing flight hands the source back, the button draws the
/// rest of the close itself until the kicks have rung out, as UIKit
/// keeps its morph on screen until then. The flight
/// provides the overlay, the pop layering, the modal barrier (without
/// dimming), the focus trap and [MorphFlight.events]. A [MorphScope]
/// above the button is used when there is one; otherwise the button
/// brings its own, and a button removed while its menu is up takes the
/// menu with it at once - put a [MorphScope] above it for the menu to
/// dissolve instead.
class MorphMenuButton extends StatefulWidget {
  /// Creates a menu button.
  const MorphMenuButton({
    required this.items,
    this.child,
    this.style,
    this.tuning = MorphMenuTuning.standard,
    this.overlay,
    this.semanticLabel = 'More',
    this.onOpen,
    this.enabled = true,
    this.order = MorphMenuOrder.automatic,
    this.dismissOnSelect,
    super.key,
  });

  /// Whether the button opens its menu.
  ///
  /// A disabled menu button keeps its glass and draws its glyph in
  /// [MorphMenuStyle.disabledIconColor], as UIKit's does; it ignores
  /// touches, and an open menu closes when the button turns disabled.
  final bool enabled;

  /// The entries of the menu, top to bottom when it opens downward.
  final List<MorphMenuEntry> items;

  /// The button's glyph; an ellipsis when null.
  final Widget? child;

  /// The look of the button and the menu; null resolves it through
  /// [MorphMenuStyle.resolve].
  final MorphMenuStyle? style;

  /// The measured motion.
  final MorphMenuTuning tuning;

  /// The overlay the menu shows in, or null for the nearest one.
  ///
  /// It must be an ancestor of this button.
  final OverlayState? overlay;

  /// The accessibility label of the button.
  final String semanticLabel;

  /// Called with the flight of the menu each time a new one launches;
  /// its [MorphFlight.events] are the seam for haptics.
  final ValueChanged<MorphFlight>? onOpen;

  /// The order of the entries relative to the button.
  final MorphMenuOrder order;

  /// Whether choosing a row closes the menu: null leaves it to each
  /// row's [MorphMenuItem.keepsMenuOpen], true closes after every row,
  /// false keeps the menu open after every row (SwiftUI's
  /// `menuActionDismissBehavior`).
  final bool? dismissOnSelect;

  @override
  State<MorphMenuButton> createState() => _MorphMenuButtonState();
}

/// The progress of a menu that flies on the engine: the measured spring
/// in motion time, the clock the kicks run on, with the flight that
/// carries the menu sent the same way through [onOpen] and [onClose].
@internal
class MorphMenuFlightProgress extends MorphMenuProgress {
  /// Creates the progress of [tuning]'s spring.
  MorphMenuFlightProgress(
    MorphMenuTuning tuning, {
    required this.onOpen,
    required this.onClose,
  }) : _spring = MorphMenuProgress.spring(tuning);

  /// Called when the menu opens: launches or retargets its flight.
  final VoidCallback onOpen;

  /// Called when the menu closes: closes its flight.
  final VoidCallback onClose;

  final MorphMenuProgress _spring;

  @override
  double valueAt(double t) => _spring.valueAt(t);

  @override
  bool isAtRestAt(double t) => _spring.isAtRestAt(t);

  @override
  void open(double t) {
    _spring.open(t);
    onOpen();
  }

  @override
  void close(double t) {
    _spring.close(t);
    onClose();
  }
}

/// Wires [content] into [motion]: its layouts, its actions and its
/// highlight callbacks.
@internal
void morphConnectMenu(
  MorphMenuMotion motion,
  MorphMenuContent content, {
  bool? dismissOnSelect,
}) {
  motion.submenuLayout = content.submenu;
  motion.onActivate = content.activate;
  motion.onHighlight = content.highlight;
  motion.dismissOnSelect = dismissOnSelect;
}

/// Checks that [overlay] is an ancestor of [context], which every
/// coordinate of a menu is measured against.
@internal
void morphCheckOverlayAncestor(BuildContext context, OverlayState overlay) {
  final overlayElement = overlay.context;
  var found = false;
  context.visitAncestorElements((Element element) {
    if (identical(element, overlayElement)) {
      found = true;
      return false;
    }
    return true;
  });
  if (!found) {
    throw FlutterError.fromParts([
      ErrorSummary('The overlay of a menu is not an ancestor of its button.'),
      ErrorDescription(
        'The menu measures its button in the coordinates of the overlay it '
        'shows in, which needs the overlay above the button.',
      ),
    ]);
  }
}

/// What [MorphMenuLayer] draws a menu from: the motion, the content and
/// the look of the source, and where the touches on the open menu go.
@internal
abstract interface class MorphMenuHost {
  /// The look of the menu.
  MorphMenuStyle get menuStyle;

  /// The look of the source, shown inside the shrinking source shape.
  Widget get menuGlyph;

  /// The content of the menu.
  MorphMenuContent get menuContent;

  /// Notifies when the motion has advanced.
  Listenable get menuRepaint;

  /// The motion, or null before the menu first opens.
  MorphMenuMotion? get menuMotion;

  /// The time of the motion's clock.
  double get menuClock;

  /// Wakes the motion's clock after a change made through [menuMotion].
  void menuWake();

  /// A finger touched the open menu.
  void menuPointerDown(PointerDownEvent event);

  /// A finger on the menu moved.
  void menuPointerMove(PointerMoveEvent event);

  /// A finger on the menu lifted.
  void menuPointerUp(PointerUpEvent event);

  /// A touch on the menu was cancelled.
  void menuPointerCancel(PointerCancelEvent event);
}

class _MorphMenuButtonState extends State<MorphMenuButton>
    with
        SingleTickerProviderStateMixin<MorphMenuButton>,
        MorphClock<MorphMenuButton>
    implements MorphMenuHost {
  @override
  void initState() {
    super.initState();
    _content = MorphMenuContent(onChanged: _contentChanged);
    _content.entries = widget.items;
    _content.order = widget.order;
  }

  @override
  void didUpdateWidget(MorphMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _content.entries = widget.items;
    _content.order = widget.order;
    final motion = _motion;
    if (motion == null) return;
    motion.dismissOnSelect = widget.dismissOnSelect;
    if (oldWidget.enabled && !widget.enabled) {
      if (motion.isOpen || motion.isOpenPending) {
        motion.close(clock);
        wake();
        return;
      }
    }
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.order != widget.order) {
      if (motion.isPresented) {
        motion.updateLayout(clock);
        wake();
      } else {
        motion.updateLayout(clock, animate: false);
      }
    }
  }

  void _contentChanged({required bool animate}) {
    final motion = _motion;
    if (_disposed || motion == null) return;
    motion.updateLayout(clock, animate: animate && motion.isPresented);
    wake();
  }

  late final MorphMenuContent _content;

  @override
  MorphMenuStyle get menuStyle => _style;

  @override
  Widget get menuGlyph => widget.child ?? _Ellipsis(color: _style.iconColor);

  @override
  MorphMenuContent get menuContent => _content;

  @override
  Listenable get menuRepaint => _repaint;

  @override
  MorphMenuMotion? get menuMotion => _motion;

  @override
  double get menuClock => clock;

  @override
  void menuWake() => wake();

  @override
  void menuPointerDown(PointerDownEvent event) => _menuDown(event);

  @override
  void menuPointerMove(PointerMoveEvent event) => _move(event);

  @override
  void menuPointerUp(PointerUpEvent event) => _up(event);

  @override
  void menuPointerCancel(PointerCancelEvent event) => _cancel(event);

  final Object _tagId = Object();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  MorphMenuMotion? _motion;
  MorphFlight? _flight;
  BuildContext? _scopeContext;
  OverlayState? _overlay;
  int? _pointer;
  int? _early;
  bool _routing = false;
  bool _disposed = false;
  bool _repaintDisposed = false;
  MorphMenuStyle _style = MorphMenuStyle.light;

  @override
  void dispose() {
    _disposed = true;
    _content.dispose();
    _unroute();
    final flight = _flight;
    if (flight == null || flight.isFinished) {
      _disposeRepaint();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        flight.close();
      });
    }
    super.dispose();
  }

  void _disposeRepaint() {
    if (_repaintDisposed) return;
    _repaintDisposed = true;
    _repaint.dispose();
  }

  MorphMenuMotion _prepare() {
    final current = _motion;
    if (current != null && current.isPresented) return current;
    final overlay = widget.overlay ?? Overlay.of(context);
    if (widget.overlay != null) morphCheckOverlayAncestor(context, overlay);
    _overlay = overlay;
    final box = context.findRenderObject()! as RenderBox;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final button = origin & box.size;
    final padding = morphTargetPaddingOf(
      context,
      overlayBox.size,
      overlayBox: overlayBox,
    );
    _content.rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _content.titleStyle = MorphTypography.resolve(_style.textStyle);
    _content.textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    _content.beginSession();
    if (current != null && identical(current.tuning, widget.tuning)) {
      current.relayout(
        button: button,
        bounds: overlayBox.size,
        padding: padding,
      );
      current.dismissOnSelect = widget.dismissOnSelect;
      return current;
    }
    final motion = MorphMenuMotion(
      button: button,
      layout: _content.root,
      bounds: overlayBox.size,
      padding: padding,
      tuning: widget.tuning,
      progress: MorphMenuFlightProgress(
        widget.tuning,
        onOpen: _launch,
        onClose: () {
          final flight = _flight;
          if (flight != null && !flight.isFinished) flight.close();
        },
      ),
    );
    morphConnectMenu(motion, _content, dismissOnSelect: widget.dismissOnSelect);
    motion.advance(clock);
    _motion = motion;
    return motion;
  }

  void _launch() {
    final launchContext = _scopeContext;
    if (_disposed || launchContext == null || !launchContext.mounted) {
      _motion?.close(clock);
      return;
    }
    final tuning = widget.tuning;
    final flight = showMorph(
      launchContext,
      from: _tagId,
      target: MorphTargetSpec.vessel(
        rectFor: (Size size, EdgeInsets padding) =>
            _motion?.menuRect ?? Rect.zero,
      ),
      builder: (BuildContext context, MorphFlight flight) =>
          MorphMenuLayer(host: this, flight: flight),
      motion: MorphMotion.springs(
        name: 'menu',
        open: tuning.openSpring,
        close: tuning.closeSpring,
      ),
      maxScrimOpacity: 0,
      onDismissRequested: _dismissRequested,
      semanticLabel: widget.semanticLabel,
      overlay: _overlay,
    );
    if (identical(flight, _flight)) return;
    _flight = flight;
    flight.closed.whenComplete(() {
      if (identical(_flight, flight)) _flight = null;
      if (_disposed && _flight == null) _disposeRepaint();
    });
    widget.onOpen?.call(flight);
  }

  void _dismissRequested() {
    _motion?.close(clock);
    wake();
  }

  @override
  void advanceMotion(double t) {
    final motion = _motion;
    if (motion == null) return;
    motion.advance(t);
    if (_early == null && !motion.isOpenPending) _unroute();
    _repaint.value++;
  }

  void _route() {
    if (_routing) return;
    _routing = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_earlyEvent);
  }

  void _unroute() {
    if (!_routing) return;
    _routing = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_earlyEvent);
  }

  void _earlyEvent(PointerEvent event) {
    final motion = _motion;
    if (motion == null) return;
    if (event is PointerDownEvent) {
      if (!motion.isOpenPending ||
          _pointer != null ||
          event.buttons != kPrimaryButton) {
        return;
      }
      _pointer = event.pointer;
      _early = event.pointer;
      motion.pointerDown(stamp(event), _local(event.position));
      return;
    }
    if (event.pointer != _early) return;
    if (event is PointerMoveEvent) {
      _move(event);
    } else if (event is PointerUpEvent) {
      _early = null;
      _up(event);
    } else if (event is PointerCancelEvent) {
      _early = null;
      _cancel(event);
    }
  }

  @override
  bool get motionSettled => _motion?.isSettled ?? true;

  Offset _local(Offset global) {
    final box = _overlay?.context.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  void _buttonDown(PointerDownEvent event) {
    if (!widget.enabled ||
        event.buttons != kPrimaryButton ||
        _pointer != null) {
      return;
    }
    final current = _motion;
    if (current != null && current.isOpen) return;
    final motion = _prepare();
    _pointer = event.pointer;
    motion.pointerDown(stamp(event), _local(event.position));
  }

  void _menuDown(PointerDownEvent event) {
    final motion = _motion;
    if (motion == null || _pointer != null) return;
    if (event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    motion.pointerDown(stamp(event), _local(event.position));
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _motion?.pointerMove(stamp(event), _local(event.position));
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final motion = _motion;
    if (motion == null) return;
    motion.pointerUp(stamp(event), _local(event.position));
    if (motion.isOpenPending) _route();
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _motion?.pointerCancel(stamp(event));
  }

  void _openFromSemantics() {
    final motion = _prepare();
    motion.open(clock);
    wake();
  }

  /// Whether the motion is up while no vessel shows it: after the latch
  /// the rest of the close plays on the button itself.
  bool get _landing {
    final motion = _motion;
    if (motion == null || !motion.isPresented) return false;
    final flight = _flight;
    return flight == null || !flight.isAirborne;
  }

  Widget _face(BuildContext context, MorphMenuStyle style, Widget glyph) {
    final motion = _motion;
    if (motion == null || !_landing) {
      final box = Offset.zero & Size.square(style.buttonSize);
      return _MenuShapes(
        style: style,
        glyph: glyph,
        source: RRect.fromRectAndRadius(box, Radius.circular(box.width / 2)),
        sourceRect: box,
      );
    }
    final origin = -motion.button.topLeft;
    final source = motion.buttonBlob;
    return _MenuShapes(
      style: style,
      glyph: glyph,
      menu: motion.menuBlob.rrect.shift(origin),
      source: source.rrect.shift(origin),
      sourceRect: source.rect.shift(origin),
      sourceScale: source.scale,
      outline: motion.silhouette?.shift(origin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphMenuStyle.resolve(context, widget.style);
    _style = style;
    final flight = _flight;
    if (flight != null && !flight.isFinished) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!flight.isFinished) flight.markNeedsBuild();
      });
    }
    final enabled = widget.enabled;
    final iconColor = enabled ? style.iconColor : style.disabledIconColor;
    final custom = widget.child;
    final glyph = custom == null
        ? _Ellipsis(color: iconColor)
        : enabled
        ? custom
        : IconTheme.merge(
            data: IconThemeData(color: iconColor),
            child: custom,
          );
    final open = _motion?.isOpen ?? false;
    final Widget button = Semantics(
      button: true,
      enabled: enabled,
      expanded: open,
      label: widget.semanticLabel,
      onTap: enabled ? _openFromSemantics : null,
      child: MorphTouchListener(
        enabled: enabled,
        behavior: .opaque,
        onPointerDown: _buttonDown,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: SizedBox.square(
          dimension: style.buttonSize,
          child: ListenableBuilder(
            listenable: frames,
            builder: (BuildContext context, Widget? child) => Transform.scale(
              scale: _landing ? 1 : _motion?.pressScale ?? 1,
              child: child,
            ),
            child: Builder(
              builder: (BuildContext context) {
                _scopeContext = context;
                return MorphTag(
                  id: _tagId,
                  shape: const CircleBorder(),
                  surfaceColor: style.glassColor,
                  child: ListenableBuilder(
                    listenable: frames,
                    builder: (BuildContext context, Widget? _) =>
                        _face(context, style, glyph),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    if (MorphScope.maybeOf(context) != null) return button;
    return MorphScope(child: button);
  }
}

/// Both shapes of the morph and the button's look inside the shrinking
/// one, in the coordinates of the box this is laid out in; with no [menu]
/// it is the resting button. An [outline] is the silhouette the two
/// shapes fuse into; without one they are drawn as their union.
///
/// The look fades only with a [look]: on the button (resting, or after
/// the latch, where the progress is at or under zero) it is drawn
/// without a layer, which keeps the glass of every resting button in its
/// backdrop group.
class _MenuShapes extends StatelessWidget {
  const _MenuShapes({
    required this.style,
    required this.glyph,
    required this.source,
    required this.sourceRect,
    this.menu,
    this.sourceScale = 1,
    this.lookStretch = 1,
    this.look,
    this.content,
    this.outline,
  });

  final MorphMenuStyle style;
  final Widget glyph;
  final RRect? menu;
  final RRect source;
  final Rect sourceRect;
  final double sourceScale;
  final double lookStretch;
  final ({double opacity, double blur})? look;
  final Widget? content;
  final MorphGlassOutline? outline;

  @override
  Widget build(BuildContext context) {
    final glass = MorphGlass.maybeOf(context);
    final menu = this.menu;
    final content = this.content;
    final look = this.look;
    final Widget glyph = Center(
      child: Transform.scale(
        scaleX: sourceScale * lookStretch,
        scaleY: sourceScale,
        child: this.glyph,
      ),
    );
    final Widget surfaces;
    if (glass == null) {
      surfaces = CustomPaint(
        painter: _GlassPainter(
          style: style,
          menu: menu,
          source: source,
          outline: outline,
        ),
      );
    } else {
      final brightness = morphBrightnessOf(context);
      surfaces = glass.buildLayer(context, [
        MorphGlassSurface(
          kind: MorphGlassKind.button,
          shape: source,
          color: style.glassColor,
          brightness: brightness,
        ),
        if (menu != null)
          MorphGlassSurface(
            kind: MorphGlassKind.menu,
            shape: menu,
            color: style.glassColor,
            brightness: brightness,
          ),
      ], outline: menu == null ? null : outline);
    }
    return Stack(
      clipBehavior: .none,
      children: [
        Positioned.fill(child: surfaces),
        ?content,
        Positioned.fromRect(
          rect: sourceRect,
          child: IgnorePointer(
            child: look == null
                ? glyph
                : _Faded(opacity: look.opacity, blur: look.blur, child: glyph),
          ),
        ),
      ],
    );
  }
}

/// [child] at [opacity] and blurred by [blur], drawn through one layer.
class _Faded extends StatelessWidget {
  const _Faded({
    required this.opacity,
    required this.blur,
    required this.child,
  });

  final double opacity;
  final double blur;
  final Widget child;

  static final ui.ImageFilter _none = ui.ImageFilter.blur(
    tileMode: TileMode.decal,
  );

  @override
  Widget build(BuildContext context) {
    final blurred = blur > 0.05 && opacity > 0;
    return Opacity(
      opacity: blurred ? 1 : opacity,
      child: ImageFiltered(
        enabled: blurred,
        imageFilter: blurred
            ? ui.ImageFilter.compose(
                outer: ui.ColorFilter.matrix(<double>[
                  1, 0, 0, 0, 0, //
                  0, 1, 0, 0, 0, //
                  0, 0, 1, 0, 0, //
                  0, 0, 0, opacity, 0,
                ]),
                inner: ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.decal,
                ),
              )
            : _none,
        child: child,
      ),
    );
  }
}

/// The menu inside the vessel: both shapes, the content and the button's
/// look, laid out over the whole overlay and drawn from the motion. The
/// rows of each card are built once per layout of that card; every frame
/// moves only the wrappers around them.
@internal
class MorphMenuLayer extends StatefulWidget {
  /// Creates the layer of [host]'s menu carried by [flight].
  const MorphMenuLayer({required this.host, required this.flight, super.key});

  /// The menu drawn.
  final MorphMenuHost host;

  /// The flight that carries the menu.
  final MorphFlight flight;

  @override
  State<MorphMenuLayer> createState() => _MorphMenuLayerState();
}

class _MorphMenuLayerState extends State<MorphMenuLayer> {
  final ScrollController _scroll = ScrollController();
  Expando<Widget> _rows = Expando<Widget>();
  final Expando<ValueNotifier<int?>> _hidden = Expando<ValueNotifier<int?>>();
  MorphMenuStyle? _rowsStyle;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrolled() {
    final motion = widget.host.menuMotion;
    if (motion == null || !_scroll.hasClients) return;
    motion.scrollOffset = _scroll.offset;
  }

  bool _scrollStarted(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        (notification.scrollDelta ?? 0) != 0) {
      final host = widget.host;
      host.menuMotion?.pointerScrolled(host.menuClock);
      host.menuWake();
    }
    return false;
  }

  Widget _rowsOf(MorphMenuLayout layout, MorphMenuStyle style) {
    if (!identical(style, _rowsStyle)) {
      _rows = Expando<Widget>();
      _rowsStyle = style;
    }
    return _rows[layout] ??= RepaintBoundary(
      child: DefaultTextStyle(
        style: MorphTypography.resolve(style.textStyle),
        child: _MenuRows(
          layout: layout,
          style: style,
          hidden: _hiddenOf(layout),
          content: widget.host.menuContent,
          onSelect: (int target) => _select(layout, target),
        ),
      ),
    );
  }

  ValueNotifier<int?> _hiddenOf(MorphMenuLayout layout) =>
      _hidden[layout] ??= ValueNotifier<int?>(null);

  void _select(MorphMenuLayout layout, int target) {
    final host = widget.host;
    final motion = host.menuMotion;
    if (motion == null || !motion.isOpen) return;
    final cards = motion.cards;
    var top = cards.length - 1;
    while (top > 0 && cards[top].progress < 0.5) {
      top--;
    }
    if (!identical(cards[top].layout, layout)) return;
    motion.select(host.menuClock, target);
    host.menuWake();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final host = widget.host;
    final motion = host.menuMotion;
    if (motion == null || !motion.isOpen) return KeyEventResult.ignored;
    final t = host.menuClock;
    final cards = motion.cards;
    final layout = cards[motion.hasSubmenu ? cards.length - 1 : 0].layout;
    final order = [for (var i = 0; i < layout.targets.length; i++) i];
    order.sort((int a, int b) {
      final ra = layout.targets[a].rect;
      final rb = layout.targets[b].rect;
      final dy = ra.top.compareTo(rb.top);
      return dy != 0 ? dy : ra.left.compareTo(rb.left);
    });
    final current = motion.highlightedCard == cards.length - 1
        ? motion.highlighted
        : null;
    final rtl = host.menuContent.rtl;
    final key = event.logicalKey;
    void move(int step) {
      if (order.isEmpty) return;
      final at = current == null ? -1 : order.indexOf(current);
      final next = at < 0
          ? (step > 0 ? 0 : order.length - 1)
          : (at + step).clamp(0, order.length - 1);
      motion.highlight(t, order[next]);
    }

    final KeyEventResult result;
    if (key == LogicalKeyboardKey.arrowDown) {
      move(1);
      result = KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      move(-1);
      result = KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (current == null) return KeyEventResult.ignored;
      motion.select(t, current);
      result = KeyEventResult.handled;
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      if (current == null ||
          layout.targets[current].kind != MorphMenuTargetKind.submenu) {
        return KeyEventResult.ignored;
      }
      motion.select(t, current);
      result = KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape ||
        key ==
            (rtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft)) {
      if (!motion.back(t)) return KeyEventResult.ignored;
      result = KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    host.menuWake();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final style = host.menuStyle;
    final glyph = host.menuGlyph;
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          host.menuRepaint,
          widget.flight.frameTicks,
        ]),
        builder: (BuildContext context, Widget? _) {
          final motion = host.menuMotion;
          if (motion == null) return const SizedBox.shrink();
          final menu = motion.menuBlob;
          final source = motion.buttonBlob;
          final size = motion.menuRect.size;
          final scale = motion.contentScale;
          final at = motion.contentRect.topLeft - menu.rect.topLeft;
          return IgnorePointer(
            ignoring: !motion.isOpen,
            child: Listener(
              behavior: .opaque,
              onPointerDown: host.menuPointerDown,
              onPointerMove: host.menuPointerMove,
              onPointerUp: host.menuPointerUp,
              onPointerCancel: host.menuPointerCancel,
              child: _MenuShapes(
                style: style,
                glyph: glyph,
                menu: menu.rrect,
                source: source.rrect,
                sourceRect: source.rect,
                sourceScale: source.scale,
                outline: motion.silhouette,
                lookStretch: motion.buttonLookStretch,
                look: (
                  opacity: motion.buttonLookOpacity,
                  blur: motion.buttonLookBlur,
                ),
                content: Positioned.fromRect(
                  rect: menu.rect,
                  child: ClipRRect(
                    borderRadius: .circular(menu.radius),
                    child: Stack(
                      clipBehavior: .none,
                      children: [
                        Positioned(
                          left: at.dx,
                          top: at.dy,
                          width: size.width,
                          height: size.height,
                          child: Transform.scale(
                            scale: scale,
                            alignment: .topLeft,
                            child: Stack(
                              clipBehavior: .none,
                              children: [
                                _Faded(
                                  opacity: motion.contentOpacity,
                                  blur: motion.contentBlur / scale,
                                  child: Stack(
                                    clipBehavior: .none,
                                    children: [
                                      ..._glow(motion, style),
                                      ..._cards(motion, style, top: false),
                                    ],
                                  ),
                                ),
                                ..._cards(motion, style, top: true),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _cards(
    MorphMenuMotion motion,
    MorphMenuStyle style, {
    required bool top,
  }) {
    final cards = motion.cards;
    final width = motion.tuning.menuWidth;
    final radius = motion.tuning.cornerRadius;
    if (top) {
      if (cards.length < 2) return const [];
      final last = cards.length - 1;
      return [_card(motion, style, cards, last, width, radius)];
    }
    final count = cards.length < 2 ? cards.length : cards.length - 1;
    return [
      for (var i = 0; i < count; i++)
        _card(motion, style, cards, i, width, radius),
    ];
  }

  /// The frame card [index] shows at in the content, scale included.
  static Rect _shown(
    MorphMenuMotion motion,
    List<MorphMenuCard> cards,
    int index,
    double width,
  ) {
    final card = cards[index];
    final s = card.scale;
    final rect = index == 0
        ? Rect.fromLTWH(0, 0, width, motion.visibleRootHeight)
        : card.rect;
    return Rect.fromLTWH(
      width / 2 + (rect.left - width / 2) * s,
      rect.top * s,
      rect.width * s,
      rect.height * s,
    );
  }

  static Rect _local(Rect rect, Offset origin, double k) => Rect.fromLTWH(
    (rect.left - origin.dx) * k,
    (rect.top - origin.dy) * k,
    rect.width * k,
    rect.height * k,
  );

  Widget _card(
    MorphMenuMotion motion,
    MorphMenuStyle style,
    List<MorphMenuCard> cards,
    int index,
    double width,
    double radius,
  ) {
    final card = cards[index];
    final s = card.scale;
    final layout = card.layout;
    _hiddenOf(layout).value = index + 1 < cards.length
        ? cards[index + 1].source
        : null;
    if (index == 0) {
      final content = SizedBox(
        width: width,
        height: layout.height,
        child: Stack(
          clipBehavior: .none,
          children: [
            ?_highlight(motion, style, layout, index),
            _rowsOf(layout, style),
          ],
        ),
      );
      final visible = motion.visibleRootHeight;
      final scrolls = layout.height > visible + 0.5;
      final Widget body = scrolls
          ? NotificationListener<ScrollNotification>(
              onNotification: _scrollStarted,
              child: RawScrollbar(
                controller: _scroll,
                thumbColor: style.secondaryColor,
                thickness: 3,
                radius: const Radius.circular(1.5),
                mainAxisMargin: radius / 2,
                crossAxisMargin: 4,
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [SliverToBoxAdapter(child: content)],
                ),
              ),
            )
          : OverflowBox(
              alignment: .topLeft,
              minHeight: layout.height,
              maxHeight: layout.height,
              child: content,
            );
      return Positioned(
        key: const ValueKey<int>(0),
        left: width / 2 * (1 - s),
        top: 0,
        width: width,
        height: visible,
        child: Transform.scale(
          scale: s,
          alignment: .topLeft,
          child: Opacity(
            opacity: card.rowOpacity,
            child: ClipRect(child: body),
          ),
        ),
      );
    }
    final rect = card.rect;
    final shown = _shown(motion, cards, index, width);
    final k = s == 0 ? 1.0 : 1 / s;
    final under = <RRect>[
      for (var j = index - 1; j >= 0; j--)
        RRect.fromRectAndRadius(
          _local(_shown(motion, cards, j, width), shown.topLeft, k),
          Radius.circular(radius * cards[j].scale * k),
        ),
    ];
    final cardRadius = math.min(radius, rect.height / 2);
    final alpha = card.closeOpacity;
    final platter = card.platterOpacity * alpha;
    final rowsAlpha = card.rowOpacity * alpha;
    MorphMenuPlaced? header;
    for (final element in layout.elements) {
      if (element.kind == MorphMenuPlacedKind.cardHeader) header = element;
    }
    final blur = motion.tuning.cardBlur * platter;
    final shape = BorderRadius.circular(cardRadius);
    return Positioned(
      key: ValueKey<int>(index),
      left: shown.left,
      top: shown.top,
      width: rect.width,
      height: rect.height,
      child: Transform.scale(
        scale: s,
        alignment: .topLeft,
        child: Stack(
          clipBehavior: .none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _CardShadowPainter(
                  radius: cardRadius,
                  color: style.submenuShadowColor,
                  opacity: platter,
                ),
              ),
            ),
            Positioned.fill(
              child: ClipRRect(
                borderRadius: shape,
                child: BackdropFilter(
                  enabled: blur > 0.05,
                  filter: ui.ImageFilter.blur(
                    sigmaX: blur,
                    sigmaY: blur,
                    tileMode: TileMode.clamp,
                  ),
                  child: CustomPaint(
                    painter: _CardPlatterPainter(
                      radius: cardRadius,
                      under: under,
                      tint: style.submenuColor,
                      rim: style.submenuRimColor,
                      blur: motion.tuning.cardBlur,
                      opacity: platter,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ClipRRect(
                borderRadius: shape,
                child: OverflowBox(
                  alignment: .topLeft,
                  minWidth: width,
                  maxWidth: width,
                  minHeight: layout.height,
                  maxHeight: layout.height,
                  child: Transform.translate(
                    offset: Offset(-rect.left, card.contentTop),
                    child: SizedBox(
                      width: width,
                      height: layout.height,
                      child: Stack(
                        clipBehavior: .none,
                        children: [
                          ?_highlight(motion, style, layout, index),
                          Opacity(
                            opacity: card.rowsOpacity * rowsAlpha,
                            child: _rowsOf(layout, style),
                          ),
                          if (header != null)
                            Positioned.fill(
                              child: Opacity(
                                opacity: rowsAlpha,
                                child: Stack(
                                  clipBehavior: .none,
                                  children: [
                                    DefaultTextStyle(
                                      style: MorphTypography.resolve(
                                        style.textStyle,
                                      ),
                                      child: _MenuElement(
                                        element: header,
                                        style: style,
                                        width: layout.width,
                                        content: widget.host.menuContent,
                                        onSelect: (int target) =>
                                            _select(layout, target),
                                        headerBold: card.headerBold,
                                        chevronTurn: card.chevronTurn,
                                        separatorOpacity: card.platterOpacity,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _highlight(
    MorphMenuMotion motion,
    MorphMenuStyle style,
    MorphMenuLayout layout,
    int card,
  ) {
    final index = motion.highlighted;
    if (index == null || motion.highlightedCard != card) return null;
    if (index >= layout.targets.length) return null;
    final target = layout.targets[index];
    if (target.kind == MorphMenuTargetKind.back) return null;
    final element = target.element < 0 ? null : layout.elements[target.element];
    final cell = switch (element?.kind) {
      MorphMenuPlacedKind.palette ||
      MorphMenuPlacedKind.small ||
      MorphMenuPlacedKind.medium => true,
      _ => false,
    };
    final rect = cell
        ? target.rect
        : target.rect
              .deflate(0)
              .inflateHorizontal(-motion.tuning.highlightInset);
    return Positioned.fromRect(
      rect: rect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style.highlightColor,
          borderRadius: .circular(
            cell ? 12 : math.min(rect.height / 2, motion.tuning.rowHeight / 2),
          ),
        ),
      ),
    );
  }

  List<Widget> _glow(MorphMenuMotion motion, MorphMenuStyle style) {
    final glow = motion.glowCenter;
    final glowOpacity = motion.glowOpacity;
    if (glow == null || glowOpacity <= 0) return const [];
    final tuning = motion.tuning;
    return [
      Positioned.fromRect(
        rect: Rect.fromCenter(
          center: _contentLocal(motion, glow),
          width: tuning.glowDiameter,
          height: tuning.glowDiameter,
        ),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: .circle,
              gradient: RadialGradient(
                colors: [
                  style.glowColor.withValues(alpha: glowOpacity),
                  style.glowColor.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

extension on Rect {
  Rect inflateHorizontal(double delta) =>
      Rect.fromLTRB(left - delta, top, right + delta, bottom);
}

/// [position] in the coordinates of the content laid out at its final
/// size, which [MorphMenuMotion.contentRect] shows scaled.
Offset _contentLocal(MorphMenuMotion motion, Offset position) {
  final frame = motion.contentRect;
  return (position - frame.topLeft) / motion.contentScale;
}

/// The elements of one card, each at its frame in the card's content.
class _MenuRows extends StatelessWidget {
  const _MenuRows({
    required this.layout,
    required this.style,
    required this.hidden,
    required this.content,
    required this.onSelect,
  });

  final MorphMenuLayout layout;
  final ValueListenable<int?> hidden;
  final MorphMenuStyle style;
  final MorphMenuContent content;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: Stack(
        clipBehavior: .none,
        children: [
          for (final element in layout.elements)
            if (element.entry is MorphSubmenu &&
                element.kind == MorphMenuPlacedKind.row)
              ValueListenableBuilder<int?>(
                valueListenable: hidden,
                builder: (BuildContext context, int? hidden, Widget? _) =>
                    _MenuElement(
                      element: element,
                      style: style,
                      width: layout.width,
                      content: content,
                      onSelect: onSelect,
                      hidden: hidden == element.target,
                    ),
              )
            else if (element.kind != MorphMenuPlacedKind.cardHeader)
              _MenuElement(
                element: element,
                style: style,
                width: layout.width,
                content: content,
                onSelect: onSelect,
              ),
        ],
      ),
    );
  }
}

class _MenuElement extends StatelessWidget {
  const _MenuElement({
    required this.element,
    required this.style,
    required this.width,
    required this.content,
    required this.onSelect,
    this.headerBold = 1,
    this.chevronTurn = 1,
    this.separatorOpacity = 1,
    this.hidden = false,
  });

  final bool hidden;

  final double headerBold;
  final double chevronTurn;
  final double separatorOpacity;

  final MorphMenuPlaced element;
  final MorphMenuStyle style;
  final double width;
  final MorphMenuContent content;
  final ValueChanged<int> onSelect;

  Color get _title => style.textStyle.color ?? style.iconColor;

  VoidCallback? get _tap {
    final target = element.target;
    return target < 0 ? null : () => onSelect(target);
  }

  Widget _at(double center, double extent, Widget child) =>
      PositionedDirectional(
        start: center - extent / 2,
        width: extent,
        top: 0,
        bottom: 0,
        child: Center(child: child),
      );

  Widget _text(
    String text,
    TextStyle base,
    Color color, {
    int maxLines = 1,
    TextAlign? align,
  }) => Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    style: MorphTypography.resolve(base).copyWith(color: color),
  );

  @override
  Widget build(BuildContext context) {
    final element = this.element;
    final rect = element.rect;
    return Positioned.fromRect(
      rect: rect,
      child: switch (element.kind) {
        MorphMenuPlacedKind.row when hidden => Opacity(
          opacity: 0,
          child: _row(),
        ),
        MorphMenuPlacedKind.row => _row(),
        MorphMenuPlacedKind.header => _header(),
        MorphMenuPlacedKind.separator => ColoredBox(
          color: style.separatorColor,
        ),
        MorphMenuPlacedKind.palette ||
        MorphMenuPlacedKind.small ||
        MorphMenuPlacedKind.medium => _cell(),
        MorphMenuPlacedKind.loading => _loading(),
        MorphMenuPlacedKind.widget => _widget(),
        MorphMenuPlacedKind.cardHeader => _cardHeader(),
      },
    );
  }

  Widget _row() {
    final entry = element.entry;
    final String title;
    final String? subtitle;
    final IconData? icon;
    final bool enabled;
    final bool destructive;
    var state = MorphMenuState.off;
    var submenu = false;
    Color? iconColor;
    switch (entry) {
      case MorphMenuItem():
        title = entry.title;
        subtitle = entry.subtitle;
        state = entry.state;
        icon = entry.iconVisibility == MorphMenuIconVisibility.hidden
            ? null
            : state != MorphMenuState.off && entry.selectedIcon != null
            ? entry.selectedIcon
            : entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        iconColor = entry.iconColor;
      case MorphSubmenu():
        title = entry.title;
        subtitle = entry.subtitle;
        icon = entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        submenu = true;
      default:
        return const SizedBox.shrink();
    }
    final color = !enabled
        ? style.disabledColor
        : destructive
        ? style.destructiveColor
        : _title;
    final check = element.checkCenter;
    final image = element.imageCenter;
    return Semantics(
      button: true,
      enabled: enabled,
      checked: state == MorphMenuState.off || submenu
          ? null
          : state == MorphMenuState.on,
      mixed: state == MorphMenuState.mixed ? true : null,
      expanded: submenu ? false : null,
      label: title,
      value: subtitle,
      onTap: enabled ? _tap : null,
      excludeSemantics: true,
      child: Stack(
        children: [
          if (check != null && state != MorphMenuState.off)
            _at(
              check,
              16,
              CustomPaint(
                size: state == MorphMenuState.on
                    ? const Size(13.33, 12.33)
                    : const Size(12.67, 3.67),
                painter: _MarkPainter(
                  color: color,
                  mixed: state == MorphMenuState.mixed,
                ),
              ),
            ),
          if (image != null && icon != null)
            _at(
              image,
              30,
              Icon(icon, size: style.iconSize, color: iconColor ?? color),
            ),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: .center,
              crossAxisAlignment: .start,
              children: [
                _text(
                  title,
                  style.textStyle,
                  color,
                  maxLines: element.maxLines,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2.67),
                  _text(subtitle, _subtitleStyle, style.secondaryColor),
                ],
              ],
            ),
          ),
          if (submenu)
            _at(
              _metrics.chevronCenter,
              16,
              Transform.flip(
                flipX: content.rtl,
                child: CustomPaint(
                  size: const Size(9.33, 12.67),
                  painter: _ChevronPainter(color: color, down: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  MorphMenuMetrics get _metrics => content.metrics;

  static const _subtitleStyle = TextStyle(fontSize: 13);

  Widget _header() {
    return Semantics(
      header: true,
      label: element.title,
      excludeSemantics: true,
      child: Stack(
        children: [
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: _metrics.headerLabelTop,
            child: _text(
              element.title ?? '',
              _subtitleStyle,
              style.secondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardHeader() {
    final entry = element.entry;
    final icon = entry is MorphSubmenu ? entry.icon : null;
    final image = element.imageCenter;
    final title = element.title ?? '';
    final bold = headerBold.clamp(0.0, 1.0);
    return Semantics(
      button: true,
      expanded: true,
      label: element.title,
      onTap: _tap,
      excludeSemantics: true,
      child: Stack(
        children: [
          if (image != null && icon != null)
            _at(image, 30, Icon(icon, size: style.iconSize, color: _title)),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                if (bold < 1)
                  Opacity(
                    opacity: 1 - bold,
                    child: _text(title, style.textStyle, _title),
                  ),
                if (bold > 0)
                  Opacity(
                    opacity: bold,
                    child: _text(
                      title,
                      style.textStyle.merge(MorphTypography.title),
                      _title,
                    ),
                  ),
              ],
            ),
          ),
          _at(
            _metrics.chevronCenter,
            16,
            Transform.flip(
              flipX: content.rtl,
              child: Transform.rotate(
                angle: chevronTurn.clamp(0.0, 1.0) * math.pi / 2,
                child: CustomPaint(
                  size: const Size(9.33, 12.67),
                  painter: _ChevronPainter(color: _title, down: false),
                ),
              ),
            ),
          ),
          Positioned(
            left: _metrics.separatorInset,
            right: _metrics.separatorInset,
            bottom: 0,
            height: 1,
            child: Opacity(
              opacity: separatorOpacity.clamp(0.0, 1.0),
              child: ColoredBox(color: style.separatorColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell() {
    final entry = element.entry;
    final String title;
    final IconData? icon;
    final bool enabled;
    final bool destructive;
    var selected = false;
    Color? iconColor;
    switch (entry) {
      case MorphMenuItem():
        title = entry.title;
        selected = entry.state != MorphMenuState.off;
        icon = selected && entry.selectedIcon != null
            ? entry.selectedIcon
            : entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        iconColor = entry.iconColor;
      case MorphSubmenu():
        title = entry.title;
        icon = entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
      default:
        return const SizedBox.shrink();
    }
    final color = !enabled
        ? style.disabledColor
        : destructive
        ? style.destructiveColor
        : _title;
    final kind = element.kind;
    final metrics = _metrics;
    final Widget body;
    if (kind == MorphMenuPlacedKind.medium) {
      body = Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: metrics.mediumLabelTop,
            child: Center(
              child: icon == null
                  ? null
                  : Icon(icon, size: style.iconSize, color: iconColor ?? color),
            ),
          ),
          Positioned(
            left: 2,
            right: 2,
            top: metrics.mediumLabelTop,
            child: _text(
              title,
              const TextStyle(fontSize: 12),
              color,
              align: TextAlign.center,
            ),
          ),
        ],
      );
    } else {
      final palette = kind == MorphMenuPlacedKind.palette;
      body = Stack(
        alignment: Alignment.center,
        children: [
          if (palette && selected)
            SizedBox.square(
              dimension: metrics.palettePlatter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: style.paletteSelectionColor,
                  borderRadius: .circular(metrics.palettePlatterRadius),
                ),
              ),
            ),
          if (icon != null)
            Icon(
              icon,
              size: palette ? metrics.paletteImageSize : style.iconSize,
              color: iconColor ?? color,
            ),
        ],
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: title,
      onTap: enabled ? _tap : null,
      excludeSemantics: true,
      child: body,
    );
  }

  Widget _loading() {
    final check = element.imageCenter ?? _metrics.imageCenter;
    return Semantics(
      label: element.title,
      liveRegion: true,
      excludeSemantics: true,
      child: Stack(
        children: [
          _at(check, 30, MorphActivityIndicator(color: style.disabledColor)),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _text(
                element.title ?? '',
                style.textStyle,
                style.disabledColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _widget() {
    final entry = element.entry;
    if (entry is! MorphMenuWidget) return const SizedBox.shrink();
    final key = element.key;
    final Widget child = Builder(builder: entry.builder);
    return OverflowBox(
      alignment: .topCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Padding(
        padding: .symmetric(horizontal: _metrics.widgetInset),
        child: entry.height != null || key == null
            ? child
            : _HeightReporter(
                onHeight: (double height) => content.reportHeight(key, height),
                child: child,
              ),
      ),
    );
  }
}

/// Reports the height [child] lays out at, after the frame.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_reported == height) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (attached) onHeight(height);
    });
  }
}

/// The checkmark or the dash of a row's selection mark.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.color, required this.mixed});

  final Color color;
  final bool mixed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    if (mixed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
        paint,
      );
      return;
    }
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.1;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final path = Path();
    path.moveTo(size.width * 0.06, size.height * 0.55);
    path.lineTo(size.width * 0.36, size.height * 0.92);
    path.lineTo(size.width * 0.94, size.height * 0.08);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mixed != mixed;
}

/// A chevron pointing forward (mirrored in right-to-left text) or down.
/// The shadow a submenu card casts around itself, kept off its face: the
/// card is translucent.
class _CardShadowPainter extends CustomPainter {
  const _CardShadowPainter({
    required this.radius,
    required this.color,
    required this.opacity,
  });

  final double radius;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || color.a <= 0) return;
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    final outside = Path();
    outside.fillType = PathFillType.evenOdd;
    outside.addRect(shape.outerRect.inflate(40));
    outside.addRRect(shape);
    canvas.clipPath(outside);
    final paint = Paint();
    paint.color = color.withValues(alpha: color.a * opacity);
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(shape, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardShadowPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity;
}

/// The face of a submenu card over its blurred backdrop: [tint] over the
/// lists [under] it, each spread by [blur] the way the card's blur
/// spreads their edges, every further one at half the tint, and [rim]
/// along the top edge.
class _CardPlatterPainter extends CustomPainter {
  const _CardPlatterPainter({
    required this.radius,
    required this.under,
    required this.tint,
    required this.rim,
    required this.blur,
    required this.opacity,
  });

  final double radius;
  final List<RRect> under;
  final Color tint;
  final Color rim;
  final double blur;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint();
    paint.maskFilter = blur > 0
        ? MaskFilter.blur(BlurStyle.normal, blur)
        : null;
    var strength = 1.0;
    for (final list in under) {
      paint.color = tint.withValues(alpha: tint.a * opacity * strength);
      canvas.drawRRect(list, paint);
      strength /= 2;
    }
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final edge = Paint();
    edge.style = PaintingStyle.stroke;
    edge.strokeWidth = 2;
    final reach = math.min(radius, size.height / 2);
    edge.shader = ui.Gradient.linear(Offset.zero, Offset(0, reach), [
      rim.withValues(alpha: rim.a * opacity),
      rim.withValues(alpha: 0),
    ]);
    canvas.drawRRect(shape, edge);
  }

  @override
  bool shouldRepaint(_CardPlatterPainter oldDelegate) => true;
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.down});

  final Color color;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final path = Path();
    final w = size.width;
    final h = size.height;
    if (down) {
      path.moveTo(w * 0.08, h * 0.12);
      path.lineTo(w * 0.5, h * 0.88);
      path.lineTo(w * 0.92, h * 0.12);
    } else {
      path.moveTo(w * 0.12, h * 0.08);
      path.lineTo(w * 0.88, h * 0.5);
      path.lineTo(w * 0.12, h * 0.92);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.down != down;
}

/// The glass of both shapes as one body - their fused [outline], or their
/// union without one - or the resting button when there is no [menu].
class _GlassPainter extends CustomPainter {
  const _GlassPainter({
    required this.style,
    required this.source,
    this.menu,
    this.outline,
  });

  final MorphMenuStyle style;
  final RRect source;
  final RRect? menu;
  final MorphGlassOutline? outline;

  @override
  void paint(Canvas canvas, Size size) {
    final menu = this.menu;
    final outline = this.outline;
    final Path shape;
    if (menu != null && outline != null) {
      shape = outline.path;
    } else {
      shape = Path();
      shape.addRRect(source);
      if (menu != null) shape.addRRect(menu);
    }
    canvas.drawShadow(shape, style.shadowColor, style.shadowElevation, true);
    final fill = Paint();
    fill.color = style.glassColor;
    canvas.drawPath(shape, fill);
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) =>
      oldDelegate.menu != menu ||
      oldDelegate.source != source ||
      oldDelegate.outline != outline ||
      oldDelegate.style != style;
}

class _Ellipsis extends StatelessWidget {
  const _Ellipsis({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: CustomPaint(painter: _EllipsisPainter(color)),
    );
  }
}

class _EllipsisPainter extends CustomPainter {
  const _EllipsisPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    final center = size.center(Offset.zero);
    for (final dx in const [-7.0, 0.0, 7.0]) {
      canvas.drawCircle(center + Offset(dx, 0), 2.2, paint);
    }
  }

  @override
  bool shouldRepaint(_EllipsisPainter oldDelegate) =>
      oldDelegate.color != color;
}
