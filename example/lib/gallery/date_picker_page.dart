import 'package:flutter/widgets.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/control_pages.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// German texts for a [MorphDatePicker]: a sample of
/// [MorphDatePickerLocalizations] that formats the labels, the calendar
/// title and the day labels, and translates the fixed English words.
final MorphDatePickerLocalizations galleryGermanDatePicker =
    MorphDatePickerLocalizations(
      dateFormatter: (DateTime d) => '${d.day}.${d.month}.${d.year}',
      timeFormatter: (DateTime d) =>
          '${d.hour}:${d.minute.toString().padLeft(2, '0')}',
      localize: (String english) => _german[english] ?? english,
      calendarTitleFormatter: (DateTime d) =>
          '${_german[_englishMonths[d.month - 1]]} ${d.year}',
      daySemanticFormatter: (DateTime d) =>
          '${d.day}. ${_german[_englishMonths[d.month - 1]]} ${d.year}',
    );

const _englishMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _german = <String, String>{
  'January': 'Januar',
  'February': 'Februar',
  'March': 'M\u00e4rz',
  'April': 'April',
  'May': 'Mai',
  'June': 'Juni',
  'July': 'Juli',
  'August': 'August',
  'September': 'September',
  'October': 'Oktober',
  'November': 'November',
  'December': 'Dezember',
  'SUN': 'SO',
  'MON': 'MO',
  'TUE': 'DI',
  'WED': 'MI',
  'THU': 'DO',
  'FRI': 'FR',
  'SAT': 'SA',
  'Show year picker': 'Jahresauswahl einblenden',
  'Hide year picker': 'Jahresauswahl ausblenden',
  'Previous month': 'Vorheriger Monat',
  'Next month': 'N\u00e4chster Monat',
  'Hour': 'Stunde',
  'Minute': 'Minute',
  'AM/PM': 'AM/PM',
  'AM': 'AM',
  'PM': 'PM',
  'Month': 'Monat',
  'Year': 'Jahr',
};

/// The 24-hour setting of the pickers: the platform's, or forced.
enum _Clock { system, twelve, twentyFour }

/// The iOS 27 compact date picker: a date, a time, both, one near the
/// bottom of the screen whose calendar opens above it, one at the trailing
/// edge, and a disabled one.
///
/// The page options set the minute step, limit the dates to October 2026,
/// force the 24-hour clock, move the first weekday and today, switch to
/// German texts and pin the pickers to an appearance table.
class DatePickerPage extends StatefulWidget {
  /// Creates the page.
  const DatePickerPage({super.key});

  @override
  State<DatePickerPage> createState() => _DatePickerPageState();
}

class _DatePickerPageState extends State<DatePickerPage> {
  DateTime _value = DateTime(2026, 10, 3, 9, 41);

  int _minuteInterval = 1;
  bool _limited = false;
  _Clock _clock = .system;
  int _firstDay = DateTime.sunday;
  bool _fixedToday = false;
  bool _german = false;
  GalleryLook _look = .theme;
  bool _highContrast = false;

  static final _minimumDate = DateTime(2026, 10, 1, 8);
  static final _maximumDate = DateTime(2026, 10, 20, 18);
  static final _today = DateTime(2026, 10, 10);

  static const _intervals = <int, String>{1: '1 min', 5: '5 min', 15: '15 min'};

  static const _clocks = <_Clock, String>{
    .system: 'System',
    .twelve: '12 hour',
    .twentyFour: '24 hour',
  };

  static const _firstDays = <int, String>{
    DateTime.sunday: 'Sunday',
    DateTime.monday: 'Monday',
    DateTime.saturday: 'Saturday',
  };

  Widget _row(String label, Widget picker) => MorphListRow(
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: FittedBox(
        fit: .scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: picker,
      ),
    ),
  );

  void _pick(DateTime v) => setState(() => _value = v);

  MorphDatePicker _picker(MorphDatePickerMode mode, {bool enabled = true}) =>
      MorphDatePicker(
        value: _value,
        mode: mode,
        semanticLabel: 'Event',
        minuteInterval: _minuteInterval,
        minimumDate: _limited ? _minimumDate : null,
        maximumDate: _limited ? _maximumDate : null,
        use24HourFormat: switch (_clock) {
          .system => null,
          .twelve => false,
          .twentyFour => true,
        },
        firstDayOfWeek: _firstDay,
        today: _fixedToday ? _today : null,
        localizations: _german
            ? galleryGermanDatePicker
            : const MorphDatePickerLocalizations(),
        appearance: _look.pick(
          MorphDatePickerAppearance.light,
          MorphDatePickerAppearance.dark,
          onLightHighContrast: MorphDatePickerAppearance.lightHighContrast,
          onDarkHighContrast: MorphDatePickerAppearance.darkHighContrast,
          highContrast: _highContrast,
        ),
        onChanged: enabled ? GalleryGlassScope.enabled(context, _pick) : null,
      );

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Values'),
      footer: const Text(
        'A minute step rounds the shown time down to its multiple. The '
        'limits allow Oct 1, 2026, 8:00 AM to Oct 20, 2026, 6:00 PM.',
      ),
      children: [
        GalleryChoice<int>(
          label: 'Minutes',
          options: _intervals,
          value: _minuteInterval,
          onChanged: (int i) => setState(() => _minuteInterval = i),
        ),
        GalleryToggle(
          label: 'Limit to October 1 to 20',
          value: _limited,
          onChanged: (bool v) => setState(() => _limited = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Calendar and clock'),
      children: [
        GalleryChoice<_Clock>(
          label: 'Clock',
          options: _clocks,
          value: _clock,
          onChanged: (_Clock c) => setState(() => _clock = c),
        ),
        GalleryChoice<int>(
          label: 'Week starts',
          options: _firstDays,
          value: _firstDay,
          onChanged: (int d) => setState(() => _firstDay = d),
        ),
        GalleryToggle(
          label: 'Today is October 10, 2026',
          value: _fixedToday,
          onChanged: (bool v) => setState(() => _fixedToday = v),
        ),
        GalleryToggle(
          label: 'German texts',
          value: _german,
          onChanged: (bool v) => setState(() => _german = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Appearance'),
      children: [
        GalleryChoice<GalleryLook>(
          label: 'Look',
          options: GalleryLook.options,
          value: _look,
          onChanged: (GalleryLook l) => setState(() => _look = l),
        ),
        GalleryToggle(
          label: 'High-contrast table',
          value: _highContrast,
          onChanged: _look == .theme
              ? null
              : (bool v) => setState(() => _highContrast = v),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GalleryPage(
          title: 'Date picker',
          options: _options,
          slivers: [
            SliverToBoxAdapter(
              child: MorphListSection(
                children: [
                  _row('Date', _picker(.date)),
                  _row('Time', _picker(.time)),
                  _row('Starts', _picker(.dateAndTime)),
                  _row('Disabled', _picker(.date, enabled: false)),
                ],
              ),
            ),
            SliverPadding(
              padding: const .symmetric(horizontal: 36),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Picked: $_value',
                  style: TextStyle(color: gallerySecondaryColor(context)),
                ),
              ),
            ),
          ],
        ),
        PositionedDirectional(
          end: 16,
          bottom: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: galleryCardColor(context),
              borderRadius: const .all(.circular(26)),
            ),
            child: Padding(padding: const .all(8), child: _picker(.date)),
          ),
        ),
      ],
    );
  }
}
