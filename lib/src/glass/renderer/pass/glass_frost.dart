import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/internal/blur_reach.dart';

/// Whether a frost up to [GlassFrost.shaderMaxDeviceSigma] is blurred by
/// the final pass itself. On by default;
/// `--dart-define=MORPH_SHADER_FROST=false` blurs it in a separate pass.
bool debugMorphShaderFrost = const bool.fromEnvironment(
  'MORPH_SHADER_FROST',
  defaultValue: true,
);

/// Where a glass layer's frost is blurred: by the final pass's softening
/// kernel, by its 24-tap frost, or by a blur pass before it.
@internal
@immutable
final class GlassFrost {
  const GlassFrost._({
    required this.softens,
    required this.shaderSigma,
    required this.passSigma,
  });

  /// The frost of a layer whose settings blur by [frost] logical pixels
  /// with [dispersion], at [devicePixelRatio]; [ownBackdrop] for a layer
  /// that blurs a copy of its own backdrop (a lifted lens).
  factory GlassFrost.of({
    required double frost,
    required double dispersion,
    required double devicePixelRatio,
    required bool ownBackdrop,
  }) {
    final softens =
        frost > 0 && frost * devicePixelRatio <= softeningMaxDeviceSigma;
    var shaderSigma = 0.0;
    if (debugMorphShaderFrost &&
        !softens &&
        !ownBackdrop &&
        dispersion == 0 &&
        frost > 0) {
      final sigma =
          morphHalfResolutionSigma(frost, devicePixelRatio) * devicePixelRatio;
      if (sigma <= shaderMaxDeviceSigma) shaderSigma = sigma;
    }
    final double passSigma = softens || shaderSigma > 0
        ? 0
        : ownBackdrop
        ? frost
        : morphHalfResolutionSigma(frost, devicePixelRatio);
    return GlassFrost._(
      softens: softens,
      shaderSigma: shaderSigma,
      passSigma: passSigma,
    );
  }

  /// Largest frost, in device pixels, folded into the final pass's
  /// softening kernel instead of a separate blur pass. Enabling the blur
  /// pass costs about four command buffers per frame on Metal regardless of
  /// its radius.
  static const double softeningMaxDeviceSigma = 1.25;

  /// Largest frost, in device pixels, the final pass blurs itself when
  /// [debugMorphShaderFrost] is on.
  static const double shaderMaxDeviceSigma = 8;

  /// Whether the frost is small enough for the final pass's softening
  /// kernel.
  final bool softens;

  /// The frost the final pass blurs itself, in device pixels; 0 when it
  /// does not: off, no frost, a frost the softening kernel covers, a
  /// dispersed lens (its taps would split the channels), a layer that
  /// blurs a copy of its own backdrop.
  ///
  /// A frost just below the sigma Impeller blurs at half resolution is
  /// raised to it ([morphHalfResolutionSigma]).
  final double shaderSigma;

  /// Sigma of the separate backdrop blur pass in logical pixels; 0 when
  /// there is none.
  ///
  /// A frost just below the sigma Impeller blurs at half resolution is
  /// raised to it, unless the layer blurs its own backdrop: that blur is
  /// already small, and its frost animates.
  final double passSigma;
}
