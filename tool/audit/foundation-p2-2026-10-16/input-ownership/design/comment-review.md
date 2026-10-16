# Comment Sicko review: input ownership

Base: `cfade8834496cc0cf580230b0e097e172ec27514`.
Scope: current working-tree diff in `example/lib/proto/menu_route_probe.dart`, `menu_transfer_probe.dart`, `example/test/proto/menu_input_ownership_test.dart`, and the async/replay/scene reference-switch tests. Read-only review; no application edits, tests, delegation, owner WIP changes, or architecture expansion.

## Result

No actionable comment findings. Proposed deletions: **0**. Proposed reshapes: **0**. Restored comments: **0**. Review reruns: **0**. Root-cause fixes or architect sketches required by this comment review: **0**.

The diff introduces two dartdoc lines and updates one:

- `menu_route_probe.dart:23`: the broader ignored-input description matches the new acquisition and continuation rejection paths; the previous closed-menu-only description would have become false.
- `menu_route_probe.dart:26`: `cancelInput` documents a domain cancellation distinct from a fabricated binding pointer event. The implementation revokes the adapter sequence and calls the transfer cancellation operation; it does not synthesize `PointerCancelEvent`.
- `menu_transfer_probe.dart:55`: the cancellation contract distinguishes held interaction from previously committed release work. The implementation delegates to `MorphMenuMotion.pointerCancel` at model time; its body clears the held pointer without clearing the timeline. The new valid-release-before-cover test at `menu_input_ownership_test.dart:253` exercises that distinction. This wording does not claim cancellation of arbitrary already-issued effects.

These are public API contracts under the repository's external lint contract: `CLAUDE.md` requires public dartdoc, root `analysis_options.yaml` enables `public_member_api_docs`, and `example/analysis_options.yaml` inherits it. Deleting these lines would remove useful consumer semantics and violate that contract. No approval/encoding offer is needed: existing analyzer configuration already enforces documentation presence, and the behavior test enforces the substantive release-work distinction.

## Surrounding comments and suppressions

No new narrative comments, dead-history notes, `IMPORTANT`, `do not remove`, or named workaround claims appear in the scoped diff. The new ownership test contains no comments or suppressions (`/usr/bin/grep -nE '//|/\*|ignore:|ignore_for_file:'` exited 1 with no output).

Existing source comments about pushing before Navigator's ancestor listener records a down and forced removal skipping visual closing were not introduced or rewritten by this change. They describe SDK integration constraints; the patch preserves the original early-push condition and forced-removal reset. No deletion is justified by this input-ownership diff.

Existing suppressions in surrounding files were audited and remain unchanged: `avoid_print` is attached to structured experiment-output lines, while `implementation_imports` / `invalid_use_of_internal_member` allow the explicit prototype-only internal model/outline seams. Existing `deprecated_member_use` is unchanged. None of the diff's additions introduces a cast, nullability, asynchronous-context, or other correctness/safety diagnostic suppression. No new production API export is justified solely to erase these experiment-only API-boundary suppressions. Their eventual elimination with the temporary prototypes remains outside this review's fence.

Unenforced comment constraints: **0**. Open comment-review work: **0**. This review does not certify the complete implementation or replace the parent's analyzer/test evidence.

## Method and limits

Read the local `no-comments` skill, `pstack-runtime`, resolved `agents/comment-sicko.md`, project rules and lint configuration. Inspected the scoped diff, added test, cancellation implementation, representative reference output, and unchanged surrounding comments. Same parent model in a fresh read-only role; no independent engine or multi-model consensus claimed.
