# How: held source reopen before hand-back

Grounding on `1d4a595c0500fdb8e02d5958b5b3b76f6013bf7a`, 2026-10-17. Read-only investigation; no tests, GUI or device runs. Explanation is one inherited-model run, not independent empirical validation.

## Overview

The complete measured `MorphMenuMotion` already accepts a source press while closing and schedules a held reopening on its existing timeline. The missing boundary is the real SDK route push. The prototype waits until that held opening actually starts to push the replacement route. At that point Navigator has already recorded the down and cancels the physical pointer. It can therefore preserve geometry yet lose the move/up that should slide onto and select a menu row.

This is a host/session problem, not a missing spring, model clone, time adapter or native tuning. The bounded goal is one live physical sequence and one complete motion through a new real route. Content and focus require an explicit contract, but the agreed sketch already specifies fresh content on reopen: `docs/architecture/foundation-sketch.md:463`, “Содержимое строится заново.” Preserving `EditableTextState` identity across this new route would change that contract. Ordinary frames, themes and a covering route have stronger identity guarantees, which remain separate.

## Key concepts

- `_MenuSession.transfer`: one whole model, protected by a unique source/route lease. Geometry, kicks, content opacity, press response and delayed work are carried together.
- `_PointerSequence`: pointer/view identity plus authority. A valid lease is insufficient to acquire input. Source acquisition requires a real Listener hit and the complete modal/Navigator source chain; popup acquisition requires currentness.
- `ProbeMenuRoute`: real root PopupRoute. Logical pop finishes the old Future/currentness immediately; its reverse drawing and model lease may continue until hand-back. An already-popped route is not a fresh active route waiting to be revived.
- `_MenuStage`: lazy preparation vs shown content, each with a closing variant. Closing input/semantics are sealed synchronously while paint remains alive.
- `ProbeMenuTransfer.readyToHandBack`: existing first-zero boundary, `isClosing && progress <= 0`, independent of complete settling.

## How it works today

1. A pointer source opens an early hidden route on the first down, inside the leaf Listener before the ancestor Navigator Listener records that down. It builds no menu and requests no focus until the model opens. This avoids SDK-generated cancellation without ignoring actual PointerCancel events.
2. Logical pop runs `_beginClosing`, clears the session pointer, disables page/barrier input and semantic exposure, and continues the complete motion on the closing route clock. SDK reverse releases menu focus; the content State remains mounted while its closing route survives.
3. A new actual source down can hit through the closing route's live `_MenuHitGate`. `_sourceCanContinue` admits it only for a revealed closing route with the underlying source chain current. `_MenuSession.handlePointer` advances and applies it on the present owner's clock, checking transfer/lease/sequence/authority before and after commands.
4. `MorphMenuMotion.pointerDown` outside opening/pending accepts the button and schedules its existing `holdDuration` reaction. It does not instantly reverse on down. On hold, `_open(s)` reverses progress, opacity, radius and relevant channels continuously; on a quick up, `pointerUp` schedules the existing tap-open delay.
5. Source Listener currently calls `_prepare` only when `activeRoute == null`. A revealed closing route still owns the model, so no replacement is pushed on this down.
6. On the later hold deadline `_MenuSession.syncInputPhase` sees `transfer.isOpen` with a closing owner and calls `present`, bound to `_prepare`. `_prepare` pushes a new PopupRoute. `_MenuSession.acquire` maps the old clock to the new lease, pauses the old clock, and calls `_relinquish` to finish the old route.
7. SDK `NavigatorState._afterNavigation` invokes `_cancelActivePointers`. Its ancestor Listener has already recorded the new held down. The real cancellation reaches the model/global transport; late movement/release cannot be treated as a valid continued held selection. Existing `menu_route_input_test.dart` contains a real-binding negative control for precisely this delayed-push mechanism.

If the old route reaches hand-back before the hold deadline, the same whole model can move to the source first; the eventual hold still has a late-push hazard. A solution cannot be restricted to a convenient early closing timestamp.

## Viable boundary

Reserve the new SDK route at the real source-down boundary, before Navigator records the down, while treating route installation, model sampling ownership, optical content lifetime and activation authority as separate decisions. A reservation is not permission to reverse on down. It must preserve the existing model's timing and hand-back contract, remain inert through a cancelled/slop-forfeited hold, and reveal content/policy/focus only on the real measured opening.

Two structural shapes remain viable, but neither is proved here:

- Keep the closing route's model/paint ownership until actual reversal or the normal hand-back, while an early hidden successor reserves the SDK navigation boundary. The hidden successor must not accidentally revoke its own held sequence as an unrelated cover; the exception must be exact predecessor/successor/root identity, never a blanket noncurrent exemption. Source clock hand-back and reentrancy now span a reserved route, requiring explicit ownership logic.
- Transfer whole-model ownership on down to the reserved route, but retain the old optical/content tail until its original lifetime boundary, and explicitly preserve the counted hand-back semantics. This is easier to get geometrically right than lifecycle-right. The prior input-ownership experiment already rejected a naive version that immediately relinquished the old route and reduced replay hand-backs despite equal geometry.

A choice between these belongs to architect comparison. Do not add a generic overlay engine or clone channels to avoid facing the boundary. Do not resurrect a popped SDK history entry or bypass Navigator's pointer cancellation globally. Do not fake an up, suppress true cancel, force immediate `open`, or move delayed input to a fresh zero-time model.

