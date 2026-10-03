import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/glass_page.dart';
import 'package:morph_example/gallery/liquid_glass_painter.dart';

/// Which painter draws the glass of every gallery control.
enum GalleryGlassRenderer {
  /// The liquid glass renderer: refraction, frost and rim light on the GPU.
  liquid,

  /// [FrostedGlassPainter]: a blurred, tinted backdrop without refraction.
  frosted,

  /// No painter: the controls draw their own flat fills.
  flat,
}

/// The session-wide look of the gallery, edited on the glass page and
/// applied to every page at once.
///
/// The values live as long as the app does; nothing is written to disk.
///
/// The renderer starts as `--dart-define=GALLERY_GLASS=<name>` says
/// (liquid, frosted or flat), liquid by default.
class GalleryGlassSettings extends ChangeNotifier {
  GalleryGlassRenderer _renderer = GalleryGlassRenderer.values.byName(
    const String.fromEnvironment('GALLERY_GLASS', defaultValue: 'liquid'),
  );
  LiquidGlassMaterial _material = LiquidGlassMaterial.regular;
  double _blur = 1;
  double _refraction = 1;
  double _light = 1;
  double _tint = 0;
  bool _fake = false;
  bool _frostControls = false;
  ThemeMode _appearance = ThemeMode.system;
  bool _rtl = false;
  bool _disabled = false;
  bool _grid = false;

  void _set<T>(T current, T next, void Function() write) {
    if (current == next) return;
    write();
    notifyListeners();
  }

  /// Which painter draws the glass.
  GalleryGlassRenderer get renderer => _renderer;
  set renderer(GalleryGlassRenderer value) =>
      _set(_renderer, value, () => _renderer = value);

  /// The material preset of the liquid glass.
  LiquidGlassMaterial get material => _material;
  set material(LiquidGlassMaterial value) =>
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
  double get tint => _tint;
  set tint(double value) => _set(_tint, value, () => _tint = value);

  /// Whether the liquid glass draws its fallback without refraction even
  /// where the GPU path is available.
  bool get fake => _fake;
  set fake(bool value) => _set(_fake, value, () => _fake = value);

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

  /// Whether the glass page's scene stands on the measurement grid
  /// ([GlassGrid]) instead of its colorful backdrop.
  bool get grid => _grid;
  set grid(bool value) => _set(_grid, value, () => _grid = value);

  /// The painter these settings select, or null for flat fills.
  MorphGlassPainter? get painter => switch (_renderer) {
    GalleryGlassRenderer.liquid => LiquidGlassRendererPainter(
      material: _material,
      blur: _blur,
      refraction: _refraction,
      light: _light,
      tint: _tint,
      fake: _fake,
      frostControls: _frostControls,
    ),
    GalleryGlassRenderer.frosted => const FrostedGlassPainter(),
    GalleryGlassRenderer.flat => null,
  };
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
