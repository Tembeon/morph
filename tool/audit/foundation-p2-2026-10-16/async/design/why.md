# Historical constraints for P2 asynchronous dismissal

Read-only investigation, 2026-10-16. Repository base `9fcf9d1930dec44ac875756e15f9169afe53bf88`, branch `wip/measured-liquid-glass`. No repository files, tests, devices or external accounts changed. This report records why and constraints; it does not choose a design.

## Direct evidence

1. **Admission exists to prevent an input-driven model close from bypassing SDK policy.** `5bad38c8`'s input report explicitly records that the model already entered closing before the host called unconditional `Navigator.pop`, so `PopScope` could not veto. It says the request must precede the phase change, rejection must retain the open model, and accepted motion must retain original reaction time. Source: `tool/audit/foundation-p2-2026-10-16/input/report.md:61-65`, committed in `5bad38c8`; the matching plan requirement is `docs/standalone-library-plan.md:105`. Confidence: Direct.

2. **The original-time statement predates a proved asynchronous protocol.** The same input report says that SDK approval must precede closing with the original reaction time, then separately calls out pending-permission replacement/disposal. The next admission report explicitly labels its result synchronous and leaves asynchronous permission with original event time, reentrancy, multiple requests and first-build policy registration unresolved. Sources: input report:65; `tool/audit/foundation-p2-2026-10-16/admission/report.md:17,23`. Confidence: Direct. Therefore the text establishes an aspiration, not a demonstrated causal rule for delayed approval.

3. **The internal seam is temporary and deliberately narrow.** The admission report states that decorating progress would execute after phase/fusion/kick changes and that copying the complete model into example would create a second maintained implementation. It therefore permits a synchronous, non-mutating admission function before `_close`, with no installed check preserving autonomous behavior and explicit `close` bypassing it. Only the prototype installs it; it is not exported by package libraries, and unit 2.4 replaces it with typed events. Sources: admission report:9-13; `docs/architecture/foundation-review.md:192`; `docs/standalone-library-plan.md:47`; full body of commit `9fcf9d19`. Confidence: Direct.

4. **Application callbacks must be delivered outside model integration.** Admission report:17 explicitly states that refusal notification follows the input/advance call, rather than running application code inside admission. Unit 2.4 requires draining input events before the input handler returns and timed events before frame publication. Sources: admission report:17; `docs/standalone-library-plan.md:104`. Confidence: Direct. This is a delivery-boundary requirement, not evidence that an arbitrary asynchronous result can remain synchronous.

5. **Dismissal permission and action execution are different.** An action still runs when presentation dismissal is refused. Source: admission report:19. Confidence: Direct. No evidence authorizes rolling back an action when eventual permission fails.

6. **Permission to call Navigator pop does not imply permission to animate the route away.** A committed failure showed local history consumed pop while the model had closed; `willHandlePopInternally` now retains open motion and lets SDK consume the entry. Sources: admission report:21; `docs/architecture/foundation-review.md:198`; preserved failure artifacts alongside that report. Confidence: Direct.

7. **One model and one writer are architectural invariants, including tails.** The first route report explicitly describes unique owner leases, outgoing clock pause, incoming canonical time mapping and route disposal while the same model finishes its tail under the source. It also records why an omitted reference sample changed driven kick integration. Source: `tool/audit/foundation-p2-2026-10-16/route/report.md`, sections “Ownership and SDK behavior”, committed in `7d0968a7`. Confidence: Direct.

## Current behavior, separated from historical intent

These are direct code observations, not evidence of why an author chose them:

- `MorphTimeline.runDue` delivers each deadline at its scheduled time before its final clock advance (`lib/src/motion/timeline.dart:50-63`). `MorphMenuMotion.advance` runs those events before sampling the final frame (`menu_motion.dart:2756-2760`). The current synchronous admission thus sees the original measured reaction deadline before later sampling.
- The hook returns a bool and `_requestClose` immediately invokes `_close(t)` on true (`menu_motion.dart:3046-3048`). `_close` changes phase, captures current progress/fade/geometry, retargets springs and schedules subsequent work (`menu_motion.dart:3051-3087`).
- `advance(t)` ignores time older than `_now` (`menu_motion.dart:2757`), but public `close(t)` still invokes `_close(t)` after that ignored advance (`menu_motion.dart:2462-2469`). `_sample` advances kicks only for `t > _sampleTime` (`menu_motion.dart:2901-2929`). Calling close with a past deadline after the model has continued is consequently not equivalent to having closed then.
- The current host stores `(route, admitted, time)` and drains them after integration, rechecking active identity/currentness before navigation (`example/lib/proto/menu_route_probe.dart:208,225-230,324-338`). This is a synchronous recording buffer, not a pending permission transaction.

