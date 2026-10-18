# Native IME selection/reopen results

2026-10-18, base `20e8724f`. iPhone16Pro, iOS27.0.1, portrait402×874pt at3×, source `(161,406,80,48)`, safe area `(0,62,0,34)`, content size L, Reduce Motion false. Two successful serial XCTest executions: `selection-20261018-02` and `selection-20261018-03`. Each executes none/show/hide with ten menu rows and observes rows1/2/3/10. Six scenes, twelve openings and twelve selected callbacks. No phone settings changed.

## Observations

Both runs produce the same vertical placement result:

| Mode | First row before/after IME | After fresh reopen | Focus at both selected callbacks/reopen |
| --- | --- | --- | --- |
| none | 410 → 410pt | 410pt | false |
| show | 410 → 410pt | ≈135pt (−275pt) | true |
| hide | ≈135 → ≈135pt | 410pt (+275pt) | false |

Within each scene, all four observed row frames are exactly unchanged across the IME transition:24 row-frame pairs across both runs, delta0 in all coordinates. Source frames remain exactly unchanged across32 snapshots. This does not assert identical frames between separate openings: in selection02 control, first-row x changes from76⅓ to76pt on reopen while y stays410pt.

Every scene has one opaque source token, two menuTriggered events with presentation1/2, and exactly Native first/Native second selected with selectionCount1/2. After each selection, all four queried rows are absent and the source is hittable; tapping the same button causes the second presentation. Both show scenes retain first responder at the two action callbacks and reopen. Each receives six focused editorChanged events ending in `native`, through XCUIApplication.typeText without another editor tap. App and test use the same device monotonic clock; callback/reopen events lie strictly between their declared snapshot windows.

Fresh placement uses the current keyboard state while the existing menu keeps its sampled placement. This supports separating placement at each opening from the source endpoint's lifetime. It does not reveal UIKit's implementation or decide our landing policy.

## Typing and keyboard visibility

The parent inspected selection02 show-reopened, show-closedAgain and show-typed screenshots. The keyboard is visible in reopened/closedAgain; during XCTest.typeText the app emits WillHide/DidHide while fieldFocused remains true, and the typed screenshot has no visible keyboard. The typed XCUI keyboard element still exists but starts at y891, outside the874pt window. Selection03 repeats the focus/input behavior and the offscreen typed keyboard frame. Thus keyboardExists is an accessibility-existence observation, not a visibility guarantee. This protocol proves input delivery and observed first-responder retention, not sustained software-keyboard visibility during XCTest typing or uninterrupted focus between all events.

## Evidence and validation

- Both receipts record generate/test/export/copy-none/copy-show/copy-hide exit0. They reuse the compiled Swift sources from the successful build in selection01; source hashes match, and no native source changed during the two runs.
- Both analyzer executions exit0. Each imports three named geometry JSON and16 named screenshots from the private xcresult attachment export; app event journals are copied only after successful XCTest. Raw Xcode logs/bundles stay under `~/morph-re/measurements/menu-keyboard/`.
- Negative control copies selection02 to a temporary directory, moves the first show callback after closed.start, sorts the journal to preserve event ordering, and removes copied analysis. The real analyzer CLI rejects it with exit2, `first callback outside selection window`, and no new analysis output. `negative-selection-time.json` records this; original captures remain unchanged.
- An independent how explainer recomputes geometry/counters/focus/timing from public JSON and distinguishes actual observations from policy inference; see how-evidence.md.
- No Dart, native source, analyzer, dependency or shader implementation changed in this results increment. Root analyze is repeated for the documentation update. The harness failure/timeout regression passes again. Shader offline success belongs to20e8724f; no new performance or pixel-parity claim is made.
- Deslop keeps one behavior contract in menu-native-ime.md and only a short result summary in the plan/passport. Comment Sicko reviews the scoped document changes. Older artifacts.json and verification.json are the prepared-stage snapshot at20e8724f; results-artifacts.json/results-verification.json describe this increment.

## Remaining work

Settled closed/hittable source and a successful later tap establish functional reuse. They do not establish optical landing, morph contour, continuous close trajectory, or early reopening during that trajectory. Source did not move or disappear. Hidden holds/reservations, active source geometry loss, context-menu preview, different windows/keyboards/orientations and Flutter parity remain open. Design the placement-snapshot/source-validity boundary through architect before changing the conservative Dart detach. P2 and main migration stay open.

To repeat, use the canonical capture CLI with a new output name, then the analyzer --collect command from the prepared-stage report. No run remains scheduled or active after this increment.
