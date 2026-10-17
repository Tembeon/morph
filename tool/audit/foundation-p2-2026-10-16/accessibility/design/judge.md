# Architecture synthesis: accessible popup lifetime

Readonly judge at base `65dce59f`; inspected both independent same-model candidates, grounding, actual route/session/Flow code and the eight corrected failing host tests. This is one model family, not multi-model consensus. No source edits, test jobs, GUI, device access or private Apple material.

## Decision

Use A's SDK semantic widgets and domain activation boundary. Graft B's insistence on separate semantic exposure versus action authority, plus a narrowly scoped Flow semantic invalidation repair. Reject the generic render admission gate. Replace the existing `_revealed` notifier and writable `closing` field with a single private presentation-stage notifier if implementation deletes both original writers; do not add a second semantic ChangeNotifier.

| Criterion (0–3) | A | B |
| --- | ---: | ---: |
| Accessible activation and dismissal parity | 3 | 3 |
| Semantic lifetime isolation | 3 | 3 |
| SDK ownership of PopScope and focus | 3 | 3 |
| Exact raw timing preservation | 3 | 3 |
| Smallest sufficient mechanism | 2 | 1 |
| Total | 14 | 13 |

A loses one mechanism point for manually notifying a six-transition derived signal; the subtraction below removes that weakness. B owns unnecessary render attachment/subscription/child-visitation machinery when SDK exclusion already expresses the actual lifetime. Its geometry caution is valuable, but the reproduced Flow transform failure justifies a Flow repair rather than reimplementing semantic admission. Neither candidate is rejected for lacking native screen-reader evidence; both correctly bound that claim.

## Caller contract

Keep one opening operation and optional source/menu naming strings on the probe. `open()` actually opens in both modes; raw early preparation is private. Defaults may remain explicitly prototype-labelled. Consumers use ordinary menu widgets and PopScope. No semantic controller, semantic lease, synthetic PointerEvent or second motion model is exposed.

## One lifecycle representation

A private enum can replace both `_revealed: ValueNotifier<bool>` and `bool closing`:

- `preparing`: hidden, not closing, content not yet mounted;
- `shown`: exposed, not closing, content mounted;
- `closingPreparation`: hidden, closing, content remains unmounted;
- `closingContent`: not exposed, closing, previously mounted content retained.

Derive public `closing` and private revealed/ever-mounted reads from this one value. There must be no independent writable closing/revealed values. Initial command mode is shown; pointer mode is preparing. `_reveal` transitions preparing to shown only. Successful logical `didPop` maps preparing to closingPreparation and shown to closingContent before any model-close callback can observe state. Veto leaves state unchanged. The stable policy/editor subtree remains the same child across shown to closingContent; enum notification must not remove its Flow merely because semantic exposure became false. Disposal and lease checks remain existing independent lifetime facts, not more enum cases.

Semantic exposure is `stage == shown`, with existing live/disposal/lease identity checks where relevant. **Do not gate tree presence by `isCurrent`**: the covering route's ordinary SDK modality should decide whether lower semantics are retained or blocked. That distinction removes a new cover/uncover notifier protocol. Action authority is stricter and checks `isCurrent` synchronously. Old retained closing routes are excluded by stage; lease handback cannot resurrect them. Keep hit testing, paint retention and focus request policy separate.

Use SDK `ExcludeSemantics` around the whole barrier branch so its inner BlockSemantics is removed during preparing/closing. Use SDK scoped/named Semantics and exactly one route dismiss action on the visible content boundary. Keep pointer-mode barrier nondismissible for genuine pointer handling. Command-mode SDK barrier must not contribute a duplicate dismiss action; make exactly one action owner while retaining its existing physical tap behavior. No per-model-frame widget rebuild is needed for lifetime wrappers.

## Precise source activation admission

Source semantic callback validation precedes all mutation and is repeated after held-pointer cancellation/model callbacks.

