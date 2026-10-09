import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show Matrix4;
import 'package:meta/meta.dart';

/// Borrowed, already filtered source for the standalone optical experiment.
///
/// The owner provides immutable image contents for recorded scenes and retains
/// GPU targets until those scenes retire. This object captures no Flutter UI
/// and takes no ownership of the images or the per-layer shader instance.
@internal
class OwnedGlassBackdrop {
  /// Maps layer-local logical coordinates into the source's logical plane.
  OwnedGlassBackdrop({
    required this.shader,
    required this.lower,
    required this.upper,
    required this.sourceSize,
    required this.layerToSource,
    this.mix = 0,
  });

  /// A private shader instance for one layer and one uniform appearance.
  final ui.FragmentShader shader;

  /// Lower requested blur level, or the full-size source for clear glass.
  final ui.Image lower;

  /// Upper requested blur level; may be identical to [lower].
  final ui.Image upper;

  /// Full-resolution source extent in physical pixels, independent of LOD.
  final ui.Size sourceSize;

  /// Affine mapping; perspective is not supported by this experiment.
  final Matrix4 layerToSource;

  /// Linear interpolation between the two requested levels.
  final double mix;
}
