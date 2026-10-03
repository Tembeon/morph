import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The text of the measured controls: the sizes and weights UIKit draws
/// each control's labels with, and the system font set the way CoreText
/// sets it.
///
/// The role styles ([segment], [tabLabel], [largeTitle] and the rest)
/// declare only a size and a weight, measured from the labels of the
/// real controls on iOS 27. [resolve] turns one into the style a widget
/// paints with: on Apple platforms (iOS and macOS, not the web) it adds
/// what CoreText applies to the system font by itself and Flutter does
/// not - the optical size axis (`opsz`, the point size), UIKit's
/// weight-axis values (`wght` 510 for medium, 590 for semibold) and SF
/// Pro's size-dependent tracking ([tracking]). Without them a 13 pt label
/// is drawn about 1 percent wide and a 34 pt title about 8 percent wide.
/// Everywhere else the style is returned as is: the platform's own font
/// at the same size and weight, without SF tracking - SF Pro is never
/// bundled, its license limits it to Apple platforms.
abstract final class MorphTypography {
  /// The label of an unselected segment of a segmented control.
  static const segment = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);

  /// The label of the selected segment of a segmented control.
  static const segmentSelected = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  /// The title of an unselected tab bar item.
  static const tabLabel = TextStyle(fontSize: 10, fontWeight: FontWeight.w500);

  /// The title of the selected tab bar item.
  static const tabLabelSelected = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  /// The title of a glass button, plain or prominent.
  static const button = TextStyle(fontSize: 17, fontWeight: FontWeight.w400);

  /// The title of a plain bar button item.
  static const barButton = TextStyle(fontSize: 17, fontWeight: FontWeight.w500);

  /// The title of a prominent (done) bar button item.
  static const barButtonProminent = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  /// The title of a menu row.
  static const menuItem = TextStyle(fontSize: 17, fontWeight: FontWeight.w400);

  /// The inline title of a navigation bar.
  static const title = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

  /// The large title of a navigation bar.
  static const largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
  );

  /// The title of an alert.
  static const alertTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  /// The message of an alert.
  static const alertMessage = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
  );

  /// The title of an alert action, cancel and destructive alike.
  static const alertAction = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
  );

  /// The text and placeholder of a search field.
  static const searchField = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
  );

  /// The month title of the inline date picker.
  static const datePickerTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  /// The weekday initials of the inline date picker.
  static const datePickerWeekday = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// A day of the inline date picker.
  static const datePickerDay = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
  );

  /// The selected day of the inline date picker.
  static const datePickerDaySelected = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  /// The date and time labels of the compact date picker.
  static const datePickerCompact = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
  );

  /// Whether text resolves to Apple's system font on this platform.
  static bool get usesAppleSystemFont =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// SF Pro's tracking at [size], in logical pixels per glyph.
  ///
  /// Measured on iOS 27 as the advance CoreText gives the system font at
  /// [size] minus the advance of the same instance without tracking; it
  /// matches Apple's published SF Pro tracking table (17 pt -0.43, 13 pt
  /// -0.08, 12 pt 0, 28 pt +0.38). Linear between measured sizes, 0 from
  /// 80 pt up, the 6 pt value below 6 pt.
  static double tracking(double size) {
    const table = _trackingTable;
    if (size <= table.first.$1) return table.first.$2;
    if (size >= table.last.$1) return table.last.$2;
    for (var i = 1; i < table.length; i++) {
      final (s1, t1) = table[i];
      if (size <= s1) {
        final (s0, t0) = table[i - 1];
        return t0 + (t1 - t0) * (size - s0) / (s1 - s0);
      }
    }
    return 0;
  }

  /// The value of the system font's `wght` axis UIKit uses for [weight],
  /// or null where the weight was not measured.
  static double? weightAxis(FontWeight weight) => switch (weight) {
    FontWeight.w400 => 400,
    FontWeight.w500 => 510,
    FontWeight.w600 => 590,
    FontWeight.w700 => 700,
    _ => null,
  };

  /// The style a widget paints [style] with on this platform.
  ///
  /// The result is complete (`inherit` false): a label drawn with it reads
  /// the same under any ancestor - in an overlay, a bare `WidgetsApp`, or
  /// a `MaterialApp` page without a `Material`, where an inheriting style
  /// would pick up the yellow double underline and monospace family of
  /// the missing-text-style fallback - and a `TextPainter` measuring it
  /// sees exactly what is painted.
  ///
  /// On Apple platforms, for the system font (no `fontFamily`, or one of
  /// Flutter's system font aliases): the optical size and weight axes
  /// unless `fontVariations` is set, and [tracking] of the font size
  /// unless `letterSpacing` is set. Elsewhere, and for any other family,
  /// [style] as it is otherwise. [apple] overrides the platform check
  /// (tests).
  static TextStyle resolve(TextStyle style, {bool? apple}) {
    final complete = style.inherit ? style.copyWith(inherit: false) : style;
    if (!(apple ?? usesAppleSystemFont)) return complete;
    if (!_isSystemFamily(style.fontFamily)) return complete;
    final size = style.fontSize ?? 14;
    final wght = weightAxis(style.fontWeight ?? FontWeight.w400);
    return complete.copyWith(
      letterSpacing: style.letterSpacing ?? tracking(size),
      fontVariations:
          style.fontVariations ??
          [
            FontVariation('opsz', size),
            if (wght != null) FontVariation('wght', wght),
          ],
    );
  }

  static bool _isSystemFamily(String? family) => switch (family) {
    null || '.AppleSystemUIFont' || 'CupertinoSystemText' => true,
    _ => false,
  };
}

const List<(double, double)> _trackingTable = [
  (6, 0.240),
  (7, 0.228),
  (8, 0.203),
  (9, 0.167),
  (10, 0.117),
  (11, 0.064),
  (12, 0),
  (13, -0.076),
  (14, -0.150),
  (15, -0.234),
  (16, -0.313),
  (17, -0.431),
  (18, -0.440),
  (19, -0.446),
  (20, -0.449),
  (21, -0.359),
  (22, -0.258),
  (23, -0.101),
  (24, 0.070),
  (25, 0.135),
  (26, 0.216),
  (27, 0.290),
  (28, 0.383),
  (29, 0.382),
  (30, 0.395),
  (31, 0.393),
  (32, 0.407),
  (33, 0.387),
  (34, 0.382),
  (35, 0.376),
  (36, 0.369),
  (37, 0.361),
  (38, 0.372),
  (39, 0.362),
  (40, 0.371),
  (44, 0.365),
  (48, 0.352),
  (56, 0.301),
  (64, 0.219),
  (72, 0.105),
  (80, 0),
];
