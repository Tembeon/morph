# Native sweep 2026-10-14 - morph widgets against iOS 27 UIKit

A pass over the widget families (sheets and menus/context menus excluded:
both are being reworked elsewhere) to find behaviour, look and API that
differ from native. It records discrepancies only; nothing in `lib/` was
changed.

## How it was captured

- Simulator: an own iPhone 17 Pro, iOS 27.0 (24A434), 402 x 874 pt @3x,
  60 Hz, booted headless (created, locked, deleted for this pass).
- Native: the probe app (`tool/ios_reference/Sources`, scenes `segmented`,
  `controls`, `tabbar4/5`, `nav`, `x3search` (`PROBE_SEARCH=tab`,
  `PROBE_TBITEMS=1`), `w2search` (`PROBE_MINIMIZE=1`), `x3alert`, `x3date`,
  `w2progress`, `list`, `merge`, `x4dis`).
- morph: the gallery pages (debug build, liquid tier forced) behind an
  untracked entry point that opens one page inside a `MorphNavigationStack`.
- Input: one XCUITest runner drives both apps with the same coordinates
  (taps, holds, drags, edge swipes, typing). Films come from
  `simctl io recordVideo` (variable rate), stills from the runner.
- Evidence lives outside the repo: `~/morph-re/runs/native-sweep-20261014/`
  (`native/`, `morph/` stills light + dark, `runs/<side>-<run>/` films,
  stills and step logs, `pairs/` side-by-side crops). Paths below are
  relative to that directory.
- Two read-only API audits compared the current `lib/` against
  `spec/api/*.md` and the passports' gap lists (results under "API").

Limits: Flutter runs in debug on the simulator, so timing (push stalls,
spring speeds) is NOT evidence; geometry, order of events, end states and
looks are. Optics on the simulator are not the device's (see "Needs the
phone"). XCUITest synthesis is coarse (no fine velocity control).

## Ranked discrepancies

Severity: **UV** user-visible, **S** subtle, **API** API gap. Size: S/M/L.

### 1. Nav bar - inline title draws over a trailing capsule (UV, S)

- Native: the title takes only the room between the leading and trailing
  capsules; it is truncated (or dropped) when it does not fit.