## Supported interpretation

**The evidence points toward original reaction time primarily protecting measured synchronous replay fidelity.** The hook receives deadlines before the later final sample, the reports emphasize the original measured time, and strict adapter replays compare identical command/sample sequences. Sources: timeline/model code above; admission report:11,17,19; input report:49-51; route report's driven-integration finding. Confidence: Supported. This does not prove the author intended a delayed asynchronous approval to backdate motion.

**The current statements are underspecified when combined with a live model during await.** Original scheduled closing, continued interaction/integration while permission is unresolved, and no snapshot/rewind cannot all mean “the exact same physical trajectory as immediate approval” for an arbitrary delay. This is a derived causal conflict, supported by the code observations above, rather than a historical decision. Confidence: Supported. Any chosen resolution must be named as a refinement to the plan; the old wording must not silently be presented as already satisfied.

## Preserve / Change / Avoid / Risk

### Preserve

- Refusal before *any* closing phase/channel mutation; continued open model and retry. Direct: input report:65; admission report:17-19.
- Exact measured scheduled reaction times for synchronous acceptance and existing replay commands/samples. Direct: admission report:11,17,19; route report integration findings.
- One complete model, one owner lease and one time writer; identity/lifetime checks before any later navigation. Direct: route report; admission report:17,23.
- Programmatic `Navigator.pop` retains its SDK semantics, including bypassing veto; explicit model `close` remains an unconditional command. Direct: plan:105; admission report:11.
- Local-history consumption keeps presentation open; selection action effects are not rolled back by dismissal refusal. Direct: admission report:19,21.
- Existing fixtures, tolerances, tuning, dependencies and exports; `main` unchanged. Direct: admission report:11,13,59 and current user scope.
- Internal seam remains explicitly provisional, with removal in unit 2.4. Direct: plan:47 and commit body.

### Change that the next step must define

- Meaning of event/request time versus approval time and actual closing start when permission resolves later. Unknown in existing history; admission report:23 expressly leaves this open.
- Whether repeated requests while pending are coalesced, discarded or retried, and how a new action changes eligibility. Unknown; reentrancy/multiple-request cases expressly open at admission report:23.
- Outcome of approval/refusal/throw after cover, replacement, disposal, source removal or explicit pop. Unknown beyond the declared identity/currentness and SDK requirements; no existing async tests establish it.
- How policy registered by the first content build participates in an early pending route. Unknown and explicitly open at admission report:23.

### Avoid

- Progress wrappers, close-then-reopen rollback or mirrored/cloned model as a purported veto. Direct rejection/rationale: admission report:9,59.
- Calling application policy callbacks from inside integration. Direct: admission report:17.
- Treating the synchronous bool hook as final public API or adding production host dependence without the planned migration. Direct: admission report:13.
- Treating permission to pop as certainty that the route will pop. Direct counterexample: admission report:21.
- Quietly changing a late timestamp to pretend unchanged measured behavior. Supported causal concern: monotonic advance/integration code above.

### Risks to keep visible

- A late approval applied with a past time samples springs against old time while kick state cannot rewind; exact immediate-close equivalence is unsupported. Supported code-derived concern.
- An awaited callback may close a newly active/covering route if only navigator/top route is checked rather than the originating owner. Direct requirement for pending owner checks: input report:65, admission report:23; exact race behavior currently Unknown.
- A rejected request may already have fired an action; dismissal policy cannot be advertised as action authorization. Direct: admission report:19.
- Supporting deprecated async `willPop` is an SDK-compatibility proof; no evidence in the user scope asks for a new product async permissions API. Direct current scope asks for Flutter/native API behavior; inferred product implication must remain labelled, not promoted to fact.

## What remains unknown

No reviewed local commit/doc/report defines whether “original reaction time” includes arbitrary asynchronous delay, whether live motion must freeze, whether the close should begin at approval, or how to represent both times. The available direct evidence instead labels that contract open. No user statement in the supplied conversation resolves this causal choice. The next design should make the distinction explicit and preserve the already-proven synchronous behavior.

## Search scope and provenance

Reviewed `/tmp/morph-p2-async-design/ground.md`, why epistemics, full bodies/statistics of `9fcf9d19`, `5bad38c8`, `7d0968a7`, their committed route/input/admission reports, current plan/review/sketch matches, admission hook/host code, timeline and model sampling. This is one source category: local code archaeology with committed contemporary rationale. No commit body references a ticket or PR. The fresh local change has direct written motivation; other account searches are unavailable or unrelated as the grounding file records. No external account was searched, and no absence of external motivation is claimed.
