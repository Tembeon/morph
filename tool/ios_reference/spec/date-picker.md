# Date picker passport (compact, calendar, wheels, 12h, month/year header)

Status: measured simulator (XCUITest) + device (timing, film light/dark,
month/year wheels light + dark); ported; replayed (date_picker_test incl.
its month and year groups; month/year landed in f2f0c4d).

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
touch-up) or Escape closes. SIX WEEKS (August 2026): the platter stays
320 x 332, rows 38 apart (cells 42.67 x 38, disc 38) from the same top -
no growth per week; first row 1 pt below the collection view's top
(`gridTop`). Months page on a 0.3 s sine ease (2 px rms;
UIScrollView's exact curve differs). Title 20.33 pt in, not truncated;
chevrons label-colored 10 x 17.33, 2.6 thick; chosen day not today on a label
disc (`selectedDayFillColor`/`TextColor`); today tint. Header, weekday
initials, grid geometry from the view tree.

## Spec - month and year wheels [device, light + dark, film + layers]

- Tap on the month title (`_UICalendarHeaderTitleButton`, "Show / Hide year
  picker") puts `_UICalendarMonthYearSelector` (320 x 246.33 from the weekday
  row down, rebuilt on every show) in the SAME 320 x 332 platter.
- Weekday row, day grid and both month chevrons fade out, selector in, on
  CABasicAnimation 0.25 s (0.42, 0, 0.58, 1) (`yearPicker*`; layers follow
  to 1e-4, start fitted), starting 0.069 s after the lift (0.061 - 0.077)
  and 0.019 s back (0.013 while the wheels still fade in). A second tap
  restarts the fades from the presentation value (beginFromCurrentState,
  velocity kink); the title chevron's quarter turn (image 10.33 x 14) is
  ADDITIVE - carries on to 0.82 before returning (`yearPickerTurn` sums
  running turns). Title turns accent at the tap, back to label on return,
  no animation.
- Wheels: UIDatePicker 288 x 216 at 16 x 76.84 in the platter; band 288 x
  34 capsule (0x14747480 light / 0x2E767680 dark = `wheelBandColor`);
  months left-aligned at 54 (band, 23.5 pt) / 57.95 (outside, 21 pt; morph
  centers the month box at 91.13 to land both), years centered at 230;
  cylinder radius 87.7, rows 31.87 apart (0.14 pt rms); outside rows' peak
  contrast 0.36 / 0.324 / 0.19 / 0.092 at 31.3 / 58.3 / 77.6 / 87.1 pt (fade
  table over the 0.4 faded opacity). Month wheel loops.
- Selection: wheels open on the SHOWN month (after a page turn: that month);
  a wheel coming to rest (valueChanged 0.2 - 0.36 s after the lift) sets the
  date to (wheel year, wheel month, chosen day clamped: Oct 31 -> Nov 30,
  back -> Oct 30), title follows; opening/closing the wheels alone changes
  nothing. Closing the overlay with the wheels up and reopening shows the
  grid.
- Not reproduced: UIKit's slight perspective toward the picker center (~6 pt
  at the last row).

## Spec - time wheels

Cylinder rows 31.3 / 56.7 pt out at 0.905 / 0.647 height; columns at 73.5 /
148.5 pt; 21 pt rows magnified to 23.5 in the band (band 200 x 32, rows
outside at ea 0.447); fade toward the edges by a table read from device
screenshots; fast deceleration (64 pt drag turns two rows). 12-hour: AM/PM
wheel, hour wheel 1 - 12 right-aligned, AM/PM flips as hours pass 11/12.

## Fixtures

Device `ios27-device/date_picker/` (vid-date, vid-both, wheels.json,
tm-openclose-{050,150,300}, tm-closeopen-*, my-light, my-dark, myrev-030,
myrev-120, my31, mypage, month-year.json - rows: anim, V of
_UICalendarWeekdayView / _UICalendarMonthYearSelector, chevron, evt
valueChanged v = epoch seconds UTC; see manifest). Simulator
`ios27/date_picker/` (date-open, date-page, date-low, placements.json).
Film crops `references/date-video/`.

## Recapture

Scene `x3date`: `PROBE_DMODE=time|both`, `PROBE_DATE`, `PROBE_LOCALE`,
`PROBE_DARK=1/0` (0 forces light), `PROBE_X3MY=1` (month/year sampler
pattern), `PROBE_X3TREES=1` (tree dump 1.2 s after every touch-up),
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

- Perspective of the month/year wheel rows (above).
- UIScrollView's exact paging curve.

## API gaps

- `inline` and `wheels` styles as standalone pickers (morph: compact only).
- `countDownTimer` and `yearAndMonth` modes.
- `minuteInterval` / `roundsToMinuteInterval`.
- `locale` / `calendar` / `timeZone` (non-Gregorian calendars, locale
  week start beyond `firstDayOfWeek`).
- `setDate:animated:` wheel animation.

## Implementation notes (moved from CLAUDE.md)

- Overlay glass fades through `MorphGlassSurface.opacity`, never an
  Opacity layer (that read an empty backdrop: a gray platter until
  settled).
- Quick succession [device rows, tm-openclose-* / tm-closeopen-*, the
  filler-stroke trick]: the turn-around from a tap outside while opening
  happens even when the tap lifts before the opening started (0.003 scale
  rms with the open start fitted 0.131 - 0.146); while the old overlay
  closes, two platters are on screen and the closing overlay no longer
  swallows the label tap (its outside Listener is IgnorePointer while
  leaving).
- Date-and-time switch: frame lerps between the two placements (0.04
  percent rms), contents pinned to the anchored corner, the label accent
  moves at once.
- Calendar look [film]: title chevron 6.33 x 11.67 accent; the title never
  shares the header with a spacer (it truncated to "October 2...").
- TIME WHEELS [device labels, wheels.json]: rows 21 pt at opacity 0.4
  (UIKit reports 0.447; 0.4 matches the screen), 23.5 pt in the 200 x 32
  band (ListWheelScrollView magnifier), on a true cylinder of radius 73.5
  (Flutter's angle is dy * pi / H for diameterRatio < 1, so squeeze =
  32.4 pi / (172 x 0.4405) restores arc = row; perspective ~0), darkened
  toward the edges by a measured table (`_WheelMetrics.fade`, ShaderMask;
  lossless device screenshots, digit contrast per pixel row native over
  ours: rows at 31 / 57 / 72 pt show 0.34 / 0.24 / 0.05 of the band's
  contrast, ours 0.34 / 0.24 / 0.06 - cos^1.4 gave 0.37 / 0.25 / 0.09);
  columns at 73.5 / 148.5 pt; fast deceleration (a 64 pt drag turns two
  rows as on the device; the default physics turned six).
- 12-HOUR WHEELS [device, en_US@hours=h12, tree dump + screenshots]: hour
  1..12 right-aligned ending 51.33 pt in (55 in the band), minutes centered
  110.67, AM/PM left-aligned at 158 (156 in the band), same 232 x 204
  platter; the hour wheel crossing 11 <-> 12 flips AM/PM (7 AM + 5 rows =
  12 PM, back 3 = 9 AM); the flip's animation is not measured (200 ms ease,
  like the accessibility steps). `use24HourFormat` null follows
  MediaQuery.alwaysUse24HourFormat (the phone's 24-Hour Time).
- Dark platter color (owner film, 44 vs native 33 gray): the renderer draws
  the surface color as the tint; `MorphDatePickerStyle.dark` platterColor
  0xF22C2C2E is the cause - the menu's measured dark glass 0xF2222222 reads
  33 - 34. OPEN (date_picker.dart not changed yet).
