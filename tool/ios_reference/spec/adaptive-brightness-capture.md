# Adaptive bar brightness - capture protocol (iPhone 16 Pro)

For the coordinator's device run. The reading
([adaptive-brightness.md](adaptive-brightness.md)) already gives the live
mechanism (the glass material's adapted scheme with per-base hysteresis
ranges, two candidate default sets) and the input chain. The capture
measures only what is still open: which range set is live, the look's
latency and transition, glass vs glyph sync, which elements flip, the luma
weights, and scrolling. Follows [README.md](README.md) (device lock,
recording pipeline, clocks, fixture conventions). Agents do not touch the
phone outside a lock session and never change phone settings.

## Owner-only steps

- Before the light run: Settings > Display & Brightness: Light. Reduce
  Motion OFF, Reduce Transparency OFF, Increase Contrast OFF (the start
  rows record `rm`, `rt`; note Increase Contrast by hand). Developer >
  Enable UI Automation ON. Phone unlocked, on the cable, Auto-Lock long
  enough for the run (about 30 minutes). Do not change anything else.
- After the light run finishes: switch to Dark, then the dark run.
- The headless MorphRecorder films the phone from the Mac during the filmed
  passes (camera permission granted to it once).

## Do NOT force the appearance

The material adapts against the base (system) scheme, and UIKit's other
path stops tracking for a fixed style. `PROBE_DARK` stays UNSET in every
pass (the UI test never sets it); the analysis flags any capture whose
window style was forced.

## Run

```sh
cd tool/ios_reference/lab
python3 capture_abright.py --theme light   # owner set Light; about 25 min
python3 capture_abright.py --theme dark    # owner set Dark; about 16 min
python3 analyze_abright.py ../recordings/abright-light-<stamp> ../recordings/abright-dark-<stamp>
```

`capture_abright.py` takes the device lock itself (it refuses while
someone else holds it), builds (`--skip-build` reuses the build), runs one
`xcodebuild test-without-building` per pass, films the filmed passes,
exports the screenshot attachments and pulls the probe's rows into
`tool/ios_reference/recordings/abright-<theme>-<stamp>/` (gitignored).
`--passes a,b` picks passes, `--only <capture>` captures inside them,
`--fine <falling>,<rising>` re-centres the fine staircases (default by
theme, below), `--no-film` skips the films, `--build-only` checks the
build without a phone.

## Scene `abright` (Sources/AdaptiveBrightness.swift)

- Bars (`PROBE_AB_BARS`): `all` (default: a tab bar with Home / Star /
  Settings; Home is a navigation controller with an inline title "Bands",
  a leading `ellipsis` and a trailing `plus` item, and its toolbar shown:
  `trash`, flexible space, `square.and.pencil`), `tab`, `toolbar`,
  `search` (a search tab last), `searchbar` (a search field in the toolbar).
- Host (`PROBE_AB_HOST`): `scroll` (default: content in a scroll view) or
  `static` (a plain view). The material adapts on both; a difference would
  point at the scroll pocket.
- Content (`PROBE_AB_CONTENT`), sRGB, opaque: `solid` (recoloured by
  `grey:` / `rgb:`), `stripes:<pt>[:<a>,<b>]`, `ladder:<pt>[:<steps>]`
  (greys 0 ... 1 from the top), `split` (a white and a black part moved by
  `left:`, `edge:`, `edgeb:`).
- Luma meters: hidden backdrop layers with luma tracking over the content
  under each bar (`lm` rows): the render server's own value of the content.
- The test taps the content to start the script; every applied action is a
  `step` row. `abs` rows: per bar, its style and every glyph's and label's
  style and resolved colour (when changed; the material's flip is not
  expected to move them). `abcrops`: window boxes of the bars, glyphs,
  labels, glass patches, a content patch, the status bar and the home
  indicator. `abstart`: system style, forced style (must be 0), the UIKit
  defaults `CalistogaAllowLumaTracking` and `MPLumaChangeDuration` as read
  on the phone (read only), launch arguments, band layout.
