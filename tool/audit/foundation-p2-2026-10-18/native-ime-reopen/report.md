# Native IME selection/reopen: harness ready, device measurement pending

2026-10-18. Base `117d4b57730a4fea535a5032fd29bc536f9c324a`. No new native behavior result is admitted in this increment. The earlier nine endpoint scenes remain the only completed native IME evidence. Dart library/prototypes, measured tuning and dependencies are unchanged.

## Prepared protocol

The public UIKit scene counts presentations and selected actions, retains an opaque source token, and logs field focus and editing events. Only the first presentation schedules the keyboard command. The new XCTest flow observes four rows of a ten-row menu, selects Native first after the keyboard transition, waits for menu absence and counter1, reopens the same button, selects Native second, and waits for absence/counter2. In show mode it then types `native` through XCUIApplication without tapping the editor.

The analyzer requires two ordered presentations/actions on one source token, the exact observed row set, complete snapshot intervals around the actual IME transition and selection callbacks, absent rows/hittable source after close, and focused editor-change events for typing. It reports settled placement and focus only. Neither a stable source frame nor hittability proves optical landing or uninterrupted motion. The analyzer has not yet accepted a real selection/reopen capture; its happy path and the planned corrupted-selection-time control remain pending.

## Failed device attempt

`selection-20261018-01/commands.json` records successful project generation and build-for-testing. XCTest failed before scenario execution with “Timed out while enabling automation mode.” The owned xcodebuild coordinator was interrupted and then terminated when it remained collecting diagnostics; its receipt has test−15 and export64. The atomic phone lock was released. No scenarios or selected callbacks from this attempt count as evidence. A read-only lock-state query reported passcodeRequired=false; that does not prove UI automation readiness. No phone settings were changed.

The initial runner copied app Documents despite the failed test. All three files were byte-identical to the preceding device5 endpoint capture. Their hashes and exclusion are recorded in `stale-copies.json`; only those stale new copies were removed. Earlier evidence was untouched. The canonical runner now returns before copying Documents whenever the test fails. Its subprocess timeout records exit124. A focused host regression exercises both test failure and timeout with fake commands and a temporary fake probe: neither path invokes devicectl or leaves event files, and both release the lock context. These are harness checks, not phone runs.

Raw Xcode logs/bundles remain in `~/morph-re/measurements/menu-keyboard/selection-20261018-01/`. The repo stores the command receipt and exclusion record, not raw framework dumps/logs. The source hashes in the receipt match the compiled Swift scene/test. Later Python changes do not alter that build.

## Verification and review

- Native app and XCTest compile successfully; device test execution is blocked before initialization.
- Root `flutter analyze --no-pub`: zero issues on Flutter3.47.7 stable. Shader offline gate: exit0. No shader/device performance claim follows.
- Both Python capture/analyzer modules compile. Analyzer rejects the failed receipt with exit2 and produces no analysis output.
- Focused host regression: one test, two failure/timeout cases, pass. It does not contact a phone or run Xcode.
- Deslop preserves the existing placement test through one shared flow and removes duplicated row-identity validation in favor of the exact expected set. No library abstraction was introduced.
- Comment Sicko: no actionable comments/suppressions, zero deletions/restorations/encoding offers. Review scope and final follow-up are recorded separately.
- Root/example Flutter tests and device shader parity were not repeated: no Dart/shader behavior changed. Previous444 example tests belong to the viewport increment.

## Resume

The operator has been asked whether an automation authorization dialog is visible. Leave phone settings to the owner. Once device readiness is confirmed, run from the repository root using the unused append-only output name:

```sh
python3 tool/ios_reference/lab/capture_menu_keyboard.py \
  --out tool/audit/foundation-p2-2026-10-18/native-ime-reopen/selection-20261018-02 \
  --skip-build
python3 tool/audit/foundation-p2-2026-10-18/native-ime-reopen/analyze.py \
  tool/audit/foundation-p2-2026-10-18/native-ime-reopen/selection-20261018-02 \
  --collect "$HOME/morph-re/measurements/menu-keyboard/selection-20261018-02/attachments"
```

The skip-build path requires matching Swift source hashes; omit it after any native source edit. Repeat a successful run under a new name, inspect screenshots/events, and exercise the negative selection-time control before admitting behavior. If automation initialization still fails, retain the failure and stop device retries until the environment changes. No retry is scheduled in the background.

Placement/source-validity design, optical close/landing, context-menu preview, Flutter parity and P2/main gates remain open. The conservative Dart endpoint retirement is unchanged.
