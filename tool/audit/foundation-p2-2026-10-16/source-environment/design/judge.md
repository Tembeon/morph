# Source environment synthesis

Read-only design judgment against base `65b080d3a0ff178d57509f2f5fc9613ef88fafce`, task/ground/how/why, both full candidates, current `menu_route_probe.dart`, public installed Flutter `InheritedTheme.capture`/`CapturedThemes.wrap`, and the expanded baseline log. This is a separate inherited-model role, not independent model-family consensus. No implementation edit, runtime test, device or private framework investigation was performed by this judge.

## Caller contract first

Keep `ProbeMenuSource(menuBuilder: (popupContext) => EditorMenu())` unchanged. Local inherited themes between the source and the exact root Navigator follow compatible source value updates while the source remains mounted. The popup retains its own ModalRoute, PopScope, Navigator and Focus ancestry. After source loss the last valid local snapshot remains, while uncaptured root appearance and system environment remain ordinarily live.

Non-theme source scopes are not transported. Root MediaQuery, Localizations and Directionality remain authoritative in this unit. Page data or explicit local direction/locale can be re-provided by the caller inside the builder; that is an actual boundary limitation, not a generic context-preservation claim. Theme wrapping is SDK widget capture, not deep freezing of arbitrary data or source resolution of destination-sensitive themes.

## Rubric

Scores use 0 absent/contradictory, 1 material gap, 2 sound with bounded costs, 3 satisfies the axis directly.

| Axis | A: source subscriptions, route publication | B: one capture per presentation |
|---|---:|---:|
| Caller simplicity and truthful inherited contract | 3 | 1 |
| SDK route, PopScope and focus identity | 3 | 3 |
| Live global versus local behavior | 3 | 1 |
| Source detach and presentation lifetime | 3 | 3 |
| Minimal necessary mechanism | 2 | 3 |
| Total | **14/15** | **11/15** |

A wins because source-local live value refresh and changes during hidden preparation are recorded requirements. B explicitly and honestly loses both; this is confirmed by the two relevant baseline counterexamples, not merely architectural taste. Its smaller implementation does not offset the behavior it removes. Both preserve destination identity and explain non-theme limits clearly. A loses one mechanism point for unavoidable source observation/deferred cross-branch publication, and its sketch can still be reduced.

## Selected shape and subtractive refinement

Use A, retaining B's presentation-owned capture after source detach. Add only private state to the current prototype file. The source owns dependency registration and acquisition; each route owns its accepted snapshot and pending publication. No motion/clock/timeline/reference changes, global registry, new caller controller, per-frame walk or parallel production carrier.

The minimal snapshot needs the public SDK `CapturedThemes` plus nearest unique `InheritedTheme` widget identities in SDK traversal order. The extra list exists because SDK capture does not expose its contents and identity/type comparisons are required for bounded refresh; it must not become a second wrapping implementation. Derive kind comparisons directly from those widget objects. Use `InheritedTheme.capture(from: source, to: selectedNavigator.context)` as the only capture implementation and `CapturedThemes.wrap` as the only wrapping implementation. Source observation uses public `dependOnInheritedElement` only on actual source ancestor elements; route-to-source cross-tree dependencies violate SDK descendant assumptions.

**Remove A's `_initialKinds` field entirely.** Compare each proposed snapshot's ordered runtime types with the currently accepted snapshot. The accepted sequence never changes: initial capture establishes it and every later acceptance requires equality. This inductively preserves the initial-kind invariant without retaining the first capture or another list of types. Pending snapshots must also satisfy that sequence. Compare widget identities against the effective pending snapshot, or at least ensure a new value equal to the accepted snapshot overwrites an older pending value; otherwise A→B→A before publication can wrongly publish B. A single route-owned pending slot is sufficient.

Remove the separate queued boolean too: `_pendingThemes != null` can denote an already queued callback. Replace its value on every accepted new capture, schedule only on the null-to-nonnull transition, and take/clear it before notification. Disposing the route sets it null and the stale callback becomes a no-op. No theme revision counter or additional queue identity is necessary for one route's lifetime.

One publication mechanism is enough: either the candidate's private ValueNotifier/ValueListenableBuilder or equivalent route-local SDK invalidation. Do not combine both a notifier and `changedInternalState` for appearance refresh. The selected notifier makes the changed boundary explicit and leaves the rest of the route alone. Supply a stable `_MountedMenuPolicy` through the listenable builder's `child`; do not key content by capture identity. Registering dependencies only on nearest themes of each type is sufficient and avoids irrelevant shadowed-ancestor invalidations; the source's registered ancestors are the only legal dependency targets.

