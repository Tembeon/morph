# Implementation and deslop review

Read-only review of the current diff against `67afab10`: `example/lib/proto/menu_route_probe.dart` and the new `example/test/proto/menu_source_geometry_test.dart`. No tests, devices or GUI were run by this reviewer. The parent's corrected 28-case run was still in progress at assignment; this report does not certify its result.

## Findings to resolve

1. **Unsupported singular transforms can pass the new admission guard.** At the reviewed `_UniformMap.read` lines 514–540, `Matrix4.diagonal3Values(1e-10, 0, 1)` passes: x is positive, and the missing y scale differs from the fabricated expected scale by less than absolute `1e-8`. This produces an invented positive-height rectangle/inverse for an actually singular map. The same absolute comparison also admits large relative anisotropy for tiny scales. Reject an actual nonpositive y scale and compare x/y relative to scale, or use exact support checks appropriate to these SDK-generated affine matrices. Add this matrix to the existing unsupported-transform regression table; the current singular case covers only x=y=0. This is a coordinate-admission correctness fix, not a request for broader transform support.

2. **Validate the scaled metrics, not only the local metrics.** At reviewed lines 226–238, finite local sourceHeight/sourceRadius can overflow when multiplied by a valid source scale. For example a finite near-max sourceHeight with ordinary scale 1.25 admits an infinite height into `MorphMenuMotion.relayout`, even though the ordinary button and overlay remain valid. Compute the scaled values once, reject nonfinite results, then put those same validated values in the snapshot. A small measured-constructor regression should assert rejection before callback/model input/push.

Both findings were sent directly to the parent. They are bounded guard corrections; they do not invalidate the chosen architecture.

## Ownership, reentry and phase assessment

The core implementation follows the selected design. `_canRelayout` checks source ownership, empty routes, absent route/reservation/pointer, closed/unarmed/no-pending state and full settlement. The motion is retained rather than rebuilt for idle movement. The new source painter checks geometry before owner filtering and maps the entire carried contour back through the inverse; popup menu metrics remain in overlay logical coordinates.

Readiness is installed only in `admitGeometry`; `_newMotion` clears geometry/readiness without invoking the user callback. Thus forced route disposal does not introduce a new callback under the tree lock. Marking readiness before the callback allows nested `open` to share the existing prepared model; the outer call subsequently uses the route created by the nested call. Model identity, source clock, attachment and geometry are rechecked after the callback. I found no concrete unsafe redirection to a fresh token in that path. Callback exceptions and callers directly mutating the exposed laboratory model are not established recovery contracts.

Loss clears State's current capability synchronously and uses a guarded microtask to construct a replacement and publish `setState`; old-session detach clears its captured State closures and defers observable retirement. Replacement is currently queued before old retirement. That does not itself transfer old authority: callbacks retain old session/model references, old cancellation runs on the actual old owner, and the new session has a separate clock and model. Do not reverse or otherwise restructure this ordering merely for tidiness without a demonstrated problem.

A route frame observes source loss and still samples its own lease; a source frame stops. Handback validates geometry, and the source paint fence covers layout movement after a transfer-time check. The included same-frame regression deliberately preserves the recorded handback while abandoning the subsequently invalid tail. This matches the chosen observation-based contract rather than continuous following.

Global input is projected using the pinned overlay's live inverse. The original event remains the timestamp/observer input; only `transfer.pointer` receives the copied overlay position. Unprepared measured sessions skip global-router samples. Ignoring `checkGeometry`'s return in route sampling and input is intentional for detached shown popup independence; changing this mechanically to an early return would stop or disable its old owner.

## Simplification assessment and evidence limits

No substantive deletion is justified by this diff. The repeated attachment/semantic checks around `admitGeometry` protect a user callback boundary and should remain. The immutable geometry record and small uniform-map helper hide coordinate knowledge without a second public protocol. The fixed constructor remains the explicit recording control.

The tests inspect actual pointer hit behavior, root scaling and placement, source scaling without menu-metric scaling, semantic admission, idle scrolling/recapture, invalid geometry, readiness reentry, old popup independence, hidden and reserved attempts, lost tails and retained-paint handback parity. This is stronger than mirroring helpers. Final passing counts, analyzer results, fixed replay equality and pixel counts must come from the parent's completed verification. This host review establishes neither native active-geometry policy nor IME/safe-area integration; zero placement padding and observation-based invalidation remain deliberate limits.

## Final fix disposition

Re-read the parent's subsequent implementation and added regression cases. Both guard findings are resolved in source: supported matrix coefficients now match the finite positive uniform 2D form exactly, while tolerance remains only in snapshot agreement; scaled height/radius products are checked for finiteness before snapshot publication. Tiny singular/shear and overflowing-height cases are present in the test file.

The additional persistent-callback admission fence correctly rejects new interaction admission during build/layout/paint even when render boxes already have valid sizes. It leaves observation/retirement available in painting and does not invoke readiness from `_newMotion`. The later-layout regression exercises valid existing boxes rather than relying only on initial missing layout.

The revised painter retains the accepted model's existing container composite through the inverse whenever prepared geometry still agrees. It only uses a local resting container outline for an unprepared, lost, or moved fully resting endpoint. That resolves the accidental unconditional idle switch to a plain RRect, without changing route ownership or active model state. The independent contour/tail test remains meaningful; the parent's reported 64 frames with zero changed pixels have not been independently rerun by this reviewer.

No remaining actionable finding in the reviewed changes. No further structural cleanup is justified. The current 34-case targeted run and final broader checks remain the parent's verification responsibility; this disposition is source review, not a completed-test claim.
