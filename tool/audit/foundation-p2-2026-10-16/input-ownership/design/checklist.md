# P2 input ownership and nested dismissal, base cfade883
- [x] Ground: how + rationale, actual failure traces
- [x] Sketch: two structural alternatives and fresh cross-judge
- [x] Agree: synthesize, no requested human checkpoint
- [x] Implement: prototype-only input lifetime and SDK integration
- [x] Verify/scrap: replay, example, analyzer, evidence and local commit
Arena: frame -> fan out -> cross-judge -> pick -> graft -> verify.
Rubric 0..3: real pointer/measurement fidelity; single input owner and cover cancellation; correct Escape/Back scope without caller burden; lifecycle/reentrancy/multi-navigator safety; smallest coherent Flutter SDK boundary.

Verification: prototype217/example307/analyzer0. Evidence and scoped commit prepared; commit receipt is repository history. Production gate and full P2 remain open.
