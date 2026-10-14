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

MorphFlexSpec.forSize (= dynamicWithSize) [tuning; selection read from
UIKit, notes private]:
- selection is by the SHORT and LONG sides, not width/height: long < 120
  -> ultraSmall (small with threshold 2000, little glow 1); otherwise
  s = clamp((short - 44) / 116) and l = clamp((long - 44) / 116).
- lift 16 -> 4 px, stretch threshold 6000 -> 24000, glows by s (absolute
  px). Portrait 80 x 200: lift 12.275862, threshold 11586.206897.
- scale spring 0.4/0.375 -> 0.36/0.6 and tracking spring 0.262/0.625 ->
  0.314/0.625 by l.
- press = tracking spring, release = scale spring [device-confirmed].
- glow opacities: bigGlowOpacity / littleGlowOpacity (274 x 62 bar: 0.845 /
  0.2845).
`loupeForSize` = liquidLensWithSize: t = clamp((short - 37) / 33), lift
and threshold 0.

Lens PTSettings [tuning]: small lift 0.27/0.625, unlift 0.5/0.7, small
optics; large 0.25/1 both ways; hang 0.22 s.

Flex interaction (`_UIFlexInteraction`, one machine for every flexible
glass surface) [read from UIKit, notes private; device-confirmed where
noted]:
- Four channels scaleX, scaleY, driftX, driftY, at rest (1, 1, 0, 0).
  While a finger is down they chase the targets on the spec's tracking
  spring, after the lift they return on its scale spring.
- Touch source, t = the finger's travel since the touch-down, it = the
  same with the finger clamped into the bounds, T = scaleDistanceThreshold:
  lift s = (L + liftScalePoints) / L on both scales (L the long side);
  per axis k = |it| / (4 T) + (|t| - |it|) / T (0 without travel),
  sx += kx - ky, sy += ky - kx, driftX = sign(t.x) kx W, driftY likewise
  with H.
- Movement source (a moving surface), m = a / movementNormalizationFactor
  with a the filtered rate of change of speed per axis: bounds per axis
  lo = max(minScale, (e - movementScalePts) / e), hi = min(maxScale,
  (e + movementScalePts) / e); along the motion L = soft(1 + m (hi - 1)),
  across soft(1 + m (lo - 1)), drift += (1 - L) e / 2 sign(v). soft eases
  a value beyond a bound toward a third of the range further out,
  entering at slope 0.55.
- Menu variant (open menu): its own targets and pulse, menu-button.md.
- What shows: Scale(sx, sy) . Translate(dx, dy), the drift times the scale
  [device: glass button drag-off-back, tx = sx dx replays to 0.065 pt
  rms, tx = dx to 0.18].
- Sources per control: glass button, bar capsule and alert platter lift
  and stretch [device]; search field and menu button press lift (a drag
  on them is not measured, morph does not stretch them).
- The lens, knob and thumb deformation targets are this movement law
  with `loupeForSize` of the lens: the resting lens, or the fully lifted
  one (W + liftWidth, H + liftHeight) while lifted [device: fed UIKit's
  own vi_ax / vi_vx, the law reproduces the recorded f_scaleX to 0.0053 /
  0.0003 rms on the segmented control resting / lifted, 0.0028 / 0.00003
  on the tab bar, 1e-4 - 4e-3 on switch knobs and slider thumbs (with
  f_scaleY); flex_law_test]. On a segmented control that is 2.5e-5 per
  px of min(W, 100) at rest (smallLoupe: 0.5 x 0.1 / 2000, the cap where
  (W + 10) / W reaches 1.1) and 2.626e-5 per px lifted (the loupe of a
  44 pt tall lens). `MorphLensMotion` runs on it.
- Channels (`_UIDebouncingAnimatableFloat`) [device, iOS 27.0.1, read
  from UIKit, notes private]: an unchanged target is skipped; a changed
  one retargets from the presentation with its velocity, on the tracking
  pair while a finger tracks, else the plain pair, and adds velocity
  stiffness x retargetImpulse x (new - old target): the menu's 0.016
  replays every recorded menu retarget (dv / (k imp dT) = 1.0000) and a
  release to 1e-4 over 11 updates; dynamic specs carry 0; a slider
  thumb's drift replays best with 0 (0.136 pt rms, 0.229 with the small
  loupe's 0.032). UIKit publishes channels at 60 Hz tracking and 30 Hz
  settling (not reproduced, NEAR).
