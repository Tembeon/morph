# Segmented control passport

Status: measured device + simulator; ported; replayed (lens_test).
Shared machinery: [lens-and-flex.md](lens-and-flex.md).

## Native

`UISegmentedControl` (lens = `_UILiquidLensView`). Public API (SDK 27.0):
`initWithItems:`, `initWithFrame:actions:`, insert/remove segment
(title / image / action, animated), `setTitle/Image/Action/Width/
ContentOffset/Enabled:forSegmentAtIndex:`, `selectedSegmentIndex`,
`momentary`, `apportionsSegmentWidthsByContent`, `selectedSegmentTintColor`,
`setTitleTextAttributes:forState:`, background/divider images,
`contentPositionAdjustment`.

## Spec

- Selects on touch-UP. A press on a non-selected segment does nothing
  until release [device].
- Release outside [device, 2026-10-13, 300 x 32, press on a non-selected
  segment, slide straight down, release]: 30, 50 and 60 pt below the
  bottom edge select the pressed segment; 70, 80, 100 and 130 pt below
  change nothing. morph `MorphSegmentedControl.releaseSlop` 70: within it
  the release picks the slot nearest the finger, beyond it the touch ends
  as a cancel (the lens settles back). 70 rather than 65 because one 70 pt
  bound with the far edges excluded (`CGRectContainsPoint`) also gives
  the glass button's four measured edges. A selected-segment drag that
  leaves, and the other sides, are not measured.
- Unlift anchored 0.25 s after the touch-up (`hangFromTouch`); the lift
  start varies with input latency, the touch-up anchor does not [device].
- Press on the SELECTED segment lifts in place after `pressDelay` 40 ms and
  drags it: grab offset preserved, follow spring 0.225/1.0 [device],
  rubber band past the end CENTERS (12, 0.55); release picks the slot
  nearest the FINGER. dragGain 1.
- Tap on the selected segment: lifts in place, lands no earlier than
  `pressHang` 0.25 s after the touch (or `releaseDelay` after a longer hold).
- Lens lift +24 x +16 px; travel 0.401/0.856; flex gains see lens-and-flex.
  Replay-verified against ios27{,-device}/lens: the former passport
  0.392/0.863 fails the device tap replay at unchanged tolerances.
- Text: segments 13 regular, selected 13 medium (wght 510; UIKit also uses
  GRAD 466/448 `.SFUI-RegularG3`, not reproduced - width unaffected).
  Labels follow text scale up to 1.4, sized by the wider of both styles.
- Look: track is a PLAIN fill (tertiary fill, not glass); resting lens is
  an opaque platter; lifted lens is clear glass, magnification 0 (held label
  0.996, in place), shrink 0.20 with rim profile (see glass-optics).
- Geometry in morph style: height 32, inset 2, contentPadding 16
  ([layout], simulator view tree).

## Disabled [device, light + dark, 2026-10-03]

- The WHOLE control at opacity 0.5 (`UISegmentedControl` alpha 0.5; track,
  platter and labels together). Pixels = 0.5 enabled + 0.5 background, rms
  0.11 (dark) / 0.27 (light) of 8 bit. Label colors unchanged.
- Switches in one frame both ways (no animation).
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method and recapture in [states](states.md) (StatesUITests testDisabled, scenes x4dis / x4disbars / x4distab / x4disalert).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): `disabledOpacity` 0.5 as one layer (pixel rule
  checked light + dark).

## Fixtures

Device `ios27-device/lens/segmented-*` (seg2/seg3 taps, tap-selected,
seg5 drag slow from selected, release-choice rubberband, scrub overrun back,
narrow content, seg5seg4 taps); `ios27-device/tracking/release-outside.jsonl`
(lab scenario `tracking-bounds`, control at 51,600 300x32 A/B/C). Simulator `ios27/lens/segmented-*`.
Reference: `references/dark/segmented-{resting,held-selected}.png`.

## Recapture

Scene `segmented` (rows seg2..seg5, segContent, segContent4, segNarrow).
Device: `PROBE_PLAN=lens` (or `recaplens`), `PROBE_ONLY=<capture>`;
ProbeUITests.testLens / testRecapLens.

## morph

`MorphSegmentedControl` (+`MorphSegmentedStyle`), segmented_control.dart,
lens_motion.dart (`MorphLensTuning.segmented`). Tests: lens_test (sim 60 Hz
and device 120 Hz), lens_scrub_test, lens_widgets_test,
lifted_lens_look_test, controls_scroll_test (the control owns a touch
after 150 ms or a horizontal drag past slop), release_bounds_test (replays
release-outside.jsonl).

## Not reproduced / open

- GRAD axis of the label font.
- Reduce Motion unmeasured (plan in states.md).

## API gaps (UIKit has, morph lacks)

- Image segments (and image + title), UIAction segments.
- Per-segment enabled, per-segment fixed width, content offset.
- `momentary` mode.
- Animated insert/remove of segments (is there a lens/width animation? not
  measured).
- `selectedSegmentTintColor` exists as style only; title attributes per
  state only via style text styles.
