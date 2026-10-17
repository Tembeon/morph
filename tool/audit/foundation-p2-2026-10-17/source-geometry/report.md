# P2 measured source admission

2026-10-17, base `67afab104a5d003812cd05898742ed89927860b7`, branch `wip/measured-liquid-glass`. Prototype only. Main/P2/production code gate remain open; no push/merge/device work.

## Result

An explicit `ProbeMenuSource.measured` prepares source geometry in the actual root overlay before the first interaction. Source-local button and shape metrics map through a finite positive uniform scale/translation. Model, popup painter and Flow remain overlay-local; menu width/rows/tuning do not inherit source scale. Actual overlay size replaces a guessed screen size. Global pointer is mapped through the live root-to-global inverse only for transfer input; observers/time calibration retain the original event. Source painting inverse-maps the unchanged complete composite, including carried Gaussian contour.

One accepted immutable geometry belongs to one session. The fixed constructor remains the deterministic recording control, unchanged in meaning. Before admission the measured session has an unobserved nominal local resting model; no model input or measured sample, including ignored global pointer, escapes before preparation. `onMotionReady` configures that existing model once after valid geometry, outside SDK persistent build/layout/paint phase, before opening/pointer commands. After callback reentry the exact token/model/geometry is checked again.

Only fully closed/rested source ownership without route/reservation/accepted pointer can relayout. Idle source movement/scroll is freshly measured on next interaction without replacing the model. Active source-relative geometry/overlay-size disagreement seals the endpoint and uses existing safe retirement. Shown popup retains its original model/content/clock/policy; hidden preparation/reservation finishes on its old owner; source-owned lost tail is honestly abandoned and may stay unsettled. Replacement construction and publication run in a microtask. Old callbacks cannot operate the fresh session.

Source paint checks the snapshot before its owner filter. A later same-frame paint-only move can invalidate an earlier tick-time hand-back: stale tail is suppressed, endpoint retired, and recorded handBack remains an honest transfer-time fact. This is observation-based snapshot invalidation, not continuous source following or P3 closure. Root global translation/scale alone preserves local geometry and updates pointer conversion.

Caller contract: `docs/architecture/menu-source-geometry.md`.

## Design provenance and review

The how/history investigations completed before a runtime refresh removed their /tmp files. Their findings and lineage were reconstructed from the visible conversation in `design/ground.md`; that file is labeled as a parent reconstruction. The A runner hit a usage limit without producing a file. Parent authored A, command-time snapshot with existing Stack/Positioned/CustomPainter. Completed independent B proposed a render-owned link/RenderShiftedBox host; its full report had been read before loss, and the surviving reconstruction is labeled accordingly. This is a reduced panel, not two completed independent candidate files or cross-model evidence.

A fresh same-model judge read actual source and reconstructed alternatives, chose A14/15 versus B12/15: retain SDK layout/hit/semantics and add one private coordinate boundary rather than another render protocol. B's retained-layer and late-paint scrutiny became acceptance tests. Judge/implementation review found no ownership/reentry defect but did find absolute-epsilon admission of tiny singular geometry and unchecked scaled shape overflow. Both are fixed: supported coefficients are validated exactly, scaled products are finite-checked, and tiny singular/shear plus overflow cases are retained. Snapshot agreement precision is separate from matrix family admission.

Comment Sicko found four contract groups, all addressed: readiness timing, source-relative rather than root-global invalidation, fixed/measured coordinate spaces and throws/bounds contract. Admission now rejects persistent callbacks before relayout/readiness/push, with a real later-layout test whose boxes already have sizes. Zero ordinary comment deletions/restorations/rejected-review reruns/interactive encoding offers. Two localized renderer-oracle suppressions are retained with proof; no production exports or correctness/safety suppressions are added. Independent deslop review recommends no further structural deletion.

## Experiments and corrections

