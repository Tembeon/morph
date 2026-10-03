# Progress view passport

Status: measured on the simulator, CONFIRMED on the device (2026-10-03);
ported (indicators_test).

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

## Device [iPhone 16 Pro, 120 Hz, 2026-10-03, testProgressDevice]

Identical to the simulator rule, frame for frame:
- Linear, |delta| seconds (300 pt bar = 300 pt/s): 0.2 -> 0.3 in 0.100 s,
  0.3 -> 1.0 in 0.700 s, 1.0 -> 0 in 1.000 s, 0.52 -> 0 in 0.517 s, first
  moved frame 0.014 - 0.016 s after the call (next commit).
- Appearing / disappearing fill: at least 0.2 s (0 -> 0.05 took 0.200 s);
  the fill's OPACITY ramps linearly with the same clock (1 -> 0 while 1.0
  -> 0 shrinks, 0 -> 1 while it grows from empty), never under 8 pt wide.
- ADDITIVE: a retarget 0.25 s into 0.2 -> 0.9 (0.7 s) toward 0.4 plateaus
  (the two animations cancel at +300 / -300 pt/s) until the first ends at
  0.7 s, then falls at 300 pt/s to 0.4 at 0.75 s; two calls 0.1 s apart
  (-> 0.6, -> 1.0) run 600 pt/s while both are active. Each animation is
  an additive linear offset (old - new model, to 0 over |delta| s) on the
  new model value.
- Bar style (`.bar`) runs the same timing.
- To port: nothing new - the simulator model was right; the additive
  replay can use progress-additive.jsonl.

## Fixtures

`ios27/progress/progress2.jsonl`, `progress3.jsonl` (simulator);
`ios27-device/progress/progress2.jsonl`, `progress3.jsonl`,
`progress-additive.jsonl` (device, manifest.json).

## Recapture

Scene `w2progress` (`PROBE_PV0` initial value, `PROBE_SCRIPT progress:<v>`).

## morph

progress.dart (`MorphProgressView`, `MorphProgressMotion`,
`MorphProgressStyle`, `MorphProgressViewStyle`).

## Open

- Bar style geometry; Reduce Motion (plan in states.md).

## API gaps

- Track / progress images; `observedProgress`.
