# Why: early menu route lifecycle and policy before first content mount

Read-only source-control investigator, 2026-10-16. Repository `/Users/tembeon/IdeaProjects/morph`, base `d121d18628242bfb7fefe54cc8df347542c82c79`, branch `wip/measured-liquid-glass`. Only this temporary findings file is written. No jobs, devices, agents, external accounts or repository edits.

## The question and code anchor

Which historical constraints should govern the next narrow P2 step: observable early root PopupRoute lifecycle, nested navigation and policy before first mount? Relevant anchors: `ProbeMenuSourceState.open` and source Listener (`example/lib/proto/menu_route_probe.dart:114-141`), model admission (`:225-234`), `syncInputPhase` (`:325-358`), permission transaction (`:442-579`), push/pop/sample/reveal/barrier/content (`:618-728`).

`git log --follow` and recent log show four introduction/evolution commits for this file: `7d0968a7` real root route, `5bad38c8` recorded input/early push, `9fcf9d19` sync admission/contour carry, `d121d186` causal async/single-use pop. Full commit bodies have no PR/ticket identifiers. Inspected patches, current code, blame for source opening and deferred content, and their contemporary reports. Blame retains root selection from 7d, early Listener and content reveal from 5bad, synchronous admission from 9fc, and async identity/claim handling from d121.

## What we found — Direct evidence

1. **Early installation addresses lost held-pointer input, not a desire to present invisible product navigation.** The input report explicitly says late `Navigator.push` cancels active pointers on Flutter 3.47.2; cancellation removes the binding hit-test path so ignoring cancel cannot restore later move/up delivery. It names SDK `_afterNavigation`/`_cancelActivePointers` and `_handlePointerEventImmediately`. Its negative control sends move/up after push and observes only down/cancel. Sources: `tool/audit/foundation-p2-2026-10-16/input/report.md:53-59`; test `example/test/proto/menu_route_input_test.dart:167` onwards; patch `5bad38c8`.

2. **The dispatch-order dependency and early observable route are acknowledged compromises, not already-approved production semantics.** The same report explicitly says source Listener pushes before ancestor Navigator Listener records down; content/focus wait for measured open; pending barrier has a separate lifetime. It expressly leaves root observer/isCurrent effects, nested routing and accessibility for review before production. Source: input report:57-59. Current plan still lists them open: `docs/standalone-library-plan.md:59`.

3. **Root routing is an explicit target, and a basic nested-stack proof predates raw input.** Plan P2 requires menu as root route (`docs/standalone-library-plan.md:53`); product unit 5.3 separately requires a menu from sheet/nested Navigator to go root (`:217`). The first route report says root popup leaves nested stack unchanged (`tool/audit/foundation-p2-2026-10-16/route/report.md:42,52`). Its test uses `state.open()`, not a real held pointer (`example/test/proto/menu_route_probe_test.dart:120-150`). Thus it is not the missing proof that early input dispatch/currentness works through both Navigators.

4. **Delayed content was introduced with early push to preserve measured presentation timing.** The input report explicitly defers content/focus until measured opening and removes canceled hidden routes without building contents (input report:57). Existing real-input tests check focused content appears on measured hold and a canceled pre-hold press builds no content (`menu_route_input_test.dart`, tests near :230 and :270). These obligations are stronger than visually hiding eagerly built contents.

5. **Pre-first-mount policy is explicitly unresolved.** Async design rejected a mandatory first-build barrier for that increment because it is stronger than consulting already registered SDK policy. It does not establish that dropping a not-yet-mounted veto is acceptable. Sources: `docs/architecture/menu-dismissal-protocol.md:52-54`; `tool/audit/foundation-p2-2026-10-16/async/report.md:5,11,21`. The predecessor admission report also lists first-build registration open (`.../admission/report.md:23`).

6. **SDK policy must precede model closing; SDK programmatic pop and local history retain ordinary semantics.** Input report:63-65 reproduces the old model-first-close bypass of PopScope. Admission report:17-23 records policy before channels mutate, delivery after integration, retained action execution, local-history consumption retaining open motion, and deliberate sync-only initial proof. Async report:17-25 now records route-owned async, revalidation, programmatic pop bypass, cover/uncover cancellation and source-only-loss survival. A new first-mount mechanism must preserve these established distinctions.

7. **One model/writer and causal time are already proved obligations.** Route report:44-48 explains leases, stopped outgoing clock, exact handback and driven-channel integration partition. Async report:35-43 refines original-time text: sync deadlines retained, delayed close begins from current state, settled canonical time pauses. Reopening/cover/pop cannot be implemented through duplicate models, rewind or adding idle wall time.

8. **Single-use permission is necessary even with SDK local history.** Async report:27-33 preserves the reproduced two-maybePop/history failure and claimed-success fix. It expressly does not promise atomic cancellation after a success has been returned to SDK. This is a limit, not a license to enlarge scope into a replacement navigation transaction.

## What we can reasonably infer — Supported / Inferred

- **Supported:** The most useful next proof should instrument real pointer dispatch through nested/root Navigators and observer/currentness before modifying route-install timing. The real regression motivating early push plus the command-only earlier nested test leave exactly this gap. Sources: Direct 1-3. This is a planning conclusion, not an author decision in history.
- **Supported:** A first-build gate necessarily changes either cancellation-before-content behavior, the time of policy evaluation, or eligibility of early requests. Current deferral means no content-scoped policy exists before that subtree mounts; the reports require no content mount on a canceled pre-hold press. Sources: Direct 4-5 and code :721-728. Which change is acceptable remains a new choice requiring explicit contract/evidence.
- **Inferred:** Treating “pending press reservation” and “revealed presentation” as named observable phases may make the lifecycle honest while keeping one actual SDK route. That is a candidate interpretation only; history has not selected phase API, public events or observer filtering.
- **Supported:** Quietly suppressing observer notifications/currentness to make pending push appear late would move away from the stated goal of SDK integration and hide the mechanism. History explicitly flags observable effects, rather than promising invisibility (Direct 2). No evidence currently authorizes SDK-private stack manipulation.

