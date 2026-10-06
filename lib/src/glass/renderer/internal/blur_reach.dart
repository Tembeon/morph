import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

/// The device-pixel sigma Impeller blurs with for [sigma] logical pixels
/// at [devicePixelRatio]: its sigma correction, then the canvas scale.
@internal
double morphImpellerBlurSigma(double sigma, double devicePixelRatio) {
  final clamped = math.min(sigma, 500.0);
  return clamped *
      (1 - 3.4e-3 * clamped + 3.4e-6 * clamped * clamped) *
      devicePixelRatio;
}

/// The logical pixels around a region that Impeller's Gaussian blur of
/// [sigma] logical pixels reads at [devicePixelRatio].
///
/// The engine's kernel reaches 1.732 of its device sigma, and the texels
/// its downsample and upsample add, rounded up to whole device pixels.
@internal
double morphBlurReach(double sigma, double devicePixelRatio) {
  final scaled = morphImpellerBlurSigma(sigma, devicePixelRatio);
  final scale = scaled <= 4
      ? 1.0
      : math
            .pow(
              2.0,
              math.max(-4.0, (math.log(4 / scaled) / math.ln2).roundToDouble()),
            )
            .toDouble();
  return (1.7320508 * scaled + 2 / scale + 2).ceilToDouble() / devicePixelRatio;
}

/// The device sigma from which Impeller blurs at half resolution: below
/// it the downsample factor rounds to 1, and the blur runs over every
/// device pixel.
const double _halfResolutionDeviceSigma = 4 * math.sqrt2;

/// Whether [morphHalfResolutionSigma] raises a sigma; off keeps every
/// sigma as given, for an A/B.
@visibleForTesting
bool debugMorphHalfResolutionBlur = true;

/// How much [morphHalfResolutionSigma] raises a sigma at most.
@internal
const double morphHalfResolutionMaxRaise = 1.12;

/// [sigma] raised to the smallest sigma Impeller blurs at half resolution
/// at [devicePixelRatio], when that is at most
/// [morphHalfResolutionMaxRaise] times larger; else [sigma] itself.
///
/// Just below that threshold Impeller blurs every device pixel and costs
/// about three times its half-resolution blur on a Mali GPU; the half
/// resolution blur of the raised sigma differs from the full resolution
/// one by a few channel steps under glass.
@internal
double morphHalfResolutionSigma(double sigma, double devicePixelRatio) {
  if (!debugMorphHalfResolutionBlur) return sigma;
  if (sigma <= 0 || devicePixelRatio <= 0) return sigma;
  if (morphImpellerBlurSigma(sigma, devicePixelRatio) >=
      _halfResolutionDeviceSigma) {
    return sigma;
  }
  final target = _halfResolutionDeviceSigma * 1.001 / devicePixelRatio;
  var raised = target;
  for (var i = 0; i < 4; i++) {
    raised = target / (1 - 3.4e-3 * raised + 3.4e-6 * raised * raised);
  }
  return raised <= sigma * morphHalfResolutionMaxRaise ? raised : sigma;
}

/// A backdrop filter that copies its backdrop: an identity color matrix,
/// within a channel step or two of its half-precision rounding.
///
/// Under a clip it gives the backdrop filters inside it a pass of the
/// clip's size: a blur there reads that pass instead of the whole pass
/// behind it. (An identity matrix filter does not: the blur inside it
/// reads an empty pass on Impeller.)
@internal
const ui.ImageFilter morphBackdropSeed = ui.ColorFilter.matrix(<double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
]);
