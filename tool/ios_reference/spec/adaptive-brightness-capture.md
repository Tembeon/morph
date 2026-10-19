# Adaptive bar brightness - capture protocol (iPhone 16 Pro)

For the coordinator's device run. Measures what
[adaptive-brightness.md](adaptive-brightness.md) leaves open: whether bar
glass and glyphs switch between a light and a dark look over content on
iOS 27.0.1, at which luma in each direction, how fast, and which elements
switch. Follows [README.md](README.md) (device lock, recording pipeline,
clocks, fixture conventions). Agents do not touch the phone outside a lock
session and never change phone settings.

## Owner-only steps

- Before the run: Settings > Display: Light. Reduce Motion OFF, Reduce
  Transparency OFF, Increase Contrast OFF (the start rows record `rm`,
  `rt`; note Increase Contrast by hand). Developer > Enable UI Automation
  ON. Do not change anything else.
- Between pass sets: switch Light -> Dark when the coordinator asks.
- MorphRecorder runs on the Mac (camera permission, `open`): the
  coordinator asks the owner before launching it.

## Do NOT force the appearance

UIKit stops tracking luma for a view whose user interface style is fixed.
`PROBE_DARK` sets the window's style, so it must stay UNSET in every pass;
the system appearance is switched by the owner instead.

## Probe scene to add (`abright`, keeper)

New file `Sources/AdaptiveBrightness.swift`, registered in the scene picker,
running the X3Sampler (it logs label text / colour and image view tint per
tick) and the `dl` rows:

- Variants by `PROBE_AB_BARS`:
  - `tab`: `UITabBarController`, 3 tabs (SF Symbols `house`, `star`,
    `gear`, with titles); tab 1 is a `UINavigationController` with an inline
    title ("Bands"), a leading `ellipsis` and a trailing `plus` bar button
    item, no toolbar.
  - `toolbar`: a `UINavigationController` (same nav bar) with the toolbar
    shown (`trash`, flexible space, `square.and.pencil`), no tab bar.
  - `search`: `tab` with a `UISearchTab` as the last tab, plus a second run
    of `toolbar` whose navigation item has a search controller with toolbar
    placement.
- Content: a vertical `UIScrollView` filling the screen, automatic content
  insets and edge effects (defaults; nothing overridden), whose content is
  a column of solid views. All colours sRGB, opaque:
  `UIColor(red: g, green: g, blue: g, alpha: 1)` for greys.
  - `PROBE_AB_CONTENT=solid`: one view 3 x the screen tall; script actions
    recolour it.
  - `PROBE_AB_CONTENT=stripes:<pt>`: alternating black / white bands of
    `<pt>`.
  - `PROBE_AB_CONTENT=split`: two views side by side (`left:<fraction>`
    white, the rest black) or one above the other (`edge:<y>`: white above
    window y, black below); script actions move the split.
- A spinner (`PROBE_SPINNER=1` behaviour) at the screen's centre, never
  under a bar, so the film keeps its clock during still periods.
- `PROBE_SCRIPT` actions (logged as `evt` rows with the display link
  timestamp of the tick that applied them, the value and the action):
  `grey:<g>`, `rgb:<r>,<g>,<b>`, `left:<f>`, `edge:<y>`,
  `scroll:<pt/s>,<seconds>` (programmatic constant-speed scroll, offset
  logged per tick), `top` (scroll to top).
- Start row extras: the values of `CalistogaAllowLumaTracking` and
  `MPLumaChangeDuration` as read from
  `UserDefaults(suiteName: "com.apple.UIKit")` and from
  `UserDefaults.standard` (object or nil; read only, never written), the
  OS build, `PROBE_AB_BARS`, `PROBE_AB_CONTENT`.
- Per tick, for the tracked bar views (`PROBE_X3TRACK` covering the tab
  bar, toolbar and navigation bar subtrees: their buttons, labels and image
  views): add `uis` = `traitCollection.userInterfaceStyle` (0 / 1 / 2) to
  the X3Sampler row, next to the logged colours.

