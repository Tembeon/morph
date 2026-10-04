import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/liquid_capability.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// Whether this build carries the liquid tier: not on the web.
@internal
bool get morphLiquidGlassAvailable {
  unawaited(_capability.precache());
  return false;
}

/// The cached web capability failure, or null before initialization.
@internal
String? get morphLiquidGlassUnavailableReason => _capability.unavailableReason;

/// The web's permanently unavailable liquid capability.
@internal
ValueListenable<bool> get morphLiquidGlassCapability => _capability;

final LiquidCapability _capability = LiquidCapability(
  load: () async {
    throw UnsupportedError('The web has no liquid glass tier.');
  },
);

/// Reports the unavailable web tier once and caches its reason.
@internal
Future<void> morphPrecacheLiquidGlass() => _capability.precache();

/// Never called on the web, where [MorphGlassRenderer.effectiveTier] is at
/// most frosted.
@internal
Widget morphLiquidSurface(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassSurface surface,
) => throw UnsupportedError('The web has no liquid glass tier.');

/// Never called on the web, where [MorphGlassRenderer.effectiveTier] is at
/// most frosted.
@internal
Widget morphLiquidBody(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassOutline outline,
  List<MorphGlassSurface> surfaces,
) => throw UnsupportedError('The web has no liquid glass tier.');

/// Never called on the web, where [MorphGlassRenderer.effectiveTier] is at
/// most frosted.
@internal
Widget morphLiquidLayer(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassLayerParts parts, {
  Widget? content,
  List<Rect> contentSlots = const [],
}) => throw UnsupportedError('The web has no liquid glass tier.');
