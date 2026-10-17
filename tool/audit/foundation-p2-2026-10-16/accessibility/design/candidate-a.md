# Candidate A: declarative semantic presentation

Independent same-model design attempt grounded at `65dce59f`. This is a sketch, not an implemented or tested result. No model/timing/tuning changes are proposed.

## Problem

A real root popup is prepared on a genuine source down before the measured model opens. That route must preserve its clock, early-push order, policy mount, editor and retained closing paint, but it must not own accessible modality during preparation or logical closing. A source semantic action must actually open the model; pushing the same hidden preparation route is insufficient. Semantic actions also outlive the semantics frame that exposed them, so live route checks remain necessary even when declarative exclusion is correct.

## Usage (caller’s view)

The widget remains one source/menu pair, with two optional descriptive labels. It does not expose a second presenter, accessibility controller, semantic lease or transport event.

```dart
ProbeMenuSource(
  pointerInput: true,
  semanticLabel: 'Show document actions',
  menuSemanticLabel: 'Document actions',
  menuBuilder: (_) => const DocumentActions(),
)
```

A real raw source down still enters the measured preparation path directly. A semantic tap on the labelled button calls the actual opening operation once, without PointerEvents. A caller using `source.currentState!.open()` gets an opening menu, including in pointer mode. The preparation distinction stays private.

```dart
final route = source.currentState!.open();
// The menu opens; this is not a raw hold preparation operation.
```

The menu consumer continues to use ordinary SDK policies and widgets. A semantic dismiss consults this same policy rather than installing its own permission flag.

```dart
PopScope<void>(
  canPop: canLeave,
  child: EditorActions(),
)
```

The default prototype strings can be `Open prototype menu` and `Prototype menu`. These fields permit consumer naming, not a localization framework. Existing `barrierLabel` can remain the prototype dismiss description for this experiment.

## Shape

### Data and module map

Keep all behavior in `menu_route_probe.dart`; keep the existing transfer and clock adapters. Add no public type. Route semantic visibility is derived from existing ownership and lifecycle fields, not stored as another lifecycle enum or boolean that can disagree with them.

```dart
class ProbeMenuSource extends StatefulWidget {
  final String semanticLabel;
  final String menuSemanticLabel;
}

class ProbeMenuSourceState {
  ProbeMenuRoute open();
  ProbeMenuRoute _prepare();
  void _semanticOpen();
}

class ProbeMenuRoute {
  final _semanticsChanged = ChangeNotifier();

  bool get _ownsSemantics; // revealed && live, current, owning presentation
  void _dismissSemantically();
  Widget _semanticPage(Widget stablePaintAndContent);
  Widget _semanticBarrier(Widget originalHitBarrier);
}
```

`_semanticsChanged` is an invalidation signal only. The route publishes when reveal, successful logical close, cover/uncover, relinquishment or disposal changes the answer. It does not publish model frames or maintain a duplicate truth. `ListenableBuilder(child: stablePaintAndContent)` updates only the semantic wrappers. The existing `_revealed` mount gate, theme bridge and policy child remain stable. Notify from the same lifecycle methods that write their source fields; dispose the notifier with the route. One small signal is justified because `changedInternalState` rebuilds the SDK barrier but does not force the cached `buildPage` content to rebuild.

The getter checks `_revealed.value`, `!closing`, `!disposed`, `isCurrent`, active route identity and current lease ownership. Hidden preparation and obsolete retained tails answer false. Under a cover the popup stops exposing its subtree; the covering route retains the SDK’s normal modality. No focus mutation or optical opacity threshold determines this answer.

### Opening boundary

Move the existing body of `open()` into `_prepare()` with no order or timing change. The real source Listener invokes `_prepare()` under precisely the existing condition after `handlePointer`. The session’s model-driven `present` callback also remains bound to `_prepare`, because the model is already open when it asks for presentation. This is essential to preserve the existing reopen path and handback counts.

Public `open()` calls `_prepare()` and, only in measured-pointer mode when it has not already opened, issues the existing transfer’s domain `open` command at the owning clock’s canonical time. Then it uses the existing phase synchronization/reveal path and resumes that owner’s clock. It neither synthesizes a pointer nor resets/recreates the model. Repeated activation on an already open current route is idempotent. The implementation must snapshot and revalidate target transfer, lease and route around callbacks exactly as the existing pointer adapter does; an onSample callback may remove or cover a presentation.

