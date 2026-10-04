import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// Whether this build carries the liquid tier: not on the web.
@internal
const bool morphLiquidGlassAvailable = false;

/// The web's permanently unavailable liquid capability.
@internal
ValueListenable<bool> get morphLiquidGlassCapability => _capability;

final ValueNotifier<bool> _capability = ValueNotifier(false);

/// Completes at once: there are no liquid glass shaders to load.
@internal
Future<void> morphPrecacheLiquidGlass() async {}

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