1. **Closed source:** mounted source, correct current View/session, and every modal ancestor of its Navigator chain current. Then open the same session through the domain command.
2. **Own hidden preparation:** allow only this session's current, nondisposed, nonclosing preparing popup with its live transfer lease. The source's root page may be noncurrent solely because this exact preparation is above it. Exempt exactly the root source ModalRoute identity captured when preparing; all nested modal ancestors must still be current. A blanket `activeRoute.isCurrent` exemption is insufficient because a new nested cover can exist below the root popup.
3. **Covered source/preparation:** reject when the popup is not current, the exempt root identity changed, or any other source modal ancestor is noncurrent. A root cover and nested child cover must both decline activation.
4. **Already shown, closing, disposed or replaced:** retained source callbacks are no-ops. In particular, do not permit a stale source callback to reverse a closing popup merely because it was callable before reveal. Programmatic `open()` retains its explicit caller-controlled semantics and can retain existing reversal behavior.
5. **Held genuine sequence:** revoke it through the existing session's domain cancellation before semantic open; its later real up is ignored and cannot commit an item action. Snapshot/revalidate transfer, owner, route and source eligibility around this cancellation and around `open`/sample callbacks. Cancellation does not revoke an already committed delayed item release.

Raw Listener down and model-driven `present` must bind to `_prepare`, retaining the exact previous `open` body and ordering. Public `open` may prepare then invoke a domain open on the existing transfer at its actual owner's clock time, sync reveal, and wake that owner, with existing command-envelope reentrancy discipline. Existing command-mode behavior should not be opened twice: acquisition already issues its domain open. Inventory the pointer-mode direct-open harness call and migrate only the test setup that intended preparation. The command-mode lifecycle callers keep their existing assertions.

## Dismissal authority

A captured route callback accepts only its exact live/current/shown/nonclosing/active owning presentation and mounted Navigator; then use `navigator.maybePop()` and the existing permission protocol. No direct pop, copied permission flag, model close before permission or second async transaction. Source removal alone does not disable dismissal of an independently live popup. Existing post-await revalidation, PopScope, LocalHistoryEntry and duplicate request coalescing remain authoritative. Repeated/stale callbacks after cover, logical pop, replacement or removal cannot pop the underlying page. No stronger post-issued-SDK-success atomicity is claimed.

## Flow geometry repair

Corrected executable evidence is actual logical left `29.993305998578332` versus current painted/model left `29.89416948953169`; DPR is already accounted for and tolerance stays `1e-6`. This warrants a private Flow widget subclass creating a private RenderFlow subclass whose `markNeedsPaint` also marks semantics dirty. Reuse inherited Flow delegate/clip update behavior. No render admission/listener framework, parallel matrix or extra ticker. The paint delegate already owns the transform; this repair makes semantics consume the transform on the same painted frame. Acceptance requires the executable geometry test, not code inspection. If ancestor caching prevents the simple override from working, inspect that exact subtree and redesign only this repair before widening scope.

## Required acceptance checks

Retain the eight corrected failures as before evidence. Add genuine semantics-action checks for own hidden preparation activation/revoked physical tail, root and nested covered stale source activation, stale dismiss after cover/pop/removal, asynchronous coalescing/veto and content-policy/editor identity across semantic transitions. Check one labelled source button and one tap action in both modes, one route scope/name and exactly one dismiss action, hidden/closing background restoration, dynamic opening geometry and zero per-frame page rebuilds. Existing recorded pointer/replay/timing/handback/scene values must remain unchanged. Do not loosen bounds, fixtures or timing.

Host semantics evidence cannot establish native VoiceOver/TalkBack announcement, assistive focus restoration, complete menu item roles, Reduce Motion, large-text/native IME or arbitrary cross-View geometry. Early root push still changes Navigator observer/currentness/traversal state; semantic exclusion does not make preparation globally invisible. These remain explicit next boundaries rather than reasons to enlarge this patch.
