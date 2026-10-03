# Page control passport

Status: measured device (120 Hz) + simulator; ported; replayed
(indicators_test).

## Native

`UIPageControl` (platter = `UIVisualEffectView`), `UIPageControlProgress`,
`UIPageControlTimerProgress`. Public API (SDK 27.0): `numberOfPages`,
`currentPage`, `hidesForSinglePage`, `pageIndicatorTintColor`,
`currentPageIndicatorTintColor`, `backgroundStyle` (automatic / prominent /
minimal), `direction` (natural / LTR / RTL / topToBottom / bottomToTop),
`interactionState`, `allowsContinuousInteraction`,
`preferredIndicatorImage`, per-page indicator images (and current-page
images), `sizeForNumberOfPages:`, `progress` (`currentProgress`,
`progressVisible`, delegate; timer: `preferredDuration`, per-page
`setDuration:forPage:`, `resetsToInitialPageAfterEnd`, `running`,
pause/resume).

## Spec

- Dots 9.67 / 7.67 pt on a 17.67 pitch; control 25.67 tall (5 pages: 126
  wide) [layout].
- Tap on either half steps on the LIFT.
- Platter fades in after 0.193 s of touch on a critically damped 0.100 s
  spring, out 0.032 s after the lift on 0.100 [device 120 Hz rows,
  0.013 - 0.017 rms; the 60 Hz simulator read 0.2, 0.106/0.973 and 0.02 and
  replays within a frame].
- Scrub = nearest dot +- 1.5 pt.
- Progress capsule 27.33 pt; old fill fades on 0.381/0.963, widths change
  on 0.398/0.927 [sim].

## Fixtures

Device `ios27-device/page_control/pc-{tap-right,hold,scrub}.jsonl`;
simulator `ios27/page_control/` (+ pc-timer).

## Recapture

Scene `w2page`: `PROBE_PAGES`, `PROBE_PCSTYLE=prominent|minimal`,
`PROBE_PCTIMER=<seconds>`, `PROBE_SCRIPT page:<n>`.
Widgets2UITests.testW2Page.

## morph

page_control.dart (`MorphPageControl`, `MorphPageControlMotion`,
`MorphPageControlTuning`, `MorphPageControlStyle`,
`MorphPageControlBackground`).

## Not reproduced / open

- A long scrub far past the dots steps irregularly in UIKit (pc-scrub-far).

## API gaps

- `direction` (vertical, explicit RTL), `hidesForSinglePage`,
  `allowsContinuousInteraction = false`.
- Custom indicator images (per page), `sizeForNumberOfPages`.
- Timer progress API (per-page duration, pause/resume, reset at end) -
  morph takes a progress value only; check parity.
