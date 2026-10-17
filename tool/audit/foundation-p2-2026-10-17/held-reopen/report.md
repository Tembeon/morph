# P2 held source reopening

2026-10-17, base `1d4a595c0500fdb8e02d5958b5b3b76f6013bf7a`, branch `wip/measured-liquid-glass`. Prototype-only result. No main/push; P2 and production code gate remain open.

## Result

A genuine source down during visible logical closing reserves one hidden real root PopupRoute before Navigator records the pointer. Installation does not acquire the complete model, start a second sampler, mount content/policy or request focus. The predecessor retains its exact clock/lease/Flow and outgoing editor until actual opening or its ordinary first-zero hand-back. The source may receive that hand-back while the reserved SDK entry still exists.

At the model's existing hold/tap opening, the installed route acquires from the actual current owner through the unchanged transfer adapter. No second push cancels the held stream. Source/route sampling stops publication after a lease/lifetime change. The new route builds one fresh content/policy tree, following the existing plan; route-local editor State is not shuttled between presentations. External controllers can retain app data.

The only new relationship is private `(route, transfer, sequence)`. activeRoute still means model owner; the harness discovers installed routes through NavigatorObserver. Full source ancestry, exact active captured-root identity, current reserved route and accepted physical sequence bound continuation. Binding-global routing remains transport, not acquisition by coordinates. New root/nested covers revoke held input.

Retirement clears the relation before callbacks and distinguishes passive abandonment, SDK pop and removal. Passive cover preserves committed release work. Explicit Back cancels pending opening on the real owner's clock/lease. Removed/inactive successor or source cancels its own pending/open model attempt, preventing generic present from creating an orphan popup. Captured transfer/owner checks protect a reentrant replacement. Never-owning reservation disposal cannot reset the predecessor model. UI retirement is deferred beyond Navigator/tree locks and targets exact route identity; an already removed route is not finalized again.

Committed model opening under a cover continues, but the first content mount/reveal/focus waits until current/uncover. A newly mounted EditableText otherwise stole primary focus from the cover. Existing shown editor State and SDK focus restoration across covers remain intact. No blanket FocusScope gate survives. On uncover the hidden route wakes its existing clock, including after model settlement. Source TickerMode under a nested page cover remains SDK-controlled.

Protocol/caller usage: `docs/architecture/menu-held-reopening.md`.

## Design and review

Two independent runs converged on early navigation reservation with delayed model acquisition. A's route/transfer/sequence relationship wins 13/15 versus B's route/predecessor/sequence at 12/15; transfer identity guards replacement models without duplicating owner history. B supplies actual-owner semantics/Back commands. This is one model family with separate runs, not multiple model families. Both considered the structurally distinct immediate-acquire plus outgoing-paint retention alternative. Existing input-ownership evidence rejects it: fast-reopen hand-backs dropped 4 to 2 despite geometry equality. No fake hand-back counter or paint borrowing was added.

`design/` retains ground/how, candidates, judge, implementation/deslop review and Comment Sicko. The judge's first implementation-review follow-up failed due an agent usage-limit error and produced no implementation report. Candidate A then performed a separate read-only implementation review, found the orphan fallback defect, and accepted the final source after its reproduction/fix. That acceptance was conditional on the parent's full gates; their actual results appear below. Final 24-case harness adds two color-presence observations and source-page removal at opening beyond the earlier reviewed 23-case harness.

Comment review found zero new/deleted/restored comments, suppressions, reruns, encoding offers or open constraints. Complete ordered source comment text matches the base; the new test contains no comments/suppressions. Existing prototype implementation/legacy SDK suppression is unchanged and is not a production recommendation. No further substantive deslop deletion was identified.

## Experiments and corrections

