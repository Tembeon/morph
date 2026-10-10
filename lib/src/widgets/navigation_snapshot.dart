import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Draws a sliding page from a snapshot of itself while its transition
/// moves, so each frame of the slide translates an image instead of
/// re-rasterizing the page.
///
/// Off by default: `--dart-define=MORPH_NAV_SNAPSHOT=true`, or
/// [debugEnabled] in tests. With it off, a page's slide builds the tree it
/// always built.
///
/// While a page's own animation or the animation of the page pushed over it
/// is moving (running, or held by a finger dragging it), its content is
/// frozen in the snapshot taken at the first moving frame: scrolling,
/// animations, glass backdrops and text input inside the page do not
/// update until it comes to rest. At rest, and in every frame of a
/// finished or not yet started transition, the page is live.
@internal
abstract final class MorphNavigationSnapshot {
  /// Whether the build enables the page snapshots.
  static const bool defined = bool.fromEnvironment('MORPH_NAV_SNAPSHOT');

  /// Overrides [defined] when not null.
  @visibleForTesting
  static bool? debugEnabled;

  /// Whether a sliding page draws from a snapshot while it moves.
  static bool get enabled => debugEnabled ?? defined;
}

/// Wraps a sliding page in a [SnapshotWidget] whose snapshot is allowed
/// exactly while [animation] or [secondaryAnimation] is running.
///
/// The widget is mounted for the whole life of the page, so the page's state
/// never remounts when a transition starts or ends; only the controller
/// changes.
@internal
class MorphNavigationSnapshotHost extends StatefulWidget {
  /// Creates a host for the page [child] sliding on [animation] and
  /// [secondaryAnimation].
  const MorphNavigationSnapshotHost({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    super.key,
  });

  /// The page's own transition.
  final Animation<double> animation;

  /// The transition of the page pushed over this one.
  final Animation<double> secondaryAnimation;

  /// The page.
  final Widget child;

  @override
  State<MorphNavigationSnapshotHost> createState() =>
      _MorphNavigationSnapshotHostState();
}

class _MorphNavigationSnapshotHostState
    extends State<MorphNavigationSnapshotHost> {
  final SnapshotController _controller = SnapshotController();

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_statusChanged);
    widget.secondaryAnimation.addStatusListener(_statusChanged);
    _sync();
  }

  @override
  void didUpdateWidget(MorphNavigationSnapshotHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_statusChanged);
      widget.animation.addStatusListener(_statusChanged);
    }
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      oldWidget.secondaryAnimation.removeStatusListener(_statusChanged);
      widget.secondaryAnimation.addStatusListener(_statusChanged);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_statusChanged);
    widget.secondaryAnimation.removeStatusListener(_statusChanged);
    _controller.dispose();
    super.dispose();
  }

  void _statusChanged(AnimationStatus status) => _sync();

  void _sync() {
    _controller.allowSnapshotting =
        !kIsWeb &&
        (widget.animation.status.isAnimating ||
            widget.secondaryAnimation.status.isAnimating);
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _controller,
    mode: SnapshotMode.permissive,
    child: widget.child,
  );
}
