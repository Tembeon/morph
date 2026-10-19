import 'package:flutter/foundation.dart';

/// The quality tiers of the built-in glass, cheapest first.
///
/// Every tier draws the same shapes: the package computes each surface's
/// outline, the fused silhouettes of a menu and its button or of a bar's
/// capsules, the lens deformation and the content placement once, and a
/// tier only decides how the outline is shaded. A device whose GPU cannot
/// hold liquid glass draws a cheaper tier and the controls keep their
/// geometry, their motion and their fusion.
enum MorphGlassTier {
  /// A flat fill of each outline in the surface's color, no backdrop
  /// sampling: the cheapest tier, for weak devices.
  flat,

  /// Fake glass: the liquid material without refraction. The backdrop is
  /// frosted and color-filtered as the liquid tier's face transfer does,
  /// and each surface's rim, bevel and highlight are drawn analytically
  /// along its shape; a fused body is clipped to its outline, each region
  /// faced by its largest surface. No lens optics (magnification and
  /// backdrop shrink), no Flutter GPU, so it runs wherever Flutter runs,
  /// the web included.
  fake,

  /// Liquid glass: refraction at the rim, magnification and the measured
  /// lens optics, frost and rim light, rendered on the GPU by the package's
  /// glass renderer. Needs Impeller with Flutter GPU (iOS, macOS,
  /// Android); elsewhere the renderer draws [fake] in its place.
  liquid,
}

/// Which glass the controls draw: chosen by the device, or one fixed tier.
@immutable
sealed class MorphGlassRenderer {
  const MorphGlassRenderer();

  /// Liquid glass where the GPU holds it; flat glass on the GPUs where
  /// sampling the backdrop misses the frame budget (the OpenGL ES
  /// fallback, Skia, Apple GPUs before the A13); fake glass where the
  /// liquid tier cannot load, such as the web.
  ///
  /// The choice is made once from the GPU's capabilities, never from frame
  /// timings, so the glass never changes its look while the app runs.
  const factory MorphGlassRenderer.adaptive() = _AdaptiveGlass;

  /// Always [tier]; a build without the liquid tier draws fake glass for
  /// [MorphGlassTier.liquid].
  const factory MorphGlassRenderer.tier(MorphGlassTier tier) = _FixedGlass;

  /// The fixed tier, or null when the device chooses.
  @internal
  MorphGlassTier? get fixedTier;
}

final class _AdaptiveGlass extends MorphGlassRenderer {
  const _AdaptiveGlass();

  @override
  MorphGlassTier? get fixedTier => null;

  @override
  bool operator ==(Object other) => other is _AdaptiveGlass;

  @override
  int get hashCode => (_AdaptiveGlass).hashCode;
}

final class _FixedGlass extends MorphGlassRenderer {
  const _FixedGlass(this.fixedTier);

  @override
  final MorphGlassTier fixedTier;

  @override
  bool operator ==(Object other) =>
      other is _FixedGlass && other.fixedTier == fixedTier;

  @override
  int get hashCode => fixedTier.hashCode;
}
