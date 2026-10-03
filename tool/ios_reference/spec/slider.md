# Slider passport

Status: measured device (rows + film light/dark) and simulator; ported;
replayed. Thumb = small lens: [lens-and-flex.md](lens-and-flex.md).

## Native

`UISlider` (thumb `_UILiquidLensView`). Public API (SDK 27.0): `value`,
`minimumValue`, `maximumValue`, `setValue:animated:` (fixed velocity),
`continuous`, `minimumValueImage`, `maximumValueImage`,
`minimumTrackTintColor`, `maximumTrackTintColor`, `thumbTintColor`,
thumb/track images per state, `sliderStyle` (`UISliderStyle` default /
thumbless), `trackConfiguration` (`UISliderTrackConfiguration`:
`configurationWithNumberOfTicks:`, `configurationWithTicks:` of
`UISliderTick` position/title/image, `allowsTickValuesOnly` default YES,
`neutralValue`, `minimumEnabledValue`, `maximumEnabledValue`),
`trackRectForBounds:`, `thumbRectForBounds:trackRect:value:`.

## Spec

- Only the thumb is a handle; a track tap does nothing.
- Pan after `panSlop` 11 pt (slow device drags and simulator agree; fast
  device starts recognize later - synthesizer delivery).
- value = value0 + finger travel / FULL track width (device divisors
  298 - 302 for 300, 199 - 200 for 200); thumb follows the value directly,
  trailing the finger.
- NO catch-up at the ends [device, 200/260 pt, 40-80 pt past]: value hits an
  end with the finger leading by ~11 + 37 x (1 - value0) pt; the stretch
  starts only there; the return re-enters where it left (no re-basing).
- Past an end the WHOLE track stretches: near edge rubber band 13/0.74, far
  edge 0.357 of it, height thins 6 - 0.2936 n; springs back ~0.63/0.85
  [sim fit, within 0.35 pt on device].
- Glide after a moving release: release speed held `glideCoast` 0.04 s,
  then exponential decay `glideDecay` 0.083 s (total 0.123 s x v), stopped
  at the ends [device].
- Thumb rms vs device: 0.4 - 1.9 pt slow drags, 3.4 fast.
- Look [film 2026-10-03]: fill 0x0088FF light / 0x0091FF dark; track black /
  white at 10 percent; thumb platter white in BOTH appearances; fill is its
  own rounded bar ending at the thumb center; within `fillRamp` 0.0198 of an
  end the fill is min(center, s v), s = 18.5 / 0.0198 + travel (mirrored at
  max) - full = whole track, empty = nothing. Mid-track the fill presentation
  trails a fast value by one frame.
- Ticks (`numberOfTicks`): dots 3 pt at 18 + i travel / (n - 1), 8.5 below
  the center, static under the stretch, colors 0xC6C6C8 / 0x38383A; value =
  nearest stop of the finger-mapped value; thumb AND fill show
  stop + sign h min(0.72, f^4.5) (f = distance to stop / half step h) on a
  0.03 crit follow spring; settle 0.035 s after release on 0.115 crit; no
  glide. Replay rms fill 1.6 / thumb 1.3 pt (probe rows show the PREVIOUS
  frame - feed touches one frame early). 0.72 hold is a compromise (moving
  frames reach 0.8 h, still finger 0.71).
- Lifted thumb: shrink 0 (track unchanged inside).

## Disabled [device, light + dark, 2026-10-03]

- `_UISliderGlassVisualElement` at opacity 0.5: track, fill, thumb platter
  and tick dots together (plain and 5-tick slider). Pixels exact: rms
  0.09 / 0.10 of 8 bit against 0.5 enabled + 0.5 background.
- One frame, no animation, both ways.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method and recapture in [states](states.md) (StatesUITests testDisabled, scenes x4dis / x4disbars / x4distab / x4disalert).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): one 0.5 layer over track, fill, thumb and ticks
  (pixel rule checked light + dark).

## Fixtures

Device `ios27-device/controls/slider-*` (w300 drags/flings/glides/taps/
hold, w200 ends min/max slow/fast/fill, nearend, atend, offgrab, sweep,
w260 sweep, ticks5-drag, video-dark rows). Simulator `ios27/controls/slider-*`.
Film crops `references/slider-video/`. Recordings `device-sliderends`,
`device-slidervideo*`.

## Recapture

Scenes `sl<W>` (width), `slT<N>` (ticks), `slV<pct>` (initial value);
`PROBE_SLIDER_VALUE`, `PROBE_DARK`. Device plans `controls`, `sliderends`,
`slidervideo` (film with MorphRecorder), `recapcontrols`. morph film:
example/integration_test/slider_video_test.dart.

## morph

`MorphSlider` (`ticks`, `keyboardStep`, `onChangeEnd`), `MorphSliderStyle`,
`MorphSliderMotion` (slider.dart, slider_motion.dart). Tests:
controls_test, controls_scroll_test (a drag taken over by the list returns
to its start value).

## Not reproduced / open

- Two frames of white resting platter at the release of a drag held
  stretched or stepped (`references/slider-video/native-release-white-flash.png`).
- Dark lifted thumb: native is a uniform +21 gray wash with no fill
  refracted into its rim; ours is black inside with blue rim bands
  (renderer issue, not package motion).
- Owner report "native thumb reaches the end under the finger" did not
  reproduce with synthesized touches; a hand-recorded probe drag is next.
- Reduce Motion unmeasured (plan in states.md).

## API gaps

- `minimumValue` / `maximumValue` (morph is 0..1 only).
- `continuous = false`.
- `sliderStyle = .thumbless`.
- `UISliderTrackConfiguration`: custom tick positions, tick titles/images,
  `allowsTickValuesOnly = false`, `neutralValue` (fill from a neutral
  point), enabled sub-range.
- min/max value images; `setValue:animated:` (fixed-velocity animation,
  unmeasured).
