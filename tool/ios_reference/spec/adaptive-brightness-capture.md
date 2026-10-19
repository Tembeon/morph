# Adaptive bar brightness - capture protocol (iPhone 16 Pro)

For the coordinator's device run. Measures what
[adaptive-brightness.md](adaptive-brightness.md) leaves open: whether bar
glass and glyphs switch between a light and a dark look over content on
iOS 27.0.1, at which luma in each direction, how fast, and which elements
switch. Follows [README.md](README.md) (device lock, recording pipeline,
clocks, fixture conventions). Agents do not touch the phone outside a lock
session and never change phone settings.

## Owner-only steps

- Before the light run: Settings > Display & Brightness: Light. Reduce
  Motion OFF, Reduce Transparency OFF, Increase Contrast OFF (the start
  rows record `rm`, `rt`; note Increase Contrast by hand). Developer >
  Enable UI Automation ON. Phone unlocked, on the cable, Auto-Lock long
  enough for the run (or the coordinator keeps it awake). Do not change
  anything else.
- After the light run finishes: switch to Dark, then the dark run.
- The headless MorphRecorder films the phone from the Mac during the filmed
  passes (camera permission granted to it once).

## Do NOT force the appearance

UIKit stops tracking luma for a view whose user interface style is fixed.
`PROBE_DARK` sets the window's style, so it stays UNSET in every pass (the
UI test never sets it); the analysis flags any capture whose window style
was forced.

## Run

```sh
cd tool/ios_reference/lab
python3 capture_abright.py --theme light   # owner set Light; about 32 min
python3 capture_abright.py --theme dark    # owner set Dark; about 17 min
python3 analyze_abright.py ../recordings/abright-light-<stamp> ../recordings/abright-dark-<stamp>
```

`capture_abright.py` takes the device lock itself (it refuses while
someone else holds it), builds (`--skip-build` reuses the build), runs one
`xcodebuild test-without-building` per pass, films the filmed passes,
exports the screenshot attachments and pulls the probe's rows into
`tool/ios_reference/recordings/abright-<theme>-<stamp>/` (gitignored).
`--passes a,b` picks passes, `--only <capture>` captures inside them,
`--fine <lower>,<upper>` re-centres the fine staircases (default 0.40,
0.70; rerun `--passes stairs --only fine-lower,fine-upper` when the coarse
staircase finds other flips), `--no-film` skips the films,
`--build-only` checks the build without a phone.

## Scene `abright` (Sources/AdaptiveBrightness.swift)

- Bars (`PROBE_AB_BARS`): `all` (default: a tab bar with Home / Star /
  Settings; Home is a navigation controller with an inline title "Bands",
  a leading `ellipsis` and a trailing `plus` item, and its toolbar shown:
  `trash`, flexible space, `square.and.pencil`), `tab` (no toolbar),
  `toolbar` (navigation controller and toolbar, no tab bar), `search` (a
  search tab last), `searchbar` (a search field in the toolbar).
- Host (`PROBE_AB_HOST`): `scroll` (default: the content is a scroll view's,
  automatic insets and edge effects, so the bars get the scroll pocket,
  path 1) or `static` (a plain view, no scroll view: only the glass itself
  can adapt, path 2).
- Content (`PROBE_AB_CONTENT`), sRGB, opaque: `solid` (recoloured by
  `grey:` / `rgb:`), `stripes:<pt>[:<a>,<b>]` (two greys alternating,
  default black / white), `ladder:<pt>[:<steps>]` (greys 0 ... 1 from the
  top in 1/steps), `split` (a white and a black part moved by `left:`,
  `edge:`, `edgeb:`).
- Luma meters: hidden backdrop layers with luma tracking over the content
  under each bar and under the top and bottom 160 pt bands; the render
  server reports their luma (`lm` rows), the same value the scroll pocket
  receives, so flip lumas come in the render server's own units.
- The test taps the content to start the script; every applied action is a
  `step` row. `abs` rows: per bar, its style and every glyph's and label's
  style and resolved colour (when changed). `off`: content offset.
  `abcrops`: window boxes of the bars, glyphs, labels, glass patches, a
  content patch, the status bar and the home indicator. `abstart`: system
  style, forced style (must be 0), the UIKit defaults
  `CalistogaAllowLumaTracking` and `MPLumaChangeDuration` as read on the
  phone (suite `com.apple.UIKit` and standard; read only), launch
  arguments, band layout.
