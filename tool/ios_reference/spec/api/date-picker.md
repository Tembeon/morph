# Date picker - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIDatePicker`, `UICalendarView` (+ `UICalendarSelectionSingleDate` / `MultiDate` / `WeekOfYear`,
`UICalendarViewDecoration`); SwiftUI `DatePicker`, `DatePickerComponents`, `datePickerStyle(_:)`,
`MultiDatePicker`. morph: `MorphDatePicker`, `MorphDatePickerMode`, `MorphDatePickerStyle`,
`MorphDatePickerMotion`, `MorphDatePickerPlacement`, `MorphDatePickerTuning`, `morphPlaceDatePicker`.
Passport: [../date-picker.md](../date-picker.md).

SDK 27.0 check: `UIDatePicker.h`, `UICalendarView*.h` and the SwiftUI `DatePicker` family carry NO
iOS 26 / 27 API. The Liquid Glass change is visual only (glass overlay platter); the API is legacy.

Naming note: morph uses `Morph<X>Style` for the color table of every control. UIKit's `UIDatePickerStyle`
is a presentation enum (compact / inline / wheels), so it cannot take that name; see Breaking changes.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIDatePicker.date` (iOS 2+) | the picked moment | `MorphDatePicker.value` | none | keep |
| `UIControl.Event.valueChanged` | user picked | `MorphDatePicker.onChanged` | null disables (Flutter idiom) | keep |
| `UIControl.isEnabled` | disabled look (capsules removed) | `onChanged == null` | measured, ported | keep |
| `UIDatePicker.datePickerMode` (iOS 2+) | what is picked | `MorphDatePicker.mode` | default differs: UIKit `.dateAndTime`, morph `date` | keep (morph default is the common case; document) |
| `UIDatePickerMode.time` / `.date` / `.dateAndTime` | modes | `MorphDatePickerMode.time` / `date` / `dateAndTime` | none | keep |
| `UIDatePickerMode.countDownTimer` (iOS 2+) | hours + minutes duration wheels | none | missing | add `MorphDatePickerMode.countDownTimer` + `countDownDuration` |
| `UIDatePickerMode.yearAndMonth` (iOS 17.4) | month + year wheels only | none (the wheels exist inside the calendar overlay) | missing as a mode | add `MorphDatePickerMode.yearAndMonth` (reuse `_MonthYearWheels`) |
| `UIDatePicker.preferredDatePickerStyle` (iOS 13.4) | compact / inline / wheels / automatic | none (compact only) | missing | add `MorphDatePicker.variant` (`MorphDatePickerVariant`) |
| `UIDatePickerStyle.compact` (iOS 13.4) | labels that open an overlay | `MorphDatePicker` (always) | none | keep as default |
| `UIDatePickerStyle.inline` (iOS 14) | calendar in place (date), wheels/field for time | none (calendar drawn only in the overlay) | missing | add `MorphDatePickerVariant.inline` |
| `UIDatePickerStyle.wheels` (iOS 13.4) | wheels in place | none (time wheels only in the overlay) | missing; no date wheels at all | add `MorphDatePickerVariant.wheels` (date wheels need a measurement) |
| `UIDatePickerStyle.automatic` | platform picks (compact on iPhone) | none | resolves to compact | add as `automatic` = compact, or skip (one platform) |
| `UIDatePicker.datePickerStyle` (readonly, iOS 13.4) | resolved style | none | - | skip (no automatic resolution needed) |
| `UIDatePicker.minimumDate` / `maximumDate` (iOS 2+) | range | `MorphDatePicker.firstDate` / `lastDate` | name differs from UIKit AND `CupertinoDatePicker` (`minimumDate` / `maximumDate`); matches Material `showDatePicker` | rename -> `minimumDate` / `maximumDate` |
| `UIDatePicker.minuteInterval` (iOS 2+) | minute wheel step 1..30 | none | missing | add `minuteInterval` (int, divides 60) |
| `UIDatePicker.roundsToMinuteInterval` (iOS 15) | round `date` to the interval | none | missing | add `roundsToMinuteInterval = true` with `minuteInterval` |
| `UIDatePicker.countDownDuration` (iOS 2+) | seconds for countDownTimer | none | missing | add `countDownDuration` (`Duration`) with the mode |
| `UIDatePicker.setDate(_:animated:)` (iOS 2+) | programmatic change, wheels spin | none (a new `value` jumps) | no animated external change | add `animateValueChanges` or animate when the overlay is open; low |
| `UIDatePicker.locale` (iOS 2+) | language, 12/24h, week start, formats | `dateFormatter`, `timeFormatter`, `localize`, `calendarTitleFormatter`, `daySemanticFormatter`, `numberFormatter`, `use24HourFormat`, `firstDayOfWeek` | one concept spread over 8 params; default English | reshape -> one `MorphDatePickerLocalizations` (see Breaking) |
| `UIDatePicker.calendar` (iOS 2+) | non-Gregorian calendars, firstWeekday | `firstDayOfWeek` only | Gregorian only | keep `firstDayOfWeek`; skip other calendars (Dart `DateTime` is Gregorian) |
| `UIDatePicker.timeZone` (iOS 2+) | zone of displayed date | none (`DateTime` local or UTC) | - | skip (Dart `DateTime` carries local/UTC; document `value.isUtc` is kept) |
| `UICalendarView` (iOS 16) | standalone inline calendar | none | missing | covered by `MorphDatePickerVariant.inline`; skip a separate widget |
| `UICalendarView.availableDateRange` (iOS 16) | range | `firstDate` / `lastDate` | same concept | keep (renamed per above) |
| `UICalendarView.visibleDateComponents` + `setVisibleDateComponents(_:animated:)` (iOS 16) | shown month, programmatic paging | none | missing | add with inline (`displayedMonth` + `onDisplayedMonthChanged`); low |
| `UICalendarViewDelegate.decorationFor(dateComponents)` + `UICalendarViewDecoration` (default / image / customView, size small/medium/large) (iOS 16) | marks under days (event dots) | none | missing | add `dayDecorationBuilder` (Widget? per day) with inline; low-med |
| `UICalendarSelectionSingleDate` (iOS 16) | single selection, `canSelectDate` | `value` + `firstDate`/`lastDate` | no per-day predicate | add `selectableDayPredicate` (name from Material); low |
| `UICalendarSelectionMultiDate` (iOS 16) | multiple days | none | missing | add later as `MorphMultiDatePicker`; low |
| `UICalendarSelectionWeekOfYear` (iOS 18) | week selection | none | missing | skip (rare) |
| `UICalendarView.fontDesign` (iOS 16) | rounded / serif digits | none | - | skip (typography via theme) |
| `UICalendarView.wantsDateDecorations`, `reloadDecorations` | decoration refresh | none | - | skip (rebuild) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `DatePicker(_:selection:in:displayedComponents:)` (iOS 13) | picker with a leading label | `MorphDatePicker` (no visible label; `semanticLabel`) | SwiftUI draws the title row | skip (put the picker in `MorphListRow.trailing`) |
| `DatePickerComponents.date` / `.hourAndMinute` (iOS 13) | option set | `MorphDatePickerMode` | same as UIKit mode row | keep |
| `in: ClosedRange / PartialRangeFrom / PartialRangeThrough<Date>` | range | `firstDate` / `lastDate` | same as UIKit min/max row | rename (above) |
| `datePickerStyle(.compact / .graphical / .wheel / .automatic)` (iOS 13/14) | presentation | none | `.graphical` = UIKit inline; names differ (`.wheel` vs `.wheels`) | add `MorphDatePickerVariant` with UIKit case names (`compact`, `inline`, `wheels`) |
| `.field` / `.stepperField` | macOS only | - | - | skip (unavailable on iOS) |
| `MultiDatePicker(selection:in:)` (iOS 16) | set of `DateComponents` | none | missing | same as UIKit multi row |
| `.environment(\.locale / \.calendar / \.timeZone)` | locale | formatter callbacks | same as UIKit locale row | reshape (see Breaking) |

## Not relevant for Flutter
- `UIDatePicker` `NSCoding`, `UIAppearance` tint proxies, `UIControl` target-action plumbing (onChanged covers it).
- `datePickerStyle` resolution traits (Mac Catalyst / iPad idiom).
- `UICalendarSelection.updateSelectableDates()` (Flutter rebuilds).
- Accessibility traits and adjustable actions: Flutter `Semantics` (morph already labels days and wheels).

## morph-only API
- `MorphDatePicker.today` (tint date override; Material calls it `currentDate`) - keep (tests and demos need it).
- `MorphDatePicker.use24HourFormat` - keep (CupertinoDatePicker has `use24hFormat`; UIKit derives it from locale); fold into localizations object if that lands.
- `MorphDatePickerMotion`, `MorphDatePickerTuning`, `MorphDatePickerPlacement`, `morphPlaceDatePicker` - keep (measured motion, package convention).
- `MorphDatePickerStyle` color table (17 colors + 2 opacities) - keep.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | `minuteInterval` + `roundsToMinuteInterval` | high (booking, alarms, reminders) | S | add both on `MorphDatePicker` |
| 2 | inline style (calendar in place, UICalendarView / `.graphical`) | high (forms, booking screens) | M (calendar exists; needs in-place host, size, no overlay motion) | add `MorphDatePickerVariant.inline` |
| 3 | locale: defaults are English; 8 separate params | high for non-English apps | M | `MorphDatePickerLocalizations` (one object, optional default from `Localizations`) |
| 4 | `countDownTimer` mode + `countDownDuration` | med (timers) | M (new wheels: hours / min with fixed labels; needs a measurement) | add mode |
| 5 | wheels style in place (date and time) | med | M-L (date wheels unmeasured) | add `MorphDatePickerVariant.wheels` |
| 6 | `yearAndMonth` mode | med (card expiry, reports) | S-M (wheels exist) | add mode |
| 7 | day decorations / selectable predicate | low-med | S-M | add with inline |
| 8 | multi-date selection | low | M | later `MorphMultiDatePicker` |
| 9 | animated external `value` change | low | S | add |

## Breaking changes before 1.0
- `MorphDatePicker.firstDate` / `lastDate` -> `minimumDate` / `maximumDate`: UIKit's names, and Flutter's
  own `CupertinoDatePicker` uses them; iOS developers and Cupertino users both expect them.
- `dateFormatter`, `timeFormatter`, `localize`, `calendarTitleFormatter`, `daySemanticFormatter`,
  `numberFormatter` (and possibly `use24HourFormat`, `firstDayOfWeek`) -> one `localizations:
  MorphDatePickerLocalizations?` object (UIKit's single `locale` concept), so a 1.0 addition of a field
  (count-down labels, month-year mode) is not another constructor parameter on every call site.
- Reserve the presentation enum name now: `MorphDatePickerVariant { compact, inline, wheels }` (UIKit case
  names) with `MorphDatePicker.variant = compact`, since `MorphDatePickerStyle` is taken by the color table.
  Coordinator: align the word (`Variant` / `Presentation`) with the other families (progress has
  `MorphProgressViewStyle` as the shape enum, the opposite convention).
- `MorphDatePickerMode` default `date` vs UIKit `.dateAndTime`: keep, but document the difference.
