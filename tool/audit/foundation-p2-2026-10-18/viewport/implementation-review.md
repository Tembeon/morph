# Viewport implementation correctness and deslop review

2026-10-18. Independent same-model read-only verifier. Base HEAD `3095d2fe20308c17bc97ed8bcac7af541534b76f`; reviewed only the task changes in `example/lib/proto/menu_route_probe.dart` and `example/test/proto/menu_source_geometry_test.dart`, their immediate callers, production placement/relayout, design panel, judge and existing host logs. Applied local deslop/pstack-runtime instructions and repository rules. No application edits, agents or test jobs were started by this verifier. Owner WIP is excluded. This report is the verifier's sole write.

Initial reviewed SHA-256:

- implementation: `262bcbb8074cf8273a105d3409a3a3673c3d6f3ad30ec96939f4dcb3ed11b38a`
- tests: `dacfb396bd6da0d491f92f0859208cf115e95bd99876fb1966d238a3a82f20f8`

## Finding requiring resolution

**P2 — Invalid active admission is observed but does not retire the endpoint.** In `_MenuSession.admitGeometry`, `current == null` returns before the existing active-change retirement branch. `_prepare` invokes this method before returning an already shown route. A concrete sequence is: fully open and settle the popup; synchronously change the test view to an invalid viewport (for example, IME covers the source or leaves less than the fixed menu width); call `sourceState.open()` before pumping; it measures the invalid availability and throws, but leaves the old endpoint attached; restore the metrics before the next paint/tick/land. The restored geometry can then agree, allowing the old popup to hand back. The valid-but-changed case already calls `loseGeometry`, so these two observations have different sticky-loss semantics. This is a static control-flow reproduction, not a test run by this verifier.

Judge acceptance #5 explicitly includes changed **or invalid** observed active availability. For a previously admitted active session, a null measurement should retire the exact old endpoint; unprepared and strictly idle sessions should retain conservative refusal/recapture. Add a regression with the invalid observation and restoration before the next pump so the ordinary paint/clock fences cannot mask it. Preserve persistent-callback rejection before any callbacks/mutations. This discrepancy already existed for invalid geometric measurements; the new physical viewport rejection makes it a direct current feature path.

## Checked and accepted

- Physical authority is the attachment's `presentationView`, with the existing source/presentation view identity and actual navigator/overlay attachment gates. Source-local MediaQuery data cannot override the physical keyboard.
- DPR is validated positive/finite; physical dimensions and each nonnegative finite edge are validated; per-edge `max(viewPadding, viewInsets)` is divided by DPR once. Safe and keyboard values are not added.
- Positive uniform overlay-to-view mapping is validated before inverse projection. The safe rectangle is checked before `Rect.fromPoints`; unsupported reflection/rotation/shear/perspective cannot become an accepted AABB. Derived coordinates, extents and padding deltas are checked for finite overflow. Intersection uses actual overlay bounds, avoiding double subtraction for an already safe smaller root.
- Fixed minimum width and row-plus-two-insets height come from the actual model tuning. They must be finite, positive and fit; no menu squeezing is introduced. Mapped button containment is complete and inclusive, rather than overlap/center-only.
- `available` is one immutable snapshot fact; padding is derived. Effective rectangle equality is exact, while the original source/overlay identity and source map/shape equality remain. Raw DPR/physical metrics/global-map equality does not add spurious retirement.
- Only existing strict idle admission invokes relayout, installing the complete snapshot before readiness. Post-readiness attachment/model/clock/fresh-geometry checks prevent stale pushes. Existing readiness reentry and persistent-phase gates remain intact.
- Existing `checkGeometry` routes changed/invalid active observations through exact-session retirement; hidden preparation, reservation, shown popup and source-tail behavior retain their old owners and time. Shown popup continues from its pinned model, while hand-back to a retired source is prohibited. No observer or additional ticker is introduced.
- Existing root movement test covers equal-effective motion and preserved input/hand-back. The already-safe smaller-root test changes raw IME values while its effective rectangle stays equal. New negative root movement covers changed availability despite equal source-local mapping.
- The expanded log records 58 focused passing cases, including both 64-frame zero-difference contour oracles, but these are parent-run logs, not verifier execution. Their scope is host Flutter behavior only.

