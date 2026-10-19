import 'package:meta/meta.dart';

/// The compiled variants of the liquid glass final pass
/// (shaders/liquid_glass_final_render.frag), the one table they are built
/// from: hook/build.dart compiles each to
/// `build/shaderbundles/<fileName>.iplr` with its [defines], and the asset
/// keys, the warm-up and tool/audit/shader/offline.py derive from it.
///
/// Each variant compiles only what its layers can meet, which keeps it
/// inside the Mali-G78's register budget. The matte variants are declared
/// in the order a layer binds them, the separate-shape and the fused
/// analytic variants in the order of the layer's analytic sets.
///
/// Pure Dart: the build hook imports it.
@internal
enum LiquidShaderVariant {
  /// One appearance for the layer, the direct color model (a lifted lens).
  direct(directModel: true),

  /// One appearance for the layer, an iOS 27 color model.
  ios27(ios27Models: true),

  /// Shapes with their own appearances, any color models blended per
  /// pixel.
  material(shapeAppearance: true, directModel: true, ios27Models: true),

  /// Shapes that differ only by tint, the direct color model.
  tint(shapeTint: true, directModel: true),

  /// Shapes that differ only by tint, an iOS 27 color model.
  tintIos27(shapeTint: true, ios27Models: true),

  /// [direct] with up to eight separate shapes evaluated in the pass
  /// instead of read from a geometry matte.
  analytic(analyticGeometry: true, directModel: true),

  /// [ios27] with separate shapes evaluated in the pass.
  analyticIos27(analyticGeometry: true, ios27Models: true),

  /// [tint] with separate shapes evaluated in the pass.
  analyticTint(analyticGeometry: true, shapeTint: true, directModel: true),

  /// [tintIos27] with separate shapes evaluated in the pass.
  analyticTintIos27(analyticGeometry: true, shapeTint: true, ios27Models: true),

  /// [direct] with a glass container's fused body of up to four boxes
  /// merged in the pass.
  analyticFused(analyticGeometry: true, fused: true, directModel: true),

  /// [ios27] with a fused body merged in the pass.
  analyticFusedIos27(analyticGeometry: true, fused: true, ios27Models: true),

  /// [tint] with a fused body merged in the pass, the tints from its
  /// shapes.
  analyticFusedTint(
    analyticGeometry: true,
    fused: true,
    shapeTint: true,
    directModel: true,
  ),

  /// [tintIos27] with a fused body merged in the pass, the tints from its
  /// shapes.
  analyticFusedTintIos27(
    analyticGeometry: true,
    fused: true,
    shapeTint: true,
    ios27Models: true,
  );

  const LiquidShaderVariant({
    this.shapeAppearance = false,
    this.shapeTint = false,
    this.directModel = false,
    this.ios27Models = false,
    this.analyticGeometry = false,
    this.fused = false,
  });

  /// Whether every shape carries its own appearance, read from a material
  /// map (SHAPE_APPEARANCE).
  final bool shapeAppearance;

  /// Whether the shapes differ only by tint (SHAPE_TINT).
  final bool shapeTint;

  /// Whether the direct color model is compiled in (DIRECT_MODEL).
  final bool directModel;

  /// Whether the iOS 27 color models are compiled in (IOS27_MODELS).
  final bool ios27Models;

  /// Whether the shapes are evaluated in the pass instead of read from a
  /// geometry matte (ANALYTIC_GEOMETRY).
  final bool analyticGeometry;

  /// Whether the body is a fused body of boxes merged in the pass
  /// (ANALYTIC_FUSED).
  final bool fused;

  /// The compiled file's name without its extension.
  String get fileName => [
    'liquid_glass_final_render',
    if (analyticGeometry) '_analytic',
    if (fused) '_fused',
    if (shapeAppearance) '_material',
    if (shapeTint) '_tint',
    if (ios27Models && !directModel) '_ios27',
  ].join();

  /// The preprocessor names the variant compiles with: `WITH_<switch>` for
  /// each switch it turns on, which the entry shader maps to 1 (impellerc's
  /// `--define` takes a name without a value).
  List<String> get defines => [
    if (shapeAppearance) 'WITH_SHAPE_APPEARANCE',
    if (shapeTint) 'WITH_SHAPE_TINT',
    if (directModel) 'WITH_DIRECT_MODEL',
    if (ios27Models) 'WITH_IOS27_MODELS',
    if (analyticGeometry) 'WITH_ANALYTIC_GEOMETRY',
    if (fused) 'WITH_ANALYTIC_FUSED',
  ];
}
