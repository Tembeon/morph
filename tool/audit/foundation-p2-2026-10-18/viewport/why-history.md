# Viewport lineage investigation

2026-10-18. Read-only source investigation at `3095d2fe20308c17bc97ed8bcac7af541534b76f`, `wip/measured-liquid-glass`. Only this report is written. No tests, device work, configuration changes or external requests. Paths below are repository-relative; line anchors refer to this revision.

## Question and code anchor

Why does measured admission pass zero placement padding, and why does changed active geometry retire a source endpoint rather than relayout its menu? What must a physical FlutterView safe-area/IME projection preserve?

- `example/lib/proto/menu_route_probe.dart:192`: `_readGeometry`, actual source/overlay render boxes and supported transforms.
- `example/lib/proto/menu_route_probe.dart:684`: `_canRelayout`, `checkGeometry`, `admitGeometry`.
- `lib/src/widgets/menu_motion.dart:1471`: `MorphMenuMotion.relayout`, idle-only mutation and default zero padding.
- `lib/src/widgets/menu_motion.dart:2794`: `place`, bounds/padding based final placement.
- `docs/architecture/menu-source-geometry.md:29` and `:35–55`: explicit caller contract and limitations.

Commands inspected: scoped blame for both admission regions and production relayout; bounded `git log --follow -3 -p` for prototype/model; focused patches for original relayout introduction; complete bodies of `3095d2fe`, `67afab10`, `d9973893`, `9c41085d` and `5c381ddba`; architecture documents, prior design alternatives/judge, and geometry tests. The long first patch output was truncated, so admission/retirement/relayout portions were read again through bounded contextual filtering. The requested source-control playbook is named `references/sources/code-archaeology.md` here; an initial lookup for `source-control.md` found no such file and was corrected.

## Direct evidence

1. **Zero padding is an explicit deferred boundary.** `docs/architecture/menu-source-geometry.md:29` says safe area/keyboard insets are not accounted for and IME adaptation is not claimed. The previous judge likewise says “Insets and placement padding are explicitly zero in this increment” (`tool/audit/foundation-p2-2026-10-17/source-geometry/design/judge.md:34`). Its final scrap criteria reject claiming native IME/rotation/scroll-follow policy without separate measured work (`:62`). This record does not support interpreting zero as the desired product behavior.
2. **The active snapshot protects the existing whole model and owner.** The judge explicitly requires keeping the original model/content/clock/snapshot for a shown popup, retiring hidden preparation/reservation on the old owner, and abandoning an already source-owned tail without an invisible ticker (`judge.md:50–56`). The resulting contract records the same policy (`docs/architecture/menu-source-geometry.md:41–47`).
3. **The stronger host idle gate was intentional.** The judge explains that `isSettled` also describes a fully open menu and the model's phase guard alone does not protect a held idle press or scheduled opening (`judge.md:44`). Thus `_canRelayout` additionally excludes routes, reservations, pointers, presented/arming/pending states, and requires source ownership.
4. **Retirement inherits an earlier ownership boundary.** `docs/architecture/menu-source-affinity.md:12–30` describes preserving the old popup's model/clock/content/focus/policy when a source changes root/View, immediately revoking source authority, deferring observable tree mutation, and honestly abandoning a source-owned tail. `3095d2fe` reuses this boundary for geometry mismatch; it did not introduce another retirement clock.
5. **Whole-model time continuity predates geometry admission.** `docs/architecture/foundation-sketch.md:378` explicitly says capture/resume must transfer the complete model with continuous timeline/driven-channel time; isolated per-spring rebasing was removed as an unsupported responsibility. Commit `9c41085d` is titled “prototype whole-menu ownership and clock transfer”.
6. **Production relayout has been idle-only since introduction.** Blame attributes the non-idle return, default padding, and documented “ignored while the menu is shown” contract to `5c381ddba` (2026-10-03). Its initial patch already has those elements. The broad “WIP 0.7.0: measured iOS 27 Liquid Glass widgets” body does not explain why active relayout was excluded. This establishes an implementation constraint, not a measured native keyboard rule.

## Supported conclusions

- The evidence points strongly toward a bounded host/coordinate experiment rather than a product decision to ignore system obstructions: both alternatives explicitly defer insets; the implemented phase preserves production motion and transfer unchanged; the report separates host equivalence from native policy. Sources: previous `design/candidate-a.md`, `design/candidate-b-reconstruction.md`, `design/judge.md`, `report.md`.
- Retirement is exercised as finite ownership behavior, not merely documented. `example/test/proto/menu_source_geometry_test.dart:528` preserves a shown old popup until settled/disposed with no hand-back; `:548` cancels hidden hold finitely; `:567` freezes an abandoned unsettled tail without a transient callback. These assertions converge with the written design. No jobs were rerun in this investigation; previous pass counts are historical evidence.
- Reusing an existing model for fully closed recapture and preserving active model identity/time are different boundaries. The idle movement test at `:381` covers same-model reuse; shown/tail loss tests cover sticky endpoint invalidation. Adding padding should retain that distinction.

## Inference and alternatives

Given the explicit no-retuning scope and existing idle-only model, it seems likely that active retirement was the smallest way to avoid inventing spring/placement retargeting semantics while fixing actual offset/scale input errors. The judge states the ownership constraints directly, but the precise economic preference for each guard remains an interpretation.

