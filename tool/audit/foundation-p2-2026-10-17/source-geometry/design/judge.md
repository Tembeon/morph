# Fresh architecture judgment

Base `67afab10`, 2026-10-17. Read-only same-model judgment against the actual source/session, transfer adapter and `MorphMenuMotion.relayout`. This is a reduced panel: A is parent-authored after its runner dropped out; B is a parent reconstruction of an independent completed report whose original file disappeared. These are two structural alternatives, not two completed independent candidate files or multi-model agreement.

## Verdict

Choose A: SDK Stack/Positioned source, one immutable presentation snapshot per session, admission-time measurement, inverse source painting, and finite source endpoint retirement. B's custom render host is currently more surface than the demonstrated failures justify. Graft its explicit render-space and retained-layer scrutiny into A's acceptance tests. No human checkpoint is needed.

| Criterion, 0–3 | A | B | Reason |
|---|---:|---:|---|
| Coordinate/input/paint correctness | 3 | 3 | Both require exact supported transforms and separately project global input. Neither may accept a rotated AABB as the shape. |
| Public SDK integration | 3 | 2 | A preserves SDK layout, hit testing and semantics; B assumes additional render ownership. |
| Whole model/time/lease continuity | 3 | 3 | Both keep the active model unchanged and detach the endpoint on disagreement. |
| Finite invalid/active geometry lifetime | 2 | 2 | Both need observation fences and retained-paint regressions; neither establishes native active geometry policy. |
| Minimum caller/internal surface | 3 | 2 | Same small measured constructor, but A needs no new render protocol. |
| Total | 14 | 12 | Conditional on the guards and acceptance cases below. |

## Chosen boundary

Caller: `ProbeMenuSource.measured(button: localButton, sourceHeight: ..., sourceRadius: ..., onMotionReady: configureMotion, menuBuilder: ...)`. Keep the existing fixed constructor and replay semantics unchanged. The measured constructor has no caller-supplied bounds, matrix, factory, neighbors or controller. Fixed remains an explicit laboratory control rather than a second product geometry API.

Use these responsibilities; exact private names may follow surrounding style:

```dart
_MenuGeometry? _readGeometry(_MenuSession session);
bool _admitGeometry(_MenuSession session);
bool _sourceGeometryAgrees(_MenuSession session);
void _loseSourceGeometry(_MenuSession session);
Offset? _overlayPosition(PointerEvent event);
```

The immutable `_MenuGeometry` owns source-to-overlay transform/inverse, overlay-local button, actual overlay size, and scaled source height/radius. Store the source and pinned overlay render identities needed to validate it. Session owns the single accepted snapshot. Do not separately cache equivalent geometry in State, route and painter.

`_readGeometry` validates current session/affinity, active attached laid-out render boxes, finite nonzero size, and an exact positive uniform 2D scale plus translation. Validate the overlay-to-global transform independently. Root movement in global space does not itself change overlay-local model geometry. Reject singular, reflected, anisotropic, rotated, sheared, perspective and nonfinite transforms, cross-View, pre-layout and Offstage sources. Conservative full-button containment is an admission rule; it does not establish arbitrary clipping/opacity/occlusion detection. Insets and placement padding are explicitly zero in this increment.

Input uses the inverse of the live overlay-to-global transform on the original `event.position`; pass `event.copyWith(position: overlayPosition)` only to `transfer.pointer`. Keep the original event for timestamp calibration and observers. `PointerEvent.transformed` alone is insufficient because the adapter reads `position`, not `localPosition`. Recheck session/model/lease after any callback and before continuing the command, as existing input ownership already does.

Source paint maps the carried model composite back through overlay-to-source; do not scale the popup's text/menu metrics. The ordinary child button, its hit test and semantics stay in source-local coordinates under the same SDK Stack/Positioned layout.

## Initial model and safe admission

An unobserved nominal idle model is acceptable inside this prototype. It must not be presented as prepared root geometry: document pre-admission frame/getter space, draw its resting source locally, and do not publish `onMotionReady` or measured samples until a valid snapshot is installed. Global pointer routing sees unrelated events too; an unprepared session must not emit a nominal root-space sample merely because it ignored such an event.

Relayout is permitted only when all of these hold: source lease owns the model; no active route, reservation or pointer; `!isPresented`, `!isArming`, `!isOpenPending`, and `isSettled`. `isSettled` alone also describes a fully open menu. The model's implementation only rejects non-idle phases; it does not protect an idle held press or a scheduled opening for the host.

Keep a session reference to its existing motion for idle relayout, with transfer remaining the owner of sampling/commands. Install geometry before invoking `onMotionReady`, outside paint/layout/tree-lock work, and invoke it once per actual model. `_newMotion` also runs from route disposal: do not put that user callback there. A replacement nominal model must become ready at its next safe admission. After the callback, recheck current session, model identity, geometry agreement and command eligibility; a callback may synchronously rebuild, detach or attempt to open. A small readiness/reentrancy guard may decline or throw for recursive admission rather than continuing on half-published state. No callback from a retired token may configure the new model.

## Geometry loss and phase safety

Observe the live source snapshot at admission, source-owned frame sampling, eligible input, handback, and source painting. Source painting checks geometry before the owner filter, including while the popup owns the model. A fully closed resting model may refresh geometry in place. Any other mismatch seals that session's source endpoint immediately and reuses affinity detach/retirement behavior. Shown popup keeps the original model/content/clock/snapshot; hidden preparation/reservation retires on its old owner; an already source-owned tail is abandoned. Never reset/rebase an active model or spawn an invisible retirement ticker.

Do not stop the old route's own animation merely because its source was detached. A route frame may detect and seal the source endpoint, then continue sampling its existing lease. A source frame detecting loss stops source authority. `land` must validate the accepted snapshot before transfer. A later same-frame layout change can still invalidate a transfer-time success: paint suppresses stale carried geometry and retires the endpoint; do not erase a recorded handback or pretend it never happened.

Loss discovered in paint/layout or a model callback may clear the current capability and dispose/pause its source clock synchronously, as existing detach does. Defer Navigator mutation, notifier publication, replacement session construction/user callbacks and `setState` to the existing safe microtask boundary. Capture the losing token, clear current before detach, and recreate only if still mounted/active and still awaiting that replacement. A stale event declines; it does not silently operate a fresh token. An explicit later `open` may acquire a fresh valid session. There is no queued-open promise.

This is observation-based snapshot invalidation, not continuous active following. An idle popup with retained source paint and no input may not notice geometry change until the next observation. State that limit. During a source-owned tail, frame notifications must invalidate the source paint despite ancestor Transform/RepaintBoundary retention. If the existing painter cannot provide that guarantee, narrow or redesign this boundary before claiming tail safety.

## Acceptance and scrap

Prove offset/scaled source and scaled root pointer/first-frame placement against actual root-overlay geometry; idle recapture after scrolling; carried handback paint through inverse transform; and ordinary fixed recordings unchanged. Exercise invalid geometry before any push, foreign/retired callbacks, readiness callback reentry, root global transform changes, hidden press, held reservation, active shown and source-owned-tail loss. Include the same-frame layout-after-land and ancestor Transform/RepaintBoundary cases. Invalid explicit open throws before pushing; raw/semantic activation declines. Verify model identity/time/lease continuity and finite clocks/route retirement, not only screenshots.

Scrap A if source/overlay rectangles need multiple independently synchronized owners, a general render framework leaks into callers, repeated hidden timers compensate for missing invalidation, or the same reentrancy workaround appears at several boundaries. No evidence here justifies active animation retuning, model transfer edits or claiming native IME/rotation/scroll-follow policy. Those remain separate measured work.
