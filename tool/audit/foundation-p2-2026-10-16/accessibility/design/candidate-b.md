# Candidate B: retained render boundary owns semantic admission

## Problem

The prototype already separates raw pointer input from model ownership and keeps closing content mounted for its optical tail. Semantics must follow the logical presentation rather than that retained widget lifetime. A widget-only policy can rebuild ExcludeSemantics when route state changes; this candidate instead puts semantic child admission beside the existing synchronous render hit gate. It is a real alternative because the render boundary, rather than a rebuilt widget snapshot, owns exclusion and geometry invalidation. The route remains the sole owner of logical state. No timing, tuning, model, or raw pointer behavior changes.

## Usage (caller's view)

The consumer supplies names in its own locale. Accessible activation is automatic; there is no new public presenter or semantic clock API.

```dart
ProbeMenuSource(
  pointerInput: true,
  semanticLabel: 'More actions',
  routeSemanticLabel: 'Message actions',
  menuBuilder: (context) => messageActions(context),
)
```

A second call site uses the same API for command mode, without duplicate semantic tap actions:

```dart
ProbeMenuSource(
  semanticLabel: 'Playback options',
  menuBuilder: (context) => playbackOptions(context),
)
```

A policy-owning menu stays ordinary Flutter content:

```dart
ProbeMenuSource(
  pointerInput: true,
  semanticLabel: 'Edit attachment',
  routeSemanticLabel: 'Attachment actions',
  menuBuilder: (context) => PopScope<void>(
    canPop: !isSaving,
    child: attachmentEditor(context),
  ),
)
```

Both labels can remain nullable in the reduced probe to avoid rewriting unrelated harnesses. Null does not magically provide an accessible name: the implementation and report must not claim that an unnamed source is fully accessible. The eventual production API needs a deliberate localized naming contract. A route name is optional because not every popup should invent an announcement. The semantic dismiss action itself is a platform action; this candidate does not add a hard-coded English dismiss label or a localization subsystem.

## Shape

### Data and signatures

All implementation stays in `example/lib/proto/menu_route_probe.dart`; add only `example/test/proto/menu_accessibility_test.dart`. Public additions are two optional string properties. The private API hides domain activation, render subscriptions, and route policy.

```dart
class ProbeMenuSource extends StatefulWidget {
  final String? semanticLabel;
  final String? routeSemanticLabel;
  // Existing inputs remain unchanged.
}

class ProbeMenuSourceState extends State<ProbeMenuSource> {
  void _activateFromSemantics();
  // Validate source/presentation eligibility, then issue one domain activation.
}

class _MenuSession {
  void activateFromSemantics(ProbeMenuRoute route);
  // Sample the existing owner clock, open the existing transfer, reveal and wake it.
  // Never synthesize pointer events or allocate a second motion model.
}

class ProbeMenuRoute extends PopupRoute<void> {
  final ChangeNotifier _semanticInvalidation;
  bool get _exposesSemantics;
  bool get _acceptsSemanticDismiss;
  void _dismissFromSemantics();
  void _invalidateSemanticBoundary();
}

class _MenuPresentationGate extends SingleChildRenderObjectWidget {
  final ProbeMenuRoute route;
  // Retains current hit-test behavior and adds semantic subtree admission.
}

class _MenuPresentationGateRender extends RenderProxyBox {
  void _onSemanticInvalidation();
  void _onModelFrame();
  @override void visitChildrenForSemantics(RenderObjectVisitor visitor);
  @override bool hitTest(BoxHitTestResult result, {required Offset position});
  // attach/detach manage notifier subscriptions; route replacement unsubscribes first.
}
```

`_exposesSemantics` is derived from revealed, nonclosing, nondisposed presentation and current model lease. It is not a second writable `visible` boolean or a cached model phase. Normal covering-route modality belongs to Navigator; do not additionally hide a route merely because `isCurrent` is false. `_acceptsSemanticDismiss` is stricter: exposed, current, still attached to the same active presentation. These are two policies because semantic tree presence and authority to execute a stale action are different invariants.

