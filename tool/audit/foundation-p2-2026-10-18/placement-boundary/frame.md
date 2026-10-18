# Design frame

Base f96094e4. Target: measured P2 prototype in example/lib/proto/menu_route_probe.dart only. Produce a usage-first sketch that separates source endpoint facts from placement admission while preserving EVERY current observable result, including conservative sticky retirement on effective available-rect change. Native selection/reopen establishes functional reuse, not optical landing. Relaxation of retirement is explicitly outside this increment.

The caller remains ProbeMenuSource.measured(button: localButton, menuBuilder: buildMenu). No public options, policy toggle, observer, new ticker, or library/dependency/export change. Do not add a generic presentation framework. Private one-file change must earn its structure by putting validation/derived state next to the facts it owns. Keep one capture/admission path, one immutable admitted snapshot and one model, no independently updated stored placement/endpoint epochs. Future landing policy can read different facts, but no future-only APIs or enum/diagnostic flags are needed now.

Read grounding-how.md and grounding-why.md plus current code/tests and docs/architecture/menu-native-ime.md. Important: _readGeometry null presently encodes unsupported source transforms, invalid/empty viewport, menu minimum fit and covered source. A split which compares only source fields silently misses null/containment behavior. Painter repeats read/agrees even before checking owner, protecting same-frame land→layout movement. onMotionReady may mutate metrics and reentrantly open a popup; invalid active admission must sticky-retire even if restored before next pump.

Artifact per candidate: candidate-A/design.md and sketch.dart.txt (or B). Use architect/references/runner-prompt.md and rationale-template.md. Sketch types and bodies as not implemented/pseudocode; no live code edits or tests. Explain how actual admission, source paint, input/frame/handback call sites use the shape. State if splitting the live code would add shallow bags without practical isolation; propose a smaller meaningful seam instead.

Parent rubric (0–3 each):
1. Preserves full safe-admission/sticky-active/callback/paint behavior, including null and minimum-fit.
2. Separates invariant knowledge with one authority and no hand-synced snapshots.
3. Small caller surface and short call chain; no public configuration or speculative abstractions.
4. Makes future placement-versus-endpoint decision local without pretending optical policy is proven.
5. Implementable in one prototype file, tested by existing62 geometry cases/full example and replay/contour checks.

Phases: frame, two independent whole shapes, cross-judge, base pick/graft, implementation, verification. Two structurally distinct candidates required; same-model runs are independent attempts, not multi-model agreement. No main/push/native device work.