- A red spinner at the screen centre keeps the film's clock during still
  periods; it is never under a bar.

## Passes

Dwell 2.5 s per staircase step (render-server grid 0.25 s, the 0.35 s
settle and the transition, with margin), 4 s per transition step.
Screenshots (attachments) 0.7 s before the end of every step in the shot
passes; films for the transition and scroll passes. The look per step comes
from the screenshot (glyphs lighter than the glass = dark look).

| pass (`--passes`) | captures | bars, host, content | script | measures | min |
|---|---|---|---|---|---|
| stairs | stairs, fine-down, fine-up | all, scroll, solid | 0 -> 1 -> 0 in 1/32; 1/128 steps falling from light around 0.15 (light base; covers 0.20 / 0.10) or 0.65 (dark; 0.60 / 0.70) and rising from dark around 0.40 (light; 0.50 / 0.30) or 0.90 (dark) | which range set, every bar at once (shots) | 6.7 |
| toolbar | toolbar-stairs | toolbar, scroll, solid | coarse staircase | the floating toolbar alone (shots) | 2.9 |
| steps | steps, steps-static, hold, hold-static | all, scroll and static, solid | 0 / 1 x 3 at 4 s (filmed); from 0 and from 1, alternating inside the base's range (light 0.25 / 0.45, dark 0.65 / 0.85) (shots) | latency, transition, glass vs glyphs; hold inside the band (set A holds, set B flips once); static = scroll | 3.9 |
| colours | colours | all, scroll, solid | R, G, B, C, M, Y from black and from white | luma weights (shots, meters) | 1.3 |
| coverage | split-width | all, scroll, split | white share of the width 0 ... 1, each way | area mean over capsules (shots) | 0.9 |
| scroll | stripes-300, stripes-100, ladder | all, scroll, stripes / ladder | 300 and 1200 pt/s each way, finger flings; the grey ladder at 150 pt/s down and up | behaviour while scrolling (film) | 3.8 |
| search | search-tab, search-toolbar | search / searchbar | 0 / 1 at 4 s | search tab circle, bottom search field (film) | 0.9 |
| pocketflag | flag-steps, flag-hold | all, scroll, solid | steps and hold with `-CalistogaAllowLumaTracking YES` | the scroll pocket's added style flip (optional, NOT stock) | 1.9 |

Light run: stairs, toolbar, steps, colours, coverage, scroll, search.
Dark run: stairs, steps, scroll. Add about 45 s of xcodebuild per pass.

pocketflag sets a UIKit default for the probe process only (argument
domain), not a phone setting; run it (`--passes pocketflag`) only if the
coordinator wants the pocket path's look on record.

## Analysis (`lab/analyze_abright.py`)

- Environment: system style per capture against the run's theme, forced
  styles (discard), the UIKit defaults read on the phone, meter rows.
- Range set: per bar, the bound crossed going down and going up (midpoint
  of the flipping step and the one before, fine staircases first) and the
  nearest default set for the run's base.
- Per shot capture: a step table per bar (content value, meter luma, trait
  style, glass-patch luma, look) and the flips with their direction.
- Per filmed step capture: the film aligned to the steps through the
  content patch; per step and crop (glass patches, glyphs, labels, status
  bar, home indicator) the immediate change (the glass transmits the
  content at once) and the delayed one: latency, 5 / 50 / 95 percent
  times, the best of the UIKit curves and a critically damped spring, and
  glyph minus glass timing.
- Per scroll capture: every style change with the meter luma and the
  content luma under the bar at that moment (trait rows; the film shows the
  look).

## Deliverables

- Fixtures `test/fixtures/ios27-device/adaptive-brightness/` (compact
  jsonl rows of the captures, a `manifest.json` documenting the row keys).
- Reference crops (lossless) `tool/ios_reference/references/adaptive-brightness/`
  before and after a flip, light and dark base.
- A passport update with every number tagged `[device]`, the live range
  set, and the answers to its open questions.
