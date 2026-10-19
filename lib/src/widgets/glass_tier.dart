import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_device.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/theme/glass.dart';

/// The GPU class of the device as Flutter GPU reports it, which
/// [GlassAdaptiveScope] picks its tier by.
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
  /// so the device gets [GlassAdaptiveScope.cheapTier].
  gles,

  /// An iPhone or iPad GPU older than the A13, told by the missing HDR
  /// ASTC support that Metal reports from the A13 (GPU family Apple 6)
  /// on. Not measured on such a device; it gets
  /// [GlassAdaptiveScope.cheapTier].
  appleBeforeA13,

  /// Skia, a native runtime without Impeller (Android before API 29, or an
  /// app that turns Impeller off), told by `ImageFilter.isShaderFilterSupported`,
  /// which only Impeller supports.
  ///
  /// There is no liquid tier, and glass that blurs its backdrop goes
  /// through Skia's multi-pass blur: on a Redmi 6A (Android 9, PowerVR
  /// GE8320, 2026-10-11, profile, the gallery's autodemo) every page drew
  /// raster p95 30 - 265 ms with backdrop-blurred glass, so the device
  /// gets [GlassAdaptiveScope.cheapTier].
  skia,

  /// The class is not known: no Flutter GPU, the web, or the liquid tier
  /// not initialized yet.
  unknown,
}

/// Reads the device class; tests replace it.
@internal
MorphGlassDeviceClass Function() morphGlassDeviceClassProbe =
    morphProbeGlassDeviceClass;

/// Installs a [GlassBuiltInPainter] at one tier for the whole session:
/// [tier] when given, else the tier the device class allows.
///
/// The automatic choice is made once from the GPU's capabilities
/// ([deviceClass]), never from frame timings: liquid on a capable GPU,
/// [cheapTier] on the OpenGL ES fallback, on Skia and on Apple GPUs older
/// than the A13, and the [renderer]'s own tier when it is lower. Liquid,
/// chosen or given as [tier], is installed as flat until the liquid tier
/// is ready and wherever it cannot load (the web), and turns liquid when
/// the tier resolves. An ancestor [BackdropGroup] is reused, otherwise
/// this widget installs one for its controls.
class GlassAdaptiveScope extends StatefulWidget {
  /// Installs [renderer] for [child] at [tier], or at the tier the device
  /// class allows when [tier] is null.
  const GlassAdaptiveScope({
    required this.child,
    this.renderer = const GlassBuiltInPainter(),
    this.tier,
    super.key,
  });

  /// The renderer; its tier is the best one the automatic choice uses.
  final GlassBuiltInPainter renderer;

  /// The tier to draw, or null to choose it by the device class.
  final MorphGlassTier? tier;

  /// The subtree that draws its glass with the renderer.
  final Widget child;

  /// The tier a device that cannot hold liquid glass draws.
  ///
  /// Flat: on the GLES fallback of a Pixel 6a glass that samples the
  /// backdrop misses the frame budget. Glass audit, 5 runs, medians,
  /// frames over 16.7 ms per scene (controls / home scroll / menu /
  /// segmented / sheet / tab bar, 2026-10-05): liquid 83 / 14 / 75 / 6 /
  /// 54 / 73, flat 0 / 5 / 20 / 0 / 1 / 3.
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
    if (deviceClass == MorphGlassDeviceClass.skia) return cheapTier;
    if (best != MorphGlassTier.liquid) return best;
    return switch (deviceClass) {
      MorphGlassDeviceClass.capable ||
      MorphGlassDeviceClass.unknown => MorphGlassTier.liquid,
      MorphGlassDeviceClass.gles ||
      MorphGlassDeviceClass.appleBeforeA13 ||
      MorphGlassDeviceClass.skia => cheapTier,
    };
  }

  /// The effective tier of the [GlassBuiltInPainter] installed above
  /// [context], or null when the painter above is not one.
  static MorphGlassTier? tierOf(BuildContext context) =>
      switch (MorphGlassScope.maybeOf(context)) {
        final GlassBuiltInPainter renderer => renderer.effectiveTier,
        _ => null,
      };

  @override
  State<GlassAdaptiveScope> createState() => _GlassAdaptiveScopeState();
}

class _GlassAdaptiveScopeState extends State<GlassAdaptiveScope> {
  MorphGlassDeviceClass _deviceClass = GlassAdaptiveScope.deviceClass;

  bool get _resolving =>
      _deviceClass == MorphGlassDeviceClass.unknown ||
      !GlassBuiltInPainter.liquidAvailable;

  @override
  void initState() {
    super.initState();
    if (_resolving) morphLiquidGlassCapability.addListener(_capabilityChanged);
  }

  void _capabilityChanged() {
    if (!mounted) return;
    setState(() => _deviceClass = GlassAdaptiveScope.deviceClass);
    if (!_resolving) {
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
    final asked =
        widget.tier ??
        GlassAdaptiveScope.tierFor(_deviceClass, widget.renderer.effectiveTier);
    // Liquid draws flat until the tier is ready, which the painter's ==
    // does not see: installing flat until then changes the painter on the
    // flip, so every dependent rebuilds with liquid glass.
    final tier =
        asked == MorphGlassTier.liquid && !GlassBuiltInPainter.liquidAvailable
        ? MorphGlassTier.flat
        : asked;
    final glass = MorphGlassScope(
      painter: widget.renderer.copyWith(tier: tier),
      child: widget.child,
    );
    return BackdropGroup.of(context) == null
        ? GlassPlaneScope.plane(child: glass)
        : glass;
  }
}
