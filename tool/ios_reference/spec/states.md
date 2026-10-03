# States passport (disabled look, light references, Reduce Motion)

Status: DISABLED measured on the device, light + dark (2026-10-03); light
reference set captured; REDUCE MOTION prepared, waiting for the owner to
switch the phone setting (plan below). The per-control numbers are repeated
in each control's passport under "Disabled"; this page has the method, the
cross-control summary and the porting checklist.

## Disabled look [device, layers + lossless screenshots, light + dark]

Method: probe scenes `x4dis` (every control twice: ENABLED left column
x 101, DISABLED right column x 301, same rows; search field and date picker
full width, enabled above), `x4disbars`, `x4distab`, `x4disalert`
(States.swift). Each capture: a deep view + layer dump at rest (every
layer's opacity, bg, filters with inputs, compositing filter,
contentsMultiplyColor, label textColor, tint), a lossless screenshot at
rest, then the disabled twins are ENABLED and disabled again (script
toggle, X3Sampler V/anim rows every frame) with a screenshot each. The
pixel verdicts compare the two columns of the same screenshot.

Summary (tertiaryLabel = dark 0x4CEBEBF5 [0.9216, 0.9216, 0.9608, 0.298],
light 0x4C3C3C43 [0.2353, 0.2353, 0.2627, 0.298]; systemGray4 = dark
0x3A3A3C, light 0xD1D1D6):

| control | disabled look | evidence |
|---------|---------------|----------|
| segmented control | whole control opacity 0.5 (UISegmentedControl.alpha) | layer op 0.5; pixels = 0.5 en + 0.5 bg, rms 0.11 dark / 0.27 light (8-bit) |
| switch (off and on) | `UISwitchModernVisualElement` opacity 0.5 (track, knob, both) | pixels exact, rms 0.07 / 0.05 |
| slider (plain and ticks) | `_UISliderGlassVisualElement` opacity 0.5 (track, fill, thumb, ticks) | pixels exact, rms 0.09 / 0.10 |
| stepper | NO change (pixel-identical, 0.00) | dump identical; a half at its limit dims its own glyph to tertiaryLabel whether enabled or not |
| glass button `.glass()` | glass UNCHANGED (body and rim pixel-identical); title / image -> tertiaryLabel | label tc + image cmul tertiaryLabel; dark label peak 249 -> 93 on body 32, light 13 -> 189 on 245 |
| prominent glass `.prominentGlass()` | tint accent -> systemGray4 (body dark 59.7 gray, light 210.3/210.3/214.3); title -> tertiaryLabel | pixels; body = the tint color exactly, like the enabled 0x0091FF / 0x0088FF body |
| menu button (glass, image) | as `.glass()`: glyph tertiaryLabel, glass unchanged | cmul tertiaryLabel |
| page control | NO change (pixel-identical) | dump + pixels |
| search field (UISearchTextField) | the GLASS goes: flat fill 0x767680 at 0.12 dark / 0.06 light, no rim, no lift; magnifier unchanged (label color), placeholder unchanged (tertiaryLabel) | layer bg; pixels 14,14,15 on black / 235,235,240 on 242 |
| date picker compact labels | the tertiarySystemFill capsule goes (dark 0x767680 at 0.24, light at 0.12); text unchanged (label color) | the fill UIView is absent; text pixels identical |
| bar button, plain (nav bar / toolbar) | tint -> tertiaryLabel, capsule glass unchanged; rendered through the bar's vibrancy: ICON dark 249 -> 83 on 32, light 12 -> 167 on 245; TEXT dark 249 -> 47, light 13 -> 221 | pixels (the item tint feeds the bar's own color path, so text and icons differ) |
| bar button, prominent | tint accent -> systemGray4 body (dark 59.8, light 209.8/214.2), glyph stays WHITE | pixels |
| tab bar item (UITabBarItem.isEnabled NO) | NO visual change (pixel-identical, both rows of the selected-tint copy) | `_UITabButton.enabled` false only |
| alert action | title -> tertiaryLabel (destructive too: red goes), fill unchanged (tertiarySystemFill); a disabled PREFERRED action loses the accent fill (plain fill), title stays semibold (fw 0.3) | dump; pixels text dark 111 on 60, light 121 on 198 |

Transitions: every enable / disable switches in ONE frame (V rows change
on the first tick after the call, no CAAnimation logged, both directions,
every control and appearance).

Not measured: touches on disabled controls (testDisabledTouch prepared:
does a disabled tab item select or lift, does a disabled glass button lift);
`UIControl.isEnabled` on bars inside a scroll edge effect; the activity
indicator and progress view have no enabled state.

## Light reference set [device, 2026-10-03]

