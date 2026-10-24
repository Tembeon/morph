import 'package:flutter/widgets.dart';

/// Optional app-authored contours, independent of the glass tier and motion.
///
/// Native controls have no added contour by default. A fused body draws one
/// contour from its first visible non-empty border, along the fused silhouette;
/// give its member roles the same border for a uniform transition.
@immutable
class MorphSurfaceBorders {
  /// Creates per-role borders; omitted roles have no added contour.
  const MorphSurfaceBorders({
    this.bar = BorderSide.none,
    this.track = BorderSide.none,
    this.menu = BorderSide.none,
    this.button = BorderSide.none,
    this.lens = BorderSide.none,
    this.knob = BorderSide.none,
    this.thumb = BorderSide.none,
  });

  /// Uses [border] on every surface role.
  const MorphSurfaceBorders.all(BorderSide border)
    : bar = border,
      track = border,
      menu = border,
      button = border,
      lens = border,
      knob = border,
      thumb = border;

  /// The floating tab bar and bar capsules.
  final BorderSide bar;

  /// Segmented-control, switch, slider and stepper tracks.
  ///
  /// A custom segmented track widget owns its own decoration.
  final BorderSide track;

  /// Menu platters and floating presentation bodies.
  final BorderSide menu;

  /// Glass buttons and the source of a morphing menu.
  final BorderSide button;

  /// Selection lenses, at rest and lifted.
  final BorderSide lens;

  /// Switch knobs, at rest and lifted.
  final BorderSide knob;

  /// Slider thumbs, at rest and lifted.
  final BorderSide thumb;

  /// A copy with only the supplied roles changed.
  MorphSurfaceBorders copyWith({
    BorderSide? bar,
    BorderSide? track,
    BorderSide? menu,
    BorderSide? button,
    BorderSide? lens,
    BorderSide? knob,
    BorderSide? thumb,
  }) => MorphSurfaceBorders(
    bar: bar ?? this.bar,
    track: track ?? this.track,
    menu: menu ?? this.menu,
    button: button ?? this.button,
    lens: lens ?? this.lens,
    knob: knob ?? this.knob,
    thumb: thumb ?? this.thumb,
  );

  /// Whether every role is visually empty, including transparent borders.
  bool get isEmpty => [
    bar,
    track,
    menu,
    button,
    lens,
    knob,
    thumb,
  ].every((side) => side.style == BorderStyle.none || side.color.a == 0);

  @override
  bool operator ==(Object other) =>
      other is MorphSurfaceBorders &&
      other.bar == bar &&
      other.track == track &&
      other.menu == menu &&
      other.button == button &&
      other.lens == lens &&
      other.knob == knob &&
      other.thumb == thumb;

  @override
  int get hashCode => Object.hash(bar, track, menu, button, lens, knob, thumb);
}
