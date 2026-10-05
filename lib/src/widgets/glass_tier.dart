import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_device.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// The GPU class of the device as Flutter GPU reports it, which
/// [MorphAdaptiveGlass] picks its tier by.
enum MorphGlassDeviceClass {
  /// Impeller on Vulkan or Metal, an Apple GPU from the A13 on: the
  /// liquid tier.
  capable,

  /// Impeller on its OpenGL ES fallback (Android without a usable
  /// Vulkan driver), told by Flutter GPU's
  /// `doesSupportFramebufferRenderMipmap`, which only that backend lacks.
  ///
  /// On a Pixel 6a forced to GLES (2026-10-05, profile, glass audit
  /// medians at 60 Hz) liquid missed the frame budget on 11 - 69 frames
  /// per scene where Vulkan missed 0 - 22, its raster p95 3 - 6 ms higher,
  /// and frosted missed even more (17 - 132), so the device gets
  /// [MorphAdaptiveGlass.cheapTier].
  gles,

  /// An iPhone or iPad GPU older than the A13, told by the missing HDR
  /// ASTC support that Metal reports from the A13 (GPU family Apple 6)
  /// on. Not measured on such a device; it gets
  /// [MorphAdaptiveGlass.cheapTier].
  appleBeforeA13,

  /// The class is not known: no Flutter GPU, the web, or the liquid tier
  /// not initialized yet.
  unknown,
}

/// Reads the device class; tests replace it.
@internal
MorphGlassDeviceClass Function() morphGlassDeviceClassProbe =
    morphProbeGlassDeviceClass;

/// Installs a [MorphGlassRenderer] at one tier for the whole session:
/// [tier] when given, else the tier the device class allows.
///
/// The automatic choice is made once from the GPU's capabilities
/// ([deviceClass]), never from frame timings, so the glass never changes
/// its look while the app runs: liquid on a capable GPU, [cheapTier] on
/// the OpenGL ES fallback and on Apple GPUs older than the A13, and the
/// [renderer]'s own tier when it is lower or the build has no liquid tier.
/// The device class is known once the liquid tier is initialized; call
/// [MorphGlassRenderer.precache] before `runApp` so the first frame
/// already draws the chosen tier instead of the frosted fallback. The
/// shapes, motion and fusion of every control are the same on every
/// tier.
///
/// Read the tier in use with [MorphAdaptiveGlass.tierOf]. An ancestor
/// [BackdropGroup] is reused, otherwise this widget installs one for its
/// controls.
///
/// Resting glass in one [BackdropGroup] shares one copy of the screen,
/// taken where the group's first glass paints, so glass painted after
/// other content misses that content - a button on a card drawn over a
/// list whose own glass painted first shows the list as it stood before
/// the card. Give such a section a group of its own:
///
/// ```dart
/// BackdropGroup(child: card)
/// ```
///
/// Its glass then reads a copy taken where the section paints, at the
/// price of one more full-screen copy per frame while anything in it
/// moves. Bars, menus, sheets and lifted glass already take their own.
class MorphAdaptiveGlass extends StatefulWidget {
  /// Installs [renderer] for [child] at [tier], or at the tier the device
  /// class allows when [tier] is null.
  const MorphAdaptiveGlass({
    required this.child,
    this.renderer = const MorphGlassRenderer(),
    this.tier,
    super.key,
  });

  /// The renderer; its tier is the best one the automatic choice uses.
  final MorphGlassRenderer renderer;

  /// The tier to draw, or null to choose it by the device class.
  final MorphGlassTier? tier;

  /// The subtree that draws its glass with the renderer.
  final Widget child;

  /// The tier a device that cannot hold liquid glass draws.
  ///
  /// Flat: on the GLES fallback of a Pixel 6a frosted costs more raster
  /// than liquid (see [MorphGlassDeviceClass.gles]), so flat is the one
  /// tier there that is cheaper.
  static const MorphGlassTier cheapTier = MorphGlassTier.flat;

  /// The device class, or [MorphGlassDeviceClass.unknown] until the
  /// liquid tier is initialized.
  static MorphGlassDeviceClass get deviceClass => morphGlassDeviceClassProbe();

  /// The tier the automatic choice draws on [deviceClass] when [best] is
  /// the best tier the renderer can draw.
  static MorphGlassTier tierFor(
    MorphGlassDeviceClass deviceClass,
    MorphGlassTier best,
  ) {
    if (best != MorphGlassTier.liquid) return best;
    return switch (deviceClass) {
      MorphGlassDeviceClass.capable ||
      MorphGlassDeviceClass.unknown => MorphGlassTier.liquid,
      MorphGlassDeviceClass.gles ||
      MorphGlassDeviceClass.appleBeforeA13 => cheapTier,
    };
  }

  /// The effective tier of the [MorphGlassRenderer] installed above
  /// [context], or null when the painter above is not one.
  static MorphGlassTier? tierOf(BuildContext context) =>
      switch (MorphGlass.maybeOf(context)) {
        final MorphGlassRenderer renderer => renderer.effectiveTier,
        _ => null,
      };

  @override
  State<MorphAdaptiveGlass> createState() => _MorphAdaptiveGlassState();
}

class _MorphAdaptiveGlassState extends State<MorphAdaptiveGlass> {
  MorphGlassDeviceClass _deviceClass = MorphAdaptiveGlass.deviceClass;

  @override
  void initState() {
    super.initState();
    if (_deviceClass == MorphGlassDeviceClass.unknown) {
      morphLiquidGlassCapability.addListener(_capabilityChanged);
    }
  }

  void _capabilityChanged() {
    if (!mounted) return;
    setState(() => _deviceClass = MorphAdaptiveGlass.deviceClass);
    if (_deviceClass != MorphGlassDeviceClass.unknown) {
      morphLiquidGlassCapability.removeListener(_capabilityChanged);
    }
  }

  @override
  void dispose() {
    morphLiquidGlassCapability.removeListener(_capabilityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier =
        widget.tier ??
        MorphAdaptiveGlass.tierFor(_deviceClass, widget.renderer.effectiveTier);
    final glass = MorphGlass(
      painter: widget.renderer.copyWith(tier: tier),
      child: widget.child,
    );
    return BackdropGroup.of(context) == null
        ? BackdropGroup(child: glass)
        : glass;
  }
}
