import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
// The renderer's material, frost, refraction and light knobs are not
// public API; this file is the gallery's renderer lab.
// ignore_for_file: implementation_imports
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glass_tier.dart';
import 'package:morph/morph.dart';
import 'package:morph/glass_painter.dart';

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
/// auto (the default: the theme picks it by the device's GPU), liquid,
/// fake or flat. A build without the liquid tier
/// (the web) draws fake glass in its place.
class GalleryGlassSettings extends ChangeNotifier {
  /// The tier name a new settings object starts with; the device benches
  /// set it at launch so one build serves every tier.
  static String initialTier = const String.fromEnvironment(
    'GALLERY_GLASS',
    defaultValue: 'auto',
  );

  MorphGlassTier? _tier = switch (initialTier) {
    'auto' => null,
    final String name => MorphGlassTier.values.byName(name),
  };
  MorphGlassMaterial _material = MorphGlassMaterial.regular;
  double _blur = 1;
  double _refraction = 1;
  double _light = 1;
  double _tint = 0;
  bool _frostControls = false;
  Brightness? _appearance;
  bool _rtl = false;
  bool _disabled = false;
  bool _inspector = false;
  GalleryFrameRate _frameRate = GalleryFrameRate.auto;
  bool _reduceMotion = false;
  bool _highContrast = false;
  bool _haptics = true;
  Color? _accent;

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

  /// Light, dark, or null for the system appearance.
  Brightness? get appearance => _appearance;
  set appearance(Brightness? value) =>
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

  /// Whether the gallery reduces motion as iOS Settings > Accessibility >
  /// Motion > Reduce Motion does, on top of the platform's own setting.
  bool get reduceMotion => _reduceMotion;
  set reduceMotion(bool value) =>
      _set(_reduceMotion, value, () => _reduceMotion = value);

  /// Whether the controls draw their high-contrast looks, as iOS Settings
  /// > Accessibility > Display > Increase Contrast does, on top of the
  /// platform's own setting.
  bool get highContrast => _highContrast;
  set highContrast(bool value) =>
      _set(_highContrast, value, () => _highContrast = value);

  /// Whether the controls play their haptics.
  bool get haptics => _haptics;
  set haptics(bool value) => _set(_haptics, value, () => _haptics = value);

  /// The accent of every control that draws one, or null for systemBlue.
  Color? get accent => _accent;
  set accent(Color? value) => _set(_accent, value, () => _accent = value);

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
  GlassBuiltInPainter get renderer => GlassBuiltInPainter(
    tier: GlassBuiltInPainter.bestTier,
    material: _material,
    blur: _blur,
    refraction: _refraction,
    light: _light,
    tint: _tint,
    frostControls: _frostControls,
  );
}

/// The parts of [GalleryGlassSettings] a widget can depend on alone.
enum GalleryGlassAspect {
  /// The glass tier and the renderer's look: material, frost, refraction,
  /// light, tint and frosted controls.
  glass,

  /// Light, dark or the system appearance.
  appearance,

  /// The text direction.
  rtl,

  /// Whether the demo controls are disabled.
  disabled,

  /// Whether the glass inspector runs.
  inspector,

  /// The display refresh rate.
  frameRate,

  /// Reduce Motion and Increase Contrast.
  accessibility,

  /// The haptics and the accent.
  theming,
}

/// Rebuilds the [GalleryGlassScope] under it whenever [settings] change,
/// so only the widgets that depend on a changed aspect rebuild.
class GalleryGlassHost extends StatefulWidget {
  /// Hands [settings] to [child].
  const GalleryGlassHost({
    required this.settings,
    required this.child,
    super.key,
  });

  /// The settings handed down.
  final GalleryGlassSettings settings;

  /// The widget below.
  final Widget child;

  @override
  State<GalleryGlassHost> createState() => _GalleryGlassHostState();
}

class _GalleryGlassHostState extends State<GalleryGlassHost> {
  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_changed);
  }

  @override
  void didUpdateWidget(GalleryGlassHost old) {
    super.didUpdateWidget(old);
    if (old.settings == widget.settings) return;
    old.settings.removeListener(_changed);
    widget.settings.addListener(_changed);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      GalleryGlassScope._(widget.settings, child: widget.child);
}

/// Hands the gallery's [GalleryGlassSettings] to every page, and rebuilds
/// a dependent only when the [GalleryGlassAspect] it reads changes.
class GalleryGlassScope extends InheritedModel<GalleryGlassAspect> {
  GalleryGlassScope._(this.settings, {required super.child})
    : _glass = (settings.tier, settings.renderer),
      _appearance = settings.appearance,
      _rtl = settings.rtl,
      _disabled = settings.disabled,
      _inspector = settings.inspector,
      _frameRate = settings.frameRate,
      _accessibility = (settings.reduceMotion, settings.highContrast),
      _theming = (settings.haptics, settings.accent);

  /// The settings handed down.
  final GalleryGlassSettings settings;

  final (MorphGlassTier?, GlassBuiltInPainter) _glass;
  final Brightness? _appearance;
  final bool _rtl;
  final bool _disabled;
  final bool _inspector;
  final GalleryFrameRate _frameRate;
  final (bool, bool) _accessibility;
  final (bool, Color?) _theming;

  static final _defaults = GalleryGlassSettings();

  Object? _value(GalleryGlassAspect aspect) => switch (aspect) {
    .glass => _glass,
    .appearance => _appearance,
    .rtl => _rtl,
    .disabled => _disabled,
    .inspector => _inspector,
    .frameRate => _frameRate,
    .accessibility => _accessibility,
    .theming => _theming,
  };

  @override
  bool updateShouldNotify(GalleryGlassScope old) =>
      GalleryGlassAspect.values.any((a) => _value(a) != old._value(a));

  @override
  bool updateShouldNotifyDependent(
    GalleryGlassScope old,
    Set<GalleryGlassAspect> dependencies,
  ) => dependencies.any((a) => _value(a) != old._value(a));

  /// The settings above [context], or the defaults outside a scope;
  /// [context] rebuilds when [aspect] changes, or any aspect when null.
  static GalleryGlassSettings of(
    BuildContext context, [
    GalleryGlassAspect? aspect,
  ]) =>
      InheritedModel.inheritFrom<GalleryGlassScope>(
        context,
        aspect: aspect,
      )?.settings ??
      _defaults;

  /// The settings above [context] without depending on them, for a
  /// caller that only writes them.
  static GalleryGlassSettings read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GalleryGlassScope>()?.settings ??
      _defaults;

  /// [callback] while the gallery's demo controls are enabled, else null.
  static T? enabled<T extends Function>(BuildContext context, T callback) =>
      of(context, .disabled).disabled ? null : callback;
}

/// Draws the glass below with the renderer settings of the
/// [GalleryGlassScope], at the tier the theme above installs.
class GalleryGlassTuning extends StatelessWidget {
  /// Tunes the glass of [child].
  const GalleryGlassTuning({required this.child, super.key});

  /// The subtree whose glass is tuned.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final renderer = GalleryGlassScope.of(context, .glass).renderer;
    final tier = GlassAdaptiveScope.tierOf(context) ?? renderer.tier;
    return MorphGlassScope(
      painter: renderer.copyWith(tier: tier),
      child: child,
    );
  }
}
