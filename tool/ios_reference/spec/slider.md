# Slider passport

Status: measured device (rows + film light/dark) and simulator; ported;
replayed. Thumb = small lens: [lens-and-flex.md](lens-and-flex.md).

## Native

`UISlider` (thumb `_UILiquidLensView`). Public API (SDK 27.0): `value`,
`minimumValue`, `maximumValue`, `setValue:animated:`,
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
- Pan [read from UIKit, notes private; device-checked]: a plain pan with
  hysteresis `panSlop` 10 pt begins on the first move at |dx| >= 10 and
  counts only the travel past 10 (UIKit removes the hysteresis from the
  translation). The same for continuous and stepped sliders. A pan whose
  begin had to wait on another gesture instead resets its translation and
  counts from the touch where it began (`pointerMove(begin: true)`); in
  the recordings something outside the slider held a few starts (device
  drag-slow w200/w300, glide-v400 w200/w300; simulator pastend*,
  paststart, fling*), identified from each drag's first valueChanged.
  Every other device drag counts from exactly 10.00 pt.
- value = value0 + travel past the slop / FULL track width; thumb follows
  the value directly, trailing the finger. Replayed device valueChanged
  rms 0.003 - 0.46 pt (glide-v400 w300 1.4), with the touches fed 12.5 ms
  after their stamps: every valueChanged reflects a touch 12 - 17 ms old
  and none 5 - 10 ms old, so the probe stamps synthesized touches before
  UIKit gets them (the old fit's slop 11 at the first touch past it was
  absorbing that delay).
- NO catch-up at the ends [device, 200/260 pt, 40-80 pt past]: value hits an
  end with the finger leading by ~10 + 37 x (1 - value0) pt; the stretch
  starts only there; the return re-enters where it left (no re-basing).
- Past an end the WHOLE track stretches: near edge rubber band 13/0.74, far
  edge 0.357 of it, height thins 6 - 0.2936 n; springs back ~0.63/0.85
  [sim fit, within 0.35 pt on device].
- Glide after a moving release: release speed held `glideCoast` 0.04 s,
  then exponential decay `glideDecay` 0.083 s (total 0.123 s x v), stopped
  at the ends [device].
- Thumb rms vs device: 0.34 - 0.62 pt slow drags, 1.5 - 3.2 fast.
- `setValue:animated: YES` [tuning + fit, sim 2026-10-14]: the glass
  slider moves fill and thumb per frame (no CAAnimation) on
  the programmatic-update spring = response 0.4, damping 0.8
  (read from UIKit, notes private); fill fits 0.400 - 0.404 / 0.79 - 0.80
  for jumps 0.01 to 0.8 (rms <= 0.16 pt, 300 pt track), start one frame
  after the call, overshoot 1.5 percent of the jump at every distance. NOT
  fixed velocity: the duration does not depend on the distance.
  `MorphSliderMotion.programmaticSpring`, `MorphSlider.animated`;
  test/slider_set_value_test.dart replays the 0.1 -> 0.9 fill (< 1 pt).
- Look [film 2026-10-03]: fill 0x0088FF light / 0x0091FF dark; track black /
  white at 10 percent; thumb platter white in BOTH appearances; fill is its
  own rounded bar ending at the thumb center; within `fillRamp` 0.0198 of an
  end the fill is min(center, s v), s = 18.5 / 0.0198 + travel (mirrored at
  max) - full = whole track, empty = nothing. Mid-track the fill presentation
  trails a fast value by one frame.
- Ticks (`numberOfTicks`): dots 3 pt at 18 + i travel / (n - 1), 8.5 below
  the center, static under the stretch, colors 0xC6C6C8 / 0x38383A.
- Ticks motion [read from UIKit 27.0.1, notes private; device-checked]: the
  glass slider drags with UIKit's elastic fluid-slider driver. Place p =
  finger-mapped value, applied at once (no smoothing). Thumb AND fill show
  T + D u^5, T = nearest stop (a tie keeps the lower), u = (p - T) / D,
  D = half the gap to the neighbour on p's side (0 beyond the outer stops:
  p shows as is). No cap, no velocity term: speed only decides how long the
  finger dwells in the steep band near the midpoint (u^5 < 0.03 for
  u < 0.5), so a fast drag jumps stop to stop and a slow one shows the thumb
  between. Value = nearest stop. Release: target = nearest stop of
  p + 0.099 s x release speed when that projection is 10 pt or more, else
  of p; p springs there on 1.0 / 0.4 s from the release speed, shown
  through the same curve; no glide. Detent haptic when the nearest inner
  stop changes (not ported: the package has no haptics seam; apps would
  watch the reported value). Device check: every off-stop device thumb of
  ticks5-video-dark and ticks5-drag (x - tx) inverted through u^5 lands on
  the 1/3 pt touch grid (median 0.002 / 0.008 pt; exponent 4.5 gives 0.065).
  Timing replay rms fill 1.77 / thumb 1.47 pt with the pan counting past
  10 pt and the 12.5 ms touch delivery (fitted law before: 1.6 / 1.3).
  Not ported: the over-shoot of p past an outer stop on release (clamped;
  UIKit rubber-bands it).
- `allowsTickValuesOnly = NO` [read, not ported]: D = 0.05 of the track
  around each stop, only within 0.05 of one (free tracking elsewhere);
  value and release target snap only inside that zone.
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

`MorphSlider` (`ticks`, `keyboardStep`, `onChangeEnd`), `MorphSliderAppearance`,
`MorphSliderMotion` (slider.dart, slider_motion.dart). Tests:
controls_test, controls_scroll_test (a drag taken over by the list returns
to its start value), slider_ticks_rest_test and
slider_ticks_device_clock_test (a stepped thumb leans off its stop only
while the finger is down - by the detent curve - and rests on the stop
after every release, tap, fling,
cancel, loss to a list, disable, parent change and keyboard step; touches
stamped as the device delivers them). A keyboard or screen reader step of a
stepped slider goes to the next stop on that side, so a value set between
stops lands on one (not measured on the device).

The thumb lens settles as the switch knob does (`MorphSmallLens`,
lens-and-flex.md "Rest").

## Not reproduced / open

- Two frames of white resting platter at the release of a drag held
  stretched or stepped (`references/slider-video/native-release-white-flash.png`).
- Dark lifted thumb: native is a uniform +21 gray wash with no fill
  refracted into its rim; ours is black inside with blue rim bands
  (renderer issue, not package motion).
- Owner report "native thumb reaches the end under the finger" did not
  reproduce with synthesized touches; a hand-recorded probe drag is next.
- Reduce Motion read from UIKit (notes private): the thumb never lifts ([states](states.md#read-from-uikit-static-2026-10-14-notes-private)). End and detent haptics, Increase Contrast fill: states.md.

## API gaps

- `minimumValue` / `maximumValue` exist (`min` / `max`; the motion runs
  in the track's 0..1 and the widget maps), as do `onChangeStart` (on the
  thumb's touch down) and `onChangeEnd`.
- `continuous = false`.
- `sliderStyle = .thumbless`.
- `UISliderTrackConfiguration`: custom tick positions, tick titles/images,
  `allowsTickValuesOnly = false`, `neutralValue` (fill from a neutral
  point), enabled sub-range.
- min/max value images.
- `setValue:animated:` overshoot at an end: on iOS the spring's overshoot
  past the max/min drives the track stretch (0.31 -> 1.0 peaked at 1.11 of
  the travel in the fill); morph clamps the animated thumb to the ends.
