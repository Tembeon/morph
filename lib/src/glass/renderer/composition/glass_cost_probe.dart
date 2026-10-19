import 'package:meta/meta.dart';

/// A device timing probe that replaces one part of every liquid layer's
/// composition; [GlassCostProbe.off] draws the glass as it is.
///
/// The probes change pixels: they exist to split the cost of a glass
/// surface on the device (tool/audit/2026-10-12-glass-composition.md).
@internal
GlassCostProbe debugGlassCostProbe = GlassCostProbe.off;

/// The part of a liquid layer's composition that [debugGlassCostProbe]
/// replaces, to time it on a device.
@internal
enum GlassCostProbe {
  /// The glass as it is.
  off,

  /// The glass filter is an identity color matrix: the backdrop read, the
  /// layer's offscreen pass and its composite stay, the frost blur and the
  /// glass shader go.
  copy,

  /// No backdrop filter at all: the floor the other probes are read from.
  skip,

  /// Every liquid layer reads one backdrop key: a single backdrop read per
  /// frame, each layer still filtered in its own offscreen pass.
  shared,

  /// The frost blur goes, the glass shader stays in the filter.
  nofrost,

  /// Every liquid layer draws its glass as a paint over opaque black: the
  /// glass shader over the layer's area without a backdrop read or an
  /// offscreen pass.
  solid,
}
