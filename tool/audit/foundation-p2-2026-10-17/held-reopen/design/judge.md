# Held reopen synthesis

2026-10-17; base `1d4a595c0500fdb8e02d5958b5b3b76f6013bf7a`. Fresh read-only review of both independent inherited-model candidates, ground/how, actual route/session source, baseline harness and logs. No test or device execution by judge. This is not cross-model consensus.

## Decision

Use candidate A's navigation reservation before model ownership, with the actual-owner activation/dismissal discipline from B. The sufficient relationship is `(route, transfer, sequence)`. Do not add predecessor identity: before hand-back `activeRoute` already identifies the owner; afterward source owns it. Capturing `transfer` prevents the successor from acquiring a replacement model after forced predecessor removal. A predecessor object cannot provide that guard after the ownership history changes and would duplicate provenance that is not needed for navigation authority.

The two runners converged on this viable ownership shape. That convergence does not satisfy a demand for two distinct viable solutions, and we should not manufacture one. Both evaluated a structurally distinct immediate-acquire plus outgoing-paint retention alternative; reject it on existing evidence: `input-ownership/report.md` records fast-reopen hand-backs falling 4 to 2 despite equal geometry. The required total is 40 real hand-backs, not invented counters. Retaining old pixels cannot restore lost ownership boundaries; doing so would require extra transfers or simulated observations. Reservation separates SDK installation from existing ownership without creating another paint authority.

| Candidate, before synthesis | Physical hold | Model/time/hand-backs | Modal/reentry | Content/focus | Minimal interface | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A: route, transfer, sequence | 3 | 3 | 2 | 2 | 3 | 13/15 |
| B: route, predecessor, sequence | 3 | 2 | 2 | 2 | 3 | 12/15 |

Scores assess designs, not proved implementation. Modal score needs the exact Back/semantic/cover rules below. Content score remains limited by actual first-reveal paint/focus evidence.

## Usage and state

App callers keep the same `ProbeMenuSource(menuBuilder: ...)`. A pre-handback genuine source down installs one hidden successor, while old editor/model/clock/lease continue unchanged. If first-zero arrives before hold, normal hand-back proceeds and source samples the same model. At measured opening, the installed successor acquires from whichever owner is real at that moment and mounts one fresh content tree. No second push occurs at hold expiry.

One private nullable immutable relation is sufficient:

```dart
final class _MenuReservation {
  _MenuReservation(this.route, this.transfer, this.sequence);
  final ProbeMenuRoute route;
  final ProbeMenuTransfer transfer;
  final _PointerSequence sequence;
}
```

Keep `activeRoute` meaning model-owning route. Register the reserved route in the existing `_routes` disposal set but do not acquire, resume its clock, reveal, mount builder/policy or request focus in its `didPush`. Its projection starts at zero. No reserved bool, extra lifecycle enum, retained optical frame, second sampler or successor model.

Source construction/navigation remains in source State; admission, promotion, retirement and exact sequence exceptions stay in session. A private return value from `handlePointer` can prove the genuine down was accepted. Merely seeing `_pointer` non-null is not enough if a model operation rejected or synchronously revoked the event. Publish the relation before push callbacks, validate afterward, roll back by exact identity. Do not expose a second input protocol.

## Required authority rules

- Only a genuine accepted source down during `closingContent` may create this new reservation path. Cold early preparation keeps its existing path. `closingPreparation`, unrelated covers and second pointers stay sealed.
- Continue only the captured held sequence, captured unchanged transfer, installed/current reservation and full source modal ancestry with the existing exact **active** root-page exception. This is continuation, not new global-down acquisition.
- Own successor installation must not revoke its captured sequence. Any unrelated root or nested cover revokes the held sequence on the actual owner. Reservation route callbacks must participate even though it is not `activeRoute`.
- A passive cover preserves already committed tap-open work. With no remaining held sequence, use existing `isOpenPending`/domain facts to keep the installed reservation until measured opening, even behind the cover; no new input, semantic or focus authority follows. Do not equate passive covering with explicit close.
- When transfer opens, consume the exact valid reservation and use existing owner-clock transfer/acquire, then reveal. Recheck transfer/route/source lifetime around callback-producing work. Old sampler must stop publication after lease change.
- Source clock callbacks need the same post-`syncInputPhase` owner/lifetime checks as route callbacks when promotion can happen there. Preserve canonical timing and never publish against disposed frames or a replacement model.

