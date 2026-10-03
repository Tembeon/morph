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

## Not reproduced / open

- The glass morph is a rect lerp fitted to film, no tuning value found.

## API gaps

- `automaticallyActivatesSearch = false` variant (tab without auto focus).
- Search tab inside sidebar mode; scope bars; suggestions.
