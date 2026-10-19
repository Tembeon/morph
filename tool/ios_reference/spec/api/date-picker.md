# Date picker - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIDatePicker`, `UICalendarView` (+ `UICalendarSelectionSingleDate` / `MultiDate` / `WeekOfYear`,
`UICalendarViewDecoration`); SwiftUI `DatePicker`, `DatePickerComponents`, `datePickerStyle(_:)`,
`MultiDatePicker`. morph (public, `lib/morph.dart`): `MorphDatePicker`, `MorphDatePickerMode`,
`MorphDatePickerStyle`, `MorphDatePickerAppearance`, `MorphDatePickerLocalizations`. Internal:
`MorphDatePickerMotion`, `MorphDatePickerTuning`, `MorphDatePickerPlacement`, `morphPlaceDatePicker`,
`morphFloorToMinuteInterval`. Passport: [../date-picker.md](../date-picker.md).

SDK 27.1 check: `UIDatePicker.h`, `UICalendarView*.h` and the SwiftUI `DatePicker` family carry no
iOS 26 / 27 / 27.1 API (newest: `UIDatePickerModeYearAndMonth`, iOS 17.4). Liquid Glass changed the
look only (glass overlay platter).

Naming: morph follows option (b) of the naming rule. `MorphDatePickerStyle` is the presentation enum
(UIKit `UIDatePickerStyle`), `MorphDatePickerAppearance` the look table.

## UIKit
| UIKit API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `date` (iOS 2) | the picked moment | `value` | covered | - |
| `UIControl.Event.valueChanged` | user picked | `onChanged` | covered | - |
| `isEnabled` | disabled look (capsules removed) | `onChanged == null` | covered | - |
| `datePickerMode` (iOS 2) | what is picked | `mode` | covered; default `date` (UIKit `.dateAndTime`) | document the default in the dartdoc |
| `.time` / `.date` / `.dateAndTime` | modes | `MorphDatePickerMode.time` / `date` / `dateAndTime` | covered | - |
| `.countDownTimer` (iOS 2) | hours + minutes duration wheels | none | gap | `MorphDatePickerMode.countDownTimer` + `countDownDuration` (measure first) |
| `.yearAndMonth` (iOS 17.4) | month + year wheels only | none (the wheels exist inside the calendar overlay) | gap | `MorphDatePickerMode.yearAndMonth` over the month/year wheels |
| `preferredDatePickerStyle` (iOS 13.4) | compact / inline / wheels / automatic | `style` | partial: only `compact` draws, others assert | draw `inline`, then `wheels` |
| `.compact` (iOS 13.4) | labels that open an overlay | `MorphDatePickerStyle.compact` | covered | - |
| `.inline` (iOS 14) | calendar in place | `MorphDatePickerStyle.inline` (reserved) | gap | in-place calendar host |
| `.wheels` (iOS 13.4) | wheels in place | `MorphDatePickerStyle.wheels` (reserved) | gap; no date wheels exist | measure the date wheels first |
| `.automatic` | resolves to compact on iPhone | none | gap (low) | add as an alias of `compact` or leave out |
| `minimumDate` / `maximumDate` (iOS 2) | range; both ignored when min > max | `minimumDate` / `maximumDate` | covered; min > max differs (see fidelity) | follow the header: ignore both |
| `minuteInterval` (iOS 2) | minute step 1..30, divides 60 | `minuteInterval` (asserted) | covered | - |
| `roundsToMinuteInterval` (iOS 15) | floor the date to the interval | always on | partial: cannot be turned off | add `roundsToMinuteInterval = true` |
| `countDownDuration` (iOS 2) | seconds for countDownTimer | none | gap | with the mode (`Duration`) |
| `setDate(_:animated:)` (iOS 2) | programmatic change, wheels spin | none (a new `value` jumps) | gap | animate a new `value` while the overlay is open |
| `locale` (iOS 2) | language, 12/24 h, formats | `localizations` (6 formatter callbacks), `use24HourFormat` | partial: English defaults, nothing read from `Localizations` | default from the app's `Localizations` |
| `calendar` (iOS 2) | non-Gregorian calendars, first weekday | `firstDayOfWeek` | partial: Gregorian only | keep; document |
| `timeZone` (iOS 2) | zone of the shown date | - | n/a | Dart `DateTime` is local or UTC |
| `datePickerStyle` (readonly, iOS 13.4) | resolved style | - | n/a | no idiom resolution |
| `UICalendarView` (iOS 16) and its selections, decorations, `visibleDateComponents` | standalone calendar | none | not counted (separate view) | covered by `inline` later; `dayDecorationBuilder`, `selectableDayPredicate` with it |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `DatePicker(_:selection:in:displayedComponents:)` (iOS 13) | picker with a leading title row | `MorphDatePicker` + `semanticLabel` | partial: no visible title | put the picker in `MorphListRow.trailing` |
| `DatePickerComponents.date` / `.hourAndMinute` | option set | `mode` | same as UIKit mode rows | - |
| `in:` ranges | range | `minimumDate` / `maximumDate` | same as UIKit rows | - |
| `datePickerStyle(.compact / .graphical / .wheel / .automatic)` | presentation | `style` | same as UIKit style rows (`.graphical` = `inline`) | - |
| `.field` / `.stepperField` | macOS only | - | n/a | - |
| `MultiDatePicker(selection:in:)` (iOS 16) | set of days | none | gap | later `MorphMultiDatePicker` |
| `.environment(\.locale / \.calendar / \.timeZone)` | locale | `localizations` | same as UIKit locale row | - |

