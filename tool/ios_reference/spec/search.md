# Search field and search toolbar passport

Status: measured simulator + device (toolbar transition, keyboard
timing) + film light/dark; ported; replayed (search_test). Tab bar search:
[search-tab-bar.md](search-tab-bar.md).

## Native

`UISearchController` (bottom toolbar placement on iPhone), `UISearchBar`,
`UISearchTextField`, glass `GlassInteractionView`, keyboard
`UIKeyboardItemContainerView`. Tuning: SwiftUI
`GlassContainerSearchTransitionPTSettings` [tuning].
Public API (SDK 27.0): `searchResultsController`, `searchResultsUpdater`,
`active`, `obscuresBackgroundDuringPresentation`,
`hidesNavigationBarDuringPresentation`, `automaticallyShowsCancelButton`,
`automaticallyShowsSearchResultsController`, `showsSearchResultsController`,
`scopeBarActivation`, `searchSuggestions`, `searchBarPlacement`,
`ignoresSearchSuggestionsForSearchBarPlacementStacked`; delegate
will/didPresent, will/didDismiss; UISearchBar scope buttons, tokens
(UISearchTextField `tokens`), bookmark/results buttons.

## Spec - field

- 48 pt capsule; magnifier at 12 (13.33 pt ring, 1.75 thick); text at
  40.67, 17 medium; placeholder secondaryLabel (resting placeholder lighter:
  `restingPlaceholderColor`); clear button 20 pt, 13.33 from the end (disc
  16.67); close cross 16.67 pt, 2.3 thick; cursor 66/106/243 (dark
  64/107/248) [layout + film].
- Touch lifts it on the glass-button model 0.05 s after contact; a held
  touch focuses when it lifts.
- Sentence capitalization like UIKit.

## Spec - bottom search toolbar

- Rest: items in 48 circles + flexible field, 28 from sides/bottom, 12
  apart. Focused: field + 48 close button, 8 from the sides, 10 above the
  keyboard.
- ONE progress on 0.25/0.9 [tuning; free fits 0.238 - 0.246 / 0.92 - 0.94
  sim and device], starting 0.067 s after the change [device cancel;
  0.077 - 0.086 sim]; a close tap starts it 0.080 s after the lift.
- A FOCUS that brings the keyboard waits for it: field starts 0.015 s after
  the keyboard's first frame (`keyboardLag`; 0.17 - 0.19 s after the tap,
  0.28 for the launch's first keyboard); `keyboardWaitLimit` 0.3 s guard.
- Field rect lerps; arriving items (close) scale 1.2 -> 1 with alpha =
  progress and blur, from their slot in the OLD configuration; leaving
  items freeze where they stood (close fades in place while the keyboard
  drops); returning items come from the focused layout WITHOUT keyboard
  (UIKit's virtual slots, y = H - 10 - 24).
- Vertical: field lerps toward 10 above the LIVE viewInsets (UIKit aims at
  the final keyboard frame). Closing falls straight from above the keyboard
  to rest (no dip). 0.7 - 2 pt rms over 300 pt.

## Disabled field [device, light + dark, 2026-10-03]

- `UISearchTextField.isEnabled = NO`: the GLASS capsule is replaced by a
  flat fill 0x767680 at 0.12 dark / 0.06 light (the field's own layer bg;
  pixels 14,14,15 on black / 235,235,240 on 242,242,247), no rim, no lift.
  Magnifier unchanged (label color), placeholder unchanged (tertiaryLabel,
  rendered 80 dark / 183 light on the flat fill).
- One frame, no animation.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method in [states](states.md).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): `MorphSearchFieldStyle.disabledFillColor`; the
  body pixel matches 14,14,15 / 235,235,240.

## Fixtures

Device `ios27-device/search/` (search-toolbar, search-tap, search-hold);
simulator `ios27/search/` (search-close, search-hold, search-toolbar,
search-toolbar-items). Film crops `references/search-video/`.

## Recapture

Scene `x3search` (`PROBE_SEARCH=toolbar|nav|tab|tabauto`, `PROBE_DARK`,
`PROBE_SCRIPT` focus/activate/cancel/resign/type/type2/clear);
ExtrasUITests testX3Search, testX3Device, testX3Video (film), testX3Timing.
Older scene `w2search` (Widgets2UITests.testW2Search, `PROBE_MINIMIZE`).
morph film side: example/integration_test/search_date_scenes.dart.

## morph

search_field.dart (`MorphSearchField`, `MorphSearchFieldStyle`,
`MorphSearchToolbar`), search_motion.dart (`MorphSearchMotion`,
`MorphSearchTuning`).

## Not reproduced / open

- UIKit moves the close button two frames behind the field.
- The large-title nav bar collapsing during search (app's business).
- UIKit's empty prediction bar (autocorrect off + spell check on cannot be
  requested through Flutter's engine; keeping the bar avoids a 27 pt drop).

## API gaps

- Search in the navigation bar (integrated / stacked / integratedButton /
  inline placements) - only the bottom toolbar placement exists.
- Scope bar, search tokens, suggestions, results controller semantics,
  bookmark / results list buttons.

## Implementation notes (morph side, moved from CLAUDE.md)

- SCREEN-RECORDING PASS (2026-10-03, search-video/ crops): a held touch
  focuses on the lift (the field's Listener; text selection gestures only
  while focused - a 0.5 s hold used to win Flutter's long press and never
  focus). A closing search falls straight to rest: the focused layout keeps
  the keyboard inset of the moment the search ended (`_frozenKeyboard`)
  instead of following the dropping keyboard (which dipped the field 18 pt
  below rest). The field paints BEFORE the toolbar items: glass inside an
  Opacity (a fading or disabled item) that is the first user of the
  BackdropGroup's shared copy makes every later glass read the empty layer
  (the resting field went invisible on dark). Resting placeholder lighter
  than focused (149 vs 133 on 252 light, 110 vs 142 on 32 dark);
  keyboardAppearance follows the brightness; the cursor is not the accent.
- KEYBOARD [device, ExtrasUITests.testX3Timing / testX3Shots /
  testX3AlertVideo, morph's board via PROBE_BUNDLE]: UIKit's search text
  field reports autocorrectionType NO, spellCheckingType default,
  capitalization by sentences, return key Search; that pair keeps the
  prediction bar on screen but empty (328 pt keyboard). Flutter's engine
  sets spellChecking from the same `autocorrect` flag, and autocorrect false
  drops the bar (keyboard 27 pt shorter, the focused field 27 pt lower than
  native - filmed), so the field keeps autocorrect on (suggestions show in
  the bar: NOT reproduced without an engine change) and asks for sentence
  capitalization.