`_semanticOpen` first checks `mounted` and source-route eligibility, then calls `open()`. The existing strict `_sourceCanAcquire()` is correct for a closed source but rejects its own hidden root preparation. That retained source action needs a narrowly defined exception: the route must be this session’s current, hidden, nonclosing, owning preparation, created while the source was eligible. All other nested source route ancestors must still be current. Capture the prepared root source route identity if necessary and exempt only that route from the currentness check, rather than broadly exempting every noncurrent ancestor. A newly covering root or nested route rejects the action. Before semantic activation, revoke any genuine held sequence using the existing domain cancellation boundary; its later physical up must not commit another action. Revalidate eligibility/ownership after cancellation callbacks before opening. Programmatic `open()` retains its explicit caller-controlled role; source action admission is not silently imposed on every programmatic call.

Wrap the existing source hit widget with `Semantics(button: true, label: ..., expanded: ..., onTap: _semanticOpen)`. Give command-mode GestureDetector `excludeFromSemantics: true` to avoid a second tap action, while preserving its real recognized pointer `onTap`. The raw Listener remains unchanged. Hidden preparation reports collapsed because accessible presentation has not started.

There is a migration cost: existing pointer-mode tests that called public `open()` to construct hidden preparation must instead use an actual TestGesture down. Inventory these call sites before changing the meaning. A new public `prepare()` API solely to avoid updating tests exposes the internal temporal protocol and should be rejected.

### Semantic tree and dismissal

The stable page is wrapped in `ExcludeSemantics(excluding: !_ownsSemantics)` and a route scope with `scopesRoute: true`, `explicitChildNodes: true`, and one named route child (`namesRoute: true`, label `menuSemanticLabel`). Do not replace the Flow or policy child when this bool changes. The rendered tail survives logical close, but its obsolete labels and child actions disappear from the assembled semantic tree on the next semantics pipeline update.

Make exactly one accessible dismiss action, owned by the route scope or the barrier’s explicit semantic node. Prefer the route scope, so the action belongs to the named presentation and is independent of whether the physical barrier is a raw hit surface or a GestureDetector. Do not leave the SDK command-mode barrier’s dismiss action as a duplicate.

To keep pointer behavior intact while controlling semantics, wrap the original barrier in an inner `ExcludeSemantics` that removes its incidental SDK semantics, then an explicit outer `BlockSemantics` and lifetime `ExcludeSemantics`. The outer blocker is present only while `_ownsSemantics`; the original raw/command barrier still controls the exact same physical input and layout. Removing the inner SDK BlockSemantics via exclusion is deliberate; the explicit outer blocker replaces its semantic responsibility. Test the assembled tree rather than relying on the wrapper diagram.

```text
ExcludeSemantics(excluding: !ownsSemantics)
  BlockSemantics
    ExcludeSemantics
      original physical modal barrier

ExcludeSemantics(excluding: !ownsSemantics)
  Semantics(scopesRoute, explicitChildNodes, onDismiss: guardedDismiss)
    Semantics(namesRoute, label: menuSemanticLabel)
      existing retained paint/content subtree
```

`_dismissSemantically` checks the live `_ownsSemantics` predicate and Navigator mountedness synchronously, then calls `navigator.maybePop()` once. The existing `willPop` attempt deduplication, PopScope, LocalHistoryEntry behavior and Navigator revalidation perform the actual decision. Do not call `pop` directly, manually issue a model close, create a second async permission future, or clear an existing committed item action. Repeated/stale callbacks after logical close, cover, route replacement, source loss or final disposal become no-ops rather than popping a lower page. Source loss alone does not revoke an independently live popup, so dismissal should remain valid for that route.

### Geometry boundary

The parent’s executable semantic-bounds test now reproduces stale geometry after correcting root physical coordinates by View DPR: expected left `29.89416948953169`, actual `29.993305998578332`, corresponding to a previous opening frame. This is real evidence for a render-level correction, distinct from semantic lifetime.

