import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// The display refresh rate the gallery asks the system for.
///
/// Applied on Android only, where a device may hold an app at a lower rate
/// than its panel offers; other platforms ignore it.
enum GalleryFrameRate {
  /// The system picks the rate.
  auto(0),

  /// The display mode closest to 60 Hz.
  hz60(60),

  /// The display mode closest to 120 Hz.
  hz120(120);

  const GalleryFrameRate(this.hertz);

  /// The rate asked for in hertz, 0 for the system's choice.
  final double hertz;
}

/// The channel that carries the frame rate to the Android activity.
const MethodChannel galleryDisplayChannel = MethodChannel(
  'dev.tembeon.morph_example/display',
);

/// The session-wide look of the gallery, edited on the glass page and
/// applied to every page at once.
///
/// The values live as long as the app does; nothing is written to disk.
///
/// The glass tier starts as `--dart-define=GALLERY_GLASS=<name>` says:
/// auto (the default: [MorphAdaptiveGlass] picks it by the device's
/// GPU), liquid, fake or flat. A build without the liquid tier
/// (the web) draws fake glass in its place.
class GalleryGlassSettings extends ChangeNotifier {
  MorphGlassTier? _tier = switch (const String.fromEnvironment(
    'GALLERY_GLASS',
    defaultValue: 'auto',
  )) {
    'auto' => null,
    final String name => MorphGlassTier.values.byName(name),
  };
  MorphGlassMaterial _material = MorphGlassMaterial.regular;
  double _blur = 1;
  double _refraction = 1;
  double _light = 1;
  double _tint = 0;
  bool _frostControls = false;
  ThemeMode _appearance = ThemeMode.system;
  bool _rtl = false;
  bool _disabled = false;
  bool _inspector = false;
  GalleryFrameRate _frameRate = GalleryFrameRate.auto;

  void _set<T>(T current, T next, void Function() write) {
    if (current == next) return;
    write();
    notifyListeners();
  }

  /// The glass tier, or null to let the device's GPU pick it.
  MorphGlassTier? get tier => _tier;
  set tier(MorphGlassTier? value) => _set(_tier, value, () => _tier = value);

  /// The material preset of the liquid tier.
  MorphGlassMaterial get material => _material;
  set material(MorphGlassMaterial value) =>
      _set(_material, value, () => _material = value);

  /// The factor on the preset's frost.
  double get blur => _blur;
  set blur(double value) => _set(_blur, value, () => _blur = value);

  /// The factor on the preset's refraction.
  double get refraction => _refraction;
  set refraction(double value) =>
      _set(_refraction, value, () => _refraction = value);

  /// The factor on the preset's rim glint.
  double get light => _light;
  set light(double value) => _set(_light, value, () => _light = value);

  /// The Liquid Glass slider of iOS Settings, 0 clear and 1 tinted.
  ///
  /// Starts at 0, Clear, the closest to the owner's iPhone 16 Pro: there
  /// the bars frost by the renderer's 2 pt.
  double get tint => _tint;
  set tint(double value) => _set(_tint, value, () => _tint = value);

  /// Whether tracks and buttons frost as bars and menus do.
  bool get frostControls => _frostControls;
  set frostControls(bool value) =>
      _set(_frostControls, value, () => _frostControls = value);

  /// Light, dark or the system appearance.
  ThemeMode get appearance => _appearance;
  set appearance(ThemeMode value) =>
      _set(_appearance, value, () => _appearance = value);

  /// Whether the whole gallery lays out right to left.
  bool get rtl => _rtl;
  set rtl(bool value) => _set(_rtl, value, () => _rtl = value);

  /// Whether the demo controls of every page are disabled.
  bool get disabled => _disabled;
  set disabled(bool value) => _set(_disabled, value, () => _disabled = value);

  /// Whether the glass inspector counts the glass layers of every frame
  /// over the gallery (debug and profile builds).
  bool get inspector => _inspector;
  set inspector(bool value) =>
      _set(_inspector, value, () => _inspector = value);

  /// The display refresh rate asked for, applied at once on Android.
  GalleryFrameRate get frameRate => _frameRate;
  set frameRate(GalleryFrameRate value) => _set(_frameRate, value, () {
    _frameRate = value;
    _applyFrameRate(value);
  });

  Future<void> _applyFrameRate(GalleryFrameRate value) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await galleryDisplayChannel.invokeMethod<void>(
        'setFrameRate',
        value.hertz,
      );
    } on PlatformException {
      // The activity may not answer; the rate stays where it was.
    } on MissingPluginException {
      // No activity behind the channel, as in a widget test.
    }
  }

  /// The renderer these settings describe, at the best tier the build
  /// has; [tier] picks the one drawn.
  MorphGlassRenderer get renderer => MorphGlassRenderer(
    tier: MorphGlassRenderer.bestTier,
    material: _material,
    blur: _blur,
    refraction: _refraction,
    light: _light,
    tint: _tint,
    frostControls: _frostControls,
  );
}

/// Hands the gallery's [GalleryGlassSettings] to every page.
class GalleryGlassScope extends InheritedNotifier<GalleryGlassSettings> {
  /// Provides [settings] to [child].
  const GalleryGlassScope({
    required GalleryGlassSettings settings,
    required super.child,
    super.key,
  }) : super(notifier: settings);

  static final _defaults = GalleryGlassSettings();

  /// The settings above [context], or the defaults outside a scope.
  static GalleryGlassSettings of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GalleryGlassScope>()
          ?.notifier ??
      _defaults;

  /// [callback] while the gallery's demo controls are enabled, else null.
  static T? enabled<T extends Function>(BuildContext context, T callback) =>
      of(context).disabled ? null : callback;
}