Count (UIKit + SwiftUI-only members, `UICalendarView` excluded): 24 applicable, 11 covered, 5 partial, 8 gaps.

## Not relevant for Flutter
- `NSCoding`, `UIAppearance` proxies (`MorphThemeData.appearances` carries a `MorphDatePickerAppearance`), target-action plumbing.
- Style resolution traits (Mac Catalyst, iPad idiom); `UICalendarSelection.updateSelectableDates()` (Flutter rebuilds).

## morph-only API
- `today` (the day tinted as today; Material `currentDate`), `use24HourFormat` (null follows `MediaQuery.alwaysUse24HourFormat`).
- `MorphDatePickerAppearance` (17 colors, 2 opacities, light / dark / high-contrast tables).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | inline style (calendar in place) | H | M | draw `MorphDatePickerStyle.inline` |
| 2 | locale defaults are English; nothing read from `Localizations` | H | M | default `MorphDatePickerLocalizations` from the app's locale |
| 3 | `countDownTimer` + `countDownDuration` | M | M (measure first) | add the mode |
| 4 | wheels style in place (date wheels) | M | M-L (measure first) | draw `MorphDatePickerStyle.wheels` |
| 5 | `yearAndMonth` mode | M | S-M | reuse the month/year wheels |
| 6 | `roundsToMinuteInterval = false` | L | S | add the flag |
| 7 | animated external `value` change | L | S | animate while open |
| 8 | day decorations, selectable predicate, multi-date | L | S-M | with inline |

## Breaking changes before 1.0
- Done: `firstDate` / `lastDate` -> `minimumDate` / `maximumDate`; the six formatters -> `MorphDatePickerLocalizations`; the presentation enum is `MorphDatePickerStyle { compact, inline, wheels }` with `style`; `minuteInterval`.
- Open: decide whether `use24HourFormat` and `firstDayOfWeek` move into `MorphDatePickerLocalizations` (UIKit derives both from `locale` / `calendar`).
- Open: `minimumDate` later than `maximumDate` should ignore both, as UIKit's header states.

## Behaviour fidelity
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page | inline / wheels styles, countDownTimer, yearAndMonth |
| layout | replayed | passport "Spec - compact labels", "overlay", "calendar", "month and year wheels", "time wheels"; `ios27/date_picker/placements.json`, `date-low.jsonl`; test/date_picker_test.dart (placement, 16 pt margin, six-week rows, time and 12-hour wheel rows, month/year wheel rows within 0.5 - 0.8 pt) | inline / wheels layouts; RTL placement is mirrored, not measured |
| states | unbacked | disabled labels replayed (`ios27-device/disabled/disabled.json`, test/disabled_test.dart); chosen-day and today colors [film] | `unavailableDayOpacity` 0.35 unmeasured; `todayFillColor` has no source |
| transitions | approx | open / close / turnaround / reopen / switch replayed on device rows (`vid-date`, `tm-openclose-*`, `tm-closeopen-*`, `vid-both`; scale rms < 0.015 - 0.02); year picker fades and chevron replayed (`my-*`, `myrev-*`, `my31`, `mypage`; rms < 0.035); label dim replayed (sim `date-open`) | month page turn is a 0.3 s sine ease, 2.5 pt tolerance (UIScrollView curve differs, declared); AM/PM flip 200 ms unmeasured; Reduce Motion picker switch not ported |
| boundaries | unbacked | minute floor read from UIKit (notes private; test/date_picker_interval_test.dart); month-end clamp on device (`my31`); six-week months [device] | min > max clamps to `minimumDate` (UIKit ignores both); time wheels at a boundary day and the disabled-day look unmeasured |
| configuration | missing | date / time / dateAndTime, 12 and 24 h measured on device | inline, wheels, countDownTimer, yearAndMonth |
| events | measured | wheel-rest `valueChanged` rows in `my31` / `mypage`; widget tests assert the same values | time-wheel `valueChanged` timing (0.2 - 0.36 s after the lift) not compared |
| input | measured | quick succession, tap outside while opening, label tap while closing (device rows, filler-stroke taps): replayed | wheel deceleration (64 pt drag = two rows) measured, not replayed; Escape / Space / Enter have no native twin |
| mutation | unbacked | test/date_picker_updates_test.dart (behaviour contracts only) | external `value` change while open and min / max change while open have no recording; `setDate(animated:)` missing |
| accessibility | unbacked | Reduce Motion fade, Increase Contrast tables and wheel haptic read from UIKit (notes private; states.md) | overlay text scale capped at 1.2 without a source; Dynamic Type of the labels unmeasured; English defaults |
| optics | approx | platter color light / dark [device]; NEAR raster and fade trades declared in `MorphDatePicker` | month/year wheel perspective not reproduced; flat-tier shadow (blur 20, offset 6, 0x24000000) has no source |
| platform | unbacked | margins 16 / 20 by screen width [device + sim] | RTL placement inferred; Gregorian only |
| performance | measured | passport "Performance trade" sections (Pixel 6a matrix runs); test/glyph_strikes_test.dart, test/glyph_scale_date_test.dart, example/test/control_matrix_test.dart | - |
