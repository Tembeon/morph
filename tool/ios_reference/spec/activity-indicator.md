# Activity indicator passport

Status: measured (tuning + rendered pixels, simulator); ported.

## Native

`UIActivityIndicatorView`; tuning `_UIActivityIndicatorSettings`
(`fullLoopDuration`) [tuning]. Public API (SDK 27.0): style (medium /
large), `color`, `hidesWhenStopped`, `startAnimating`, `stopAnimating`,
`animating`.

## Spec

- 8 spokes, 16 images per 0.8 s turn (`fullLoopDuration` 0.8) [tuning].
- Head and a four-spoke tail read from the rendered pixels [film/pixels].
- Color (morph default) 0x993C3C43.

## Recapture

`PROBE_SPINNER=1` in the x3 scenes adds a spinner for the screen recorder
(Extras.swift).

## morph

activity_indicator.dart (`MorphActivityIndicator`,
`MorphActivityIndicatorSize`, `MorphActivityIndicatorFrames`,
`MorphActivityIndicatorStyle`). Test: indicators_test.

## Open

- Start/stop transition (fade?) not measured.

## API gaps

None of note.