## Content and focus contract

The existing sketch and command-mode tests say replacement creates new content (`menu_route_probe_test.dart` expects two builder calls over two presentations). Existing editor tests prove identity across ordinary motion and a cover, then disposal at close; they do not promise editor identity across reopen.

For this stage a coherent bounded contract is: old content remains available for its old closing optical lifetime; the replacement lazily builds one fresh tree at actual reveal; controllers explicitly owned outside the tree may retain their data; route-local State is new. New PopScope/async policy must be registered before its first close is admitted. Do not let an old registration, `LocalHistoryEntry`, pending dismissal answer or `_policyMount` become the successor's permission accidentally. SDK focus returns on logical close and is requested by the revealed successor; hidden reservation must not capture primary focus. This fresh-tree choice follows the plan, but the exact old-tail retention timing still needs to be stated and tested.

If the implementation instead preserves State across route replacement, that is a separate product change needing a deliberate reparenting/route-scope policy and new tests, not a free consequence of carrying motion. External FocusNode/controller identity alone does not prove StatefulWidget identity or proper route-local policy registration.

## Evidence and constraints

### Preserve

- The exact complete model, canonical time and existing source/route clock translation. At most one sampler/lease at every boundary.
- Real source hit/currentness checks, exact pointer/view identity, genuine terminal cancellation, reentrant transfer guards, no input through unrelated cover.
- Existing first-zero hand-back and source landing tail; all recorded replay route/hand-back counts, not geometry alone.
- Lazy zero-builder cancellation, one fresh builder per real replacement presentation, no per-frame content rebuild.
- Existing SDK sync/async/first-mount policy, route dismissal semantics, theme capture, source detach and semantics behavior.
- No production model, timeline, clock, constants, fixtures or tolerance changes for a host-only route problem.

### Change

The narrow stage is the source-down-to-successor reservation boundary and the session's definition of which exact route may acquire/retain that sequence. Route lifecycle and content ownership may need small explicit state to distinguish reserved successor from an unrelated cover. That state should derive from identities/stages where possible and have a finite cancellation/disposal path.

### Avoid

Changing every rapid tap reopen into early lease replacement without replay evidence; equating new-route existence with menu reveal; rebuilding the editor/policy on every stage transition; making focus globally sticky; identity exemptions for removed source roots; detached callbacks publishing another transfer's frame; duplicate rendering/sampling; treating held press as `isArming` while still closing (`MorphMenuMotion.isArming` explicitly requires idle).

### Risks requiring real tests

- Genuine held reopen before and after normal hand-back at 60/120 Hz, then move onto a row and up: one action, no binding cancel caused by our own reservation, continuous frame-by-frame reference motion.
- Cancel, early up, slop forfeiture and cover during the reservation: no accidental menu/content/focus, no zombie route or lost press relaxation.
- Old source removal, predecessor disposal, forced successor removal and callback-driven cover/removal at each ownership boundary: no wrong-current pop or stale publication.
- Immediate semantic activation/SDK Back while reserved; async first-mount policy; retained old semantic handlers and page hit surfaces remain stale/inert.
- Fresh editor State/build count, externally owned data, old/new PopScope registrations and focus transitions; no old tree disposed prematurely while still expected to draw.
- Historical 40 hand-backs and 459 flat-scene frames retain their meaning. New synthetic held traces do not establish native device parity.

## Recorded native fact vs product inference

`tool/ios_reference/spec/menu-button.md:89-94` records hold duration/slide selection generally and tap reopen during closing with velocity reversal. Lines 506-511 record continuous opacity reversal. Lines 535-541 describe first-zero host hand-back and complete kick settling in the current measured port.

The passport does not independently establish a held source reopen during visible closing with persistent UIKit content identity or assistive/native IME focus. Supporting that gesture by applying the existing measured model is a host integration expectation; choosing fresh content follows the agreed Flutter plan. This investigation neither retunes behavior nor claims new native evidence. Device/native accessibility/performance remain open.

## Where things live

- `example/lib/proto/menu_route_probe.dart`: source Listener, `_prepare`, `_MenuSession.handlePointer/acquire/land/syncInputPhase`, route stage/close/relinquish, content/policy/semantics.
- `example/lib/proto/menu_transfer_probe.dart`: whole-model lease and owner-clock offset.
- `example/lib/proto/motion_clock_probe.dart`: event timestamps and absolute resume anchors, kept unchanged.
- `lib/src/widgets/menu_motion.dart`: `pointerDown`, `pointerUp`, `_open`, `isArming`, `isSettled`; already supplies the held reversal.
- `example/test/proto/menu_route_input_test.dart`: real late-push cancellation negative control; normal hold, lazy content and genuine cancel.
- `example/test/proto/menu_route_probe_test.dart`: command reopen model continuity/fresh content and editor identity across covers.
- `docs/architecture/menu-input-ownership.md` and its audit: previous premature early-replacement rejection.
- Installed Flutter `widgets/navigator.dart`: `_afterNavigation`, `_cancelActivePointers`, leaf/ancestor down ordering. `widgets/routes.dart`: ModalScope reverse focus/currentness, route-local policy/tree ownership.
