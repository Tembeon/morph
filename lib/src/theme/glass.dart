import 'package:flutter/foundation.dart';

/// The two looks of the built-in glass, cheapest first.
///
/// Both tiers draw the same shapes: the package computes each surface's
/// outline, the fused silhouettes of a menu and its button or of a bar's
/// capsules, the lens deformation and the content placement once, and a
/// tier only decides how the outline is shaded. A device whose GPU cannot
/// hold liquid glass draws flat and the controls keep their geometry,
/// their motion and their fusion.
enum MorphGlassTier {
  /// A flat fill of each outline in the surface's color, no backdrop
  /// sampling: runs wherever Flutter runs, the web included.
  flat,

  /// Liquid glass: refraction at the rim, magnification and the measured
  /// lens optics, frost and rim light, rendered on the GPU by the package's
  /// glass renderer. Needs Impeller with Flutter GPU (iOS, macOS,
  /// Android); elsewhere, and until its shaders are ready, the renderer
  /// draws [flat] in its place.
  liquid,
}

/// Which glass the controls draw: chosen by the device, or one fixed tier.
@immutable
sealed class MorphGlassRenderer {
  const MorphGlassRenderer();

  /// Liquid glass where the GPU holds it; flat glass everywhere else: on
  /// the GPUs where sampling the backdrop misses the frame budget (the
  /// OpenGL ES fallback, Skia, Apple GPUs before the A13) and where the
  /// liquid tier cannot load, such as the web.
  ///
  /// The choice is made once from the GPU's capabilities, never from frame
  /// timings. The first [MorphTheme] that chooses it loads the liquid
  /// shaders and holds the app's first frame until they are ready, for at
  /// most a second; glass drawn before then is flat and turns liquid when
  /// they are.
  const factory MorphGlassRenderer.adaptive() = _AdaptiveGlass;

  /// Always [tier]; a build without the liquid tier, or a runtime whose
  /// liquid shaders are not ready yet, draws flat glass for
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
