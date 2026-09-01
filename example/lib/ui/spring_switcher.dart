import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';

/// Content switching on the engine's own physics: a [MorphController]
/// drives a crossfade-and-rise, and a swap MID-FLIGHT stays continuous
/// by construction - the outgoing layer picks up exactly the opacity
/// the incoming one had (value := 1 - value via the scrub API), then
/// the spring retargets to 1.
///
/// The two children live in two STABLE keyed slots: the outgoing
/// element keeps its position in the tree (and therefore its live
/// state - tickers, controllers, MorphTags) until the spring settles,
/// and switching back mid-flight returns to the still-living old
/// subtree instead of rebuilding it. The example shell uses this for
/// every panel and canvas change.
class SpringSwitcher extends StatefulWidget {
  /// Creates a switcher showing [child].
  const SpringSwitcher({super.key, required this.child, this.rise = 14});

  /// The current child; a change of [Widget.key] (or runtimeType)
  /// triggers the transition, mirroring AnimatedSwitcher's contract.
  final Widget child;

  /// How far the incoming content rises into place, in px.
  final double rise;

  @override
  State<SpringSwitcher> createState() => _SpringSwitcherState();
}

class _SpringSwitcherState extends State<SpringSwitcher>
    with TickerProviderStateMixin {
  late final MorphController _controller;
  Widget? _a;
  Widget? _b;
  bool _aActive = true;

  @override
  void initState() {
    super.initState();
    _a = widget.child;
    // Mount settled: the first child appears without a transition.
    _controller = MorphController(vsync: this, motion: .fast)
      ..beginScrub()
      ..updateScrub(1)
      ..open()
      ..addListener(_onTick);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  void _onTick() {
    // Retire the outgoing slot only when the spring has SETTLED at 1:
    // beginScrub also notifies with isAnimating false, so an
    // isAnimating check alone would drop it mid-swap.
    final bool settled =
        !_controller.isAnimating &&
        !_controller.isScrubbing &&
        _controller.progress >= 1;
    if (settled && (_aActive ? _b : _a) != null) {
      setState(() {
        if (_aActive) {
          _b = null;
        } else {
          _a = null;
        }
      });
    }
  }

  @override
  void didUpdateWidget(SpringSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final Widget current = (_aActive ? _a : _b)!;
    if (Widget.canUpdate(current, widget.child)) {
      if (_aActive) {
        _a = widget.child;
      } else {
        _b = widget.child;
      }
      return;
    }
    // Flip the active slot; if the target slot still hosts the old
    // subtree of the same kind (an interruption back), it updates in
    // place and its state survives.
    _aActive = !_aActive;
    if (_aActive) {
      _a = widget.child;
    } else {
      _b = widget.child;
    }
    _controller
      ..beginScrub()
      ..updateScrub(1 - _controller.progress)
      ..open();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        final double p = _controller.progress;

        Widget slot(String name, Widget? child, {required bool active}) {
          if (child == null) {
            return SizedBox.shrink(key: ValueKey<String>(name));
          }
          return KeyedSubtree(
            key: ValueKey<String>(name),
            child: IgnorePointer(
              ignoring: !active,
              child: Opacity(
                opacity: active ? p : 1 - p,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    active ? widget.rise * (1 - p) : -widget.rise * 0.5 * p,
                  ),
                  child: child,
                ),
              ),
            ),
          );
        }

        return Stack(
          alignment: Alignment.topCenter,
          fit: .passthrough,
          children: <Widget>[
            if (_aActive) ...<Widget>[
              slot('b', _b, active: false),
              slot('a', _a, active: true),
            ] else ...<Widget>[
              slot('a', _a, active: false),
              slot('b', _b, active: true),
            ],
          ],
        );
      },
    );
  }
}
