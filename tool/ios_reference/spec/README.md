# Spec passports - the native golden standard

morph copies iOS 27 Liquid Glass. The spec is UIKit itself, measured with
the probe in `tool/ios_reference/`. A PASSPORT is one compact page per
control or family that says everything a porting agent needs, so it never
has to read all of CLAUDE.md:

- the native classes and their public API (from the iPhoneOS27.0.sdk
  UIKit headers - `xcrun --sdk iphoneos --show-sdk-path`),
- every measured number with its SOURCE and spread,
- fixtures, recordings and reference images,
- how to recapture (probe scene, UITest, env),
- where morph implements it and which test replays it,
- what is NOT reproduced, open questions, and API gaps.

Source tags used in the passports:

| tag      | meaning |
|----------|---------|
| [tuning] | read live from UIKit/SwiftUI PTSettings or a CASpringAnimation (exact) |
| [fit]    | fitted to recorded presentation-layer rows (spread given when known) |
| [film]   | fitted to screen recordings (MorphRecorder or simctl recordVideo) |
| [layout] | read from the view tree / layer properties at rest |
| [sim]    | iOS 27.0 simulator only (60 Hz), not yet confirmed on the device |
| [device] | iPhone 16 Pro, iOS 27.0.1, 402 x 874 pt, 120 Hz (the owner's phone) |

The device wins over the simulator whenever they disagree beyond noise.

## How a porting agent uses a passport

1. Read the passport (and `lens-and-flex.md` for anything that lifts).
2. Load the fixtures with `test/support/trace.dart`:
   `Trace.load('test/fixtures/ios27-device/<family>/<file>.jsonl')` gives
   `touches` (`TraceTouch` t, phase 0 began / 1 moved / 2 stationary /
   3 ended, x, y in window pt, t on the media clock), `frames`
   (`TraceFrame`, raw row map, `opt(key)`), `layers`, `events`, `states`,
   `layer(path)`, `track(cls, yRange:)`. Every family's `manifest.json`
   (or `manifest.txt`) documents its row keys - read it first.
3. Write the behaviour as a PURE motion class (explicit time in, geometry
   out; `MorphSpringState`, `MorphTimeline`, `MorphSubClock`), then the
   replay test: feed the recorded touches at their recorded times, advance
   to every recorded frame (step frames the recorder missed too), compare
   geometry within per-quantity tolerances. Tolerances are not knobs; a red
   replay is a fidelity regression.
4. Only then the widget host (Listener, MorphClock, painting).
5. A value without a measurement behind it is a measurement REQUEST, not a
   tuning job (see below).

## Requesting a measurement from the keeper

Send (through the coordinator) a request naming: the control, the exact
quantity (e.g. "close spring of X, per frame center"), the gesture or
programmatic trigger, light/dark, device or simulator, and whether layer
rows suffice or a film is needed (glass edges living in SwiftUI, alpha
outside the sampled layers and anything visual need a film). The keeper
answers with a fixture path plus a passport update.

## Device lock (one phone, many agents)

`/tmp/morph-native/device.lock` is a DIRECTORY (mkdir is atomic) with an
`owner` file: `<agent / task>, <date>`.

```sh
mkdir /tmp/morph-native/device.lock 2>/dev/null \
  && echo "keeper: tab bar recapture, $(date)" > /tmp/morph-native/device.lock/owner \
  || cat /tmp/morph-native/device.lock/owner   # busy: wait, ask the coordinator
# ... use the phone ...
rm -rf /tmp/morph-native/device.lock
```

Never touch the phone without the lock; never break someone else's lock.
The Mac belongs to the owner: no GUI apps, simulators or anything that
steals focus unless the coordinator says the Mac is free (MorphRecorder is
launched with `open` - ask first).

## Recording pipeline

Probe app: `Sources/` (App, Scenes, Controls, Recorder, Settings, Merge,
Bars, Widgets2 `w2*`, Extras `x3*`, SheetNav `sn*`, Typography `fonts`),
UITests in `UITests/` (ProbeUITests, BarsUITests, Widgets2UITests,
ExtrasUITests, SheetNavUITests, MenuAnchorUITests). The recorder samples
presentation layers every display-link tick and logs only changed rows.

- Simulator: `build.sh` (swiftc, installs on the booted sim), launch with
  `SIMCTL_CHILD_PROBE_SCENE=<scene> xcrun simctl launch --terminate-running-process booted dev.tembeon.morph.probe`,
  `pull.sh` copies Documents to `recordings/`.
- Device: `device.sh` (xcodegen project.yml -> build-for-testing ->
  test-without-building -> devicectl pull). `PROBE_PLAN=lens|controls|menu|
  sliderends|slidervideo|dragtiming|recaplens|recapcontrols|recapmenu|refs|
  tablook|tabglowdrag|merge|mergedyn|bars|all`, `PROBE_ONLY`, `PROBE_UDID`
  (default 00008140-001039D01442801C), `PROBE_TEAM` (83S63575XD),
  `PROBE_STEP_HZ` (30), `PROBE_SKIP_BUILD=1`, `PROBE_RESULT` (keep the
  xcresult; refs screenshots are attachments), `PROBE_OUT`. Other UITest
  classes: `xcodebuild test-without-building -only-testing:ProbeUITests/<Class>/<test>`
  with `TEST_RUNNER_PROBE_*` env, then `xcrun devicectl device copy from
  --domain-type appDataContainer --domain-identifier dev.tembeon.morph.probe
  --source Documents`. Phone: unlocked, trusted, developer mode,
  Settings > Developer > Enable UI Automation ON. Never edit device.sh
  while it runs (sh reads it incrementally).
- Common env: `PROBE_SCENE`, `PROBE_REC` (record name), `PROBE_DARK=1/0`,
  `PROBE_SCRIPT="action@seconds;..."` (w2/x3/sn scenes), `PROBE_W2TRACK` /
  `PROBE_X3TRACK` (class regex, `.` = everything), `PROBE_W2DEPTH` /
  `PROBE_X3DEPTH`, `PROBE_W2FILTERS=1` (backdrop filter inputs),
  `PROBE_LENS_ANIMS=1`, `PROBE_TABLAYERS=1`. Scene-specific env is listed
  in each passport.
- Reading tuning live: `objc_copyClassList` over the RAW pointer array,
  keep PTSettings subclasses, alloc/init + `setDefaultValues`, read
  properties via `class_copyPropertyList` + typed IMP casts. NEVER KVC on
  private classes (throws, kills the probe).
- Screen recorder (device film): `screen_recorder/build.sh` builds
  MorphRecorder.app (CoreMediaIO, full resolution; camera permission once).
  `: > log.txt; open -W .../MorphRecorder.app --args "$PWD/log.txt" /abs/out.mov <seconds>`
  in the background, then drive the phone. The stream is variable-rate and
  DROPS frames at UIKit morph starts (~45 fps): extract with
  `ffmpeg -fps_mode passthrough` and real pts, never `fps=60`; align the
  film to the probe's layer rows of the same run. A video app's strokes
  must be timed on a clock, not per pumped frame. Simulator film:
  `xcrun simctl io <udid> recordVideo --codec=h264`.
- morph side of a film: `example/integration_test/*_video_test.dart`
  (menu, slider, menu_anchor, search_date_scenes) as a profile build
  launched with devicectl; menu_trace_test writes per-frame geometry.

### XCUITest synthesizer quirks (device)

- Dense paths replay late and in bursts (120 Hz points: a 1 s ramp arrived
  in 0.48 s); 60 Hz is smooth but ~16 percent slow, 30 Hz ~9 percent slow
  -> `PROBE_STEP_HZ` 30. UIKit still receives touches at 120 Hz.
- Flings under ~100 ms collapse into one jump move; faster than ~250 pt/s
  slider flings could not be synthesized.
- Strokes in ONE record are re-timed: each starts at the previous lift
  whatever its planned offset. Timed double taps use the FILLER-STROKE
  trick (`ExtrasUITests.twoTaps`): tap A, a filler stroke held `gap`
  seconds at an inert point, tap B - the gap is then real.
- A second stroke whose start equals the first's lift is delivered as the
  SAME finger (garbled touches) - start it later.
- Two synth requests in flight are refused (XCTDaemonErrorDomain 21);
  separate calls have ~217 ms minimum latency.
- Analyses use the LOGGED touch rows, never the plan.
- A nearly full host disk caused 0.3 - 1.7 s main-thread stalls in held
  gestures - discard such passes.
- XCUIElement keyboard frames exclude the bottom row: the iPhone 16 Pro
  keyboard is 328 pt tall (top 546).
- Glass morphs living in SwiftUI (tab search morph, zoom) do not show in
  view frames: film them.

### Fixture conventions

`test/fixtures/ios27/<family>` = simulator (60 Hz), `ios27-device/<family>`
= device (120 Hz). Compact jsonl rows (`k` = start, touch, dl, frame,
state, evt, L, V, f, ...), one manifest per family. Recaptures APPEND
(note "recapture <date>"), nothing is overwritten. Raw recordings live in
`tool/ios_reference/recordings/` (gitignored); fit scripts and reports in
`/tmp/morph-native/` (volatile - fixtures and tests are the durable
record). Lossless reference PNGs: `tool/ios_reference/references/`
(`dark/` static set; `*-video/` native-top / morph-bottom crops; `merge/`).
The LIGHT static set is still pending.

## Status

M = measured (D device, S simulator only), P = ported + replayed, G = known gaps.

| passport | measured | ported | main gaps |
|----------|----------|--------|-----------|
| [lens-and-flex](lens-and-flex.md) | D tuning + fit | P | 60 Hz lens refresh on 120 Hz not copied (by choice) |
| [segmented-control](segmented-control.md) | D+S | P (lens_test) | images, per-segment enable/width, momentary, insert/remove animation |
| [tab-bar](tab-bar.md) | D (lens, glow, look) | P | slow lift not modelled; minimize, accessory, badges, sidebar |
| [search-tab-bar](search-tab-bar.md) | D film | P | glass morph rect-lerp fit only |
| [switch](switch.md) | D | P | checkbox style, title, on/off images |
| [slider](slider.md) | D + film | P | white release flash; thumbless style, neutral value, tick titles/images, min/max images; dark lifted thumb look |
| [stepper](stepper.md) | S | P | wraps, continuous, autorepeat flag, images; device check |
| [glass-button](glass-button.md) | D | P | clear glass, sizes, corner styles, subtitle, menus |
| [menu-button](menu-button.md) | D + film | P | submenus, palettes, inline sections, selection state, "Ask Siri" row |
| [context-menu](context-menu.md) | D | P | preview-vc, commit/pop preview, badges, rich/compact appearance |
| [bars](bars.md) | D | P | title menu, subtitles, search integration, badges, toolbar drift |
| [navigation-pages](navigation-pages.md) | D | P (incl. push zoom) | zoom alignment rect, interactive dismiss filter |
| [sheets](sheets.md) | D + film (zoom) | P | 8 pt present drift, 2 percent stretch, keyboard avoid motion, edge-attached, placement |
| [alerts](alerts.md) | D+S | P | source tint dim, severity, popover arrow in glass |
| [search](search.md) | D + film | P | scope bar, suggestions, placements other than bottom toolbar |
| [date-picker](date-picker.md) | D + film | P (month/year IN PROGRESS) | inline style, countdown, minuteInterval, locale/calendar |
| [page-control](page-control.md) | D | P | far scrub irregular steps; vertical direction, custom indicator images |
| [progress-view](progress-view.md) | S | P | bar style look, observedProgress |
| [activity-indicator](activity-indicator.md) | S | P | none of note |
| [typography](typography.md) | D == S | P | Dynamic Type, GRAD axis, date wheel |
| [glass-optics](glass-optics.md) | D (refs, layers) | P (renderer) | light reference set; lens rim minification profile approximated |
| [skin-merge](skin-merge.md) | D | P | 3+ mass normal mixing unmeasured |
| [engine-flight](engine-flight.md) | D tuning | P | - |

Disabled opacities and Reduce Motion are unmeasured for EVERY control.