- morph: `MorphFlexInteraction` (flex_interaction.dart) on `MorphChannel`
  (channel.dart).

Flex loop (`_UIVelocityIntegrator`) [tuning + device fit]:
- three one-pole filters (position, velocity, rate of change of SPEED
  |v|), alpha 0.3 PER RENDERED FRAME whatever the interval; dt = frame
  interval. Time constant 23.4 ms at 120 Hz, 46.7 ms at 60 Hz.
- runs every 120 Hz tick on the device. A fixed 60 Hz sub-clock or a
  time-normalized alpha is WRONG (sx error 0.051 vs 0.006).
- input = the previous frame's VISIBLE center; the filtered rate of
  change of speed and the velocity feed the flex movement law above;
  drift/sx/sy follow on a presentation spring (segmented 0.442/0.582,
  tab bar 0.5/0.73).
- width changes by -2D, center shifts +D: the LEADING edge rides the
  travel spring exactly, only the trailing edge lags.

Lens frame (MorphLensMotion): center on travel spring 0.401/0.856; lift and
slot-width changes share ONE critically damped 0.25 s spring; lift +24 x
+16 px (segmented) / +16 x +16 (tab bar) [fit, device].
The former passport value 0.392/0.863 fails the device segmented tap
replay and tab bar scrub release replay at the existing tolerances;
0.401/0.856 keeps both green (lens_test.dart, lens_scrub_test.dart,
ios27{,-device}/lens fixtures).

Small lens (switch knob, slider thumb, `MorphSmallLens`) [fit, device]:
lift 0.27/0.625 (peak 1.12; measured initial velocity part of the fit),
initial velocity 18/s only from rest; a re-lift during landing carries
the current value and velocity. Min hang 0.22 s from lift start; unlift glass progress 0.40/1.0, SIZE on
its own 0.48/0.70 (dips under rest); deformation by the flex movement
law for a loupe of the lens's current size (a small loupe: sx = 1 +
5e-5 a below the 1.1 bound, sy across), the drift shown at the scale as
a shift of the knob or thumb, all three on smallLoupe 0.444/0.56; the
filter reads the visible center (position + shift) [device: slider
drags and glides sx / sy 0.0205 / 0.0207 rms, shift 0.60 pt; switch
drags and taps 0.0050 / 0.0053, shift 0.15 pt; flex_law_test].

## Fixtures

`ios27{,-device}/lens/*` (manifest: frame rows ctl, x, y, w, h, bw, bh, sx,
sy, lifted, lpp, p_driftX, f_driftX, f_scaleX, vi_x, vi_vx, vi_ax),
`ios27{,-device}/controls/*` (frame rows for knob/thumb).

## morph

lib/src/widgets: spring_state.dart, timeline.dart, clock.dart,
flex_integrator.dart (MorphFlexIntegrator, MorphSubClock), flex_spec.dart,
lens_motion.dart, lens_driver.dart, small_lens.dart,
lib/src/spring.dart. Tests: lens_test, lens_scrub_test, switch_test,
controls_test, timeline_test, spec_test.

Rest: settles once every spring's remaining swing (`MorphSpringState.reach`)
is under `MorphRest` - 0.1 pt (0.3 device px at 3x, 0.26 at 2.625x), a scale
over its surface's extent, an opacity under half an 8-bit step - and snaps
onto its targets: invisible, NEAR. Lens tails end 0.2-0.4 s earlier
(segmented 1.63 -> 1.30 s, tab bar 1.55-1.86 -> 1.33-1.46 s after a
programmatic selection); a lens left lifted by a residue now returns to its
resting (non-glass) drawing. The replays read the motions directly and are
unaffected.

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
  `MorphLensMotion`) accepts the primary button and one pointer at a time.
- Reduced motion (`reducedMotion` on MorphLensMotion, MorphSmallLens,
  MorphGlassButtonMotion, from `MediaQuery.disableAnimations`): lens and
  knob travel, the button glows, nothing lifts, deforms, leans or swells;
  off by default so replays are unchanged.
- Replay rule: frames the recorder missed must still be stepped (UIKit's
  integrator ran them); skipping them doubles the scale error. lens_test
  replays the segmented control on the sim at 60 Hz AND the device at
  120 Hz; the tab bar on the undeformed frame only.