## Remaining acceptance/evidence gaps

1. The test called “local removed or fabricated MediaQuery” supplies only a fabricated `MediaQueryData`; it does not exercise an actual `MediaQuery.removePadding/removeViewInsets/removeViewPadding` scope. Rename the case accurately or add the explicit consumed/removed scope requested by the judge. The implementation itself reads no MediaQuery.
2. The selected design intentionally does not observe a settled retained popup immediately on physical metric changes. Add an explicit frozen-MediaQuery/retained-paint test proving that no proactive retirement occurs until a subsequent input/clock/paint/hand-back observation, and describe this limitation in the stage document. The current shown-popup case pops after the change and therefore exercises an eventual close-clock observation, not this negative guarantee.
3. Update historical current-contract wording in `docs/architecture/menu-source-geometry.md` when integrating this stage: it currently says placement padding is zero and root-global motion unconditionally preserves geometry. Keep the previous stage's historical evidence clear. No production/P3, native active IME following, floating-keyboard, nonrectangular display-feature, device or performance claim is supported by these host results.

## Deslop result

No substantive deletion is justified in the new projection/snapshot code. The pure projection helper, single `available` field and derived padding avoid duplicate mutable facts, public knobs, observers and lifecycle wrappers. Existing defensive finite checks cover different arithmetic stages rather than narrating the same condition. No speculative fallback or unrelated redesign is recommended. The behavioral issue above needs a narrow fix with a regression, not an abstraction layer.


## Follow-up resolution

Final read-only inspection on 2026-10-18:

- implementation SHA-256: `178da40713d9990863d33dbf5e368c05b602a0ba7c5e4fcf8bb8908fed15386a`
- tests SHA-256: `8a31454dc3fcc1c5b1760a1c35a74429a37526d3fe13a81ecd449f3da6b097d0`

**P2 resolved.** A null measurement now retires an already admitted, non-idle endpoint before refusal. Unprepared and strictly idle sessions still refuse without losing their reusable endpoint. Persistent-phase rejection remains before this logic. The new regression restores metrics before any pump, so the invalid observation cannot be masked by a later observation. `invalid-admission-before.log` records the pre-fix nonnull hand-back failure.

The parent identified and fixed the analogous post-readiness path: readiness can reentrantly open a nested route and then alter metrics. A final null/mismatching observation now retires the captured active session after the original model/clock/attachment checks. Callback metric changes without an active route remain idle and recapturable. The regression in `readiness-before.log` records a real nonnull hand-back before the fix; its final revision conditionally pops only an active, nonclosing nested route, allowing legitimate hidden-preparation retirement to complete without accidentally popping the base route.

The actual `MediaQuery.removeViewInsets` case asserts descendant insets are zero while placement still respects the physical keyboard. The settled frozen-MediaQuery case now explicitly proves the chosen observation boundary: metrics plus a pump leave the exact old route and frame counter untouched; the first subsequent gesture observes loss and is rejected by the existing retirement barrier; after deferred retirement, a second gesture can select within the independently retained old popup, with no hand-back. `frozen-input-tests.log` records its focused pass.

`final62-tests.log` was read after completion and records **62 passing focused cases**, including the original and inset independent contours at 64 zero-difference frames each. These jobs were run by the parent, not by this verifier. The new `docs/architecture/menu-viewport.md` documents observation-only invalidation, retained old placement and native/P3 limits. Its provisional test count and the historical source-geometry document wording still need final documentation integration by the parent; they are not code correctness blockers.

No remaining P2 implementation finding in the reviewed source/test snapshot. The narrow fixes preserve the existing ownership and time model without adding observers, caches or wrappers. Deslop outcome remains: no justified substantive deletion and no unrelated cleanup. This verdict does not attest to full-suite/analyzer results not yet reviewed, native behavior, device output or performance.
