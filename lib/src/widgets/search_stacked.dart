import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/theme/localizations.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/search_field.dart';
import 'package:morph/src/widgets/search_motion.dart';
import 'package:morph/src/motion/spring_state.dart';

/// The search of a [MorphNavigationScaffold] page: a search field stacked
/// under the large title (UIKit `UINavigationItem.searchController` with
/// the `stacked` search bar placement, the page of a search tab without
/// `automaticallyActivatesSearch`; SwiftUI `searchable` with
/// `navigationBarDrawer` placement).
///
/// At rest the field is a flat 44 point capsule 16 points from the sides,
/// right under the large title, and scrolls with the content. A tap on it
/// presents the search on [MorphSearchTuning.stackedSpring]: the page (the
/// large title with it) moves up until the field sits under the status
/// bar, the field narrows for a 44 point close button that slides in from
/// the trailing side, its capsule turns to glass, and the navigation bar
/// hides ([hidesNavigationBarDuringPresentation]); the field takes the
/// focus at once and the keyboard rises over whatever is below (a tab
/// bar stays where it is, under the keyboard). Scrolling the content
/// keeps the search and the keyboard. The close button (or Escape) clears
/// the text and returns the page and the field to rest.
///
/// Measured on the iOS 27 simulator (geometry from stills, the spring from
/// a 60 Hz film); the moment the motion starts after the tap and the
/// field's switch to glass (here at the middle of the motion) are not
/// measured. Not reproduced: UIKit pins a scrolled stacked field under the
/// inline title when `hidesSearchBarWhenScrolling` is false (here it
/// scrolls away with the content, as UIKit's default does), and it blurs
/// the content under a presented field where this draws the page's
/// background.
@immutable
class MorphNavigationSearch {
  /// Describes the search of a page.
  const MorphNavigationSearch({
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.active,
    this.onActiveChanged,
    this.hidesNavigationBarDuringPresentation = true,
    this.appearance,
    this.closeLabel,
  });

  /// The controller of the query; null keeps one inside.
  final TextEditingController? controller;

  /// The focus node of the query; null keeps one inside.
  final FocusNode? focusNode;

  /// The text shown while the field is empty; null takes
  /// [MorphLocalizations.searchPlaceholder].
  final String? placeholder;

  /// Called whenever the query changes, including the empty query when the
  /// search ends.
  final ValueChanged<String>? onChanged;

  /// Called when the keyboard's search key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Whether the search is presented, set from code (UIKit
  /// `UISearchController.isActive`); null leaves it to the user. A change
  /// is not reported back through [onActiveChanged].
  final bool? active;

  /// Called when the user presents (true) or ends (false) the search.
  final ValueChanged<bool>? onActiveChanged;

  /// Whether the navigation bar hides while the search is presented
  /// (UIKit `hidesNavigationBarDuringPresentation`, true by default).
  final bool hidesNavigationBarDuringPresentation;

  /// The look of the field; null resolves it from the theme.
  final MorphSearchFieldAppearance? appearance;

  /// The label screen readers announce for the close button; null
  /// takes [MorphLocalizations.closeLabel].
  final String? closeLabel;
}

class _StackedScope extends InheritedWidget {
  const _StackedScope({
    required this.state,
    required this.presenting,
    required super.child,
  });

  final _MorphStackedSearchHostState state;
  final bool presenting;

  @override
  bool updateShouldNotify(_StackedScope oldWidget) =>
      oldWidget.presenting != presenting || oldWidget.state != state;
}

/// The stacked field at rest, in the page's scroll content under the large
/// title: a flat capsule that presents the search of the nearest
/// [MorphStackedSearchHost] when tapped, and holds its place while the
/// search is presented.
@internal
class MorphStackedSearchSlot extends StatelessWidget {
  /// Creates the slot.
  const MorphStackedSearchSlot({super.key});