## Passes

Dwell 2.5 s per step everywhere (render-server luma grid 0.25 s + glass
settle 0.35 s + an expected 0.6 s transition, with margin). Every pass
records probe rows AND a MorphRecorder film (full resolution).

| pass | scene | script | measures |
|---|---|---|---|
| P1 | `tab`, `solid` | `grey:0` then up to 1 in 1/32 steps, then down to 0 | flip luma up and down (coarse) |
| P1b | `tab`, `solid` | 1/128 steps over +- 3/32 around each P1 flip, approached from the flip's starting side | flip luma (fine) |
| P2 | `toolbar`, `solid` | P1 and P1b | the same for the toolbar and nav bar |
| P3 | `tab` and `toolbar`, `solid` | 0 -> 1 -> 0 x 3 with 4 s dwell; then 0.3 <-> 0.8 x 3 | latency, transition duration and curve, glass vs glyphs |
| P4 | `tab`, `solid` | from `grey:0` (8 s): 0.45 / 0.65 alternating x 6; from `grey:1` (8 s): the same | hysteresis hold (no flip expected for a 0.40 / 0.70 rule) |
| P5 | `tab`, `solid` | from `grey:0` and from `grey:1` (5 s each): `rgb` red, green, blue, cyan, magenta, yellow at 1.0 and 0.5 | luma weights |
| P6a | `tab`, `split` | from all black / all white: `left:` 0, 0.25, 0.5, 0.75, 1 | statistic (area mean?) |
| P6b | `tab` and `toolbar`, `split` | `edge:` from the bottom up to 300 pt above it in 8 pt steps and back; top band: from the top down to 300 pt and back | the sampled region of each band |
| P7 | `tab`, `stripes:300` and `stripes:100` | `scroll:` 300 and 1200 pt/s, 6 s each; then one finger fling (XCUITest swipe) | behaviour while scrolling |
| P8 | owner switches to Dark | P1, P2 (coarse), P3, P4 | the dark-mode base |
| P9 | `search` | P3 | search tab circle, bottom search field |
| P10 | optional, `tab` | P3 and P4 with the launch argument `-CalistogaAllowLumaTracking YES` | the pocket path's look when stock shows no discrete flip |

P10 sets a default for the probe process only (argument domain), not a
phone setting; run it only if P1 - P4 show no discrete flip and the
coordinator agrees. Its results are labelled "not stock".

Total about 25 minutes of phone time plus film handling.

## Analysis (host, after the run)

- Flip events: from the `uis` rows of each bar view and from the film
  (per-frame mean colour of fixed crops: one tab glyph's interior, a label,
  a glass capsule area free of glyphs, the nav bar item glyph, the toolbar
  glyph, the status bar, the home indicator). A flip = a monotonic change
  of more than 8 / 255 that settles.
- Flip luma: the grey of the step that triggered a flip, per direction,
  per bar, per appearance; P1b brackets it to 1/128.
- Latency: from the step's `evt` timestamp to the first film frame that
  moves (film aligned to the probe rows as README describes), and to the
  `uis` change.
- Transition: normalise each crop 0 -> 1; duration 10 - 90 percent and
  full; fit the curve (UIKit curve families and springs); report the glass
  vs glyph onset and duration difference.
- Elements: a yes / no table per element and pass.
- Statistic and region: P6a against an area mean; P6b's flip positions give
  each band's sampled extent above the screen edge.
- Scrolling: flips per second and their lag behind the content in P7.

## Deliverables

- Fixtures `test/fixtures/ios27-device/adaptive-brightness/` (compact
  jsonl, `manifest.json` documenting the row keys and the `evt` actions).
- Reference crops (lossless) `tool/ios_reference/references/adaptive-brightness/`
  before and after a flip, light and dark base.
- A passport update with every number tagged `[device]`, and the answers
  to its open questions.
