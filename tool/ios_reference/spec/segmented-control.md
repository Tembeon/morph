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
- Title highlight [sim 2026-10-14, XCUITest tap and 1 s hold, the
  CABasicAnimations UIKit adds to `UISegmentLabel` read live]: a touch on
  a NON-selected segment dims its title 1 -> 0.2 over 0.47 s, timing
  (0.25, 0.1, 0.25, 1), from the touch-down frame; the release returns it
  to 1 over 0.2 s on the same curve from where it is (a quick tap reaches
  about 0.93 first). `MorphSegmentHighlightMotion`; the selected segment
  and a finger sliding to another segment are not measured (the dim
  stays on the pressed segment). test/highlight_motion_test.dart. The dim
  sets the alpha of the title's own layer (no build, no repaint); each
  title adds one proxy paint where the glass records the labels (perf
  counts segmented-drag / lens-held fake and liquid +1.7 / +3 paints,
  ceilings re-pinned).
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

`MorphSegmentedControl` (+`MorphSegmentedControlAppearance`), segmented_control.dart,
lens_motion.dart (`MorphLensTuning.segmented`). Tests: lens_test (sim 60 Hz
and device 120 Hz), lens_scrub_test, lens_widgets_test,
lifted_lens_look_test, controls_scroll_test (the control owns a touch
after 150 ms or a horizontal drag past slop), release_bounds_test (replays
release-outside.jsonl).

Repaints: the control is a repaint boundary, so its lens no longer
repaints the page around it, and on the flat tier (and without a painter)
its labels sit in a boundary of their own: the lens's frames repaint the
lens fill alone. Host recorder, programmatic selection, flat: 0/2/29 ->
0/2/8 a frame. The liquid tier records the labels for its lens copy and
keeps them in its picture.

## Not reproduced / open

- GRAD axis of the label font.
- Reduce Motion unmeasured (plan in states.md).

## API gaps (UIKit has, morph lacks)

- Image segments (and image + title), UIAction segments.
- Per-segment enabled and fixed width exist (`MorphSegment.enabled`,
  `.width`); morph draws a disabled label at `disabledOpacity`. UIKit
  [read from UIKit, notes private]: an image segment's content drops to
  alpha 0.5; a disabled title takes the control's disabled color, a gray
  of the inherited tint's white level (capped at 0.6 in light) at alpha
  0.45 light / 0.35 dark. Not ported: which tint a segmented label
  inherits is not read, so the color needs a device capture. Content
  offset is missing.
- No selection exists (`selectedIndex: null`, `noSegment`): the lens is
  hidden; the first selection appears at rest on its segment. UIKit's
  classic selection view fades in (opacity spring, 0.1 s delay) and pops
  from a hidden scale [read from UIKit, notes private], but the iOS 27
  lens path was not traced, so the phone's first-selection animation is
  still NOT known - needs a capture.
- `momentary` mode.
- Animated insert/remove of segments (is there a lens/width animation? not
  measured).
- `selectedSegmentTintColor` exists as style only; title attributes per
  state only via style text styles.