Keep the existing Flow delegate and add a private Flow subtype whose `createRenderObject` returns a `RenderFlow` subtype. Override `markNeedsPaint` to call `super.markNeedsPaint()` and `markNeedsSemanticsUpdate()`. The SDK delegate repaint subscription then dirties both paint and semantics for exactly the same frames, and semantics reads the transform recorded by the current paint. Preserve all SDK delegate/clip update behavior through the inherited widget implementation. Verify the same test over opening and release/handback. This is the smallest candidate bridge, subject to the test proving that this exact invalidation reaches transformed child nodes. If semantics caching still skips children, inspect the concrete semantic subtree transform update before adding a broader proxy.

Do not introduce a parallel geometry model, a second ticker, per-frame page rebuilds, global semantics scheduler, or an abstract render framework. The custom render subclass repairs Flow frame invalidation only; SDK `ExcludeSemantics` still owns accessible lifetime.

### Interface depth and red-flag screen

Two labels plus the existing opening operation hide raw preparation, route lifetime, model ownership and SDK dismissal policy. Callers do not coordinate semantic stages. There is one route-owned semantic decision, one model, one transfer lease, one action admission boundary and one SDK pop protocol. The new signal publishes a derived view without owning domain state. No public temporal flags or per-caller caches leak the implementation. This follows boundary discipline, single-source-of-truth and interface depth while accepting explicit lifecycle notifications as the smallest seam in the cached route page.

## Synthesis decision

Candidate only; parent synthesis selects the base and any graft. This attempt does not claim consensus or a second model.

## Tradeoffs accepted

- Accept one private route invalidation signal in exchange for stable policy/editor/Flow subtrees and no per-frame page rebuild.
- Accept a bounded public `open()` semantic correction and test setup migration in exchange for an honest operation that opens in both modes.
- Accept the existing early root push’s currentness, observer and focus-traversal effects in exchange for unchanged measured pointer behavior; semantic exclusion does not make the route fully invisible.
- Accept host semantics-tree evidence in exchange for deferring VoiceOver/TalkBack announcement and assistive focus claims until real-device work.

## Alternatives considered

- Extend `_MenuHitGateRender` to own semantic visitation and blocking. This unifies hit and semantic gating in one render proxy but hides different lifetimes behind a pointer-oriented abstraction; its reader must understand semantic blocking, scope assembly, geometry invalidation and route retention in one custom mechanism. Public SDK widgets express that policy more directly, so this candidate rejects it unless the executable geometry reproducer demonstrates a precise render-level need.
- Replace `_revealed`, `closing`, ownership and disposal with a new presentation state enum. That could encode more invariants, but this bounded accessibility task would then refactor dismissal/sampling lifetimes and many existing call sites. A parallel enum without deleting old writers is split ownership and loses outright.
- Push the popup only on accessible reveal, or use a second accessible presenter. Either changes raw early-push behavior or creates a second model/policy/route protocol; both expose more coordination than two labels and one opening operation.

## Verification and remaining risks

Required tests: one labelled collapsed source button/action; semantic activation opens once in pointer mode; real hidden prep retains page labels and focus; retained source semantic activation during its own hidden prep revokes the held physical sequence and opens once; the same action is rejected after a root or nested cover; reveal blocks page and supplies one scope/name; one dismiss action in both modes; PopScope veto then success; async duplicate/cover/removal invalidation; stale source callback admission; logical close releases page semantics during visual retention; policy/editor state survives semantic changes; dynamic semantic bounds follow actual opening geometry. All existing recorded inputs, routes, handbacks and optical frames must remain unchanged.

Questions retained for later product work: what are the final localized source/menu/dismiss names, menu item roles and keyboard semantics? What does real VoiceOver/TalkBack do with route announcement and focus restoration across this early root preparation? These do not block the bounded prototype implementation, and no host test resolves them. Reduced Motion, cross-View source geometry, text scaling and native IME behavior remain outside this claim.

## Next implementation step

Keep the new failing accessibility harness as the boundary, introduce private preparation versus actual activation first, then apply the declarative lifetime wrappers while preserving replay metrics and retained-state tests.