## Lifetime and phase gates

1. `open` selects its root Navigator once, captures synchronously to that exact context, constructs a route with the capture, and pushes onto that Navigator. Reusing a nonclosing route keeps existing behavior. Hidden pointer preparation receives data but does not mount builder/PopScope early.
2. Source `didChangeDependencies` registers ancestor theme dependencies and acquires a new snapshot. It may queue that immutable data to still-live session presentations whose `navigator` is the same selected Navigator. Registration is performed on the source Element, never on sibling route context. Ancestor capture must happen only while the source is active.
3. Source invalidation can occur during build. Store a pending snapshot immediately but defer listener notification until post-frame. Take and clear pending data and the queued flag before notifying; re-check disposal, then notify only on changed identity values. Multiple invalidations coalesce to the latest compatible data. This feature does not assume `addPostFrameCallback` itself schedules a frame; its normal queue site is dependency processing during a scheduled frame.
4. Post-frame callbacks close over their own route, not source State/BuildContext or a mutable session `activeRoute`. A source removed after acquisition cannot invalidate the captured value or cause a stale context lookup. An obsolete route callback cannot overwrite a replacement presentation because it writes only its own route. Navigator migration must reject a new-root capture for an old-root route at acquisition/publication boundary; it does not retroactively invalidate a valid old-root pending snapshot.
5. Route disposal clears pending data and disposes its notifier. A queued callback checks `disposed` before any notifier use. Initial synchronous acquisition and post-frame deferred notification must be tested separately; a green initial snapshot test proves neither update ordering nor detach safety.
6. Closing but not disposed old presentations may retain or receive compatible appearance until teardown. Updating their own snapshot does not grant input/motion ownership. Source-only removal stops new captures and retains already acquired route data.

## Explicit topology caveat

Live refresh is bounded to the initial ordered nearest theme runtime-type sequence and stable `wrap` child topology. Adding/removing/reordering theme kinds retains the last compatible snapshot for the current presentation; a new presentation adopts the new topology. Comparing current accepted kinds is enough to implement this. Matching theme types cannot protect against a custom theme whose `wrap` swaps widget types/keys or changes child topology for a value update. Do not promise general State preservation for arbitrary custom wrappers. This is a documented SDK boundary, not grounds to build a speculative theme engine.

## Rejected alternatives and grafts

- Reject B unchanged: one-shot capture freezes valid live local values, including a changed value before first reveal. Keep its immutable-after-detach ownership principle.
- Reject source-owned portal: it naturally retains page inheritance but preserves source ModalRoute/PopScope/Focus ancestry, contradicting the presentation policy already proven in P2.
- Reject route-owned foreign inherited subscriptions: direct public API availability does not waive SDK dependent-descendant assertions.
- Reject generic context copying, Localizations override loaders and MediaQuery field merging for this unit. They change route/system behavior and add contracts outside this measured theme task.
- Reject a separate retained initial capture/type list, per-route revision counter or source-context callback. Current accepted snapshot and route identity already encode those boundaries.

## Required discriminating checks

The expanded baseline is nine executable checks: four pass and five fail. Preserve it as a before artifact. Implementation acceptance needs more than making those five green:

- Local text/icon/custom themes reach plain and nested-Navigator popups; root popup identity and its PopScope remain authoritative.
- Compatible value refresh preserves editor State/focus and policy; no build-phase notification exception. Coalesced A→B→A publishes A. A refresh acquired before source disposal can publish afterward without a source read.
- Root shared themes/system environment stay live and local same-kind overrides keep shadowing them. Plain providers and local non-theme overrides remain scoped; explicit content provisioning works.
- Hidden preparation still has zero builder calls; latest compatible pre-reveal themes appear on its first actual content mount, and preparation cancellation remains safe.
- Disposing/replacing a route before a queued publication cannot mutate a disposed notifier or the replacement snapshot. Global-key source migration must at least be bounded/documented if not exercised.
- An incompatible type sequence retains prior accepted content/State; reopening adopts it. Ordinary motion frames do not trigger capture or theme notifications.
- Existing replay/async/scene metrics, ownership, handbacks and all measured constants remain unchanged. This bridge proves inherited appearance behavior only; semantics, geometry, native fidelity and multi-View migration stay separate.

Proceed with A reduced as above. No human checkpoint is needed under the invoked architect default, and this review does not close P2 or approve production/main promotion.
