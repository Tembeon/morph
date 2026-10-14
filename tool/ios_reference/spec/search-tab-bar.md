# Search tab bar passport

Status: measured (simulator video + device rows and film); ported.
See also [tab-bar.md](tab-bar.md), [search.md](search.md).

## Native

`UISearchTab` in a `UITabBarController` (`automaticallyActivatesSearch`),
field container `UIKit._UITabHostedSearchContainer`, glass
`GlassInteractionView`. The tab -> field glass morph lives in SwiftUI and
is INVISIBLE in view frames (they jump to endpoints): measure from film.

## Spec

- Rest = `MorphTabBar` 21 from side/bottom + a 62 pt search circle.
- Searching = 48 pt tab circle (selected glyph) at 28 + field 88 .. W - 28.
- Focused = field 8 .. W - 64 + close button 8 apart, 8 above the keyboard;
  tab circle fades (keyboard covers it in UIKit).
- Morph between = rect lerp of the two glass bodies on 0.276/0.80 [film,
  sim video, still true on device; 1.7 pt rms on glass edges].
- Field focuses itself 0.16 s after the tap while the morph runs
  (`tabActivationDelay`; focusing on the build frame lost the keyboard).
- After the keyboard rises (+0.07 s, `tabKeyboardLag`) the field rises
  above it on its OWN `tabFocusSpring` 0.3/1.0 [device, 0.19 pt rms over
  308 pt; 0.25/0.9 leaves 12]; falls back 0.04-0.05 s after the close tap
  (`tabUnfocusDelay`), straight from above the keyboard to rest (no
  following the keyboard down).
- Tab circle takes a tap while the morph into the field runs and turns it
  around with its velocity; the search circle ignores taps while the morph
  back runs [device].

## Fixtures

`ios27-device/search/tab-search-focus.jsonl`, `vid-tab.jsonl`;
`ios27/search/tab-search-video.json` (sim video fit). Film crops
`references/search-video/`.

## Recapture

Scene `x3search` with `PROBE_SEARCH=tab|tabauto`; ExtrasUITests.testX3Device,
testX3Video (film), testX3Timing (`tm-tab-in/out-<gap>` via twoTaps,
`PROBE_GAPS`).

## morph

`MorphSearchTabBar` (search_tab_bar.dart), `MorphSearchTuning`
(search_motion.dart). Test: search_test. Film side:
example/integration_test/search_date_scenes.dart.

Per-frame work (lifecycle.md, 2026-10-14): the bar is a repaint boundary
(the page under it no longer repaints with the morph); the close button
travels at its size to the bit (`morphLerpRect`), so it is neither laid
out nor its glass rebuilt every frame; the tab spring lands on its
target once it rests within 0.001 and the focus transition does the same
(`MorphSearchMotion.land`) - NEAR: the shapes jump by at most 0.001 of
their travel (0.3 pt over 300 pt), once, where they used to freeze that
far off; what the tabs and the circle show or take (the label, the
placeholder, touches) is pushed to the part that reads it, so a flip
rebuilds that part, not the whole morph. Side effect, policy-declared:
the close button's content holds still while it scales in, so the glyph
policy draws it from its raster (NEAR) where it snapped before.
Still per frame: the tab and search shapes are boxes that follow the
morph by layout (about 10 layouts each, their glass, clip and touch
wrappers), and the field relayouts while the focus transition changes
its width.

## Not reproduced / open

- The glass morph is a rect lerp fitted to film, no tuning value found.

## Minimizing

`minimizeBehavior` and `bottomAccessory` (passport
[tab-bar-minimize.md](tab-bar-minimize.md)): minimized, the bar is the
same 48 pt tab circle the search morph ends in, and the search circle
shrinks to 48 pt at the trailing side; searching from there leaves the tab
circle in place. The accessory fades while searching (not measured).

## API gaps

- `automaticallyActivatesSearch = false` variant (tab without auto focus).
- Search tab inside sidebar mode; scope bars; suggestions.

## Implementation notes (morph side, moved from CLAUDE.md)

- The hidden field is mounted from the start: focusing it the frame it was
  built made the device's engine close the fresh input connection (no
  keyboard, focus dropped 70 ms later) - hence `tabActivationDelay`.
- `tabUnfocusDelay` 0.05 s (0.038 / 0.064 in two captures; the fall itself
  0.8 pt rms).
- ONLY the activating search tab is a separate circle in iOS 27: without
  `automaticallyActivatesSearch` UIKit draws the search tab as an ordinary
  "Search" tab inside the bar (filmed), so the widget models the activating
  kind only.
- TAB MORPH REVERSAL (films tm-*): a tap on the tab circle while the morph
  into the field runs turns it around with its velocity (UIKit, taps 0.125
  and 0.225 s after the search tap; at 0.375 the keyboard covers the
  circle), so the tab circle takes taps whenever searching until the close
  button shows (focus progress 0.5); a tap on the search circle while the
  morph back runs is IGNORED by UIKit (0.125 / 0.225 / 0.375 s). The
  reversal's start latency was not readable (film clock); ours retargets
  at the lift.
