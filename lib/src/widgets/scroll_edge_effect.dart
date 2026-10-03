import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// How a [MorphScrollEdgeEffect] separates the content under a bar.
enum MorphScrollEdgeEffectStyle {
  /// UIKit's `.soft` edge effect: a light blur over a band that reaches
  /// past the bar, with a fade toward the background that dissolves
  /// along the lower part of the band.
  soft,

  /// UIKit's `.hard` edge effect (the "thin film" a navigation bar uses
  /// by default): a blur with raised saturation and brightness over the
  /// bar's own band, a uniform fade toward the background and a hairline
  /// at the bar's edge.
  hard,
}

/// The look of a [MorphScrollEdgeEffect].
///
/// The values are UIKit's `PocketSettings` and the layers of
/// `UIKit.ScrollEdgeEffectView` as read on iOS 27: the band reaches
/// [softOverhang] past the bar for the soft style; the soft blur is
/// [softBlurRadius], the hard one [hardBlurRadius] (radii are taken as
/// Gaussian sigmas); the content fades toward [backgroundColor] by
/// [fadeOpacity] (UIKit's "replay" layer re-draws what lies behind the
/// content over it); the soft fade starts to dissolve at [softFadeStart]
/// of the band and is gone at its far end.
@immutable
class MorphScrollEdgeEffectThemeData {
  /// Creates a look; the defaults are the iOS light appearance.
  const MorphScrollEdgeEffectThemeData({
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.fadeOpacity = 0.5,
    this.separatorColor = const Color(0x1A000000),
    this.softBlurRadius = 1.5,
    this.hardBlurRadius = 2,
    this.softOverhang = 40,
    this.softFadeStart = 0.3407,
    this.hardSaturation = 1.25,
    this.hardBrightness = 0.03,
  });

  /// What lies behind the scroll content: the color the content fades
  /// toward under the bar.
  final Color backgroundColor;

  /// How far the content fades toward [backgroundColor]: UIKit's replay
  /// alpha, 0.5 in light mode and 0.6 in dark mode.
  final double fadeOpacity;

  /// The hairline of the hard style: black or white at 10 percent.
  final Color separatorColor;

  /// The blur of the soft style, in logical pixels.
  final double softBlurRadius;

  /// The blur of the hard style, in logical pixels.
  final double hardBlurRadius;

  /// How far the soft band reaches past the bar's edge.
  final double softOverhang;

  /// Where along the soft band, as a fraction from the edge of the
  /// screen, the fade starts to dissolve.
  final double softFadeStart;

  /// The saturation of the content under the hard style.
  final double hardSaturation;

  /// The brightness added to the content under the hard style, as a
  /// fraction of full intensity.
  final double hardBrightness;

  /// The light appearance.
  static const light = MorphScrollEdgeEffectThemeData();

