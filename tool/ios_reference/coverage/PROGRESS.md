# Checkpoint: 2026-10-14

The goal remains active. This is the first infrastructure milestone, not a claim
that the complete UI kit or even the menu family is ready.

Implemented:

- Draft inventory of 58 widget/foundation/adapter families, including missing
  text input, picker, sidebar, scrolling and system-service families.
- Semantic monitoring of 214 current public exports, including constructor
  parameters/defaults and declared members. CI fails on unreviewed API drift.
- 3,064 baseline obligation/profile pairs; all remain unverified. Broad questions
  cannot be certified until narrowed and approved. Readiness intentionally fails.
- Evidence integrity checks, reviewed scenario bindings, related gates, settings
  read-back, artifact hashes and stale candidate/harness/dependency detection.
- Seeded configuration covering arrays and reachable ordered transition pairs.
  Seed 128 produces 640 menu research plans; 11 actions still need adapters.
- Paired native/Flutter simulator capture using the existing XCUITest scenario protocol,
  independent locks, append-only output and explicit environment provenance.
- Runner journals survive failed assertions; failed captures retain observations.

Native pilot:

1. The physical-phone `menu-return` fixture failed its Ask Siri footer expectation
   on the iOS 27.0 iPhone 17 simulator. The trace and log are preserved at
   `/tmp/morph-native-menu-return-sim-2026-10-14-01`. Xcode hung after the failing
   suite; only that invocation was terminated after preserving its trace.
2. `menu-return-simulator` explicitly expects the footer to be absent. It passed
   on the same simulator: 402 × 874 pt, scale 3, Reduce Motion/Transparency false,
   all 9 expected gestures received, 7 screenshots, 1,570 source samples and
   2,132 menu-row-container samples across three instances. Native quality checks
   returned no errors. Capture cadence median 16.67 ms, maximum gap 206.04 ms,
   12 gaps over two median periods. Screenshot interruptions make this unsuitable
   as complete high-frequency motion proof.
3. Raw capture and `native-quality.json` live outside Git at
   `~/morph-re/runs/2026-10-14-menu-return-simulator-02/`. There is no candidate,
   paired film or approved fidelity gate; no obligation was closed.

## Continuation checkpoint

- Linux CI initially detected six type snapshots with different named-parameter
  spellings. Its resolver had upgraded from analyzer 10.1 to 10.2. The older
  resolver leaked private field spellings; 10.2 reports the public parameter
  names. After review, analyzer 10.2.0 is pinned and the local/Linux snapshots
  are identical. CI at `9b119444` passed. Failed CI runs now preserve API,
  coverage and dependency artifacts for review.
  Snapshots also track enum ordering and const/factory/static/abstract/final
  flags; the integration test catches enum reordering and const-constructor loss.
- The first paired run found 1,361 Flutter runtime error records and only eight
  received gestures despite the runner completing nine. The laboratory wrote
  to IOSink while its asynchronous flush was pending. A queued `LabTraceWriter`
  fixes the overlap; a blocked-consumer test verifies all 101 rows survive in
  order. The repeat has zero native/candidate quality errors and all nine
  gestures. Full example tests: 70 passed. Production motion/tuning is unchanged.
- Explicit `observationWindows` now verify finite per-property acquisition,
  maximum gaps and interval boundaries relative to actually received input.
  The ledger requires approved telemetry claims to name those windows. Dense
  aggregate traces cannot close incomplete critical intervals. The interactive
  viewer displays each interval and its missing acquisition.
- The new shot-free menu fixture declares 12 windows. Seven are complete; five
  fail the 50 ms acquisition requirement. A repeat without concurrent host tests
  confirms the holes: first-open gap 272.563 ms native / 123.277 ms candidate;
  native submenu-entry gap 89.199 ms. Source-layout bounds are unchanged in some
  intervals; that does not imply unchanged physical glass. All three later
  row-container windows pass their explicitly narrower acquisition scope.
- These are `REVIEW` results, not fidelity passes. No ledger obligation was
  certified. The 50 ms criterion is a protocol requirement, not fitted physics.
  Individual cold/warm behavior and sampler/display scheduling need separate
  diagnosis; do not relax the threshold to make these runs green.

Raw paired observations:

- `~/morph-re/runs/2026-10-14-menu-return-paired-01/` (failed writer)
- `~/morph-re/runs/2026-10-14-menu-return-paired-02/` (clean telemetry)
- `~/morph-re/runs/2026-10-14-menu-return-critical-paired-01/` (critical holes)
- `~/morph-re/runs/2026-10-14-menu-return-critical-paired-02/` (controlled repeat)

The latest interactive report is in the last capture's
`comparison-window-viewer/index.html`. Local inspection at
`http://127.0.0.1:8841/` verified both complete/incomplete interval selections.
The temporary report server was started by exec session 80245; revalidate that
handle before reusing it. Reading raw report JSON is sufficient without a server.

Validation: ledger unit tests, real-analyzer export integration (show filtering,
default changes, private named parameters, enum ordering, const flags and
body-only stability), 43 laboratory tests, 70 example tests, zero Flutter analyzer
issues, integrity/API drift check. `--require-ready` correctly returns 2.

Next work:

1. Decompose menu/context-menu public API and native states into concrete
   contracts; expand the draft graph for hold/drag/release, cancellation,
   mutations, deferred content, previews/commit, keyboard and accessibility.
2. Implement model actions on both adapters with observed state assertions;
   generate runnable scenarios, including critical transitions without shots.
3. Paired simulator telemetry and declared-window acquisition checks are now
   implemented. Next, add independent movie/display observation and clock
   provenance to recover visual transitions the main-thread sampler misses.
   `simctl io recordVideo` is available and emits a first-frame readiness signal;
   it finalizes on SIGINT. An app-updated marker can freeze during a UI stall, so
   do not map all repeated-marker frames to one physical instant or erase PTS.
   Investigate a public Core Animation clock marker independent of UI-thread
   sampling. Keep debug simulator timing separate from release performance.
4. Pin and import usable public datasets with source/configuration/hash checks.
   Add native SDK/API drift discovery outside the repository and seeded sequence
   fuzzing with failure shrinking.
5. Design/implement missing menu behavior from confirmed contracts, verify on
   simulator and device, then apply the process to every remaining family.

Constraints: use `wip/measured-liquid-glass`; no `main`/release changes. Simulator
use is authorized. Preserve other owners' phone/device locks and keep private
Apple-derived research outside Git. Push authorization remains in effect.
