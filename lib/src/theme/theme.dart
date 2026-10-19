import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/theme/glass.dart';

/// A control's look as one value: its colors, metrics and materials.
///
/// Every control's appearance class implements this, so a
/// [MorphThemeData] can carry it in [MorphThemeData.appearances].
abstract interface class MorphAppearance {}

/// The settings every morph control below a `MorphTheme` reads.
@immutable
class MorphThemeData {
  /// Creates theme settings; every field has a working default.
  const MorphThemeData({
    this.brightness,
    this.tint,
    this.haptics = true,
    this.glass,
    this.appearances = const <MorphAppearance>[],
  });

  /// The appearance the controls draw in; null follows the platform.
  final Brightness? brightness;

  /// The accent the controls take, iOS's tint color; null keeps each
  /// control's own system color.
  final Color? tint;

  /// Whether the controls play haptic feedback where their UIKit
  /// counterparts do: a switch flipped by touch, a page control, a wheel
  /// or a menu row changing under the finger, a slider reaching an end or
  /// a stop, a context menu's preview.
  ///
  /// The haptics play through Flutter's [HapticFeedback]: the impact and
  /// selection ones as the same generators UIKit uses (near; UIKit tweaks
  /// the pattern per control), the slider's and the context menu's
  /// CoreHaptics patterns as the nearest impact (an approximation).
  final bool haptics;

  /// Which glass the controls draw, or null to keep the glass of the
  /// theme above; with no glass chosen above, the controls draw flat.
  final MorphGlassRenderer? glass;

  /// Looks that replace a control's built-in tables, at most one per type.
  ///
  /// A control's own `appearance` argument still wins over these.
  final List<MorphAppearance> appearances;

  /// The appearance of type [T] in [appearances], or null.
  T? appearance<T extends MorphAppearance>() {
    for (final appearance in appearances) {
      if (appearance is T) return appearance;
    }
    return null;
  }

  /// A copy with the given fields replaced.
  MorphThemeData copyWith({
    Brightness? brightness,
    Color? tint,
    bool? haptics,
    MorphGlassRenderer? glass,
    List<MorphAppearance>? appearances,
  }) => MorphThemeData(
    brightness: brightness ?? this.brightness,
    tint: tint ?? this.tint,
    haptics: haptics ?? this.haptics,
    glass: glass ?? this.glass,
    appearances: appearances ?? this.appearances,
  );

  @override
  bool operator ==(Object other) =>
      other is MorphThemeData &&
      other.brightness == brightness &&
      other.tint == tint &&
      other.haptics == haptics &&
      other.glass == glass &&
      listEquals(other.appearances, appearances);

  @override
  int get hashCode => Object.hash(
    brightness,
    tint,
    haptics,
    glass,
    Object.hashAll(appearances),
  );
}

/// Publishes a theme's [data] to the controls below it.
///
/// An [InheritedTheme], so menus, sheets and alerts shown from a themed
/// subtree carry the theme into their routes.
@internal
class MorphThemeScope extends InheritedTheme {
  /// Publishes [data] to [child].
  const MorphThemeScope({required this.data, required super.child, super.key});

  /// The settings this theme applies.
  final MorphThemeData data;

  /// The nearest theme's settings, or null when there is no theme.
  static MorphThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MorphThemeScope>()?.data;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      MorphThemeScope(data: data, child: child);

  @override
  bool updateShouldNotify(MorphThemeScope oldWidget) => oldWidget.data != data;
}

/// The brightness the controls at [context] draw in.
@internal
Brightness morphBrightnessOf(BuildContext context) =>
    MorphThemeScope.maybeOf(context)?.brightness ??
    MediaQuery.maybePlatformBrightnessOf(context) ??
    Brightness.light;

/// Whether the platform asks for reduced motion.
@internal
bool morphReducedMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Whether the platform asks for higher contrast.
@internal
bool morphHighContrastOf(BuildContext context) =>
    MediaQuery.maybeHighContrastOf(context) ?? false;

/// Whether the controls at [context] play haptics.
@internal
bool morphHapticsOf(BuildContext context) =>
    MorphThemeScope.maybeOf(context)?.haptics ?? true;

/// The theme's tint at [context], or null.
@internal
Color? morphTintOf(BuildContext context) =>
    MorphThemeScope.maybeOf(context)?.tint;

final Expando<Map<Color, Object>> _tinted = Expando('morph tinted tables');

/// Resolves a control's appearance: [explicit], else the theme's
/// appearance of type [T], else the built-in table for the brightness
/// and contrast, tinted by the theme's tint when [tinted] is given.
@internal
T morphResolveAppearance<T extends MorphAppearance>(
  BuildContext context,
  T? explicit, {
  required T light,
  required T dark,
  T? lightHighContrast,
  T? darkHighContrast,
  T Function(T table, Color tint)? tinted,
}) {
  if (explicit != null) return explicit;
  final theme = MorphThemeScope.maybeOf(context);
  final own = theme?.appearance<T>();
  if (own != null) return own;
  final isDark = morphBrightnessOf(context) == Brightness.dark;
  final contrast = morphHighContrastOf(context)
      ? (isDark ? darkHighContrast : lightHighContrast)
      : null;
  final table = contrast ?? (isDark ? dark : light);
  final tint = theme?.tint;
  if (tint == null || tinted == null) return table;
  final cache = _tinted[table] ??= <Color, Object>{};
  return cache.putIfAbsent(tint, () => tinted(table, tint)) as T;
}
