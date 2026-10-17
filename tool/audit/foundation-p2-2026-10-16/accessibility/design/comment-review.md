# Comment Sicko: P2 accessibility

Read-only review of the current working diff from `65dce59f` in `example/lib/proto/menu_route_probe.dart` and the new `example/test/proto/menu_accessibility_test.dart`. Read the local no-comments skill, runtime adapter, reviewer role, repository rules, actual source, and the installed Flutter SDK's WillPopScope / ModalRoute implementations. No source edits, tests, delegation, or owner-WIP operations were performed.

## Findings

No actionable comment findings in this scope.

- Keep `menu_route_probe.dart:69,72`: the two new dartdocs describe the consumer-facing meaning of independently configurable source-button and route names. They satisfy the repository's `public_member_api_docs` rule. They do not preserve implementation history or excuse complexity.
- Keep `menu_accessibility_test.dart:385` (`ignore: deprecated_member_use`): this is a one-expression compatibility-test seam. The test deliberately mounts the SDK's real `WillPopScope`, returns an unresolved `Future<bool>`, dispatches two semantic dismiss actions, and asserts one permission call and one eventual pop. The installed SDK's `WillPopScope` registers scoped callbacks on ModalRoute; `ModalRoute.willPop` awaits those callbacks. Replacing this with `PopScope.canPop` would remove the asynchronous permission path being tested. Replacing it with a fake route override would stop exercising descendant SDK policy registration. The diagnostic is deprecation, not a correctness/safety error. This keep does not recommend WillPopScope for new production APIs or claim predictive-Back support.
- The inline Navigator Listener ordering explanation at `menu_route_probe.dart:253` is pre-existing, moved by the source Semantics wrapper. It explains an external event-dispatch ordering dependency rather than restating `_prepare()`. Keep.
- The forced-removal explanation at `menu_route_probe.dart:512` and the final file-level suppression at `:1351` are unchanged from the base. No new file-wide suppression was introduced. The new accessibility adapter adds no private SDK import or internal-member access. Existing prototype implementation imports and deprecated route-policy integration remain within the prior experiment boundary; this review does not turn them into a production API recommendation.

## Accounting

- New explanatory/API comments: 2 public property dartdocs.
- New lint suppressions: 1 narrowly scoped SDK deprecation suppression.
- Newly introduced correctness/safety suppressions: 0.
- Deletions recommended/performed: 0 / 0.
- Restored comments: 0.
- Rejected-report reruns: 0.
- Architect sketch or implementation fixes required by this review: none.
- Constraint-comment encoding offers / encodings: 0 / 0; no new `do not remove`, wording-preservation, or approval constraint comments exist.
- Unenforced constraints / open comment work: none in the requested diff.

Verification is source review only; use the parent's analyzer and behavior-test evidence for execution results. The compatibility test already encodes its reason for preserving the deprecated SDK seam through its name and assertions; adding a second prose rationale beside the suppression would duplicate that evidence.
