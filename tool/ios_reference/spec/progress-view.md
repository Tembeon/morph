# Progress view passport

Status: measured on the simulator; ported (indicators_test).

## Native

`UIProgressView`. Public API (SDK 27.0): `progressViewStyle` (default /
bar), `progress`, `setProgress:animated:`, `progressTintColor`,
`trackTintColor`, `progressImage`, `trackImage`, `observedProgress`
(NSProgress).

## Spec [sim]

- Animated change is LINEAR for |delta| seconds (as many seconds as the
  progress changes), at least 0.2 s when the fill appears or disappears;
  additive like UIKit's.
- An empty bar shows no fill; the fill is never under 8 pt.
- Colors (morph style): track 0x33787880, progress 0xFF0088FF.

## Fixtures

`ios27/progress/progress2.jsonl`, `progress3.jsonl`.

## Recapture

Scene `w2progress` (`PROBE_PV0` initial value, `PROBE_SCRIPT progress:<v>`).

## morph

progress.dart (`MorphProgressView`, `MorphProgressMotion`,
`MorphProgressStyle`, `MorphProgressViewStyle`).

## Open

- Device confirmation; bar style geometry.

## API gaps

- Track / progress images; `observedProgress`.
