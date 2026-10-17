# Comment Sicko: source affinity

Read-only review against `d9973893`; inspected the entire scoped comment inventory, changed source surroundings, new test file and `docs/architecture/menu-source-affinity.md`. No application edits or tests executed.

## Actionable public-contract corrections

1. `example/lib/proto/menu_route_probe.dart:63–67`, `ProbeMenuSource.menuBuilder`: qualify “Theme values follow the source”. It is now false after an affinity rotation: `didChangeDependencies` queues themes only for `_current`, while `detachSource` seals the old session and its popup deliberately retains the old captured themes/content. Preserve the public dartdoc and state that updates follow the source only within the same root Navigator/View attachment; an independently retained popup keeps its last captured themes after the source moves. This documents the existing intentional lifetime; no implementation reshaping is needed.

2. `example/lib/proto/menu_route_probe.dart:955`, `ProbeMenuRoute` class: “the same menu model the source later resumes” is now an unconditional promise that the new contract intentionally rejects. A moved source never resumes that popup model, and its closing route runs to rest independently. Keep public dartdoc but replace with, for example, “A PopupRoute retaining its model when the source moves to another root or View.” Alternatively qualify resumption on the original attachment surviving. No code change is called for.

3. `example/lib/proto/menu_route_probe.dart:243`, public `open()`: its existing sentence remains true but omits the newly meaningful precondition and failure mode. Extend it to say an active source and root overlay must share a FlutterView and otherwise it throws `StateError` before pushing. This is a consumer contract addition, not a redundant comment deletion.

## Verified keeps

- Source pointer-down ordering at line 341 is an external Flutter dependency, not an excuse for our own complexity: SDK `NavigatorState._handlePointerDown` adds to `_activePointers`; push updates call `_cancelActivePointers`, which cancels the recorded pointers. Keeping the push in the source Listener before the ancestor sees the down protects held acquisition. No simpler in-scope API eliminates that ordering requirement while preserving raw held input. The new code still obeys it.
- Forced-removal rationale at line 732 explains the intentional reset for a surviving source when the SDK bypasses route closing; it is not false under session retirement, because a detached source has no sourceClock and does not enter that reset branch. SDK remove-route semantics run no exit animation. Keep.
- Other public dartdoc describes genuine harness inputs/observations. Its brevity is required by the repository public-member documentation rule and is not a deletion reason. Fixed root-coordinate geometry remains explicitly intentional in the constructor documentation and architecture contract.

## Scoped suppression audit

The final `ignore_for_file` at line 1639 is unchanged from the base. It contains three categories, none a correctness/safety analyzer suppression:

- `implementation_imports`: prototype deliberately imports internal outline and close-admission seams rather than expanding production exports.
- `invalid_use_of_internal_member`: `morphMenuSetCloseAdmission` is actually annotated `@internal` in `lib/src/widgets/menu_motion.dart`; using it is the intentional admitted-close prototype seam.
- `deprecated_member_use`: SDK `ModalRoute.willPop` and `hasScopedWillPopCallback` are genuinely deprecated but still implement scoped asynchronous WillPop callbacks. The probe and existing lifecycle/async/accessibility tests intentionally retain those callbacks. Replacing the calls with `popDisposition` would drop that behavior, so this is not a valid trivial “use the real API” fix.

No suppression should be deleted blindly to manufacture a comment count, and no production API/export change is justified by this review. Narrowing these to individual lines could localize exemptions but does not remove an underlying dependency and is not required by the present change.

## Counts and constraint encoding

- Recommended deletions: **0**.
- Recommended public-contract edits: **3** (two false/unqualified claims and one new failure contract).
- Actual deletions/restorations/reruns: **0 / 0 / 0**. Parent owns edits.
- New test file contains **0 comments**, verified with `/usr/bin/grep -nE '//|/\*'` returning no matches.
- No “do not remove”, “do not change wording”, “talk to X”, thin IMPORTANT, license or TODO constraints occur in scope. No interactive encoding approval or additional architect sketch is needed. Existing held acquisition tests and the new independent-session/foreign-overlay-view tests encode the relevant ordering and attachment behavior; no new encoding offer is necessary.
- No comments hide an avoidable state-machine workaround in this diff. Affinity/session identity, active-element checking and deferred retirement address concrete external tree-lock and ownership boundaries.