- `baseline-harness.dart.txt` and `baseline-before.log`: three assertions fail on base code. Actual offset tap and scaled-root tap do not open; initial route button center is (46,102) instead of actual (126,142). This durable baseline was rerun after temporary evidence disappeared.
- `first-implementation.log`: all three baseline cases pass on measured admission.
- `expanded-before.log`: 19 pass / 5 fail among 24 cases. Three assertions wrongly required exactly 250 visual width while the measured spring still has small rest-tolerance displacement; they now separately assert exact layout metric250 and actual painted width against the model frame/root scale. One required exact runtimeType instead of accepting the SDK transformed PointerDown subclass; the assertion now uses event subtyping and checks original global position. A nonfinite Transform was sent to the engine/semantics before admission; that boundary fixture now sets the actual RenderTransform, checks rejection, restores it before a frame, and does not claim the engine can render NaN. No old tolerance/fixture was weakened.
- `paint-before.log`: 26 pass / 2 fail. The remaining event assertion had not yet been edited. Initial pixel capture also contained the WidgetsApp DEBUG banner; banner is disabled only in the harness.
- `targeted-tests.log` and `paint-diagnostic.log`: 27 pass / 1 fail, then isolated failure. After removing the banner, pixel comparison exposed a real resting contour change. Model time/RRects/fusion match exactly, but the source painter switched to a simple resting RRect once all motion was settled. Prepared, agreeing geometry now retains the original composite through rest; local unprepared/lost/moved-rest fallback uses the container outline as well. No golden/tolerance relaxation.
- `final-targeted-tests.log`: all31 pass, including64 tail frames with zero changed pixels and later-layout callback rejection.
- `analyze-before.log`: seven brace-style infos, fixed without suppressions.
- `final34-tests.log`: all34 pass after overflow, recognized-tap and readiness-cover cases.
- Full `example-tests.log`: all416 pass, including the34 new and292 prior prototype cases plus90 other example cases. A standalone full-prototype directory job was not repeated;326 prototype cases are included in this full run.
- `retained34-tests.log`: after the full run, the same34-case harness is strengthened with an inner RepaintBoundary under the source Transform. The same-frame case now changes a paint-only ancestor transform rather than layout padding. All34 still pass; the independent root contour comparison still covers64 tail frames with0 changed pixels. Source behavior is unchanged after the full run.

Negative transform cases include rotation, nonuniform scale, reflection, singular/tiny singular, tiny/ordinary shear, perspective and nonfinite. Other cases cover actual smaller/offset/scaled overlay, DPR1/2, uniform source scale, actual down/move/up and row selection, semantic and recognized-tap paths, idle move/scroll, root global movement, Offstage/outside bounds, silent pre-admission global input, readiness reentry/cover, hidden/shown/reserved source loss, source-owned abandonment, missing layout and already-laid-out persistent-phase admission.

The pixel oracle drives a separate continuous MorphMenuMotion from the original observed command/time stream and uses the existing flat renderer in root space, without source coordinate conversion or ownership switching. Source scale1.25, overlay402×874, DPR1,1× time,120Hz host steps. The64 compared frames start at hand-back and include final rest. This proves bounded same-renderer equivalence, not native optical fidelity or arbitrary transforms.

## Verification

Flutter3.47.2 stable / Dart3.13.2, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`. Heavy jobs serial, nice10, concurrency2. Targeted34, full example416, then strengthened targeted34 and root analyzer. Analyzer reports zero issues.

All20 strict replay,8 async timing,6 fixed flat scene records and the backdating control match the previous source-affinity evidence exactly:2346 recorded inputs,40 routes/hand-backs,3167 async samples and459 old flat frames with0 changed pixels. The new geometry scene adds64 matching tail frames; it is not merged into the historical459 count.

Production model/host/clock/timeline, prototype clock/transfer adapter, public exports, dependencies and measured tuning are unchanged. Root package tests are not rerun; historical2362 pass/2 skip belong to `../../foundation-p2-2026-10-16/admission/report.md`. Owner bar WIP remains byte-identical and is context for the full example job. Exact scope/core/context/evidence hashes are in artifacts.json, excluding its own digest. Failed/analyzer logs strip trailing whitespace; passing logs are preserved.

## Boundaries

Only supported uniform positive axis-aligned maps are accepted, not arbitrary affine/3D shapes. Full-button overlay containment and Offstage checks do not establish full ancestor clipping/opacity/occlusion visibility. Placement padding is explicitly zero; safe area/keyboard insets, IME adjustment, active scroll/resize/rotation retargeting and native policy are not implemented. An idle popup may only observe changed geometry at the next input/frame/source paint; no perpetual geometry watcher is added. Cross-View conversion remains prohibited.

No device/native multiwindow/accessibility/IME/optics/frame-time/energy proof is claimed. Early root push product acceptance, hidden keyboard/local locale/RTL policy, remaining menu API/full bar, selective runDue interruption, SDK answer-to-commit atomicity and P1/P3 remain open. Main is not migrated and release readiness is not claimed.