- `baseline-before.log`, with `baseline-harness.dart.txt`: two failing checks on base source. The real stream is down → PointerCancel, with no later move/up. The second check stopped before pixels because it assumed activeRoute would become the installed successor; corrected to use an observer while preserving activeRoute as model owner.
- `first-implementation.log`: 26 pass / 3 fail across 9 new checks plus 20 replays. All 20 replay metrics already match. Two 120 Hz / 5× waits used 600 physical frames instead of the same model-time allowance; the color capture awaited toImage inside fake async and timed out. Corrected harness uses 600 × timeDilation frames and tester.runAsync for image work. No model/tuning/tolerance change.
- `expanded-before.log`: 16 pass / 4 fail. Successor forced removal exposed duplicate SDK finalization; source loss exposed synchronous notifier publication while the widget tree was locked. Deferred retirement distinguishes popped versus removed routes and avoids disposed notifier writes. A committed opening under cover exposed real late-autofocus theft.
- `focus-gate-before.log`: 54 pass / 2 fail across new, route and accessibility checks. A broad FocusScope gate prevented the theft but broke the existing editor focus-restoration assertion. It was removed in favor of delaying first reveal under cover. The predecessor-removal harness was also wrong: SDK removeRoute on an already popping entry is a no-op. Actual early termination now uses public finalizeRoute; old tests are unchanged.
- `reveal-before.log`: 55 pass / 1 fail. The new under-cover harness awaited completed visible projection while the deliberately unrevealed model had settled; it now awaits model settlement under cover and the normal projection/focus after uncover.
- `opening-removal-before.log`: 21 pass / 2 fail. One new nested test wrongly awaited a source tail while SDK TickerMode was muted; it now settles after uncover. Actual successor removal on the first isOpen frame rejected promotion but fell through to generic presentation and created another popup. Retirement now closes only the captured actual-owner attempt. That defect is accepted by independent review and reproduced by the retained log.
- `targeted23-tests.log`: 23 pass after the source fixes.
- `first-visible-probe-before.log`: final additional source-page-removal check passes; first-reveal color assertion fails because its 20-byte green threshold cannot detect a deliberately 1%-alpha green child. Classifier now tests positive green-minus-red, which distinguishes the green child from the r==g prototype background. This is a new presence harness, not a relaxed motion tolerance or golden.

The final optical check captures the predecessor during preparation and the first successor frame whose content alpha exceeds 0.01, requiring real green content in both. It does not compare all pixels or every intermediate frame. The final source-page-removal check removes the root source page on the opening-frame observation, then verifies finite old/reserved teardown, no third popup, no content/action, and no remaining transient callbacks.

## Verification

Flutter 3.47.2 stable, Dart 3.13.2, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`. Heavy jobs are serial, nice 10, concurrency 2.

```sh
cd example
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto
nice -n 10 flutter test --no-pub -j 2 --timeout 60s
cd ..
nice -n 10 flutter analyze
```

All 275 prototype checks and 365 full example tests pass; analyzer has zero issues. After those full runs, the new nested-cover case was strengthened to wait beyond the hold deadline without another user move/up; SDK cancellation still retires it. All final 24 new checks pass in final-targeted-tests.log. No source behavior changed after the full runs. The 24 new checks include 8 genuine held traces at 60/120 Hz, 1×/5× and early/late closing down. They compare canonical time, progress, content opacity, button/menu kicks, fusion radius and main RRect geometry against a continuous model, require actual down/move/up, one selected action and a single model. Early reversal precedes hand-back; later reversal preserves predecessor hand-back. Other checks cover outgoing/new content, fresh State/focus/policy, cancel/outside release, Back/pending Back, covers, source loss, forced successor/predecessor disposal, semantic takeover and reentrant removal. Every completed path asserts no remaining transient callbacks.

All 20 strict replay records match preceding accessibility evidence: 2346 recorded inputs, 40 routes and 40 hand-backs. All 8 async timing records/3167 samples, the backdating negative control, and all 6 flat scenes/459 frames with zero changed pixels match exactly. Existing tests, fixtures and tolerances are untouched. These are host adapter/model and same-renderer comparisons, not device/native fidelity measurements.

Production model/host/clock/timeline, prototype transfer/clock adapters, public exports, dependencies and measured tuning are unchanged. The root package suite was not rerun; historical 2362 pass / 2 skip remains in `../../foundation-p2-2026-10-16/admission/report.md`. Owner bar WIP remains byte-identical and is included as context in the example suite. Artifact hashes verify unchanged core, owner context, final code/docs/evidence and preserved previous audit.

## Remaining gates

No GUI/device/native IME, VoiceOver/TalkBack, frame-time or energy run was performed. The native passport records tap reversal and ordinary hold/slide; these host traces do not independently prove UIKit held-reopen content identity, assistive focus or native IME behavior. Compared frame channels are the bounded list above, not all possible internal channels.

P2 still needs transformed source geometry, cross-root/multi-View ownership, remaining menu API, full bar/optical carry and device/perf. Product acceptance of early root push with observer/currentness/traversal changes, hidden keyboard policy and source-local locale/RTL remains open. Selective runDue effects interruption and SDK-success-to-commit atomicity remain unproved. The branch is not migrated to main or declared release ready.

Passing logs are copied unchanged; failed/analyzer logs strip trailing line whitespace. The baseline harness is our own Dart code. Historical audit files are not rewritten. `artifacts.json` excludes its own digest.
