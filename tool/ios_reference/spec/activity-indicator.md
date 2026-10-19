# Activity indicator passport

Status: measured (tuning + rendered pixels, simulator), CONFIRMED on the
device (2026-10-03, tuning + layers + screenshots light/dark); ported.

## Native

`UIActivityIndicatorView`; tuning `_UIActivityIndicatorSettings`
(`fullLoopDuration`) [tuning]. Public API (SDK 27.1, unchanged since
27.0): style (medium / large), `color`, `hidesWhenStopped`,
`startAnimating`, `stopAnimating`, `animating`.

## Spec

- 8 spokes, 16 images per 0.8 s turn (`fullLoopDuration` 0.8) [tuning].
- Head and a four-spoke tail read from the rendered pixels [film/pixels].
- Color (morph default) 0x993C3C43.

## Device [iPhone 16 Pro, 2026-10-03, testActivityDevice]

- `_UIActivityIndicatorSettings` on the device: fullLoopDuration 0.8,
  color 60/60/67 alpha 0.6 (= 0x993C3C43, the light default) [tuning].
- The spin is a `CAKeyframeAnimation` on the image layer's `contents`
  (16 images, duration 0.8, repeat) plus one on `contentsMultiplyColor`
  (1 value, the color). Every startAnimating hands the layer the 16
  images reordered to begin at the image the view shows, so a restart
  turns on from the image the stop left: the recording's three starts
  begin at images 0, 10 and 4, the images 42 steps after each start
  (read from UIKit, notes private; `activity-startstop.jsonl`).
- DARK color: the head spoke renders 120,120,125 on black and the light
  head 150,150,155 on 242,242,247 - the same 0.505 coverage of 0xEBEBF5
  (dark) and 0x3C3C43 (light), so dark = 0x99EBEBF5 (alpha 0.6 x the
  spoke image's ~0.84 head alpha). Shots `references/states/indicators-{dark,light}.png`.
- stopAnimating with hidesWhenStopped: hidden in ONE frame (no fade);
  startAnimating: visible in one frame, on the image it stopped on. With
  hidesWhenStopped NO the stopped indicator stays visible (no row changes
  at the stop), showing the image it stopped on (inferred: the layer keeps
  the image a restart looks up; the rows carry no pixels).
- Ported: dark default 0x99EBEBF5 (disabled_test pins the constant); the
  restart image (indicators_test replays the three starts);
  start/stop are cuts.

## Recapture

`PROBE_SPINNER=1` in the x3 scenes adds a spinner for the screen recorder
(Extras.swift). Device: StatesUITests/testActivityDevice (scene x4ind,
PROBE_SETTINGS, script stop/start/hide); fixture
`ios27-device/progress/activity-startstop.jsonl`.

## morph

activity_indicator.dart (`MorphActivityIndicator`,
`MorphActivityIndicatorSize`, `MorphActivityIndicatorFrames`,
`MorphActivityIndicatorAppearance`). Test: indicators_test.

Frames: the spin is 20 images a second, each drawn by one paint inside a
repaint boundary. The clock dozes between images and wakes for the frame
that shows the next one: one frame an image (host: 31 -> 20 frames a
second; the doze used to end half a frame early, before the image was
due, and spend a frame drawing nothing new). Native spends no main-thread
frame at all (a keyframe animation in the render server); a rotating
layer cannot replace the images, whose odd half steps sit between spokes.

## Open

- No source: the spoke width and inner / outer radii
  (`MorphActivityIndicator.metrics`); the boxes 20 / 37 are in the device
  rows.
- No Increase Contrast table; the claim that UIKit keeps turning under
  Reduce Motion has no read or recording.

## API gaps

- A caption (SwiftUI `ProgressView("Loading")`) and SwiftUI's other
  control sizes; the default label "In progress" is English only.