  /// The dark appearance.
  static const dark = MorphScrollEdgeEffectThemeData(
    backgroundColor: Color(0xFF000000),
    fadeOpacity: 0.6,
    separatorColor: Color(0x1AFFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphScrollEdgeEffectThemeData resolve(
    BuildContext context,
    MorphScrollEdgeEffectThemeData? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.scrollEdgeEffect ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };

  /// The color matrix of the hard style: UIKit's saturation matrix
  /// (Rec. 709 luminance) plus the brightness offset.
  List<double> get hardColorMatrix {
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    final s = hardSaturation;
    final o = hardBrightness * 255;
    return [
      lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, o, //
      lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, o, //
      lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, o, //
      0, 0, 0, 1, 0,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is MorphScrollEdgeEffectThemeData &&
      other.backgroundColor == backgroundColor &&
      other.fadeOpacity == fadeOpacity &&
      other.separatorColor == separatorColor &&
      other.softBlurRadius == softBlurRadius &&
      other.hardBlurRadius == hardBlurRadius &&
      other.softOverhang == softOverhang &&
      other.softFadeStart == softFadeStart &&
      other.hardSaturation == hardSaturation &&
      other.hardBrightness == hardBrightness;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    fadeOpacity,
    separatorColor,
    softBlurRadius,
    hardBlurRadius,
    softOverhang,
    softFadeStart,
    hardSaturation,
    hardBrightness,
  );
}

/// The iOS 27 scroll edge effect: what replaces a bar's solid background
/// when content scrolls under it.
///
/// Place it over the scroll content, under the bar, filling the area the
/// bar covers. [extent] is the bar's far edge measured from the screen
/// edge (status bar included for a top bar); the soft style reaches
/// [MorphScrollEdgeEffectThemeData.softOverhang] further. The effect
/// shows only while [active] - while content lies under the edge; UIKit
/// switches it on and off from one frame to the next.
///
/// It costs one backdrop blur of a narrow band per edge, so it stays
/// inside a 120 Hz frame budget.
class MorphScrollEdgeEffect extends StatelessWidget {
  /// Creates the effect for the [edge] of a scroll view.
  const MorphScrollEdgeEffect({
    required this.extent,
    this.edge = AxisDirection.up,
    this.style = MorphScrollEdgeEffectStyle.soft,
    this.active = true,
    this.theme,
    super.key,
  });

  /// The distance from the screen edge to the bar's far edge.
  final double extent;

  /// The edge of the scroll view: [AxisDirection.up] for a navigation
  /// bar, [AxisDirection.down] for a toolbar.
  final AxisDirection edge;

  /// The style of the effect.
  final MorphScrollEdgeEffectStyle style;

  /// Whether content lies under the edge.
  final bool active;

  /// The look; null resolves it from the theme.
  final MorphScrollEdgeEffectThemeData? theme;

  /// The height of the band the effect covers for [style] under a bar
  /// reaching [extent].
  static double bandExtent(
    MorphScrollEdgeEffectStyle style,
    double extent,
    MorphScrollEdgeEffectThemeData theme,
  ) => switch (style) {
    MorphScrollEdgeEffectStyle.soft => extent + theme.softOverhang,
    MorphScrollEdgeEffectStyle.hard => extent,
  };

  @override
  Widget build(BuildContext context) {
    if (!active || extent <= 0) return const SizedBox.shrink();
    final look = MorphScrollEdgeEffectThemeData.resolve(context, theme);
    final band = bandExtent(style, extent, look);
    final top = edge == AxisDirection.up;
    final ui.ImageFilter filter = switch (style) {
      MorphScrollEdgeEffectStyle.soft => ui.ImageFilter.blur(
        sigmaX: look.softBlurRadius,
        sigmaY: look.softBlurRadius,
      ),
      MorphScrollEdgeEffectStyle.hard => ui.ImageFilter.compose(
        outer: ui.ColorFilter.matrix(look.hardColorMatrix),
        inner: ui.ImageFilter.blur(
          sigmaX: look.hardBlurRadius,
          sigmaY: look.hardBlurRadius,
        ),
      ),
    };
    final fade = look.backgroundColor.withValues(
      alpha: look.backgroundColor.a * look.fadeOpacity,
    );
    final Decoration overlay = switch (style) {
      MorphScrollEdgeEffectStyle.soft => BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [fade, fade, fade.withValues(alpha: 0)],
          stops: [0, look.softFadeStart, 1],
        ),
      ),
      MorphScrollEdgeEffectStyle.hard => BoxDecoration(color: fade),
    };
    return IgnorePointer(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: SizedBox(
          height: band,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: BackdropFilter(
                  filter: filter,
                  child: DecoratedBox(decoration: overlay),
                ),
              ),
              if (style == MorphScrollEdgeEffectStyle.hard)
                Align(
                  alignment: top ? Alignment.bottomCenter : Alignment.topCenter,
                  child: Container(
                    height:
                        1 / (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
                    color: look.separatorColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
