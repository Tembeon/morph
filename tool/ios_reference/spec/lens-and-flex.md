# Lens and flex - shared machinery passport

Everything that lifts (segmented, tab bar, switch knob, slider thumb, glass
buttons, bar capsules, alert platter) uses this. Read before any of those.

## Native

- `_UILiquidLensView` (selection lens, knob, thumb), its `liftProgress`
  (`lp`, presentation `lpp`).
- `_UIFlexInteraction` + `_UIFlexInteractionSpec`
  (`dynamicWithSize:`, `liquidLensWithSize:`), `_UIVelocityIntegrator`.
- PTSettings read live: `_UILiquidLensView` small/large, `smallLoupe`.
- Public API: none (private). Public surfaces that use it: UISegmentedControl,
  UITabBar, UISwitch, UISlider, UIButton glass configurations,
  UIGlassEffect.interactive.

## Spec

Springs are UIKit's vocabulary: `MorphSpring(response, dampingRatio)`,
k = (2 pi / response)^2, c = 4 pi zeta / response, mass 1 [tuning].

MorphFlexSpec.forSize (= dynamicWithSize) [tuning]:
- lift 16 -> 4 px as height goes 44 -> 160 (absolute px).
- scale spring 0.4/0.375 -> 0.36/0.6 and tracking spring 0.262/0.625 ->
  0.314/0.625 by width from 120.
- press = tracking spring, release = scale spring [device-confirmed].
- glow opacities: bigGlowOpacity / littleGlowOpacity (274 x 62 bar: 0.845 /
  0.2845).
`loupeForSize` = liquidLensWithSize.

MorphLensSpec [tuning]: small lift 0.27/0.625, unlift 0.5/0.7, small
optics; large 0.25/1 both ways; hang 0.22 s.

Flex loop (`_UIVelocityIntegrator`) [tuning + device fit]:
- three one-pole filters (position, velocity, rate of change of SPEED
  |v|), alpha 0.3 PER RENDERED FRAME whatever the interval; dt = frame
  interval. Time constant 23.4 ms at 120 Hz, 46.7 ms at 60 Hz.
- runs every 120 Hz tick on the device. A fixed 60 Hz sub-clock or a
  time-normalized alpha is WRONG (sx error 0.051 vs 0.006).
- input = the previous frame's VISIBLE center; filtered acceleration ->
  drift target D = -T f(g af / T) (soft tanh knee). Gains: segmented
  resting 2.5e-5 per px of min(W, 100), lifted 2.626e-5 per px of W + 24;
  scale targets sx = 1 - 2D/W, sy per control; drift/sx/sy follow on a
  presentation spring (segmented 0.442/0.582, tab bar 0.5/0.73).
- width changes by -2D, center shifts +D: the LEADING edge rides the
  travel spring exactly, only the trailing edge lags.

Lens frame (MorphLensMotion): center on travel spring 0.392/0.863; lift and
slot-width changes share ONE critically damped 0.25 s spring; lift +24 x
+16 px (segmented) / +16 x +16 (tab bar) [fit, device].

Small lens (switch knob, slider thumb, `MorphSmallLens`) [fit, device]:
lift 0.27/0.625 (peak 1.12; measured initial velocity part of the fit),
min hang 0.22 s from lift start; unlift glass progress 0.40/1.0, SIZE on
its own 0.48/0.70 (dips under rest); stretch sx* = 1 + 5.0e-5 a,
sy* = 2 - sx*, presentation on smallLoupe 0.444/0.56.

## Fixtures

`ios27{,-device}/lens/*` (manifest: frame rows ctl, x, y, w, h, bw, bh, sx,
sy, lifted, lpp, p_driftX, f_driftX, f_scaleX, vi_x, vi_vx, vi_ax),
`ios27{,-device}/controls/*` (frame rows for knob/thumb).

## morph

lib/src/widgets: spring_state.dart, timeline.dart, clock.dart,
flex_integrator.dart (MorphFlexIntegrator, MorphSubClock), flex_spec.dart,
lens_spec.dart, lens_motion.dart, lens_driver.dart, small_lens.dart,
lib/src/spring.dart. Tests: lens_test, lens_scrub_test, switch_test,
controls_test, timeline_test, spec_test.

Sub-clock runs at the DEVICE refresh rate (`motionFrameRate` 120, 60 on a
60 Hz display), in motion time (timeDilation-aware). Widget tests run at
60; device replays pass 120 explicitly.

## Not reproduced (deliberate)

- Lens geometry refreshing at ~60 Hz on a 120 Hz device (integrator eats
  repeated values: a 60 Hz ripple).
- Tab bar bar-local one-frame glitch (rows with y ~ 31).
- Reduce Motion: never captured; `reducedMotion` is an approximation.

## Implementation notes (moved from CLAUDE.md)

- `MorphLensDriver` (MorphClock + raw pointer events into a
  `MorphLensMotion`) accepts the primary button only.
- Reduced motion (`reducedMotion` on MorphLensMotion, MorphSmallLens,
  MorphGlassButtonMotion, from `MediaQuery.disableAnimations`): lens and
  knob travel, the button glows, nothing lifts, deforms, leans or swells;
  off by default so replays are unchanged.
- Replay rule: frames the recorder missed must still be stepped (UIKit's
  integrator ran them); skipping them doubles the scale error. lens_test
  replays the segmented control on the sim at 60 Hz AND the device at
  120 Hz; the tab bar on the undeformed frame only.
