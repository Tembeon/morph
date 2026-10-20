import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/list.dart';
import 'package:morph/src/widgets/search_field.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/theme/glass.dart';

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
/// everything inside it, and only glass that would look the same in a
/// layer of its own joins: a control under a fade below full opacity, a
/// clip, a filter, a scrolling viewport or other glass inside the
/// container (a list of buttons, a fading or hidden button, a morph source
/// while it flies) keeps its own layer, and so does every member while the
/// container is drawn under more than a translation (a floating sheet).
/// Glass joins once it rests, and leaves in the frame after it starts to
/// move; a touch glow or a hidden morph source leaves at once. So
/// everything in [child] is content above the glass: a card, a row
/// background or an image placed inside the container would cover the
/// glass of the buttons over it. Put what the glass must show through
/// outside the container, under it.
///
/// Only glass that looks the same, or within a few channel steps, either
/// way joins: resting body glass (glass buttons, search capsules) of the
/// installed [GlassBuiltInPainter] on the liquid tier, with the
/// material the container's own resting button has, up to the most shapes
/// one geometry pass encodes. A member whose glass differs only in tint (a
/// prominent button) joins too and reads its tint from the layer's material
/// map: at most 7 channel steps on about 100 rim pixels on the iPhone 16
/// Pro. A pressed button, whose rim lights up, a lens, a bar, a
/// menu and every other surface keep their own layer, as without the
/// container. On the flat tier, under another painter or with no painter
/// installed the container does nothing.
///
/// Group neighbouring glass, as Apple advises for Liquid Glass: every
/// separate glass layer reads, filters and composites the backdrop under
/// it whatever its size, about 0.3 - 0.75 ms of raster time per layer and
/// frame on a Pixel 6a. Four resting buttons over a scrolling page draw 18
/// percent faster on that phone in a container, eight 22 percent. Wrap
/// the row or cluster itself, inside any scroll view, clip or fade: a
/// container around a scroll view joins nothing in it. A
/// [MorphListSection] already shades its rows' resting glass in one layer,
/// a resting [MorphSearchToolbar] its field and buttons. The example
/// gallery's glass inspector shows the layers of each frame and names
/// neighbouring glass that a container would join.
class MorphGlassContainer extends StatelessWidget {
  /// Shades the resting glass of the controls in [child] together.
  const MorphGlassContainer({
    required this.child,
    this.solidBackdrop,
    super.key,
  });

  /// The controls whose resting glass the container shades.
  final Widget child;

  /// The opaque color the container is painted directly over, or null.
  ///
  /// Declare it when the container sits on a fill of this color with
  /// nothing painted between, and its members are inset from the fill's
  /// edges by more than their refraction reaches - typically a cluster of
  /// buttons on a page's own background. The container then shades its
  /// members over the color itself instead of reading the backdrop: no
  /// backdrop filter at all, the most expensive part of glass on a phone's
  /// GPU. The container trusts the color: glass over anything else shows
  /// this color instead. A member that leaves the container reads its
  /// backdrop in its own layer as before. Ignored unless the color is
  /// fully opaque.
  final Color? solidBackdrop;

  @override
  Widget build(BuildContext context) =>
      _plane(context, open: true, solidBackdrop: solidBackdrop, child: child);
}

/// A glass container a package widget owns: [open] while nothing it does
/// to its members - a fade, a scale, a blur - changes how their glass
/// would look in layers of their own; a fade it draws at exactly 1 changes
/// nothing.
///
/// With [paintOrder] [GlassPaintOrder.outsideGlass] the stage paints
/// content between itself and its members, outside their outlines, and
/// shades only glass that does not frost: resting glass without a blur
/// reads only inside its own outline, a frosted one reads around its rim.
@internal
class MorphGlassStage extends StatelessWidget {
  /// Shades the resting glass in [child] together while [open].
  const MorphGlassStage({
    required this.open,
    required this.child,
    this.paintOrder = GlassPaintOrder.owned,
    this.solidBackdrop,
    super.key,
  });

  /// Whether the members are shaded together now.
  final bool open;

  /// What the stage paints between itself and its members' glass.
  final GlassPaintOrder paintOrder;

  /// The opaque color the stage is painted directly over, or null.
  ///
  /// When every member's glass would read only this color - the stage
  /// sits on a fill of it with nothing painted between, and its members
  /// are inset from the fill's edges by more than their refraction reaches
  /// - the stage shades its members over the color itself instead of
  /// reading the backdrop: no backdrop filter at all. A member that leaves
  /// the stage reads its backdrop in its own layer as before. Ignored
  /// unless the color is fully opaque.
  final Color? solidBackdrop;

  /// The members.
  final Widget child;

  @override
  Widget build(BuildContext context) => _plane(
    context,
    open: open && debugMorphGlassStagesOpen,
    paintOrder: paintOrder,
    solidBackdrop: debugMorphGlassStageSolidBackdrops ? solidBackdrop : null,
    child: child,
  );
}

/// Whether package stages that know their solid backdrop shade over it;
/// false makes them read their backdrop, the reference the solid backdrop
/// is measured against.
@visibleForTesting
@internal
bool debugMorphGlassStageSolidBackdrops = true;

/// Whether package stages shade their members together; false keeps every
/// member in its own layer, the reference a stage is measured against.
@visibleForTesting
@internal
bool debugMorphGlassStagesOpen = true;

/// The owned plane of a container or a stage: its pass has the settings
/// and the material of a resting glass button, so the glass that joins it
/// is body glass of the installed [GlassBuiltInPainter] on the liquid
/// tier; on the flat tier, under another painter or with no painter
/// installed it is [child] alone.
Widget _plane(
  BuildContext context, {
  required bool open,
  required Widget child,
  GlassPaintOrder paintOrder = GlassPaintOrder.owned,
  Color? solidBackdrop,
}) {
  final painter = MorphGlassScope.maybeOf(context);
  if (painter is! GlassBuiltInPainter ||
      painter.runtimeType != GlassBuiltInPainter) {
    return child;
  }
  return ValueListenableBuilder<bool>(
    valueListenable: morphLiquidGlassCapability,
    builder: (BuildContext context, bool _, Widget? child) {
      if (painter.effectiveTier == MorphGlassTier.flat) return child!;
      final button = MorphGlassSurface(
        kind: MorphGlassKind.button,
        shape: RRect.zero,
        color: const Color(0x00000000),
        brightness: morphBrightnessOf(context),
      );
      return GlassPlaneScope.owned(
        settings: morphLiquidSettings(painter, button),
        defaultAppearance: morphLiquidAppearance(painter, button),
        open: open,
        paintOrder: paintOrder,
        solidBackdrop: solidBackdrop,
        child: child!,
      );
    },
    child: child,
  );
}
