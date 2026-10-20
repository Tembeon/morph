import 'package:flutter/widgets.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glass_tier.dart';

/// Applies [data] to the morph controls below it and installs the glass
/// [MorphThemeData.glass] chooses.
///
/// ```dart
/// MorphTheme(
///   data: const MorphThemeData(glass: MorphGlassRenderer.adaptive()),
///   child: child,
/// )
/// ```
///
/// Place it above the app's navigator, in `WidgetsApp.builder` for
/// example, so routes pushed by the app share one theme. Menus, sheets and
/// alerts shown from a themed subtree carry the theme into their routes.
/// Controls with no theme above them use the defaults and draw flat.
///
/// Liquid glass needs Impeller with Flutter GPU: `FLTEnableFlutterGPU` in
/// the Apple app's Info.plist, `io.flutter.embedding.android.EnableFlutterGPU`
/// in the Android manifest. The first theme whose glass may be liquid loads
/// the shaders, warms their pipelines and holds the app's first frame until
/// they are ready, for at most a second, as [Localizations] holds it for
/// its resources: the first frame already draws liquid glass, and the app
/// awaits nothing. Until the shaders are ready, and where they fail or
/// cannot load (the web), liquid draws flat glass, and glass drawn flat
/// turns liquid once they are ready. Native builds package the GPU shader
/// bundle from the package's build hook in `build/shaderbundles/`.
///
/// A theme that chooses glass installs a [BackdropGroup] unless one is
/// above it. Resting glass in one group shares one copy of the screen,
/// taken where the group's first glass paints, so glass painted after
/// other content misses that content - a button on a card drawn over a
/// list whose own glass painted first shows the list as it stood before
/// the card. Give such a section a group of its own:
///
/// ```dart
/// BackdropGroup(child: card)
/// ```
///
/// Its glass then reads a copy taken where the section paints, at the
/// price of one more full-screen copy per frame while anything in it
/// moves. Bars, menus, sheets and lifted glass already take their own.
class MorphTheme extends StatelessWidget {
  /// Themes [child] with [data].
  const MorphTheme({required this.data, required this.child, super.key});

  /// The settings this theme applies.
  final MorphThemeData data;

  /// The subtree the theme applies to.
  final Widget child;

  /// The nearest theme's settings, or null when there is no [MorphTheme].
  static MorphThemeData? maybeOf(BuildContext context) =>
      MorphThemeScope.maybeOf(context);

  /// The nearest theme's settings, or the defaults.
  static MorphThemeData of(BuildContext context) =>
      maybeOf(context) ?? const MorphThemeData();

  /// Loads the liquid tier's shaders and draws every glass pipeline once
  /// offscreen, so the first glass on screen is already the real one and
  /// compiles nothing.
  ///
  /// A theme does this by itself before the app's first frame; call it to
  /// start earlier, or to load for glass installed without a theme. The
  /// warm-up takes about 0.35 to 0.45 s on a Pixel 6a (Vulkan) and moves
  /// that cost from the first glass frame to the launch. It completes
  /// after at most one second; a GPU that is slower to start finishes the
  /// warm-up in the background. On Android it can wait for the engine's
  /// GPU context; it does not wait for an application frame.
  ///
  /// Unsupported runtimes and shader loading failures complete normally,
  /// report once through [FlutterError.reportError] with library
  /// `morph glass`, and expose the cause through
  /// [liquidGlassUnavailableReason].
  static Future<void> precacheGlass() => GlassBuiltInPainter.precache();

  /// Whether the runtime GPU context and liquid shaders are ready.
  ///
  /// False on the web, whose shader compiler cannot build the renderer's
  /// shaders, and until the shaders are loaded elsewhere; meanwhile liquid
  /// glass draws flat glass.
  static bool get liquidGlassAvailable => GlassBuiltInPainter.liquidAvailable;

  /// The reason liquid glass initialization failed on this runtime.
  ///
  /// Null until initialization fails, including while it is pending and
  /// after it succeeds; await [precacheGlass] before reading a resolved
  /// result. The web reports that it has no liquid glass tier.
  static String? get liquidGlassUnavailableReason =>
      GlassBuiltInPainter.liquidUnavailableReason;

  @override
  Widget build(BuildContext context) => MorphThemeScope(
    data: data,
    child: switch (data.glass) {
      null => child,
      final glass => GlassAdaptiveScope(tier: glass.fixedTier, child: child),
    },
  );
}