- morph: on the gallery detail page ("Message 4 / From Anna, today", a
  heart+share capsule, a prominent Done, the gallery's 1x button) the
  title and subtitle are painted right on top of the heart/share capsule,
  at rest and during the edge swipe.
- Cause: `_InlineTitle` (lib/src/widgets/navigation_bar.dart ~640-654)
  narrows its room only with capsules entirely left (`r <= center`) or
  entirely right (`l >= center`) of the bar center; a capsule that
  straddles the center bounds nothing, so the title spans it.
- Evidence: `pairs/detail-s3.png` (native top, morph bottom),
  `runs/morph-nav-gest/s3.png`, `pairs/morph-pop-seq2.png`.
- Fix: classify every capsule by side (leading groups bound `lo` with
  their right edge, trailing groups bound `hi` with their left edge,
  whatever their position), then ellipsize; hide the title below a minimum
  width. Add a widget test with a wide trailing group.

### 2. Search tab without auto activation - no morph equivalent (UV, M-L)

- Native (`x3search`, `PROBE_SEARCH=tab`, `UISearchTab` with
  `automaticallyActivatesSearch = false`): at rest the search tab is an
  ordinary "Search" tab inside the bar (as the passport says). Selecting
  it shows its page: large title "Search" and a STACKED search field under
  it, x 16 - 386, 44 pt tall, full capsule, no keyboard. Tapping the field:
  the large title and nav bar slide away, the field pins at the top
  (~8 - 334 pt) with a 44 pt round close button at the trailing edge
  (~344 - 388), the keyboard rises and covers the tab bar (visible through
  it). Scrolling the list keeps the keyboard.
- morph: `MorphSearchTabBar` models only the auto-activating search tab;
  its dartdoc says a non-auto search tab is "an ordinary MorphTabItem",
  but nothing gives that tab a stacked/top field or the focus transition
  (no search placement in `MorphNavigationConfig` / scaffold).
- Evidence: `native/tabsearch-0.png`, `runs/native-tabsearch/s1..s4.png`,
  `pairs/tabsearch-native.png`.
- Fix: a stacked search placement for the navigation scaffold
  (`MorphNavigationConfig.search`, field under the large title, collapses
  with it), a focus transition (bar out, field to the top, close circle),
  then a `MorphTabItem` role or `MorphSearchTabBar.activatesSearch: false`
  that selects a page carrying that field. Correct the dartdoc. Measure the
  focus transition timing on the device first.

### 3. Search activation keeps the navigation bar (UV, M)

- Native (`x3search` toolbar placement, `PROBE_TBITEMS=1`): focusing the
  bottom field hides the navigation bar (UISearchController
  `hidesNavigationBarDuringPresentation`, default true) and the content
  moves up to the status bar.
- morph (`SearchPage`, Toolbar): the nav bar with its title stays; the
  field and close button sit at the same place as natively (field
  8 - 334, close 344 - 392).
- Evidence: `pairs/searchtb-grid.png` (top native, bottom morph; rest,
  focused, typed).
- Fix: let the search toolbar (once tied to the scaffold, item 2) hide the
  nav bar while active; a flag mirroring `hidesNavigationBarDuringPresentation`.

### 4. Interactive pop - pushed page is a rounded card over a dimmed page (UV, S-M)

- Native, during the edge swipe: the pushed page's leading edge has the
  display corner radius at top and bottom (fitted from the film: ~62 pt,
  the iPhone 17 Pro display radius) and the page underneath darkens
  (~7 percent at ~0.4 progress: 255 -> 238 in every row).
- morph: the page edge stays square and the page underneath does not dim
  (<1 percent).
- Evidence: `pairs/pop-mid.png` (native left), `pairs/pop-mid-native.png`;
  pixel rows quoted from frames 28.0 s (native) and 37.9 s (morph) of
  `runs/*-nav-gest/film.mp4`.
- Fix: in `MorphNavigationRoute`'s slide, clip the moving page to the
  display corner radius (`MediaQueryData.displayCornerRadii`, Flutter
  3.44+) on its leading side while it moves, and dim the page below with
  black whose alpha follows progress. Measure the dim law (max alpha, and
  whether a non-interactive push does the same) on the device.

### 5. Tab bar minimize - a reverse scroll does not expand natively (UV, S)

- Native (`w2search`, `PROBE_MINIMIZE=1`, search tab list): scrolled down,
  the bar minimizes; a 150 pt drag back up in the middle of the content
  (released, settled) leaves it MINIMIZED.
- morph (`MinimizeTabBarPage`, onScrollDown): the same 150 pt reverse drag
  expands it. morph's rule is the declared approximation "a 64 pt drag in
  the expanding direction expands" (tab-bar-minimize.md "Not read").
- Evidence: `pairs/minimize-grid.png` (top native s1..s4, bottom morph).
- Fix: drop the 64 pt reverse rule (expand at the top end, by tap, by
  pushing past the far end - the read rules), pending a device capture of
  a long reverse fling.

### 6. Minimized bar with a (non-auto) search tab (UV, M)

- Native: when the bar minimizes while the search tab is selected, the
  search tab becomes its own trailing circle and the leading circle shows
  the last non-search tab (Home); a tap on that circle expanded the bar
  WITH Home selected (the page switched).
- morph: `MorphTabBar` has no search-tab role; only `MorphSearchTabBar`
  splits the search circle, and only in auto mode. The passport's "a tap on
  the minimized circle expands it (no selection)" does not cover this case.
- Evidence: `runs/native-minimize/s2.png`, `s4.png`.
- Fix: with item 2, model the search tab role in the minimized layout;
  capture the tap rule on the device.

### 7. Edge swipe - native trails the finger and returned where morph popped (S, needs device)

- Same XCUITest input (press at x 3, drag to 230, hold 0.6 s, lift):
  native page edge followed at ~155 pt (0.39 W) with the finger at 230 and
  CANCELLED on lift; morph followed at ~207 pt (0.51 W) and COMMITTED. A
  fast drag to 330 popped on both.
- The passport's commit rule (pop from 0.3 W at rest) predicts a pop at
  0.39; the simulator disagrees. Synthesizer artifacts are possible (the
  passport lists one unexplained return at +1.25 W/s).
- Evidence: `pairs/native-nav-tile.png` (row 3), `pairs/morph-nav-tile2.png`
  (row 3), `runs/*-nav-gest/s4.png`.
- Fix: re-record held-still releases between 0.3 and 0.6 W on the phone
  with logged touches before changing `popDistance`; also check the finger
  -> page offset (native lag ~75 pt here).

### 8. Tab badge smeared by the lifted lens (UV, S; native twin missing)

- morph: holding or dragging the lens over a badged tab stretches the
  badge into a red drop at the lens rim (Radio's dot, Library's "3").
- Native: the probe's tab bar has no badges, so UIKit's behaviour was not
  seen. In UIKit the badge is a separate view over the item.
- Evidence: `pairs/tab-press.png` (right half, last rows),
  `pairs/tab-drag-morph.png`.
- Fix: capture a badged native tab under a held lens (probe: set
  `badgeValue` in `TabBarScene`); if UIKit keeps the badge crisp, draw
  badges above the lens instead of inside both item layers
  (tab_bar.dart ~860-915, `MorphBadged.glyph` in both copies).

### 9. Lifted lens look (segmented, tab bar) (S, needs device)

- Native lifted lens: thin cool-gray rim with chromatic fringes, a soft
  drop shadow under it, the track's inner edge visible through it.
- morph (liquid tier, simulator): heavier dark rim at the bottom-left,
  specular arcs inside, no dispersion fringe, weaker shadow.
- Evidence: `pairs/seg-lift.png` (native), `pairs/seg-lift-morph.png`.
- Fix: compare on the iPhone (simulator shaders and Metal path differ)
  before touching the renderer; glass-optics.md owns the numbers.

### 10. Hard scroll-edge band blurs more than native (S, needs device)

- Native hard band (nav bar, automatic = hard): the rows under the bar are
  washed and only lightly blurred (row text still readable).
- morph hard band: the content is blurred much harder (text unreadable).
- Evidence: `pairs/nav-s1-top.png` (native top).
- Fix: check the measured 2 pt hard radius against the device film; the
  simulator's debug renderer may exaggerate. If it holds, look at the
  half-resolution raise (bars.md "Cost, 2026-10-14").

### 11. Glass bar buttons are milky where native picks up the content (S)

- Native bar capsules over yellow rows turn yellow; morph's stay
  whitish/pink. Known: glass-optics.md "light glass material too bright".
- Evidence: `pairs/nav-s1-top.png`.

### 12. Alert / popover glass over busy content - unverified (S)

- morph's alert and date popover show the controls behind them clearly
  through a light blur; the native probe scenes have empty backgrounds, so
  native opacity over content was not seen.
- Evidence: `pairs/alert-s1.png`, `pairs/date-s1.png`.
- Fix: add busy content behind `x3alert` / `x3date` and compare before any
  change.

### 13. No scroll indicator in scaffold lists (S, S-M)

- Native tables show the indicator while scrolling and on a pull; morph
  scaffold slivers show none.
- Evidence: `pairs/pull-title.png` (native left).
- Fix: an iOS-style indicator in `MorphNavigationScaffold` (insets under
  the bars), on by default.

### 14. Search keyboard traits (S, S)

- Native search field: the return key is disabled while the field is empty
  (`enablesReturnKeyAutomatically`) and the QuickType row is empty; morph's
  field shows suggestions ("The", "I'm") and an enabled return key.
- Evidence: `pairs/searchtb-grid.png` (focused column).
- Fix: turn suggestions / autocorrect off on the search field; check
  whether the engine exposes the return-key flag (may be an engine gap).

### 15. API - top gaps from the audit (API)

Ranked by need; full lists in "API" below.

- Navigation: no full-width content back swipe
  (`interactiveContentPopGestureRecognizer`, iOS 26, on by default; morph
  only a 20 pt edge, navigation_motion.dart:166) - M after measuring.
- `largeTitleDisplayMode` defaults to `never` on config and scaffold
  (navigation_stack.dart:45, 1172); UIKit defaults to automatic, so
  `prefersLargeTitles: true` does nothing unless every page opts in - S.
- Glass: `MorphGlassContainer` does not fuse (no `spacing`,
  glass_container.dart:58-63); app glass cannot merge like
  `GlassEffectContainer` - L.
- Lists: no swipe actions, no plain/grouped style, no edit mode - L.
- Date picker: `inline` / `wheels` styles assert; `countDownTimer` /
  `yearAndMonth` missing; `firstDayOfWeek` hard-coded Sunday
  (date_picker.dart:460, 513) - M / S.
- Buttons: no size presets (`buttonSize`), no shape (`cornerStyle`), no
  `showsActivityIndicator` - M / S-M.
- Bars: no `titleView`, title menu, centered toolbar items, `hidesSharedBackground`,
  per-group tint; `MorphSearchToolbar` cannot be ended from code (no
  controlled `active`, search_field.dart:600) - S-M each.
- Zoom: no zoom from a bar button, no `dimmingColor` / dismiss veto - S-M.
- Scroll edge: no `automatic` style (soft/hard only) - S.

## Consistent with native (checked, no action)

- Segmented control statics (all seven rows, light and dark) and the lens
  drag past the end (both lift and rubber-band to the screen edge):
  `pairs/seg-light__seg-light.png`, `pairs/dark1.png`.
- Controls statics light/dark; slider dragged past the max stays at 1.0;
  stepper held 2.5 s = 4 steps on both (passport: 0.5 s, every 0.5 s):
  `pairs/ctl-grid.png`.
- Tab bar geometry (21 pt sides, lens), press-hold lifts and moves the lens
  to the held tab, drag scrub across tabs: `pairs/tab-press.png`.
- Nav bar: hard edge band height (116 pt) and default; large title follows
  the content on a pull without scaling; inline title fades in; bar items
  do not move during an edge swipe (bars.md): `pairs/pull-title.png`,
  `pairs/pop-mid.png`.
- Search toolbar focused geometry (field 8 - 334, close 344 - 392).
- Date picker compact popover size (~320 pt wide) and layout:
  `pairs/date-s1.png`.
- Dark statics of lists, indicators, alerts, tab bar: `pairs/dark2.png`.

## Not covered in this pass

RTL, push zoom, page control scrub, progress/activity motion, disabled
looks (states.md is measured), action sheets, glass fusion (the native
`merge` scene with spacing 0 never fuses; the gallery has no fusion demo
to compare), alert press-scrub (the film windows missed the drag), the
switch tap (the native XCUITest tap did not toggle - a harness issue).

## Needs the phone (not answerable on the simulator)

Timing of every spring (Flutter debug on the simulator), lens/rim/shadow
optics (items 9-11), the edge-swipe commit rule (7), the dim law (4),
haptics, 120 Hz, frame time and energy.

## API

The api pages are stale; these are CLOSED in code and should be struck
from `spec/api/*.md`: bar badge, subtitles, `backButtonDisplayMode` /
`hidesBackButton`, `largeTitleDisplayMode` enum, leading groups,
`MorphBarButtonStyle`, pages API (`MorphNavigationStack.pages`), tab badge /
`onReselected` / `selectedIcon`, search `active` rename, scroll edge
`scrolledUnder` and appearance rename, ambient tint and theme scope,
segmented `MorphSegment` (enabled, width, `selectedIndex: int?`), switch /
slider / stepper / page control / progress renames, slider `min`/`max`/
`onChangeStart`, glass button `.prominent` / `.clear` / `.prominentClear`
and `menu`, alert `enabledListenable` and text field options, date picker
`minuteInterval` / min/max / localizations, list header/footer widgets,
accessories, sliver section, `MorphGlassEffect` with per-surface style.

Open beyond item 15 (need x size): search scope bar, suggestions, tokens,
minimized search toolbar; tab `extentFor`, hidden / animated hide, Widget
icons, prominent tab, accessory insertion animation, `onReselected` on
`MorphSearchTabBar`; nav bar hidden per page, inline large title, bar
minimization, back-title shortening, toolbar item swap on push (fitted
spring in bars.md, not ported), bar item selected state and menu order;
navigation cross-fade transition, `onGenerateRoute`; segmented image
segments, momentary, lens color param; slider track configuration,
thumbless, min/max images; page control images, colors as params,
`hidesForSinglePage`, direction, timer, continuous interaction; alert
general popover, `permittedArrowDirections`, single preferred action
assert, text field return key / autofill hints / clear button; buttons
role, foreground color, subtitle / image placement, pop-up button, menu
order forwarding; stepper `wraps` / `autorepeat` / images / change
start-end; thumb color params; slider semantic formatter; localized
stepper labels; progress `animated` default true (UIKit's setter does not
animate); activity starts animating (UIKit starts stopped); captions;
badge appear/leave animation; concentric corner API.

## Status after the navigation bar pass (2026-10-14)

- 1: fixed - the inline title keeps to the room between the groups,
  measured rule in bars.md "Spec - inline title room".
- 3: fixed for the toolbar search - `MorphSearchToolbar` hides the
  scaffold's navigation bar while searching
  (`hidesNavigationBarDuringPresentation`), content up on the fitted
  spring; bars.md "Spec - bar hidden while searching" (a bar with items
  and the way back pending the iPhone).
- 13: fixed - `MorphScrollIndicator` in the scaffold, bars.md "Spec -
  scroll indicator" (dark color, minimum lengths pending).
- 15: `largeTitleDisplayMode` defaults to automatic on the scaffold;
  `navigationBarHidden` / `setNavigationBarHidden` added. Still open:
  `titleView`, title menu, centered groups.
