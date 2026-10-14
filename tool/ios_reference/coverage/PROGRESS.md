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
- Native-only simulator capture using the existing XCUITest scenario protocol,
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

Validation: ledger unit tests, real-analyzer export integration (show filtering,
default changes, body-only stability), 38 laboratory tests, zero Flutter analyzer
issues, integrity/API drift check. `--require-ready` correctly returns 2.

Next work:

1. Decompose menu/context-menu public API and native states into concrete
   contracts; expand the draft graph for hold/drag/release, cancellation,
   mutations, deferred content, previews/commit, keyboard and accessibility.
2. Implement model actions on both adapters with observed state assertions;
   generate runnable scenarios, including critical transitions without shots.
3. Add paired simulator Flutter capture, verified critical-window observation
   coverage and optical film timing. Keep debug simulator performance separate
   from physical-device performance claims.
4. Pin and import usable public datasets with source/configuration/hash checks.
   Add native SDK/API drift discovery outside the repository and seeded sequence
   fuzzing with failure shrinking.
5. Design/implement missing menu behavior from confirmed contracts, verify on
   simulator and device, then apply the process to every remaining family.

Constraints: use `wip/measured-liquid-glass`; no `main`/release changes. Simulator
use is authorized. Preserve other owners' phone/device locks and keep private
Apple-derived research outside Git. Push authorization remains in effect.
