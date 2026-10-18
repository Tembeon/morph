# Native button-menu keyboard endpoints

2026-10-18. Base `daa49e98adc1b5a1e0c5afb8d199c153e0304389`, branch `wip/measured-liquid-glass`. Measurement tooling/specification only. No Dart behavior, tuning, dependency/export, main or push changes.

## Observed result

For this real iPhone16Pro / iOS27.0.1 public UIButton.menu scene, initial keyboard state affects placement, while subsequent keyboard show/hide leaves the observed settled row coordinates unchanged. Two ten-row repetitions agree exactly. The keyboard can cover the lower part of a previously opened menu.

| Ten-row scene, both repetitions | First row before / after | Last observed row before / after | Keyboard state |
| --- | --- | --- | --- |
| Control | y410 / y410 | y788–830 / y788–830 | absent / absent |
| Show | y410 / y410 | y788–830 / y788–830 | absent / present |
| Hide | y≈135 / y≈135 | y513–555 / y513–555 | present / absent |

Only rows1,2,3,10 are observed in tall runs. Their maximum coordinate delta is0; source delta is0. Initial keyboard presence moves the first row275pt above the no-keyboard control. The did-show notification rectangle is `(0,573,402,301)`, leaving observed row10's bottom830 at257pt below the keyboard top. XCUI keyboard.frame is instead `(0,590,402,226)`; these quantities must not be substituted. The show-after screenshot visibly confirms keyboard occlusion. No optical pixel-equivalence or transient-motion claim follows.

Source `(161,406,80,48)`, portrait402×874pt, scale3, safe area LTRB `(0,62,0,34)`, Dynamic Type L, Reduce Motion false are captured at menu trigger after layout. Appearance follows the system; screenshots are dark, no appearance setting was changed. The loaded event precedes final layout and legitimately has zero source/safe-area values; it is not the environment anchor. The hide scene keeps the text field first responder while the menu is initially presented, as directly recorded at menuTriggered; this is not a Flutter focus guarantee.

The three-row exploratory run also has delta0 for its three rows but already fits above the keyboard. It is retained as a control, not accepted as the discriminator. Ten rows force overlap in show and produce different initial placement in hide. There are3 passing XCTest method executions,9 scene executions,18 before/after snapshots/screenshots and33 observed row-pair comparisons in total.

Selected screenshots: [show before](device4/show-before.png), [show after](device4/show-after.png), [hide before](device4/hide-before.png), [hide after](device4/hide-after.png). Full own data are under device3/4/5; repeated endpoint arithmetic is in each analysis.json.

## Capture and validity

Sources/MenuKeyboard.swift is a plain public UIKit scene. App.swift selects a plain UIWindow before the normal recording-window branch and returns before Recorder/LabCapture. UITextField first-responder commands are delayed6s from public menuActionTriggered so a settled before snapshot can complete first. Public keyboard notifications record their end frame, focus and monotonic time. No private APIs, class/layer dumps, phone settings changes, simulators or macOS GUI were used by this protocol.

XCTest brackets every sequence of XCUI geometry queries with CACurrentMediaTime start/end on the same physical device as app events. Analyzer requires an accepted responder command, real keyboard visibility transition, completed did-show/did-hide notification, `before.end < commandBegin`, and `keyboardDid < after.start`. Both tall runs have at least3.33s before-command and0.84s post-completion margin. Endpoint samples do not establish continuous existence or intermediate trajectories.

The analyzer was exercised through its real CLI. A copied show snapshot whose end is moved to commandBegin+0.1s is rejected with exit2 and no analysis output (`negative-control.json`). Duplicate/missing named attachments, mismatched phases, nonfinite frames and refused responder commands also fail the boundary checks; only the corrupted-interval path was exercised as a separate negative run.

Fresh independent how investigation recomputed all timing margins, zero deltas,257 and−275 from the saved public JSON. It did not run the phone or inspect pixels. Parent inspected device3 and device4 selected screenshots. `how-evidence.md` distinguishes direct observations, inferred initial-placement behavior and unknowns. This is repeated evidence on one device/environment, not a cross-device policy guarantee.

## Execution and review

- run1 stops before compilation/tests with Xcode destination exit70: device needs unlock to enable development services. Lock is released. No settings were changed.
- build2 succeeds for generic iOS, including app and UITest compilation. Parent fixed absent-element frame reads and added start/end snapshot windows before the first successful device run.
- A read-only lockState check then reports passcodeRequired=false. device3 builds/tests/exports/copies successfully for three short-menu modes.
- device4 and device5 build/test/export/copy successfully with ten rows. Each command receipt has seven exit0 operations. Every test app is terminated by its XCTest flow and every atomic device lock is released in the runner context. No heavy jobs ran in parallel.
- Xcode27.1 / build27A9275; native scene records iOS27.0.1. Full raw Xcode logs/bundles remain under `~/morph-re/measurements/native-ime-20261018/`. Only our named geometry JSON/events/screenshots and command receipts enter the repo. Early and final probe hashes are recorded separately; final tall runs use the final native Swift source. Later analysis-script changes do not modify the compiled probe.
- Final root Flutter analyzer0 issues (Flutter3.47.7 stable). Repository shader offline gate exits0 with the actual SDK bin path before the mise shim. It is a compile/static-model tool check, not a device performance result. No shaders changed; no Pixel parity/frame-time/energy claim is made.
- Python runner/parser compile; invalid run name rejects before creating a capture. Analyzer runs on all three saved captures; repeated own attachments are imported only when identical, and the invalid-phase control exits2.
- Deslop: parent removed an unused analyzer import, made duplicate-attachment refusal explicit, and ensures runner export/copy errors fail the final status. No wrapper, library API or dependency was added.
- Comment Sicko found0 actionable comments/suppressions,0 deletions/restorations/encoding offers, and0 open comment work. Final five-file hashes and one requested follow-up are in comment-review.md; no rejected review rerun. A fresh how explainer independently checked the evidence arithmetic.

The scripts are standard-library Python plus the existing project device-lock helper. No packages were installed. Root/example test suites were not rerun because no Dart implementation or test changed. Previous444 example passes and viewport replay/pixel evidence belong to the preceding viewport report. Current core hashes and initial owner WIP bytes are verified separately.

## Repeat

From the repository root, use a new append-only run name and an unlocked iPhone:

```sh
python3 tool/audit/foundation-p2-2026-10-18/native-ime/run.py device6 --rows 10
python3 tool/audit/foundation-p2-2026-10-18/native-ime/analyze.py \
  tool/audit/foundation-p2-2026-10-18/native-ime/device6 \
  --collect "$HOME/morph-re/measurements/native-ime-20261018/device6/attachments"
```

`--rows 3` repeats the short control. `--build-only` uses a generic iOS destination and does not acquire or touch the phone. Output names cannot overwrite an existing run. Source/test/run receipts and saved attachments remain tied by artifacts.json.

## Consequence and remaining scope

The older context-menu passport sentence was morph implementation documentation, not direct native IME evidence. Its provenance is now explicit; the new observation is scoped to UIButton.menu. No automatic active-IME retargeting is justified by these endpoints. The current Dart prototype already retains an old shown popup's placement/model after endpoint retirement, so unchanged native rows alone do not decide whether that conservative retirement should be removed.

Next verify native selection and close/landing after IME plus editor-focus behavior, then design placement-snapshot versus source-validity ownership before changing the prototype. Real source movement, hidden hold/reservation, arbitrary keyboard/display shapes, context-menu preview/trigger, transient/body optics, native multiwindow and Flutter parity remain open. P2, P1/P3 and main migration gates are unchanged. No tuning/performance/release claim is made.