The notifier carries invalidation only. It does not mirror route state. Reveal, logical successful pop, relinquishment and forced disposal invalidate it at their existing ownership transitions. Model-frame notifications mark semantics dirty only while the subtree is eligible, allowing semantic geometry to be recomputed from the painted Flow transform. A render object reads the live derived policy when semantic children are visited. It never changes the route or model while assembling semantics.

### Dominant flows

1. **Closed source activation.** Wrap the existing source input widget in one Semantics button node with its optional label and explicit `_activateFromSemantics` action. Set `excludeFromSemantics: true` on command-mode GestureDetector so there is one semantic action owner. The handler rechecks mounted source and route ancestry before changing anything. A current own hidden preparation may be explicitly activated through its existing route; it cannot be rejected solely because that preparation made the source's root route noncurrent. Other covering routes, closing or disposed presentations and detached sources must not accidentally acquire a new presentation. The accepted operation uses the same transfer, command envelope and canonical owner clock, explicitly opens and reveals the motion, and wakes the owner. Existing real down still follows the original early push and model-driven arming/reveal path.
2. **Hidden preparation.** The gate on the barrier excludes its entire semantic subtree, including the SDK ModalBarrier's BlockSemantics. The page gate excludes all popup semantic descendants. Hit testing retains the current pending-barrier rules. Root push still has Navigator observer/currentness/traversal effects; this candidate does not call it invisible.
3. **Visible presentation.** The barrier gate exposes the existing barrier blocker. Keep measured pointer mode's `dismissible: false`; do not install a new barrier tap recognizer as an accidental semantic fix. Wrap content with SDK `Semantics(scopesRoute: true, explicitChildNodes: true)` and, if supplied, a named route semantic node. Expose one `onDismiss` action at this route boundary. Ordinary child actions and PopScope remain mounted in the same policy/content subtree.
4. **Accessible dismissal.** The callback captures the specific route identity. Immediately before calling `navigator.maybePop()` it rechecks the route's live eligibility. It never calls `pop` or manually pairs `willPop` with a later pop. Existing SDK and prototype async admission still own veto, local history, coalescing and post-await validity. A later semantic invocation against a closing, covered, removed or replaced presentation is a no-op and cannot target the revealed underlying page. A callback that was already admitted still follows the existing async protocol; this candidate does not promise new post-success atomicity.
5. **Logical pop and retained tail.** Successful `didPop` immediately changes the route's logical state and invalidates the gates; the next semantics assembly drops both blocker and content regardless of whether the widget tree has rebuilt. The underlying page semantics return while retained Flow/editor/policy content may continue painting. Stored stale actions still have route identity guards. Semantics cannot become synchronously invisible on the operating system between Flutter frames; the promise is live-state admission plus next-flush tree exclusion.
6. **Geometry.** Flow still owns painting and its transform. `_onModelFrame` requests semantic recomputation without requiring widget rebuilds. Test actual transformed semantic bounds over opening samples. If an ancestor mark alone does not update descendant transformed bounds, this shape needs a tightly scoped Flow-adjacent invalidation target or loses to the SDK widget candidate. Do not assert that render-level invalidation is already proven merely because it is plausible.

The source node is ordinary SDK Semantics; the route gates control lifetime, not accessibility vocabulary. Route scope/name/actions remain SDK widgets instead of reimplementing SemanticsConfiguration in the gate. This keeps interface depth high: callers provide names and ordinary content while the callee hides lifecycle, currentness and transport rules. Per boundary-discipline, every platform callback revalidates at entry; per single-source-of-truth, route state is read rather than duplicated; per idempotence, repeated inaccessible callbacks cannot mutate another presentation.

## Synthesis decision

