# Native coverage programme

Goal: a complete portable Liquid Glass UI kit, including missing families and
explicit platform adapters for operating-system services. Work lands on
`wip/measured-liquid-glass`; `main` and releases stay unchanged.

The first inventory has 58 families, the current 214 resolved public Morph
exports, shared research questions, and additional menu/context-menu questions.
These numbers describe the inventory, not native fidelity. Existing widgets and
previous measurements remain useful; no old result is silently certified by this
new ledger. All families begin with `decomposed: false`. This blocks readiness
until their broad questions have been split into concrete, reviewable contracts.

## Working order

1. Inventory public native API, documentation and public datasets. Record every
   variant, default, callback, availability rule and missing question. Review
   SDK-version drift, including new families; the current catalog is a lower
   bound. Keep private RE tools, headers/symbol dumps and derivation notes in
   `~/morph-re/`, outside Git. Commit our own contracts and public measurements.
2. Build native fixtures and capture repeatable experiments. Record received
   input, geometry, semantic events, actual environment/settings, films with
   timestamps, source hashes and capture quality. Simulator and physical-device
   observations stay distinct. Preserve conflicting observations.
3. Write a contract per question: preconditions, states, transitions, boundaries,
   mutation/interruption behavior, observations and tolerances. Mark unknowns,
   inferred rules and approximations explicitly. Choose tolerances before
   comparing the candidate, using native repeatability and measurement error.
4. Design the Flutter API and implementation from the contracts. Decide which
   features need portable drawing, Flutter system integration or a native
   service adapter. Include glass/fake/flat tiers and platform capabilities.
5. Implement one family, compare native and candidate, fix discrepancies and
   retain each failure as a replayable regression. Cover transition pairs and
   risk-based configuration combinations; pairwise sampling does not prove
   higher-order interactions. Add explicit 3+ way cases for discovered risks.
6. Repeat across families. Release only with approved scope, reviewed API drift,
   native/candidate evidence for every applicable contract/profile, accessibility
   and performance checks, and explicit decisions for every remaining gap.

Menu and context menu are the first complete pilot. Afterwards: foundations and
basic controls; bars/search/navigation; presentations; text/pickers; lists and
scrolling; advanced interaction and system adapters. Foundations are researched
alongside the pilot because their contracts affect every control.

## Commands

From the package root:

```sh
dart run tool/ios_reference/coverage/export_api.dart > /tmp/morph-api.json
python3 tool/ios_reference/coverage/coverage.py check --api /tmp/morph-api.json
python3 tool/ios_reference/coverage/coverage.py report > /tmp/morph-coverage.json
python3 -m unittest discover -s tool/ios_reference/coverage/tests -v
python3 tool/ios_reference/coverage/coverage.py plan \
  tool/ios_reference/coverage/menu-model.json --seed 128 \
  --out /tmp/morph-menu-plan.json
```

`check` validates integrity; it deliberately prints `READINESS: False` while
research is incomplete. `--require-ready` returns 2 until everything tracked is
verified and decomposition is approved. API changes return 2 even when existing
tests pass. The analyzer resolves exports, `show`/`hide`, declared members,
parameter types and defaults. It records inherited behavior through supertype
signatures; framework API changes require native/Flutter SDK review separately.
Review the delta before regenerating `api-baseline.json`. This baseline records
the surface to monitor, not an assertion that every exported API is correct.

The menu model is a research hypothesis, not an extracted native state machine.
The generator guarantees reachable paths and ordered adjacent-transition pairs
for its declared graph and configuration strength. It emits **plans**, not lab
scenarios or executed tests. `unadaptedActions` lists everything still needing a
native/candidate adapter. Reset to the initial state before each case. Add
invalid-input expectations and boundary values as explicit contracts; do not
silently filter difficult cases out of the graph.

## Evidence rules

Version 1 of the importer accepts telemetry evidence only. Optical, accessibility,
haptic, lifecycle, boundary and performance contracts remain open until their
dedicated oracles and capture adapters are implemented. A report without gates,
a passing widget test or a public screenshot cannot close these contracts.

An evidence record binds an external append-only `bundle`, a catalog `profile`,
the exact `environment`, SHA-256 references for `scenario`, `report`,
`nativeManifest`, `candidateManifest`, `nativeTrace`, `candidateTrace`, and
individual `claims` containing `obligation`, `gate` and `metric`. Artifacts must
stay inside the bundle. Each obligation must list reviewed `scenarioHashes`.
The report must pass, contain no quality errors, have matching scenario hashes,
read-back settings and an actual declared gate related to the claimed metric.
Both manifests must record the exact `coverageEnvironment`; older captures
without this annotation need reviewed provenance, never an automatic label.
Candidate production-source hashes must match the current files, including
deleted files. Changes invalidate the proof until comparison is rerun.

The current four profiles distinguish light/dark and simulator/device. They are
the starting baseline. Reduced motion/transparency, contrast, Dynamic Type,
RTL/locales/calendars, rotation, iPad/multitasking, keyboard/pointer, renderer tiers
and Flutter platforms must be decomposed into additional applicable profiles.
No green baseline is allowed to imply those configurations were exercised.

## What prevents forgotten edge cases

- Every family has questions for API, states/transitions, boundaries, combinations,
  events, input, mutation, accessibility, optics, platforms and performance.
- New/changed public Morph API fails the drift check until reviewed.
- Unreachable model states fail validation; generators report missing adapters.
- Plans, native observations, implementation and verified fidelity stay distinct.
- Missing evidence, stale sources, unreviewed scenarios and unrelated gates fail.
- Each discovered discrepancy becomes a named obligation and replay regression.
- Native SDK drift, model-based seeded fuzzing with shrinking, critical-frame
  coverage and independent review are required next layers, not claimed features
  of the initial ledger.

There is no finite proof of every possible OS behavior. The aim is explicit,
expanding coverage with reproducible evidence and no silent unknowns at release.
