# P2 viewport admission

2026-10-18, base `3095d2fe20308c17bc97ed8bcac7af541534b76f`, branch `wip/measured-liquid-glass`. Prototype only. Main/P2 gates remain open; no push, merge or device run.

## Result

Measured admission projects the actual presentation FlutterView's physical safe/IME rectangle through DPR and the current positive-uniform overlay-to-view map. Per-edge max avoids adding overlapping keyboard/home insets. Intersecting actual overlay bounds avoids subtracting already consumed space twice. Source-local MediaQuery cannot erase physical obstructions. Effective available rectangle belongs to the existing immutable geometry snapshot; padding is derived and passed only through the existing strict idle relayout gate.

The complete source button, fixed menu width and minimum row height must fit. Invalid/nonfinite/inverted geometry and finite-input inverse overflow decline before readiness/push. No menu tuning is squeezed or retargeted. Active changes use sticky endpoint retirement; old shown popup retains its model, content, time and placement, potentially behind the keyboard. Hidden preparation/reservation terminate; an abandoned source-owned tail stops without a hidden ticker. This remains observation-based invalidation, not immediate metrics notification or native IME following.

Caller contract: `docs/architecture/menu-viewport.md`. The previous geometry document now marks its zero padding as historical and qualifies root movement by equal effective availability.

## Architecture and reviews

`how.md` grounds source/overlay mapping, session authority, SDK physical/logical units and existing model placement minimums. `why-history.md` is a scoped source-control investigation, not a full external seven-category search. It establishes that zero padding was a deferred boundary and active retirement preserves whole-model time; it finds no native active-keyboard policy.

Two completed independent runs of the inherited model produced snapshot extension A and attachment-owned observer B. A fresh independent run of the same model scored A15/15 and B12/15. Parent read both complete candidates and agreed with A. B's explicit tuning minimum validation and frozen MediaQuery evidence were grafted. The observer's extra lifecycle buys prompt settled observation but does not improve placement; it is deferred. These are independent runs of one model, not multi-model evidence.

Independent implementation/deslop review found an active null-admission path that refused opening without permanently revoking landing. A real test reproduced hand-back after invalid metrics were restored before a pump. Parent identified the analogous post-readiness path after a callback reentrantly opens a nested popup; a second pre-fix test reproduced it. Both observations now retire the exact active endpoint, while pristine/idle invalid admission remains recapturable. Reviewer inspected the fixes and final62 log; no code finding remains. No substantive deslop deletion was justified, and no extra abstraction was introduced.

Comment Sicko found no actionable comment issue, kept one changed public contract and audited three existing suppression directives covering five diagnostic names. No new/broadened suppressions, constraint offers, encodings, comment deletions/restorations or rejected-review reruns. Parent checked unchanged suppression text after the final code/test revisions; those revisions add no comments. Documentation counts and historical wording were integrated after the review. The final test-only change replaces two zero constructors with the SDK's named constant; both affected cases were rerun.

## Experiments

- Initial test launch crashed in Flutter native-assets discovery before running tests because example lacked its own `.dart_tool/package_config.json` after project relocation. Local `flutter pub get --offline` restored generated configuration. Its incidental lockfile changes were reversed and the owner's original lock bytes verified against the initial hash. Tests use the resolved local stable-SDK package configuration. No tracked dependencies were changed.
- Configured workspace paths now pass through a symlink to `/Volumes/Dev/projects`. Sandbox startup rejects even read-only commands, regardless of cwd. Approved escalated commands operated on the canonical project path; no sandbox/security configuration was modified.
- Actual SDK is Flutter3.47.7 stable, framework `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart3.13.5, replacing previous3.47.2/3.13.2. Baseline326 prototype cases pass before the implementation. All emitted historical records also match the prior SDK's records exactly (`sdk-baseline-comparison.json`).
- The first exploratory keyboard size still allowed the original menu to fit and therefore did not distinguish implementations. The retained baseline uses bottom620: menu reaches266.00336 while the allowed bottom is254 (`viewport-before.log`). No existing tolerance was changed.
- First implementation53 cases and expanded58 cases pass. Expanded coverage includes all asymmetric sides/max-not-sum, DPR1/2, offset/scaled/already-safe root, narrow/min-height/exact-width/empty/covered-source rejection, inverse overflow, same-model idle recapture, callback changes and shown/hidden/reserved/tail retirement. Original same-frame retained-paint fence stays covered.
- `invalid-admission-before.log` and `readiness-before.log` retain the real pre-fix nonnull hand-back failures. Both pass in final62. `final-geometry-tests.log` contains60 pass/1 fail while the new frozen-popup test incorrectly expected the first authority-revoking gesture to select. The corrected test explicitly verifies that gesture is rejected, then a second gesture selects from the retained old popup (`frozen-input-tests.log`, final62 and full example). No production input behavior was changed for that expectation.
- Actual MediaQuery.removeViewInsets removes inherited keyboard data in the source context while physical placement remains correct. Frozen/settled source does not proactively retire after a metrics notification plus pump; the next input observes loss. These assertions preserve the chosen bounded guarantee.
- Analyzer initially reports two named-constant infos. Both are fixed without suppressions; final analyzer has zero issues.

All logs have trailing whitespace stripped. Flutter's auto-generated issue URL containing an environment dump was removed from the startup crash log. The crash description and report path remain; no issue was opened.

## Verification

Heavy jobs were serial, nice10, concurrency2, no-pub after configuration recovery.

- Final focused geometry/viewport:62 pass, including28 new cases.
- Full example after behavioral fixes:444 pass, including354 prototype cases and90 other example cases. Earlier full440 pass is preserved as an intermediate result.
- Only two named-constant replacements followed the final full suite; both affected tests pass again. Production/prototype source behavior did not change after the444 run.
- Root analyzer, including example:0 issues.
- All20 strict replay,8 async timing,6 fixed flat scene,3 contour,1 backdate control and1 original geometry scene records equal both the before-change baseline and prior SDK evidence. This includes2346 recorded inputs,40 routes/hand-backs,3167 async samples and459 original flat frames with0 changed pixels.
- The original measured tail retains64 zero-difference frames. The new inset scene independently compares another64 tail frames, including final rest, at sourceScale1.25, root402×874, DPR1, 8333µs host steps and1× time. Its reference model has explicit top100/bottom620 padding. These are same-renderer host comparisons, not shader/native pixel fidelity.

Root package tests are not rerun for this prototype-only change. Historical2362 pass/2 skip belong to `../../foundation-p2-2026-10-16/admission/report.md`, not this run. No standalone full prototype-directory suite was repeated after the changes;354 cases are included in the full example run. Production model/host/clock/timeline, prototype transfer/clock, exports, pubspecs and measured tuning remain unchanged. The owner bar work and pre-existing example lock update remain separate context for tests and are excluded from the commit.

## Remaining scope

No active menu follow/retarget, prompt settled-popup metric subscription, native IME/floating keyboard/nonrectangular display feature policy, arbitrary affine/3D transforms, full occlusion, native multiwindow/accessibility, device optics/frame time/energy, P1/P3 closure or release claim. Early push product acceptance, hidden Escape/Router/local locale/RTL and remaining menu/full-bar work stay in the plan. Main remains unchanged.

`summary.json` stores exact emitted records; `artifacts.json` binds final source, documents and audit evidence, excludes its own digest, and records the owner/core hashes. The local commit includes only this stage's explicit paths.