- A red spinner at the screen centre keeps the film's clock during still
  periods; it is never under a bar.

## Passes

Dwell 2.5 s per staircase step (render-server luma grid 0.25 s + glass
settle 0.35 s + an expected 0.6 s transition, with margin), 4 s per
transition step. Screenshots (attachments) 0.7 s before the end of every
staircase step; films for the transition passes.

| pass (`--passes`) | captures | bars, host, content | script | measures | min |
|---|---|---|---|---|---|
| stairs | stairs, fine-lower, fine-upper | all, scroll, solid | 0 -> 1 -> 0 in 1/32; then 1/128 over +- 3/32 around 0.40 from light and 0.70 from dark | flip luma each way, every bar at once (shots) | 5.3 |
| toolbar | toolbar-stairs | toolbar, scroll, solid | as stairs, coarse | the floating toolbar alone (shots) | 2.9 |
| steps | steps, steps-static, hold, hold-static | all, scroll and static, solid | 0 / 1 x 3 then 0.3 / 0.8 x 3 at 4 s; from 0 and from 1: 0.45 / 0.65 x 6 | latency, transition, glass vs glyphs; hysteresis hold; path 1 vs path 2 (film) | 4.8 |
| colours | colours | all, scroll, solid | R, G, B, C, M, Y at 1 and 0.5, from black and from white | luma weights (shots, meters) | 2.3 |
| coverage | split-width, edge-bottom, edge-top, edge-bottom-toolbar | all / toolbar, scroll, split | white share 0 ... 1 each way; an edge moving 12 ... 240 pt into the bottom / top band and back | statistic and sampled extent (shots) | 6.6 |
| scroll | stripes-300, stripes-100, stripes-mid, ladder | all, scroll, stripes / ladder | scroll 300 and 1200 pt/s each way, finger flings; the grey ladder at 150 pt/s down and up | behaviour while scrolling, flip luma from scrolled bands (film) | 4.4 |
| search | search-tab, search-toolbar | search / searchbar | 0 / 1 at 4 s | search tab circle, bottom search field (film) | 0.9 |
| pocketflag | flag-steps, flag-hold | all, scroll, solid | steps and hold with `-CalistogaAllowLumaTracking YES` | path 1's look when stock shows no discrete flip (film) | 2.4 |

Light run: stairs, toolbar, steps, colours, coverage, scroll, search.
Dark run: stairs, steps, scroll. Add about 45 s of xcodebuild per pass.

pocketflag is optional and NOT stock: it sets a UIKit default for the probe
process only (argument domain), not a phone setting. Run it
(`--passes pocketflag`) only if the stock passes show no discrete flip and
the coordinator agrees.

## Analysis (`lab/analyze_abright.py`)

- Environment: system style per capture against the run's theme, forced
  styles (discard), the UIKit defaults read on the phone, meter rows.
- Per staircase, colour and coverage capture: a step table per bar (content
  value, meter luma, trait style, screenshot glass-patch luma and look:
  light glyphs on darker glass = dark look) and the flips with their
  direction and the value and meter luma that triggered them.
- Per filmed step capture: the film is aligned to the steps through the
  content patch, then per step and crop (glass patches, glyphs, labels,
  status bar, home indicator) the immediate change (the glass transmits
  the content at once) and the delayed one: latency from the content
  change, 5 / 50 / 95 percent times, the best of the UIKit curves
  (linear, easeInOut, default, easeOut, easeIn) and a critically damped
  spring, and the glyph minus glass timing (sync).
- Per scroll capture: every style change with the meter luma and the
  content luma under the bar at that moment.

## Deliverables

- Fixtures `test/fixtures/ios27-device/adaptive-brightness/` (compact
  jsonl rows of the captures, a `manifest.json` documenting the row keys).
- Reference crops (lossless) `tool/ios_reference/references/adaptive-brightness/`
  before and after a flip, light and dark base.
- A passport update with every number tagged `[device]`, and the answers
  to its open questions.
