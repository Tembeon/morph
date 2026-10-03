import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/navigation_bar.dart';
import 'package:morph/widgets.dart';

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 360, child: child)),
  ),
);

double? _axis(TextStyle? style, String tag) {
  for (final v in style?.fontVariations ?? const <FontVariation>[]) {
    if (v.axis == tag) return v.value;
  }
  return null;
}

void main() {
  group('tracking', () {
    test('reads the measured SF Pro table', () {
      expect(MorphTypography.tracking(17), -0.431);
      expect(MorphTypography.tracking(13), -0.076);
      expect(MorphTypography.tracking(12), 0);
      expect(MorphTypography.tracking(10), 0.117);
      expect(MorphTypography.tracking(20), -0.449);
      expect(MorphTypography.tracking(28), 0.383);
      expect(MorphTypography.tracking(34), 0.382);
    });

    test('interpolates between sizes and clamps outside the table', () {
      expect(MorphTypography.tracking(12.5), closeTo(-0.038, 1e-9));
      expect(MorphTypography.tracking(42), closeTo(0.368, 1e-9));
      expect(MorphTypography.tracking(2), 0.24);
      expect(MorphTypography.tracking(120), 0);
    });

    test('maps weights onto the wght values UIKit uses', () {
      expect(MorphTypography.weightAxis(FontWeight.w400), 400);
      expect(MorphTypography.weightAxis(FontWeight.w500), 510);
      expect(MorphTypography.weightAxis(FontWeight.w600), 590);
      expect(MorphTypography.weightAxis(FontWeight.w700), 700);
      expect(MorphTypography.weightAxis(FontWeight.w300), isNull);
    });
  });

  group('resolve', () {
    test('adds optical size, weight and tracking on Apple platforms', () {
      final style = MorphTypography.resolve(
        MorphTypography.largeTitle,
        apple: true,
      );
      expect(style.letterSpacing, 0.382);
      expect(_axis(style, 'opsz'), 34);
      expect(_axis(style, 'wght'), 700);
      expect(style.fontFamily, isNull);
      expect(style.fontWeight, FontWeight.w700);
    });

    test('keeps what the style states', () {
      final spaced = MorphTypography.resolve(
        const TextStyle(fontSize: 17, letterSpacing: 1),
        apple: true,
      );
      expect(spaced.letterSpacing, 1);
      expect(_axis(spaced, 'opsz'), 17);
      final varied = MorphTypography.resolve(
        const TextStyle(
          fontSize: 17,
          fontVariations: [FontVariation('wght', 300)],
        ),
        apple: true,
      );
      expect(varied.fontVariations, const [FontVariation('wght', 300)]);
      expect(varied.letterSpacing, -0.431);
    });

    test('leaves other families and other platforms alone', () {
      const custom = TextStyle(fontFamily: 'Inter', fontSize: 17);
      expect(MorphTypography.resolve(custom, apple: true), same(custom));
      const plain = TextStyle(fontSize: 17);
      expect(MorphTypography.resolve(plain, apple: false), same(plain));
      final alias = MorphTypography.resolve(
        const TextStyle(fontFamily: 'CupertinoSystemText', fontSize: 13),
        apple: true,
      );
      expect(alias.letterSpacing, -0.076);
    });

    test('follows the target platform', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(MorphTypography.usesAppleSystemFont, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(MorphTypography.usesAppleSystemFont, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(MorphTypography.usesAppleSystemFont, isFalse);
      expect(
        MorphTypography.resolve(MorphTypography.title).letterSpacing,
        isNull,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('roles', () {
    test('carry the sizes and weights measured on iOS 27', () {
      void role(TextStyle s, double size, FontWeight weight) {
        expect((s.fontSize, s.fontWeight), (size, weight));
      }

      role(MorphTypography.segment, 13, FontWeight.w400);
      role(MorphTypography.segmentSelected, 13, FontWeight.w500);
      role(MorphTypography.tabLabel, 10, FontWeight.w500);
      role(MorphTypography.tabLabelSelected, 10, FontWeight.w600);
      role(MorphTypography.button, 17, FontWeight.w400);
      role(MorphTypography.barButton, 17, FontWeight.w500);
      role(MorphTypography.barButtonProminent, 17, FontWeight.w600);
      role(MorphTypography.menuItem, 17, FontWeight.w400);
      role(MorphTypography.title, 17, FontWeight.w600);
      role(MorphTypography.largeTitle, 34, FontWeight.w700);
      role(MorphTypography.alertTitle, 17, FontWeight.w600);
      role(MorphTypography.alertMessage, 15, FontWeight.w400);
      role(MorphTypography.alertAction, 17, FontWeight.w500);
      role(MorphTypography.searchField, 17, FontWeight.w500);
      role(MorphTypography.datePickerTitle, 17, FontWeight.w600);
      role(MorphTypography.datePickerWeekday, 13, FontWeight.w600);
      role(MorphTypography.datePickerDay, 20, FontWeight.w400);
      role(MorphTypography.datePickerDaySelected, 20, FontWeight.w600);
      role(MorphTypography.datePickerCompact, 17, FontWeight.w400);
    });

    test('match the default style tables', () {
      for (final s in [MorphSegmentedStyle.light, MorphSegmentedStyle.dark]) {
        expect(s.textStyle.fontSize, MorphTypography.segment.fontSize);
        expect(s.textStyle.fontWeight, MorphTypography.segment.fontWeight);
        expect(
          s.selectedTextStyle.fontWeight,
          MorphTypography.segmentSelected.fontWeight,
        );
      }
      for (final s in [MorphMenuStyle.light, MorphMenuStyle.dark]) {
        expect(s.textStyle.fontSize, MorphTypography.menuItem.fontSize);
        expect(s.textStyle.letterSpacing, isNull);
      }
    });
  });

  group('widgets on iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('the segmented control paints resolved labels', (tester) async {
      await tester.pumpWidget(
        _host(
          MorphSegmentedControl(
            segments: const ['All', 'Unread messages'],
            selected: 0,
            onChanged: (_) {},
          ),
        ),
      );
      final selected = tester.widget<Text>(find.text('All')).style;
      final other = tester.widget<Text>(find.text('Unread messages')).style;
      expect(selected?.fontWeight, FontWeight.w500);
      expect(_axis(selected, 'wght'), 510);
      expect(other?.fontWeight, FontWeight.w400);
      expect(other?.letterSpacing, -0.076);
      expect(_axis(other, 'opsz'), 13);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the tab bar weighs the selected title', (tester) async {
      await tester.pumpWidget(
        _host(
          MorphTabBar(
            items: const [
              MorphTabItem(icon: IconData(0xe318), label: 'One'),
              MorphTabItem(icon: IconData(0xe318), label: 'Two'),
            ],
            selected: 0,
            onChanged: (_) {},
          ),
        ),
      );
      final one = tester.widget<Text>(find.text('One')).style;
      final two = tester.widget<Text>(find.text('Two')).style;
      expect(one?.fontWeight, FontWeight.w500);
      expect(two?.fontWeight, FontWeight.w500);
      expect(two?.letterSpacing, 0.117);
      final lensCopy = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((RichText r) => r.text)
          .whereType<TextSpan>()
          .where((TextSpan s) => s.text == 'One')
          .map((TextSpan s) => s.style?.fontWeight);
      expect(lensCopy, contains(FontWeight.w600));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the glass button sets regular 17 pt', (tester) async {
      await tester.pumpWidget(
        _host(MorphGlassButton(onPressed: () {}, child: const Text('Go'))),
      );
      final style = DefaultTextStyle.of(tester.element(find.text('Go'))).style;
      expect(style.fontSize, 17);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.letterSpacing, -0.431);
      debugDefaultTargetPlatformOverride = null;
    });

    test('bar titles and buttons resolve their roles', () {
      final large = morphLargeTitleStyle(const Color(0xFF000000));
      expect((large.fontSize, large.fontWeight), (34, FontWeight.w700));
      expect(large.letterSpacing, 0.382);
      expect(_axis(large, 'opsz'), 34);
      final inline = morphInlineTitleStyle(const Color(0xFF000000));
      expect(
        (inline.fontWeight, inline.letterSpacing),
        (FontWeight.w600, -0.431),
      );
      const metrics = MorphBarMetrics.navigation;
      expect(morphBarLabelStyle(metrics).fontWeight, FontWeight.w500);
      expect(
        morphBarLabelStyle(metrics, bold: true).fontWeight,
        FontWeight.w600,
      );
    });
  });
}