## Explicit activation and Back

Use B's safer actual-owner command order for semantics. Validate source plus exact current hidden reservation; revoke its physical sequence; revalidate after observers; issue explicit `open` using **actual owner lease and clock**; then promote through normal `syncInputPhase`. Do not acquire the reservation first merely to satisfy old `activate(route)` ownership assumptions. Do not retire it in the middle of the enclosing explicit activation when pointer cancellation fires. Removed source roots, new nested covers, removed successors and changed transfers abort the operation.

SDK Back on hidden reservation is an explicit close/cancel-opening request, matching existing hidden preparation behavior. It must cancel held input **and committed pending opening** through the actual owner clock/lease, emit normal command observations, revalidate, then retire only this reservation. It must not call owned-route `_beginClosing` with the successor's unowned lease. Passive cover does not issue this close and therefore preserves committed release work. This distinction resolves A's ambiguity; B's explicit actual-owner Back branch supplies the graft.

If model opening wins before Back resolves, promote and consult the fresh presentation's ordinary first-mount/async policy. A Back request begun while hidden cannot bypass a successor PopScope that has since become applicable. Never reuse predecessor policy, LocalHistory or stale permission. Hidden successor itself exposes no dismiss semantics; its real SDK Back path must remain finite rather than fail `_isLive` forever.

## Retirement and content

Clear the exact reservation before remove/dispose callbacks. Never-owning successor removal does not reset the live transfer. Use identity `removeRoute`, never a possibly wrong-current `pop`. Retire on true cancel/no pending work, source loss, forced successor removal or invalidated captured transfer. A forfeited hold may retain its inert reservation until the genuine terminal event because closing `isArming` is not a hold-intent signal. Predecessor first-zero hand-back preserves the relation; forced predecessor removal/reset invalidates its transfer and retires it.

Until actual opening or original first-zero, predecessor keeps its original painter/Flow lease and tree. Promotion must replace paint content in the same rendering turn. New tree is fresh; old route-local State is not preserved across presentations. External controller data may persist. Within one presentation retain stable child/editor/Focus/PopScope identity across frames/themes/covers and closing. Hidden reservation captures no focus; reveal grants focus through SDK route behavior only when current. First-mount policy must precede first successor dismissal.

The baseline physical check is a genuine behavioral red: accepted down followed by SDK `PointerCancelEvent`, absent move/up. The baseline optical check stops earlier at `activeRoute != first`; that assertion assumes immediate ownership and is incompatible with this chosen reservation. It has **not yet measured missing old pixels**. Update that new harness to discover the installed successor through a NavigatorObserver/public route history while retaining `activeRoute == first` until promotion; keep the real pixel/editor/focus assertions. This is correcting an uncommitted architectural assumption, not relaxing motion or optical tolerances.

## Verification gates and scrap boundary

Before claiming success: real 60/120 Hz down/move/up before and after hand-back; one selected action; exact whole-model/time sample comparison; all previous 40 route/hand-back totals and flat-scene outputs unchanged. Add cancel/slop/up/committed tap then cover, explicit Back cancel pending, semantic takeover, nested/root/source-removal races, forced old/new removal, reentrant observations and finite zero-ticker teardown. Capture old colored content through pre-reveal and successor first revealed paint; verify fresh State/build counts, focus transitions and fresh policy ownership.

The design is acceptable for implementation without human checkpoint. If satisfying those gates requires outgoing paint borrowing, fake hand-backs, retiming, repeated mutable flags or resurrecting a popped predecessor, scrap rather than bolt those changes on. Native held-reopen identity, VoiceOver/TalkBack/IME and device fidelity remain unproved.
