# Viewport arena decision

2026-10-18. Fresh same-model judge of two independent same-model design candidates. Read checklist, how, history, both candidates, repository rules and the relevant measurement, snapshot, admission and production placement code. No implementation edits or tests. Scores assess designs, not verified behavior.

| Rubric (0–3) | A: snapshot | B: observer |
| --- | ---: | ---: |
| Coordinate correctness | 3 | 3 |
| Lifecycle / ownership safety | 3 | 2 |
| Narrow API and honest active-change policy | 3 | 3 |
| Meaningful testability | 3 | 3 |
| Implementation simplicity | 3 | 1 |
| Total | **15 / 15** | **12 / 15** |

## Pick A

Both designs correctly project a view-global safe rectangle into actual overlay coordinates, intersect actual bounds, validate menu minimums and full button containment, and compare effective availability. A fits the authorized bounded admission increment with one new immutable snapshot fact. It keeps existing observation-based retirement and whole-model ownership intact.

B buys a real additional capability: a settled popup receives a metrics-triggered post-layout observation even when local MediaQuery is frozen. That capability is not required for correct admission and does not move the existing popup out of the keyboard. Its registration/disposal, queued frame and stale-token surface therefore lacks a present requirement. Defer the observer explicitly; do not claim A checks settled popups immediately when platform metrics change. This is a scope decision, not a claim that B cannot be implemented safely.

## Graft and red-flag screen

Graft B's explicit validation of the actual model tuning thresholds into A: minimum width and the computed row-height-plus-double-padding minimum must themselves be finite and positive. Graft its explicit account of a frozen/removed source-local MediaQuery and its retained settled-popup limitation into tests/documentation. These strengthen A without adding another lifecycle owner.

Keep one `available` rectangle in `_MenuGeometry`; derive padding from it and bounds. No duplicated mutable inset cache, raw-metrics generation, public viewport argument, observer or ticker. Production motion/transfer/clock APIs and fixed fixture behavior remain unchanged. B's pseudocode names `affinity.overlayView`, but the actual field is `presentationView`; implementation must use the real presentation authority. Neither candidate may interpret an AABB of unsupported transforms as valid geometry.

## Exact acceptance

1. Read the attachment's `presentationView` physical size, DPR, viewPadding and viewInsets. Validate finite positive dimensions/DPR and finite nonnegative edges. Use per-edge `max(viewPadding, viewInsets) / DPR` once. Build and validate a finite nonempty logical safe rectangle; reject inverted edges before intersection.
2. Inverse-project both corners through the validated positive-uniform overlay-to-view map. Validate the derived edges and extents, intersect actual overlay bounds, then validate again. Finite inputs alone are insufficient: subtraction/division, width/height and padding deltas may overflow. Require finite nonnegative padding, finite positive minimums, sufficient available width/height and complete inclusive source-button containment. Reject before readiness/push; do not squeeze measured menu metrics.
3. Extend snapshot agreement with exact effective-rectangle equality, not raw DPR/insets/global-map equality. The same effective availability survives unrelated metric changes. Root movement survives only when effective availability and the existing snapshot facts agree. Update the previous unconditional root-movement wording accordingly.
4. Pass derived padding only through the existing strict idle admission relayout. Install the complete snapshot before readiness, and preserve the post-callback fresh measurement plus model/token/attachment checks. Callback changes to metrics, transform or authority cannot open from the stale snapshot. Keep persistent-phase rejection before callbacks/relayout/push.
5. Changed or invalid effective availability observed while active uses existing sticky endpoint retirement. Hidden preparation, reopen reservation, source-owned tail and shown popup must be covered. Old callbacks never redirect into a fresh session; shown popup retains its pinned model/time and cannot hand back into the retired source. A retained popup may remain behind the keyboard. Do not add active retargeting, immediate settled observation, native IME parity or P3-completion claims.
6. Tests must cover all asymmetric edges and max-versus-sum; DPR 1/2; translated/scaled and already-safe smaller roots; partially off-view roots; frozen/removed local MediaQuery; exact-fit, narrow, short, empty, covered-source and finite-derived-overflow rejection; idle same-model recapture; readiness reentry; equal-effective raw-metric changes; changed/equal-effective root movement; shown/hidden/reserved/tail retirement. Preserve the existing same-frame paint fence and zero-inset replay/pixel results. Record host evidence as host evidence; no device/performance/native claim follows.

No blocking architecture issue remains for this bounded implementation. Observer-driven settled invalidation and native active keyboard behavior remain separate future decisions.
