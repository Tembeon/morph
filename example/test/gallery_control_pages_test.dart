import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/control_pages.dart';
import 'package:morph_example/gallery/date_picker_page.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_buttons_page.dart';
import 'package:morph_example/gallery/indicator_page.dart';
import 'package:morph_example/gallery/knobs.dart';
import 'package:morph_example/gallery/lens_pages.dart';

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

/// Shows [page] in the gallery on an iPhone 16 Pro screen, or one twice
/// as tall when [tall], so that a long page builds every row.
Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  bool tall = false,
}) async {
  tester.view.physicalSize = Size(1206, tall ? 2622 * 2 : 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(GalleryApp(home: MorphNavigationStack(home: page)));
  await _settle(tester);
}

Future<void> _openOptions(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Page options'));
  await _settle(tester);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

/// The options section headed [header], scrolled into the sheet: the
/// sheet's list builds only the sections in view.
Future<Finder> _section(WidgetTester tester, String header) async {
  final sheet = find.byType(ListView);
  final title = find.descendant(of: sheet, matching: find.text(header));
  await tester.scrollUntilVisible(
    title,
    100,
    scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
  );
  await _settle(tester);
  return find
      .ancestor(of: title, matching: find.byType(MorphListSection))
      .first;
}

/// Picks [option] on the row labelled [label] in the section [header].
Future<void> _choose(
  WidgetTester tester,
  String header,
  String label,
  String option,
) async {
  final section = await _section(tester, header);
  await _tapVisible(
    tester,
    find.descendant(
      of: find.descendant(
        of: section,
        matching: find.widgetWithText(MorphListRow, label),
      ),
      matching: find.text(option),
    ),
  );
}

/// Flips the toggle labelled [label] in the section [header].
Future<void> _toggle(WidgetTester tester, String header, String label) async {
  final section = await _section(tester, header);
  await _tapVisible(
    tester,
    find.descendant(
      of: find.descendant(
        of: section,
        matching: find.widgetWithText(GalleryToggle, label),
      ),
      matching: find.byType(MorphSwitch),
    ),
  );
}

/// Taps the row titled [title] in the section [header].
Future<void> _tapRow(WidgetTester tester, String header, String title) async {
  final section = await _section(tester, header);
  await _tapVisible(
    tester,
    find.descendant(of: section, matching: find.text(title)),
  );
}

/// Picks the swatch [name] on the color row labelled [label] in the
/// section [header].
Future<void> _swatch(
  WidgetTester tester,
  String header,
  String label,
  String name,
) async {
  final section = await _section(tester, header);
  await _tapVisible(
    tester,
    find.descendant(
      of: find.descendant(
        of: section,
        matching: find.widgetWithText(GalleryColorChoice, label),
      ),
      matching: find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == name,
      ),
    ),
  );
}

T _widget<T extends Widget>(WidgetTester tester, [int index = 0]) =>
    tester.widget<T>(find.byType(T).at(index));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails _) {};
    try {
      await MorphTheme.precacheGlass();
    } finally {
      FlutterError.onError = previous;
    }
  });

  testWidgets('the controls page keeps its controls and applies its options', (
    tester,
  ) async {
    await _pump(tester, const ControlsPage());
    expect(find.byType(MorphSwitch), findsNWidgets(2));
    expect(find.byType(MorphSlider), findsNWidgets(3));
    expect(find.byType(MorphStepper), findsOneWidget);
    expect(find.widgetWithText(MorphGlassButton, '120 x 44'), findsOneWidget);
    expect(find.widgetWithText(MorphGlassButton, 'Prominent'), findsOneWidget);
    expect(_widget<MorphSwitch>(tester).appearance, isNull);
    expect(_widget<MorphSlider>(tester).max, 1);
    expect(_widget<MorphSlider>(tester, 2).ticks, 5);
    expect(_widget<MorphStepper>(tester).max, 10);

    await _openOptions(tester);
    await _swatch(tester, 'Switch', 'On track', 'Purple');
    expect(
      _widget<MorphSwitch>(tester).activeTrackColor,
      const Color(0xFFAF52DE),
    );
    await _choose(tester, 'Switch', 'Look', 'Dark');
    expect(
      _widget<MorphSwitch>(tester, 1).appearance,
      MorphSwitchAppearance.dark,
    );
    await _toggle(tester, 'Switch', 'Switch high-contrast table');
    expect(
      _widget<MorphSwitch>(tester).appearance,
      MorphSwitchAppearance.darkHighContrast,
    );

    await _choose(tester, 'Slider, 300 wide', 'Range', '0 to 100');
    final wide = _widget<MorphSlider>(tester);
    expect(wide.min, 0);
    expect(wide.max, 100);
    expect(wide.value, moreOrLessEquals(30));
    await _toggle(tester, 'Slider, 300 wide', 'Animated');
    expect(_widget<MorphSlider>(tester).animated, isTrue);
    await _tapRow(tester, 'Slider, 300 wide', 'Jump to a random value');
    final jumped = _widget<MorphSlider>(tester).value;
    expect(jumped, inInclusiveRange(0, 100));
    expect(
      find.text('Slider, 300 wide: ${jumped.toStringAsFixed(2)}'),
      findsOneWidget,
    );

    await _choose(tester, 'Every slider', 'Ticks', 'None');
    expect(_widget<MorphSlider>(tester, 2).ticks, 0);
    expect(find.textContaining('Slider, no ticks'), findsOneWidget);

    await _choose(tester, 'Stepper', 'Range', '0-1 by 0.1');
    final stepper = _widget<MorphStepper>(tester);
    expect(stepper.step, 0.1);
    expect(stepper.value, 1);
    expect(find.text('Stepper: 1.0'), findsOneWidget);
    await _toggle(tester, 'Stepper', 'Spoken texts');
    final spoken = _widget<MorphStepper>(tester);
    expect(spoken.incrementLabel, 'More cups');
    expect(spoken.semanticFormatterCallback!(0.5), '0.5 cups');
  });

  testWidgets('the slider reports the start and end of a drag', (tester) async {
    await _pump(tester, const ControlsPage());
    final slider = find.byType(MorphSlider).first;
    final rect = tester.getRect(slider);
    final thumb = Offset(
      rect.left + 18.5 + 0.3 * (rect.width - 37),
      rect.center.dy,
    );
    final gesture = await tester.startGesture(thumb);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await _settle(tester);
    final end = _widget<MorphSlider>(tester).value;
    expect(end, greaterThan(0.3));
    expect(
      find.textContaining('last drag 0.30 to ${end.toStringAsFixed(2)}'),
      findsOneWidget,
    );
  });

  testWidgets('the segmented page clears, disables and sizes its segments', (
    tester,
  ) async {
    await _pump(tester, const SegmentedPage());
    expect(find.byType(MorphSegmentedControl), findsNWidgets(7));
    for (var i = 0; i < 7; i++) {
      expect(_widget<MorphSegmentedControl>(tester, i).selectedIndex, 0);
    }
    await _openOptions(tester);
    await _tapRow(tester, 'Selection', 'Clear every selection');
    for (var i = 0; i < 7; i++) {
      expect(_widget<MorphSegmentedControl>(tester, i).selectedIndex, isNull);
    }
    await _toggle(tester, 'Segments', 'Disable the second segment');
    expect(_widget<MorphSegmentedControl>(tester).segments[1].enabled, isFalse);
    await _toggle(tester, 'Segments', 'First segment 96 wide');
    expect(_widget<MorphSegmentedControl>(tester).segments[0].width, 96);
    expect(_widget<MorphSegmentedControl>(tester, 6).segments[0].width, isNull);
    await _choose(tester, 'Appearance', 'Look', 'Light');
    expect(
      _widget<MorphSegmentedControl>(tester).appearance,
      MorphSegmentedControlAppearance.light,
    );
  });

  testWidgets('the glass buttons page shows every style and its menus', (
    tester,
  ) async {
    await _pump(tester, const GlassButtonsPage(), tall: true);
    final all = [
      for (final e in find.byType(MorphGlassButton).evaluate())
        e.widget as MorphGlassButton,
    ];
    expect(all.where((b) => !b.enabled), hasLength(6));
    expect(all.where((b) => b.style == MorphGlassStyle.clear), hasLength(9));
    expect(all.where((b) => b.menu != null), hasLength(2));

    await tester.tap(find.widgetWithText(MorphGlassButton, 'Enabled').first);
    await _settle(tester);
    expect(find.text('Tapped 1 times, last: Regular'), findsOneWidget);
    await tester.tap(find.widgetWithText(MorphGlassButton, 'Disabled').first);
    await _settle(tester);
    expect(find.text('Tapped 1 times, last: Regular'), findsOneWidget);

    await tester.tap(find.widgetWithText(MorphGlassButton, 'Menu'));
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await _settle(tester);
    expect(find.textContaining('last: Menu: Copy'), findsOneWidget);

    final colored = find.widgetWithText(MorphGlassButton, 'Prominent color');
    expect(
      tester.widget<MorphGlassButton>(colored).appearance?.prominentColor,
      const Color(0xFFAF52DE),
    );
    expect(
      tester
          .widget<MorphGlassButton>(
            find.widgetWithText(MorphGlassButton, 'Accent'),
          )
          .appearance,
      isNull,
    );
    await _openOptions(tester);
    await _choose(tester, 'Size', 'Min size', '80');
    expect(
      tester.widget<MorphGlassButton>(colored).minSize,
      const Size.square(80),
    );
    await _swatch(tester, 'Fill', 'Tint', 'Teal');
    expect(
      tester
          .widget<MorphGlassButton>(
            find.widgetWithText(MorphGlassButton, 'Tap or hold'),
          )
          .tint,
      const Color(0xFF30B0C7),
    );
  });

  testWidgets('the indicators page applies its options', (tester) async {
    await _pump(tester, const IndicatorPage());
    expect(
      _widget<MorphPageControl>(tester).backgroundStyle,
      MorphPageControlBackgroundStyle.automatic,
    );
    expect(_widget<MorphActivityIndicator>(tester).hidesWhenStopped, isTrue);
    expect(_widget<MorphProgressView>(tester).animated, isTrue);
    await _openOptions(tester);
    await _toggle(tester, 'Progress', 'Animated');
    expect(_widget<MorphProgressView>(tester, 1).animated, isFalse);
    await _choose(tester, 'Page control', 'Platter', 'Minimal');
    expect(
      _widget<MorphPageControl>(tester).backgroundStyle,
      MorphPageControlBackgroundStyle.minimal,
    );
    expect(
      _widget<MorphPageControl>(tester, 1).backgroundStyle,
      MorphPageControlBackgroundStyle.prominent,
    );
    await _toggle(tester, 'Page control', 'Photo values');
    expect(
      _widget<MorphPageControl>(tester).semanticValueFormatter!(2, 5),
      'photo 2 of 5',
    );
    await _toggle(tester, 'Activity indicator', 'Hides when stopped');
    expect(
      _widget<MorphActivityIndicator>(tester, 1).hidesWhenStopped,
      isFalse,
    );
    await _swatch(tester, 'Activity indicator', 'Spokes', 'Pink');
    expect(
      _widget<MorphActivityIndicator>(tester).color,
      const Color(0xFFFF2D55),
    );
  });

  testWidgets('the date picker page applies its options', (tester) async {
    await _pump(tester, const DatePickerPage());
    expect(find.text('Oct 3, 2026'), findsNWidgets(4));
    expect(find.text('9:41 AM'), findsNWidgets(2));
    await _openOptions(tester);
    await _choose(tester, 'Values', 'Minutes', '15 min');
    expect(find.text('9:30 AM'), findsNWidgets(2));
    await _toggle(tester, 'Values', 'Limit to October 1 to 20');
    final picker = _widget<MorphDatePicker>(tester);
    expect(picker.minimumDate, DateTime(2026, 10, 1, 8));
    expect(picker.maximumDate, DateTime(2026, 10, 20, 18));
    await _choose(tester, 'Calendar and clock', 'Clock', '24 hour');
    expect(find.text('09:30'), findsNWidgets(2));
    await _choose(tester, 'Calendar and clock', 'Week starts', 'Monday');
    expect(_widget<MorphDatePicker>(tester).firstDayOfWeek, DateTime.monday);
    await _toggle(tester, 'Calendar and clock', 'Today is October 10, 2026');
    expect(_widget<MorphDatePicker>(tester).today, DateTime(2026, 10, 10));
    await _toggle(tester, 'Calendar and clock', 'German texts');
    expect(find.text('3.10.2026'), findsNWidgets(4));
    expect(
      galleryGermanDatePicker.calendarTitleFormatter!(DateTime(2026, 3)),
      'M\u00e4rz 2026',
    );
    expect(galleryGermanDatePicker.localize!('MON'), 'MO');
  });
}