  /// The slot's extent in the scroll content: the field and the space
  /// below it.
  static const double extent =
      MorphSearchTuning.stackedHeight + MorphSearchTuning.stackedBottomGap;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_StackedScope>();
    if (scope == null) return const SizedBox(height: extent);
    final search = scope.state.widget.search;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MorphSearchTuning.stackedSideInset,
        0,
        MorphSearchTuning.stackedSideInset,
        MorphSearchTuning.stackedBottomGap,
      ),
      child: Semantics(
        textField: true,
        label:
            (search.placeholder ??
            MorphLocalizations.of(context).searchPlaceholder),
        onTap: scope.presenting ? null : scope.state.present,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: scope.presenting ? null : scope.state.present,
          child: Opacity(
            key: scope.state._slot,
            opacity: scope.presenting ? 0 : 1,
            child: IgnorePointer(
              child: ExcludeFocus(
                child: MorphSearchField(
                  controller: scope.state._controller,
                  placeholder:
                      (search.placeholder ??
                      MorphLocalizations.of(context).searchPlaceholder),
                  appearance: search.appearance,
                  height: MorphSearchTuning.stackedHeight,
                  glass: false,
                  focusNode: scope.state._slotFocus,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hosts a page whose scroll content holds a [MorphStackedSearchSlot] and
/// presents its search: the page moves up by the slot's distance from the
/// status bar while the presented field and its close button take the
/// top of the screen.
@internal
class MorphStackedSearchHost extends StatefulWidget {
  /// Hosts [child].
  const MorphStackedSearchHost({
    required this.search,
    required this.background,
    required this.top,
    required this.child,
    this.onPresented,
    super.key,
  });

  /// Where the presented field's top sits: under the status bar, or under
  /// the navigation bar when the bar stays.
  final double top;

  /// The search.
  final MorphNavigationSearch search;

  /// The page's background, drawn behind the presented field over the
  /// content that scrolls under it.
  final Color background;

  /// The page.
  final Widget child;

  /// Called when the search starts (true) and once it has returned to rest
  /// (false); the page's navigation bar hides in between.
  final ValueChanged<bool>? onPresented;

  @override
  State<MorphStackedSearchHost> createState() => _MorphStackedSearchHostState();
}

typedef _Structure = ({bool presenting, bool glass, bool closing});

class _MorphStackedSearchHostState extends State<MorphStackedSearchHost>
    with
        SingleTickerProviderStateMixin<MorphStackedSearchHost>,
        MorphClock<MorphStackedSearchHost> {
  final MorphSpringState _spring = MorphSpringState(
    MorphSearchTuning.stackedSpring,
    0,
  );
  final GlobalKey _slot = GlobalKey();
  final FocusNode _slotFocus = FocusNode(
    debugLabel: 'MorphStackedSearchSlot',
    canRequestFocus: false,
    skipTraversal: true,
  );
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  FocusNode? _listening;
  double _now = 0;
  bool _presenting = false;
  bool _quiet = false;
  Rect _rest = Rect.zero;
  Rect _focused = Rect.zero;
  double _lift = 0;

  /// The swing of the presentation at which it rests. NEAR: the field
  /// lands by up to 0.001 of its travel, looser than [MorphRest.length].
  static const double _progressRest = 1e-3;
  Size _size = Size.zero;

  TextEditingController get _controller =>
      widget.search.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _focus =>
      widget.search.focusNode ??
      (_ownFocus ??= FocusNode(debugLabel: 'MorphNavigationSearch'));

  late final MorphFrameSync<_Structure> _ticks = MorphFrameSync<_Structure>(
    structure: _read,
    rebuild: (_Structure _) => setState(() {}),
  );

  _Structure _read() {
    final p = _spring.value(_now);
    return (
      presenting: _presenting,
      glass: _presenting && p >= 0.5,
      closing: _spring.target == 0,
    );
  }

  double get _p => _spring.value(_now);

  bool get _rtl => Directionality.maybeOf(context) == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    _listen();
    _ticks.follow(frames);
    if (widget.search.active ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (widget.search.active ?? false)) _startFromCode();
      });
    }
  }

  @override
  void didUpdateWidget(MorphStackedSearchHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
    final active = widget.search.active;
    if (active == null || active == oldWidget.search.active) return;
    if (active) {
      _startFromCode();
    } else {
      _end(report: false);
    }
  }

  void _listen() {
    final node = _focus;
    if (identical(node, _listening)) return;
    _listening?.removeListener(_focusChanged);
    _listening = node;
    node.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _ticks.dispose();
    _listening?.removeListener(_focusChanged);
    _slotFocus.dispose();
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  void advanceMotion(double t) {
    if (t > _now) _now = t;
    if (_spring.target == 0 &&
        _presenting &&
        _spring.isWithin(t, _progressRest)) {
      _spring.settle(t);
      _presenting = false;
      _notifyPresented(false);
    } else if (_spring.target == 1 &&
        _spring.value(t) != 1 &&
        _spring.isWithin(t, _progressRest)) {
      // NEAR: the field jumps by up to 0.001 of its travel, once.
      _spring.settle(t);
    }
  }

  @override
  bool get motionSettled =>
      _spring.isWithin(_now, _progressRest) &&
      _presenting == (_spring.target == 1);

  /// Presents the search: the slot was tapped.
  void present() {
    if (_spring.target == 1) return;
    _focus.requestFocus();
    if (!_focus.hasFocus) _begin();
  }

  void _startFromCode() {
    if (_spring.target == 1) return;
    _quiet = true;
    present();
  }

  void _focusChanged() {
    if (_focus.hasFocus && _spring.target != 1) _begin();
  }

  // Where the slot is now in this host, without the page's lift.
  Rect? _slotRect() {
    final slot = _slot.currentContext?.findRenderObject();
    final host = context.findRenderObject();
    if (slot is! RenderBox || host is! RenderBox) return null;
    if (!slot.attached || !slot.hasSize || !host.hasSize) return null;
    final origin = host.globalToLocal(slot.localToGlobal(Offset.zero));
    return (origin & slot.size).translate(0, _lift * _p);
  }

  // A change made while the tree builds (a parent's new `active`) reaches
  // the scaffold after the frame.
  void _notifyPresented(bool presented) {
    final notify = widget.onPresented;
    if (notify == null) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notify(presented);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _presenting == presented) notify(presented);
    });
  }

  void _begin() {
    final top = widget.top;
    const side = MorphSearchTuning.stackedSideInset;
    const h = MorphSearchTuning.stackedHeight;
    _focused = Rect.fromLTRB(
      _rtl ? side + h + MorphSearchTuning.stackedCloseGap : side,
      top,
      _rtl
          ? _size.width - side
          : _size.width - side - h - MorphSearchTuning.stackedCloseGap,
      top + h,
    );
    _rest = _slotRect() ?? _focused;
    _lift = _rest.top - _focused.top;
    _presenting = true;
    _spring.retarget(clock, 1, spring: MorphSearchTuning.stackedSpring);
    wake();
    setState(() {});
    _notifyPresented(true);
    final quiet = _quiet;
    _quiet = false;
    if (!quiet) widget.search.onActiveChanged?.call(true);
  }

  void _end({bool report = true}) {
    _quiet = false;
    if (_spring.target != 1) return;
    _rest = _slotRect() ?? _rest;
    _spring.retarget(clock, 0, spring: MorphSearchTuning.stackedSpring);
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      widget.search.onChanged?.call('');
    }
    _focus.unfocus();
    wake();
    setState(() {});
    if (report) widget.search.onActiveChanged?.call(false);
  }

  Rect _fieldRect() => Rect.lerp(_rest, _focused, _p)!;

  Rect _closeRect() {
    final p = _p;
    const h = MorphSearchTuning.stackedHeight;
    final field = _fieldRect();
    return Rect.fromLTWH(
      _rtl
          ? _focused.left -
                MorphSearchTuning.stackedCloseGap -
                h -
                (1 - p) * MorphSearchTuning.stackedCloseTravel
          : _focused.right +
                MorphSearchTuning.stackedCloseGap +
                (1 - p) * MorphSearchTuning.stackedCloseTravel,
      field.top,
      h,
      h,
    );
  }

  MorphNavigationSearch? _fieldFor;
  bool? _fieldGlass;
  Widget? _field;
  Widget? _close;
  Color? _closeColor;

  Widget _buildField(bool glass) {
    final search = widget.search;
    if (_field != null &&
        identical(_fieldFor, search) &&
        _fieldGlass == glass) {
      return _field!;
    }
    _fieldFor = search;
    _fieldGlass = glass;
    _close = null;
    return _field = MorphSearchField(
      controller: _controller,
      focusNode: _focus,
      placeholder:
          (search.placeholder ??
          MorphLocalizations.of(context).searchPlaceholder),
      onChanged: search.onChanged,
      onSubmitted: search.onSubmitted,
      appearance: search.appearance,
      height: MorphSearchTuning.stackedHeight,
      glass: glass,
    );
  }

  Widget _buildClose() {
    final search = widget.search;
    final glyph = MorphSearchFieldAppearance.resolve(
      context,
      search.appearance,
    ).glyphColor;
    if (_close != null && _closeColor == glyph) return _close!;
    _closeColor = glyph;
    return _close = Semantics(
      button: true,
      label: (search.closeLabel ?? MorphLocalizations.of(context).closeLabel),
      onTap: _end,
      excludeSemantics: true,
      child: MorphGlassButton(
        onPressed: _end,
        padding: EdgeInsets.zero,
        minSize: const Size.square(MorphSearchTuning.stackedHeight),
        child: SizedBox.fromSize(
          size: MorphSearchTuning.closeGlyphSize,
          child: CustomPaint(painter: _Cross(glyph)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final structure = _ticks.read();
    final presenting = structure.presenting;
    final field = _buildField(structure.glass);
    final close = _buildClose();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _end,
      },
      child: _StackedScope(
        state: this,
        presenting: presenting,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            _size = constraints.biggest;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _size.height + (presenting ? _lift : 0),
                  child: MorphLiveTransform(
                    live: _ticks,
                    writeInto: (Matrix4 into) =>
                        into.translateByDouble(0, -_lift * _p, 0, 1),
                    child: widget.child,
                  ),
                ),
                if (presenting)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height:
                        _focused.bottom + MorphSearchTuning.stackedBottomGap,
                    child: IgnorePointer(
                      child: MorphLiveOpacity(
                        live: _ticks,
                        opacityOf: () => _p.clamp(0.0, 1.0),
                        child: ColoredBox(color: widget.background),
                      ),
                    ),
                  ),
                MorphLivePositionedTemplate(
                  key: const ValueKey<String>('field'),
                  live: _ticks,
                  template: () => Positioned.fromRect(
                    rect: presenting ? _fieldRect() : _focused,
                    child: morphLiveSlot,
                  ),
                  child: IgnorePointer(
                    ignoring: !presenting,
                    child: ExcludeSemantics(
                      excluding: !presenting,
                      child: Opacity(opacity: presenting ? 1 : 0, child: field),
                    ),
                  ),
                ),
                if (presenting)
                  MorphLivePositionedTemplate(
                    key: const ValueKey<String>('close'),
                    live: _ticks,
                    template: () => Positioned.fromRect(
                      rect: _closeRect(),
                      child: morphLiveSlot,
                    ),
                    child: IgnorePointer(
                      ignoring: structure.closing,
                      child: MorphLiveOpacity(
                        live: _ticks,
                        opacityOf: () => _p.clamp(0.0, 1.0),
                        child: close,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Cross extends CustomPainter {
  const _Cross(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => morphPaintCross(canvas, size, color);

  @override
  bool shouldRepaint(_Cross oldDelegate) => oldDelegate.color != color;
}
