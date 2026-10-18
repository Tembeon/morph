# P2 placement/source-paint boundary

2026-10-18, base `f96094e4a4a704ae09ca6462f6c81fcd208be96a`, branch wip/measured-liquid-glass. Prototype-only structural increment. Main and active policy stay unchanged; no device, push or merge.

## Result

One `_admitMenuPlacement` operation now owns physical safe/IME projection, actual-overlay intersection, tuning minimum fit and full source containment. It replaces the projection-only helper; there is no second calculation path. State retains framework attachment/Offstage/source transform/finite-shape capture. The session still stores exactly one admitted `_MenuGeometry`, with derived padding and mandatory full agreement including available.

`readSourcePaintGeometry()` localizes the existing effectful double fence in the session: capture admitted snapshot before checkGeometry, then under strict idle require a fresh complete read/agreement. Measured source painter calls it under the same source-only guard before owner filtering; fixed and route painters gain no new check. This hides session lifecycle knowledge from painter without an observer, ticker, extra type/allocation or separate snapshot.

All active availability mismatches and null admission still sticky-retire. Idle recapture, snapshot-before-readiness, reentrant callback checks, source-only same-frame paint fence, route-independent input/sampling and finite hidden/reservation/tail retirement retain their prior contracts. No consumer-level API, library code, motion tuning, dependencies or tests changed. The viewport document now correctly distinguishes proven native functional close/reopen from unmeasured optical return.

Contract: `docs/architecture/menu-placement-boundary.md`.

## Grounding and design

How explainer traced the complete source/overlay/admission/input/frame/handback/paint flow; why investigator found direct recorded snapshot/retirement rationale and real invalid-admission/reentry regressions. Fresh why synthesis distinguishes those records from inferred future separation. Todoist exact scoped read query returned no matches; external chat/infra/error/analytics/remote-doc sources were unavailable. No wider external task absence is claimed.

Two inherited-model design attempts completed. A offered validated endpoint inside admission. B initially converged on composition, then produced a requested structurally distinct operation-oriented candidate. Fresh judge and parent score both14/15 and select B for smaller present interface: an independent endpoint-only consumer does not exist yet. This is multiple attempts, not multiple-model evidence. Synthesis adds an explicit effectful method instead of B getter and drops an optional one-call source comparison helper. Candidate sketches remain historical pseudocode, not importable live APIs.

Architect implementation follow-up accepted exact nullable/read/paint ordering, one placement callsite, removed old helper, preserved source-only guard and unchanged admission/handback/input algorithms. No rejected-review rerun or scrap trigger occurred.

Deslop moved complete knowledge into the operation rather than creating endpoint/admission bags or another projection wrapper. No behavioral deletion or performance win is claimed. Comment Sicko found0 actionable findings,0 added/deleted code comments,0 new/expanded suppressions,0 restorations/encoding offers/encodings/open comment work. Its final four-document pass also found0 issues; the pre-existing out-of-diff suppression is unchanged.

## Verification

Heavy jobs were serial/nice10, tests concurrency2, no-pub. Flutter3.47.7 stable, framework abaf9c523780a608bd46686fd5e53740a07077f8, Dart3.13.5.

- Before change:62 geometry cases pass; source and inset independent contour oracles each64 frames/0 changed pixels.
- After change: full example444 pass, including354 prototype cases and all62 geometry cases. No expectation/tolerance/test changed. Root analyzer0 issues; scoped Dart format clean.
- Exact emitted records match the prior viewport summary:20 replay,8 async timing,6 fixed flat scene,3 contour,1 backdate,1 original geometry and1 inset viewport record. That includes2346 inputs,40 routes/handbacks,3167 async samples,459 original flat frames and both64-frame contour oracles. The comparison normalizes record ordering only, not values.
- Shader offline gate exits0 with the actual SDK bin preceding the shim. It is a compile/static check, not device frame-time/energy or native pixel parity. No shader changed.
- Production clock/model/timeline, prototype transfer/clock, exports, pubspecs and owner WIP hashes match before. The example log lives at `/tmp/morph-placement-boundary-example-tests.log`; its digest is recorded, while all emitted result records are saved in records-comparison.json.
- Root package suite and device parity were not rerun: no library/shader behavior changed. Historical package counts are not attributed to this increment.

## Remaining boundary

This isolates a complete placement calculation and source-paint authority check; it deliberately does not provide endpoint-only validity after a failed placement read. A future policy allowing that needs a different reader/result design and optical evidence. Native functional reuse is insufficient to establish continuous morph landing, early return reopening, moving/lost source, hidden/reserved native parity or different window/keyboards. P2/P3, product presenter, remaining menu API/full bar, device/perf and main/release gates remain open. The next native experiment is optical close/landing after IME; no background job is scheduled.

verification.json, comment-review.json, judge.md and artifacts.json bind this stage. Baseline owner files are excluded from the scoped commit.
