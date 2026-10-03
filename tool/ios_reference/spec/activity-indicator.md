# Activity indicator passport

Status: measured (tuning + rendered pixels, simulator), CONFIRMED on the
device (2026-10-03, tuning + layers + screenshots light/dark); ported.

## Native

`UIActivityIndicatorView`; tuning `_UIActivityIndicatorSettings`
(`fullLoopDuration`) [tuning]. Public API (SDK 27.0): style (medium /
large), `color`, `hidesWhenStopped`, `startAnimating`, `stopAnimating`,
`animating`.

## Spec

- 8 spokes, 16 images per 0.8 s turn (`fullLoopDuration` 0.8) [tuning].
- Head and a four-spoke tail read from the rendered pixels [film/pixels].
- Color (morph default) 0x993C3C43.

## Device [iPhone 16 Pro, 2026-10-03, testActivityDevice]

- `_UIActivityIndicatorSettings` on the device: fullLoopDuration 0.8,
  color 60/60/67 alpha 0.6 (= 0x993C3C43, the light default) [tuning].
- The spin is a `CAKeyframeAnimation` on the image layer's `contents`
  (16 images, duration 0.8, repeat) plus one on `contentsMultiplyColor`
  (1 value, the color), restarted from frame 0 by every startAnimating.
- DARK color: the head spoke renders 120,120,125 on black and the light
  head 150,150,155 on 242,242,247 - the same 0.505 coverage of 0xEBEBF5
  (dark) and 0x3C3C43 (light), so dark = 0x99EBEBF5 (alpha 0.6 x the
  spoke image's ~0.84 head alpha). Shots `references/states/indicators-{dark,light}.png`.
- stopAnimating with hidesWhenStopped: hidden in ONE frame (no fade);
  startAnimating: visible in one frame, frame 0. With hidesWhenStopped NO
  the stopped indicator stays visible (no row changes at the stop).
- Ported: dark default 0x99EBEBF5 (disabled_test pins it); start/stop
  are cuts.

## Recapture

`PROBE_SPINNER=1` in the x3 scenes adds a spinner for the screen recorder
(Extras.swift). Device: StatesUITests/testActivityDevice (scene x4ind,
PROBE_SETTINGS, script stop/start/hide); fixture
`ios27-device/progress/activity-startstop.jsonl`.

## morph

activity_indicator.dart (`MorphActivityIndicator`,
`MorphActivityIndicatorSize`, `MorphActivityIndicatorFrames`,
`MorphActivityIndicatorStyle`). Test: indicators_test.

## Open

- Start/stop: measured (cuts, see Device).

## API gaps

None of note.
