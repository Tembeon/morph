import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// Shades the resting glass of the controls below it in one glass layer:
/// one geometry pass and one backdrop filter for all of them instead of
/// one each.
///
/// UIKit's `UIGlassContainerEffect` for glass that does not fuse: sibling
/// glass buttons on one plane - a row of buttons, a cluster over a map -
/// read the backdrop once and are shaded together. Each control still
/// lays out, hits, moves and paints its content as before.
///
/// The container's glass is painted where the container paints, under
/// everything inside it. So everything in [child] is content above the
/// glass: a card, a row background or an image placed inside the container
/// would cover the glass of the buttons over it. Put what the glass must
/// show through outside the container, under it.
///
/// Only glass that would look the same either way joins: resting body
/// glass (glass buttons, search capsules) of the installed
/// [MorphGlassRenderer] on the liquid or fake tier, with the material the
/// container's own resting button has and the tint of the glass already
/// in the container, up to the most shapes one geometry pass encodes. A pressed button, whose rim lights up, a lens, a bar, a
/// menu and every other surface keep their own layer, as without the
/// container. On the flat tier, under another painter or with no painter
/// installed the container does nothing.
class MorphGlassContainer extends StatefulWidget {
  /// Shades the resting glass of the controls in [child] together.
  const MorphGlassContainer({required this.child, super.key});

  /// The controls whose resting glass the container shades.
  final Widget child;

  @override
  State<MorphGlassContainer> createState() => _MorphGlassContainerState();
}

class _MorphGlassContainerState extends State<MorphGlassContainer> {
  final MorphGlassContainerLink _link = MorphGlassContainerLink();

  @override
  Widget build(BuildContext context) {
    final painter = MorphGlass.maybeOf(context);
    if (painter is! MorphGlassRenderer ||
        painter.runtimeType != MorphGlassRenderer) {
      return widget.child;
    }
    return ValueListenableBuilder<bool>(
      valueListenable: morphLiquidGlassCapability,
      builder: (BuildContext context, bool _, Widget? child) {
        final tier = painter.effectiveTier;
        if (tier == MorphGlassTier.flat) return child!;
        final settings = morphLiquidSettings(
          painter,
          MorphGlassSurface(
            kind: MorphGlassKind.button,
            shape: RRect.zero,
            color: const Color(0x00000000),
            brightness: morphBrightnessOf(context),
          ),
        );
        _link.configure(painter, settings);
        return LiquidGlassLayer(
          settings: settings,
          fake: tier == MorphGlassTier.fake,
          useBackdropGroup: true,
          child: MorphGlassContainerScope(
            link: _link,
            renderer: painter,
            settings: settings,
            child: child!,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// The glass container above a control, read by its glass hosts.
@internal
class MorphGlassContainerScope extends InheritedWidget {
  /// Publishes [link] for the hosts in [child].
  const MorphGlassContainerScope({
    required this.link,
    required this.renderer,
    required this.settings,
    required super.child,
    super.key,
  });

  /// The container's admission record.
  final MorphGlassContainerLink link;

  /// The renderer the container shades with.
  final MorphGlassRenderer renderer;

  /// The settings of the container's layer.
  final LiquidGlassSettings settings;

  /// The nearest container above [context], or null.
  static MorphGlassContainerLink? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MorphGlassContainerScope>()
      ?.link;

  @override
  bool updateShouldNotify(MorphGlassContainerScope oldWidget) =>
      oldWidget.link != link ||
      oldWidget.renderer != renderer ||
      oldWidget.settings != settings;
}

/// Which glass hosts a container shades, and how many shapes each holds.
@internal
class MorphGlassContainerLink {
  MorphGlassRenderer? _renderer;
  LiquidGlassSettings? _settings;
  LiquidGlassAppearance? _appearance;
  final Map<Object, int> _members = {};
  int _shapes = 0;

  /// The most shapes the container's layer shades.
  static const int capacity = FlutterGpuGeometryRenderer.maxShapes;

  /// The shapes the container shades now.
  int get shapes => _shapes;

  /// Sets the renderer and the layer settings members must match.
  void configure(MorphGlassRenderer renderer, LiquidGlassSettings settings) {
    _renderer = renderer;
    _settings = settings;
  }

  /// Whether [host], drawing [frame] with [renderer], is shaded by the
  /// container; records or releases its shapes accordingly.
  bool admit(Object host, MorphGlassRenderer renderer, MorphGlassFrame frame) {
    final count = _joinable(renderer, frame);
    final held = _members[host];
    if (count == 0 || _shapes - (held ?? 0) + count > capacity) {
      release(host);
      return false;
    }
    _members[host] = count;
    _shapes += count - (held ?? 0);
    return true;
  }

  /// Whether [host] is shaded by the container.
  bool holds(Object host) => _members.containsKey(host);

  /// Gives back the shapes of [host].
  void release(Object host) {
    final held = _members.remove(host);
    if (held != null) _shapes -= held;
    if (_members.isEmpty) _appearance = null;
  }

  int _joinable(MorphGlassRenderer renderer, MorphGlassFrame frame) {
    final settings = _settings;
    if (settings == null ||
        renderer != _renderer ||
        renderer.effectiveTier == MorphGlassTier.flat) {
      return 0;
    }
    final parts = frame.parts;
    if (!frame.still ||
        parts.separate.isEmpty ||
        parts.fused.isNotEmpty ||
        parts.floating.isNotEmpty) {
      return 0;
    }
    var appearance = _appearance;
    for (final surface in parts.separate) {
      final own = morphLiquidAppearance(renderer, surface);
      appearance ??= own;
      if (surface.lift != 0 ||
          surface.kind == MorphGlassKind.bar ||
          surface.kind == MorphGlassKind.menu ||
          own != appearance ||
          morphLiquidSettings(renderer, surface) != settings) {
        return 0;
      }
    }
    _appearance = appearance;
    return parts.separate.length;
  }
}