`references/light/` = the dark set's shots (`testReferences`) plus the
second-pass shots (`testW2Refs`), forced light with `PROBE_REF_DARK=0`;
`references/dark/` gained the second-pass dark shots (`PROBE_REF_DARK=1`):
actionsheet, alert, ctx-open, page-control(-prominent), progress,
search-tab-rest, sheet-medium, sheet-large. `references/disabled/{dark,light}/`
holds `dis-<scene>.png` (at rest) and `dis-<scene>-enabled.png` (both columns
enabled); `references/disabled/dumps/` the rest dumps; `references/states/`
the stepper press and indicator shots.

## Reduce Motion [PREPARED, owner must switch the setting]

The owner turns Settings > Accessibility > Motion > Reduce Motion ON (no
agent automates Settings). Then, with the device lock:

```sh
PROBE_SKIP_BUILD=0 ./reduce_motion.sh            # all steps, ~25 min
RM_STEP=controls ./reduce_motion.sh             # one family
```

Every start row carries `rm`, `rmXfade` (prefersCrossFadeTransitions) and
`rt`; the script counts the files recorded with `"rm":true`. Baseline:
`StatesUITests/testSettingsDump` with Reduce Motion OFF writes
`settings-rm-settings-off.txt` (PTSettings of the motion families); the RM
step writes `settings-rm-settings-on.txt` - diff them first (a tuning that
changes under Reduce Motion is read, not fitted).

| step | test (PROBE_ONLY) | what to read |
|------|-------------------|--------------|
| lens | testLens (segmented-seg3-taps, segmented-seg5-dragslow-from-selected, tabbar4-taps), testRecapLens (tabbar4-scrub-mid, tabbar4-tap-selected, segmented-seg3-tap-selected) | lens travel (still a spring? crossfade?), lift/liftProgress, flex drift/scale, bar swell, glow |
| controls | testControls (switch-off-tap, -hold800, -drag-right50, slider-w300-hold800-thumb, -drag-slow, -fling, button-glass-120x44/44x44-hold800, button-prominent-120x44-hold800, button-glass-120x44-drag-off-back) | knob travel and lift, thumb lift/stretch, glass button scale, glow, lean |
| menu | testMenu (center3-tap, center3-dismiss, center3-select, navbar3-dismiss) | liquid morph progress, kicks, content fades (a film is better: see below) |
| ctx | testW2Ctx (ctx-hold-release, ctx-hold-select) | hold growth, preview spring, dim |
| sheet | testW2Sheet (sheet-present-tap, sheet-drag-up-slow, sheet-flick-down, sheet-grab-tap) | present/dismiss spring, detent spring, swell |
| zoom | testSNZoom (zoom-tap-open-dim, zoom-drag-dismiss), testSNPush (push-zoom-back, push-zoom-edge), testSNBack (back-hold-open) | zoom vs crossfade, push spring, back menu |
| bars | testBars (bars-push-auto, bars-edge-commit, bars-back-tap, bars-toolbar-auto, bars-scroll-auto) | push spring / parallax, item transition pulse + blur, inline title |
| alert | testX3Device (alert-press, alert-tap, ash-tap-out) | scale 1.2 -> 1 (still?), popover scale, platter lift |
| search | testX3Device (search-tap, search-tab, search-tabauto) | search transition, glass morph (film) |
| date | testX3Timing (tm-date-oc-1500, PROBE_GAPS 1.5) | overlay scale/height |
| page | testW2Page (pc-tap-right, pc-scrub) | platter, dot steps |

Films (optional, Mac must be free; MorphRecorder with `open -g -W`): the
menu (center3-tap), the tab search morph (vid-tab*) and the alert alpha
read best on screen; run `ExtrasUITests/testX3Video` / `testX3AlertVideo`
and `ProbeUITests/testMenu` under the recorder as in the menu passport.

Each result answers, per family: same spring / shorter / crossfade / no
motion; the lift and glow present or not; durations. morph's
`reducedMotion` (lens and knob travel, glow only) is an approximation
until this pass lands.

## To port (porting agent)

- [ ] Replace the guessed `disabledOpacity` (0.5 switch/slider, 0.35
      others) by the table above: segmented 0.5 on the whole control
      (was 0.35), switch 0.5, slider 0.5 (the whole visual element incl.
      thumb and ticks).
- [ ] Stepper, page control, tab bar item: NO disabled look (remove the
      0.35 dim); keep them non-interactive.
- [ ] Glass button / menu button / bar items: content color ->
      tertiaryLabel (per appearance), glass untouched; prominent: tint ->
      systemGray4, glyph tertiaryLabel (button) or white (bar item).
- [ ] Search field disabled: no glass, flat fill 0x1F767680 dark /
      0x0F767680 light, no lift; placeholder and magnifier unchanged.
- [ ] Date picker labels disabled: no capsule fill, text unchanged.
- [ ] Alert actions: `enabled` on the action model: tertiaryLabel title,
      a disabled preferred action keeps semibold but loses the accent fill.
- [ ] All state changes instant (no animation).
- [ ] Gallery: the Glass renderer page's disabled toggle and the light
      references (`references/light/`) for the light audit.