The previous structural alternatives were SDK Stack/Positioned plus admission-time snapshot (chosen A, 14/15) versus a render-owned source link/RenderShiftedBox host (B, 12/15). Both proposed zero padding and sticky active endpoint loss. B was rejected for added render/hit/semantics surface rather than a disagreement about native insets. Provenance matters: A was parent-authored after a runner dropout, B is a labeled reconstruction of an independently completed report, and the fresh judge reviewed this reduced panel; this is not two intact independent reports or cross-model consensus. See previous `report.md` and `design/judge.md`.

An active keyboard could conceivably lead to native follow, temporary freezing, dismissal, or layout outside the available rectangle. None of these alternatives is established by this lineage. The inherited idle guard cannot decide that product behavior.

## Unknowns and limits

- No linked PR/ticket identifiers occur in the three immediate commit bodies; all three bodies are title-only. No PR review rationale was recovered.
- The original motive for excluding active relayout in `5c381ddba` is not recorded in its body/comment beyond the fact of exclusion. It must not be elevated into native behavior evidence.
- Native behavior during animated keyboard/safe-area/rotation changes, floating or nonrectangular keyboard occlusion, actual multiwindow origin behavior and device fidelity remain unmeasured here.
- This report does not establish SDK formulas or coordinate units for physical view padding/insets. The separate runtime/SDK investigation must establish those before implementation.
- Current model placement clamps an already chosen width and has a minimum row-height cap. The lineage does not establish that arbitrary tiny available rectangles can fit a menu; new admission must explicitly decide and test this rather than infer containment from `place` alone.
- Root-global movement currently preserves the local model (`menu_source_geometry_test.dart:411`). With physical view obstructions projected into overlay space, such movement can change the effective available rectangle even if source-to-overlay geometry stays equal. Retaining that regression unconditionally would conflict with the new viewport responsibility. Preserve it when effective availability is equal and explicitly test retirement when availability changes.

## Sources consulted and coverage

- Source control/in-repository documents/tests: searched as above; substantive implementation and explicit constraints found.
- Issue/ticket tracker: outside this assigned source-control investigation; no linked identifiers found in immediate commit bodies, not a claim that no external issues exist.
- Long-form external documents: not searched; in-repository design/audit records were searched.
- Team chat: not searched; no connector access requested for this local prototype investigation.
- Infrastructure observability: not searched; no infra signal is cited by the inspected prototype records.
- Error tracking: not searched; local deterministic tests are the available failure evidence.
- Product analytics: not searched; no analytics forcing function is cited by the inspected records.

This is one scoped investigator report for the parent synthesis, not a full seven-category why synthesis. It follows the read-only assignment and does not spawn further investigators.

## Preserve / Change / Avoid / Risk

**Preserve**

- One accepted geometry/environment snapshot per session; root-overlay logical model space; complete model/clock/timeline identity and chronological time for surviving old popups.
- Fully closed/rested, source-owned, no-pointer/no-route/no-reservation relayout gate; admission before first commands; install snapshot before readiness and recheck token/model/geometry after reentry.
- Exact supported uniform transform family, finite scaled dimensions, same-View authority, original event for timestamps/observers and position-copy only for transfer input.
- Sticky old-token retirement, source authority revoked immediately, tree/notifier/replacement work deferred safely, no redirection from old callbacks into replacement.
- Fixed recording constructor and historical replay/pixel oracles, measured tuning, production model/clock/transfer signatures unchanged for this bounded stage.

**Change**

- Replace measured zero padding with an explicitly defined effective available rectangle derived from physical FlutterView metrics, projected through the actual overlay-to-view transform and intersected with actual overlay bounds; let the SDK investigation determine metric units and safe/IME edge combination.
- Encode the effective rectangle as overlay-local insets only after validating nonnegative finite padding and usable extent; include effective availability in snapshot agreement and pass it to existing idle relayout.
- Treat changed effective availability during an active lifetime through the existing endpoint-loss policy unless a separately designed/measured active-retargeting change is authorized. The old shown popup keeps its old placement/model/time and can complete independently; this does not claim that its retained placement now avoids the keyboard.
- Clarify that root-global transform changes are harmless only when they preserve effective local availability. Add edge cases for translated/scaled/subsized overlays, DPR, already-consumed local MediaQuery, idle metric recapture, shown/hidden/reserved/tail changes and impossible viewport admission.

**Avoid**

- Copying source-local MediaQuery padding directly into root overlay space; double subtracting safe area after overlay resizing; changing metrics merely because unrelated inherited MediaQuery changed.
- Recreating/rebasing an active model to make placement jump, calling production relayout while shown and assuming it worked, hidden geometry polling tickers, queued stale openings, broad transform/AABB acceptance.
- Calling this native keyboard policy, continuous IME following, full clipping/occlusion support, P3 closure or release readiness.

**Risk**

- Insets may update in a phase different from layout/paint/hand-back. Keep late-paint fences and record hand-back as a transfer-time observation; do not erase historical events after later invalidation.
- Retained idle source paint may delay observation. Do not expand the existing observation-based guarantee without a real notification path and tests.
- Insets that cover a source or leave less than menu minimum dimensions need an explicit conservative admission rule; `place` is not an arbitrary-size fitting algorithm.
- Multiple raw physical metric combinations can produce the same effective rectangle. Invalidating on raw metrics rather than effective geometry can unnecessarily abandon valid sessions; define the equality boundary deliberately.

Confidence: **direct** for documented deferral, ownership boundary and stronger idle gate; **supported** for their exercised prototype behavior; **inferred** for the minimal-surface motivation; **unknown** for native keyboard policy and the original reason behind the production idle-only guard.