Pending parent synthesis. This is a same-model independent candidate, not a second-model opinion. Prefer this candidate only if testing demonstrates a concrete semantic lifecycle/geometry benefit that the simpler SDK widget boundary cannot provide. Otherwise reject the render extension and retain only its live-state action guards and explicit separation of exposure from execution authority.

## Tradeoffs accepted

- We accept render attachment/listener management in exchange for excluding retained children from live route state without relying on an intervening widget rebuild.
- We accept one private invalidation signal in exchange for keeping logical state on the route and avoiding parallel semantic visibility state.
- We accept host semantics-tree evidence in exchange for a bounded check that does not pretend to prove VoiceOver/TalkBack announcement or assistive focus behavior.
- We accept an optional probe naming API in exchange for leaving production localization and item-role contracts outside this reduced route experiment.

## Alternatives considered

- **SDK Semantics + ExcludeSemantics driven by a route listenable.** Smaller implementation and fewer custom rendering obligations, with the same public interface depth. It wins unless render-level invalidation fixes a reproduced gap. The concern is retained Flow geometry and logical transitions before widget rebuild, not a claim that SDK exclusion is intrinsically insufficient.
- **Separate semantic popup/presenter.** Rejected because it duplicates presentation, policy and focus lifetimes; callers or internal dispatch must choose between two ways of opening the same menu. It hides less complexity than it introduces.
- **Opacity/IgnorePointer/Flow paint omission as semantic policy.** Rejected because public SDK behavior retains semantic descendants or BlockSemantics; optical or hit-test visibility does not encode semantic lifetime.

## Red-flag screen

The public module remains deep: only consumer names are exposed. There is no new route coordinator, no second motion instance, no phase enum mirroring existing state, no semantic event replay and no hand-synced list of item actions. The invalidation notifier is the main risk: every logical exit must notify. That is real temporal coupling and a potential hand-maintained transition list. If existing route listenables can express all transitions, reuse them rather than add `_semanticInvalidation`; if they cannot, the render shape must justify that extra protocol with a failing test. Additional semantic and pointer gates should not become separate wrappers with diverging lease/currentness rules; extend the one boundary only if selected.

## Open questions and risks

- Does a reproduced stale Flow semantic transform require render invalidation, or will SDK semantic widgets plus the existing frame notifications suffice?
- Should a source semantic tap during its own hidden raw-pointer preparation explicitly open that same presentation, and how should the still-held raw pointer be revoked before domain activation?
- Can the semantic source action reopen a logically closing retained owner without changing the raw reopen clock/transfer contract, or should that brief stale action safely decline until source authority returns?
- Which product labels and item roles belong to the eventual public menu API after this prototype boundary is proven?

These questions do not require stopping the prototype experiment. Prefer the narrower safe activation policy and characterize it explicitly instead of inventing raw-pointer continuation semantics.

## Verification and limits

Use host SemanticsTester and genuine `SemanticsAction.tap`/`dismiss` dispatch, not direct private handler calls, for the principal action tests. Cover: one labelled source button/action in both modes; domain activation opens pointer mode once without pointer samples; hidden preparation retains lower-page labels/actions; reveal blocks them; successful logical close restores them before disposal; route scope/name is present only while semantically exposed; retained child actions vanish without editor/policy recreation; PopScope veto and async deduplication; repeated or retained stale dismiss actions after cover, pop and removal cannot pop the underlying page; source stale actions do not open under another route; semantic bounds follow actual visible Flow transforms. Keep all existing pointer/time/replay/scene baselines unchanged. A geometry failure is a design signal, not permission to loosen expected bounds.

Native screen readers, focus return/announcement order, full menu item roles and keyboard semantics, arbitrary multi-View hosting, reduced motion and source transforms stay unproved. Do not change the measured model or production exports to pass this reduced boundary.

## Next implementation step

First reproduce hidden-barrier blocking, retained closing labels and Flow semantic geometry with the existing host; select the render boundary only if that evidence defeats the smaller SDK widget alternative.