## Competing hypotheses / unknowns

- The early root route may be an acceptable documented SDK lifecycle tradeoff if tests establish pointer continuity, focus timing, Back and correct route targeting. Historical text leaves adoption pending.
- Alternatively an architecture that reserves input separately and pushes only at reveal may better match desired observer timing. The existing late-push negative control rules out a naive implementation, not every public-API alternative. No historical evidence proves such an alternative possible or impossible.
- The intended outcome of Back/Escape or external maybePop during an uncommitted hidden press is not defined in inspected reports. Cancel reservation immediately, wait for future content policy, or refuse are different choices; no one should label one existing acceptance requirement.
- No evidence establishes a desired contract for a content policy installed in first mount when input requests close in the same engine turn as reveal.
- No evidence closes route-level nested Back dispatch, a root-push observer reentering navigation, source-page currentness readers responding to hidden push, nested-route mutation while root pending, or pre-mount accessibility/semantics-dismiss behavior.
- Native fidelity, device/performance, full bar/optics, dynamic source geometry, inherited theme capture and Pages/restoration remain separate gaps. This investigation does not resolve them.

## Preserve / Change / Avoid / Risk

### Preserve

- Real down/move/up continuity and genuine cancellation behavior; existing recorded event/sample ordering and tolerances.
- Root presentation from nested navigation, with no accidental pop/push of the nested stack.
- Delayed content/focus until measured open; canceled pre-hold press does not build menu content unless an explicit design refinement justifies changing that established behavior.
- Single model/owner/time writer, exact source handback/tail and existing paused-time semantics.
- Refusal before closing mutation; selection action remains distinct from presentation permission; local history can consume one pop and leave motion open.
- One pending permission identity/single successful claim, current/owner checks, pending invalidation on cover/remove/replace/dispose, source-only-loss survival, unconditional SDK programmatic pop.
- Prototype-only scope, no new production dependency/export, no main migration or tuning/fixture edits.

### Change to define explicitly

- Observable pending-route contract: exact observer order, underlying root/nested isCurrent values, focus eligibility, Back/Escape and cancel/cover behavior.
- Eligibility/queue/refusal rule for dismissal requests before first actual content mount and timing of any required mounted-policy read.
- Whether an early request is canceled by a cover/return rather than replayed against later newly mounted content; cancellation identity must not revive.
- Evidence must distinguish source command mode from raw pointer mode, root stack from nested stack, and registered policy from hypothetical later policy.

### Avoid

- Reintroducing late push without the negative-control pointer proof, swallowing genuine cancel, fabricating/replaying framework pointer streams as a cosmetic pass.
- Eagerly mounting invisible arbitrary application content merely to discover policy without naming the canceled-press behavior change.
- Calling a PopScope “consulted” before it exists, or a refused early pop “veto” when no policy executed.
- Observer suppression, SDK-private navigation state changes, new public async guard/API, clock/timeline redesign or broad product menu migration to solve this bounded prototype gap.
- Returning unlimited pop successes, closing before approval, rollback/rewind, or navigation into whichever route happens to be top.

### Risks to expose in evidence

- Source-first hit-test order can interact with both nested and root ancestor listeners; the original one-Navigator proof is insufficient.
- Hidden root route already changes SDK observers/isCurrent and may alter external application logic even when content is absent.
- Source focus may be retained while framework root route currentness is already false; these are distinct signals and must not be conflated.
- Deferring dismissal until mount may add a frame and must not be reported as unchanged synchronous deadline behavior; denying until mount can lose a user request. A contract must select knowingly.
- Callback reentrancy can cover/remove a pending route, so an approved stale request must never target a new current route.
- Already-issued SDK success cannot be retroactively revoked; do not claim stronger atomicity from tests only covering pending guards.

## Sources consulted and coverage

- Source control: local git full commit messages, recent/follow logs, blame and patches for 7d0968a7, 5bad38c8, 9fcf9d19, d121d186; code/tests and their route/input/admission/async reports. No PR/ticket identifiers found in these commit bodies. No remote metadata needed for this fresh local prototype.
- Issue tracker: skipped as provably unrelated to this bounded source-local timing/ownership rationale; no ticket identifiers, product demand comes from supplied user scope and local plan. No absence of other tickets is claimed.
- Long-form external docs: skipped as provably unrelated personal accounts; relevant local architecture/plan/report documents inspected. External design record remains unsearched.
- Real-time team chat: skipped as provably unrelated personal account search; no linked discussion, local implementation record and supplied conversation are the relevant scope. No claim about absent conversations.
- Infrastructure observability: skipped as provably unrelated; this is an unwired local widget-test prototype with no production service/infra signal.
- Error tracking: skipped as provably unrelated external service; motivating failure is recorded locally in a binding test, not deployed exception data. No account searched.
- Product warehouse: skipped as provably unrelated; no experiment/telemetry/data threshold motivates this local SDK ordering decision.

No child investigators/synthesizer spawned: assigned role is one read-only source-control investigator; parent performs synthesis. No private UIKit reverse-engineering evidence used.

## Confidence summary

High confidence in the explicitly recorded motivations and existing boundaries; current code observations establish where the gap is, not why all future semantics should be selected. Moderate confidence in the proposed narrow proof sequence. Unknown desired product semantics before mount and whether early observer timing is acceptable. No evidence supports closing P2 or selecting a final production route driver yet.
