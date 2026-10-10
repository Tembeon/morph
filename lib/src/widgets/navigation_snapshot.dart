import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glass_tier.dart';

/// Draws a sliding page from a snapshot of itself while its transition
/// moves, so each frame of the slide translates an image instead of
/// re-rasterizing the page.
///
/// Off by default: `--dart-define=MORPH_NAV_SNAPSHOT=true`, or
/// [debugEnabled] in tests. With it off, a page's slide builds the tree it
/// always built.
///
/// Snapshots apply only under a [MorphGlassRenderer] whose effective tier
/// is [MorphGlassTier.flat]. On the fake and liquid tiers, and without a
/// renderer above the page, every page stays live: a snapshot renders the
/// page in a pass of its own whose origin is the page, while the renderer
/// places its backdrop shaders, glass containers and raster-phase anchors
/// in screen coordinates that include the slide, so glass inside a
/// snapshot would shade offset by the slide.
///
/// While a page's own animation or the animation of the page pushed over it
/// is moving (running, or held by a finger dragging it), its content is
/// frozen in the snapshot taken at the first moving frame: scrolling,
/// animations, glass backdrops and text input inside the page do not
/// update until it comes to rest. Whatever the page shows at that frame
/// stays for the whole slide - content that settles in a post-frame
/// callback, images still decoding, and a source a flight launched
/// mid-slide hides stay as they were in the first moving frame. At rest,
/// and in every frame of a finished or not yet started transition, the
/// page is live.
///
/// Each snapshot costs an offscreen pass on the frame that takes it (the
/// first moving frame of a push or pop takes two, one per page): a raster
/// spike to look for on the device.
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
/// exactly while [animation] or [secondaryAnimation] is running and the
/// glass tier above is flat.
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
  bool _flat = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_statusChanged);
    widget.secondaryAnimation.addStatusListener(_statusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flat = MorphAdaptiveGlass.tierOf(context) == MorphGlassTier.flat;
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
        _flat &&
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
