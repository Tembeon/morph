/// Liquid Glass Effect for Flutter
library;

import 'package:flutter/foundation.dart' show kDebugMode;

export 'package:morph/src/glass/renderer/fake_glass.dart' show FakeGlass;
export 'package:morph/src/glass/renderer/glass_glow.dart' show GlassGlow, GlassGlowLayer;
export 'package:morph/src/glass/renderer/internal/glass_drag_builder.dart' show GestureMode;
export 'package:morph/src/glass/renderer/liquid_glass.dart' show LiquidGlass;
export 'package:morph/src/glass/renderer/liquid_glass_appearance.dart' show LiquidGlassAppearance;
export 'package:morph/src/glass/renderer/liquid_glass_blend_group.dart' show LiquidGlassBlendGroup;
export 'package:morph/src/glass/renderer/liquid_glass_capture.dart' show LiquidGlassCapture;
export 'package:morph/src/glass/renderer/liquid_glass_color_model.dart'
    show
        DirectLiquidGlassColorModel,
        Ios27LiquidGlassColorModel,
        LiquidGlassColorModel;
export 'package:morph/src/glass/renderer/liquid_glass_settings.dart' show LiquidGlassSettings;
export 'package:morph/src/glass/renderer/liquid_glass_visibility.dart' show LiquidGlassVisibility;
export 'package:morph/src/glass/renderer/liquid_shape.dart';
export 'package:morph/src/glass/renderer/logging.dart' show LgrLogs;
export 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart' show LiquidGlassLayer;
export 'package:morph/src/glass/renderer/stretch.dart'
    show LiquidStretch, OffsetResistanceExtension, RawLiquidStretch;

/// Whether to paint the liquid glass geometry texture for debugging purposes.
///
/// When enabled, geometry textures will be drawn directly instead of the
/// liquid glass effect.
///
/// Will be set to `false` in release builds.
@pragma('vm:platform-const-if', !kDebugMode)
bool debugPaintLiquidGlassGeometry = false;
