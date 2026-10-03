# Date picker passport (compact, calendar, wheels, 12h, month/year header)

Status: measured simulator (XCUITest) + device (timing, film light/dark);
ported; replayed (date_picker_test). MONTH/YEAR HEADER: IN PROGRESS (another
agent, "dpw", holds the device lock and has uncommitted probe changes in
Sources/Extras.swift and UITests/ExtrasUITests.swift: `PROBE_X3MY=1`,
`PROBE_X3TREES=1`, testX3MonthYear / testX3MonthYearCases) - ask the
keeper for its results before porting the header.

## Native

`UIDatePicker` compact style: labels `_UIDatePickerCompact*`, overlay
`_UIDatePickerOverlayPlatterView`, `_UIDatePickerCalendarView`,
`_UIDatePickerView` (wheels). No CASpringAnimation to read: springs are fits.
Public API (SDK 27.0): `datePickerMode` (time / date / dateAndTime /
countDownTimer / yearAndMonth), `preferredDatePickerStyle` (automatic /
wheels / compact / inline), `date`, `setDate:animated:`, `minimumDate`,
`maximumDate`, `locale`, `calendar`, `timeZone`, `minuteInterval`,
`roundsToMinuteInterval`, `countDownDuration`.

## Spec - compact labels [layout]

115 x 34.33 (date) / 70 x 36 (time) capsules, tertiarySystemFill, padding
12, 4 apart; text dims toward ~0.5 under a touch on a 0.47 s
CABasicAnimation (0.25, 0.1, 0.25, 1) and turns accent while open.

## Spec - overlay

- Radius 28; calendar 320 x 332 for five weeks; wheels 232 x 204.
- ONE progress: scale 0.2 -> 1 about the anchor, alpha, box height 50 ->
  full (content revealed from the anchored edge); open 0.32/0.80, close
  0.348/0.86 [fit, 0.002 rms].
- Opens 0.14 s and closes 0.055 s after the lift (`openDelay`/`closeDelay`;
  device rows 0.010 rms vs 0.27 / 0.16 without).
- Tap outside while opening turns it around 0.037 s after the lift
  (`closeDelayWhileOpening`); tap on the label while closing opens a NEW
  overlay 0.072 s after the lift while the old one finishes (`reopenDelay`).
- Date-and-time: tapping the other label turns the open overlay into the
  other picker on a crit 0.25 s spring 0.088 s after the lift, contents
  crossfading on the same progress (`switchSpring`, `switchDelay`).
- Glass fades via `MorphGlassSurface.opacity` (no gray platter).
- `morphPlaceDatePicker`: top 6 below the label's center (bottom 6 above it
  when no room below), trailing edge 6 before the center then clamped to 20
  pt margins (16 pt on phones under 414 pt, `marginFor`); anchor = label
  center x clamped onto the overlay (5/5 placements).

## Spec - calendar

Picking a day applies at once and keeps the overlay open; tap outside (on
touch-up) or Escape closes. Months page on a 0.3 s sine ease (2 px rms;
UIScrollView's exact curve differs). Title 20.33 pt in, not truncated;
chevrons label-colored 10 x 17.33, 2.6 thick; chosen day not today on a label
disc (`selectedDayFillColor`/`TextColor`); today tint. Header, weekday
initials, grid geometry from the view tree.

## Spec - wheels

Cylinder rows 31.3 / 56.7 pt out at 0.905 / 0.647 height; columns at 73.5 /
148.5 pt; 21 pt rows magnified to 23.5 in the band (band 200 x 32, rows
outside at ea 0.447); fade toward the edges by a table read from device
screenshots; fast deceleration (64 pt drag turns two rows). 12-hour: AM/PM
wheel, hour wheel 1 - 12 right-aligned, AM/PM flips as hours pass 11/12.

## Fixtures

Device `ios27-device/date_picker/` (vid-date, vid-both, wheels.json,
tm-openclose-{050,150,300}, tm-closeopen-*). Simulator
`ios27/date_picker/` (date-open, date-page, date-low, placements.json).
Film crops `references/date-video/`.

## Recapture

Scene `x3date`: `PROBE_DMODE=time|both`, `PROBE_DATE`, `PROBE_LOCALE`,
`PROBE_DARK`, `PROBE_X3MY=1` (month/year sampler pattern, in progress),
`PROBE_SCRIPT` (open, close, next, tree-*). ExtrasUITests testX3Date,
testX3Video, testX3Timing (twoTaps, `PROBE_GAPS`), testX3Shots,
testX3MonthYear, testX3MonthYearCases. A compact picker cannot be opened
programmatically - touches only.

## morph

date_picker.dart (`MorphDatePicker`, `MorphDatePickerMode` date / time /
dateAndTime, `MorphDatePickerStyle`; `use24HourFormat`, `firstDayOfWeek`,
`firstDate`/`lastDate`, formatters), date_picker_motion.dart
(`MorphDatePickerMotion`, `MorphDatePickerTuning`, `morphPlaceDatePicker`).
Calendar drawn by morph; wheels are ListWheelScrollViews.

## Not reproduced / open

- Month/year header picker (in progress).
- UIScrollView's exact paging curve.

## API gaps

- `inline` and `wheels` styles as standalone pickers (morph: compact only).
- `countDownTimer` and `yearAndMonth` modes.
- `minuteInterval` / `roundsToMinuteInterval`.
- `locale` / `calendar` / `timeZone` (non-Gregorian calendars, locale
  week start beyond `firstDayOfWeek`).
- `setDate:animated:` wheel animation.
