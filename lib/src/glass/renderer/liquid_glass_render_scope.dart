import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';

@internal
class LiquidGlassRenderScope extends InheritedWidget {
  /// Creates a new [LiquidGlassRenderScope].
  const LiquidGlassRenderScope({
    required this.settings,
    required this.defaultAppearance,
    required super.child,
    this.useFake = false,
    this.consolidatesFakeBackdrop = false,
    this.consolidatesFakeSurface = false,
    this.backdropKey,
    this.settingsLive,
    super.key,
  });

  final LiquidGlassSettings settings;

  /// The settings of a live layer, which change without rebuilding the
  /// scope; null when [settings] is all there is.
  final ValueListenable<LiquidGlassSettings>? settingsLive;

  /// The settings now.
  LiquidGlassSettings get currentSettings => settingsLive?.value ?? settings;

  final LiquidGlassAppearance defaultAppearance;

  final bool useFake;

  /// Whether fake shapes register with the parent layer while omitting their
  /// individual backdrop filters.
  final bool consolidatesFakeBackdrop;

  /// Whether the parent layer paints each registered fake surface.
  final bool consolidatesFakeSurface;

  /// The backdrop capture shared by glass effects in this scope, if any.
  final BackdropKey? backdropKey;

  static LiquidGlassRenderScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    assert(
      scope != null,
      'No liquid glass renderer found in context. '
      'Make sure to wrap your liquid glass widgets in a LiquidGlassLayer.',
    );
    return scope!;
  }

  /// Returns the nearest [LiquidGlassRenderScope] from the widget tree,
  /// or `null` if there is none.
  static LiquidGlassRenderScope? maybeOf(
    BuildContext context, {
    bool watch = true,
  }) {
    if (watch) {
      return context
          .dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    } else {
      return context.getInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    }
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! LiquidGlassRenderScope ||
        oldWidget.settings != settings ||
        !identical(oldWidget.settingsLive, settingsLive) ||
        oldWidget.defaultAppearance != defaultAppearance ||
        oldWidget.useFake != useFake ||
        oldWidget.consolidatesFakeBackdrop != consolidatesFakeBackdrop ||
        oldWidget.consolidatesFakeSurface != consolidatesFakeSurface ||
        oldWidget.backdropKey != backdropKey;
  }
}
