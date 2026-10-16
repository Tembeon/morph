# Candidate A: source subscriptions, SDK captures, route-owned publication

## Problem

The root popup owns Navigator, ModalRoute, PopScope, focus and motion lifetime, while source-local appearance belongs to the launching subtree. The present builder closure transports neither appearance nor inherited lookup scope. Existing history and the approved foundation review require live local theme values and retention after source loss, so a one-time SDK capture alone is insufficient. Preserve that behavior with public `InheritedTheme.capture` and a source-lifetime subscription; do not restore flight, a generic context carrier, or per-frame ancestor walks.

## Usage (caller's view)

Existing source syntax stays unchanged. A theme above the target Navigator remains ordinarily inherited; local themes below it are carried automatically:

```dart
WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, child) => AppAppearance(child: child!),
  home: DefaultTextStyle(
    style: const TextStyle(fontSize: 21),
    child: ProbeMenuSource(
      menuBuilder: (context) => const EditorMenu(),
    ),
  ),
);
```

Source-local icon and custom `InheritedTheme` values can change while the menu is open. Provided the same captured theme kinds retain the same nesting order and stable wrap structure, those updates keep EditorMenu State, focus and PopScope membership:

```dart
IconTheme(
  data: IconThemeData(size: selectedSize),
  child: ProbeMenuSource(menuBuilder: (context) => const EditorMenu()),
);
```

The menu builder receives the popup context. Page-specific non-theme data is supplied explicitly; it is not discovered from that context automatically:

```dart
final selection = SelectionScope.of(context).selection;
return ProbeMenuSource(
  menuBuilder: (popupContext) => SelectionScope(
    selection: selection,
    child: const EditorMenu(),
  ),
);
```

This third example captures an ordinary value at the caller's chosen time. The prototype does not gain an open-route builder replacement API or promise updates to arbitrary captured closures.

## Shape

All additions stay private in `example/lib/proto/menu_route_probe.dart`. No production file, public parameter, dependency, tuning, clock or model changes.

```dart
class _SourceThemes {
  const _SourceThemes(this.capture, this.themes);

  final CapturedThemes capture;
  // Nearest unique themes in SDK capture traversal order.
  final List<InheritedTheme> themes;

  bool sameValues(_SourceThemes other) => throw UnimplementedError();
  bool sameKinds(_SourceThemes other) => throw UnimplementedError();
}

_SourceThemes _captureSourceThemes(
  BuildContext source,
  BuildContext targetNavigator,
) => throw UnimplementedError();

// Additions to existing State; source lifecycle owns subscriptions only.
class ProbeMenuSourceState extends State<ProbeMenuSource> {
  @override
  void didChangeDependencies() => throw UnimplementedError();

  ProbeMenuRoute open() => throw UnimplementedError();
}

// Additions to existing route; route owns all published/pending snapshots.
class ProbeMenuRoute extends PopupRoute<void> {
  ProbeMenuRoute._(this._session, this._builder, _SourceThemes initial)
    : _initialKinds = initial,
      _themes = ValueNotifier(initial);

  final _SourceThemes _initialKinds;
  final ValueNotifier<_SourceThemes> _themes;
  _SourceThemes? _pendingThemes;
  bool _themePublicationQueued = false;

  void _queueThemes(
    _SourceThemes latest,
    NavigatorState target,
  ) => throw UnimplementedError();
}
```

The sketches show additions, not a replacement of the real class inheritance, constructors or existing members. `_initialKinds` can instead be an immutable `List<Type>` if implementation finds retaining the initial widget references unnecessary; no separate enum or registry is needed.

### Capture and dependencies

`_captureSourceThemes` has one boundary walk from source up to the selected root Navigator context. During that walk it uses public `source.dependOnInheritedElement(element)` on encountered `InheritedElement`s whose widgets are `InheritedTheme`. The same walk records the nearest instance of each runtime type in traversal order. Subscription is its purpose; it does not implement wrapping. `InheritedTheme.capture(from: source, to: targetNavigator)` remains the sole capture/wrap implementation. Freeze the recorded theme list with `List.unmodifiable`.

The cutoff is a real ancestor obtained from `Navigator.of(context, rootNavigator: true)`; there is no null-cutoff fallback. Registration may include shadowed theme ancestors for simplicity, while the recorded list remains nearest-per-kind. Such an upstream change may cause one extra capture, but `sameValues` compares theme widget identities and suppresses redundant publication. `sameKinds` compares length and ordered runtime types. The two operations derive from this one recorded list; no hand-maintained set of theme classes exists.

`didChangeDependencies` captures after the existing View update and queues that capture to each still-alive route belonging to this source session with the same selected target Navigator. `open` captures synchronously before pushing a new route and passes that snapshot into its constructor. Therefore hidden preparation has complete initial data without mounting menu content, and the first revealed frame never depends on an after-the-fact source callback. Reopening gets a fresh route-local initial snapshot and its own topology baseline. Existing nonclosing-route reuse retains the current contract. A source globally reparented to a different root cannot publish its new-root capture into the old presentation: validate `identical(route.navigator, target)` at the queue boundary. Do not retain the source context to check that later. Cross-root migration itself remains unproved.

This is deliberately an invalidation path, not a motion listener. No motion callback, paint or Flow delegate performs an ancestor lookup. Source dependency invalidations unrelated to appearance may do a redundant capture; widget-identity comparison prevents a redundant theme notification. Avoid adding another refresh service to eliminate a small, bounded tree walk.

### Safe publication and lifetime

`_queueThemes` validates target Navigator identity, route disposal and initial theme-kind compatibility, replaces `_pendingThemes` with the latest accepted immutable snapshot, and queues at most one post-frame callback. Assignment to this private pending field does not notify an Element while source dependencies are updating. In the callback, take and clear the pending value and queued flag before notification; check disposal again; assign `_themes.value` only when the relevant theme widget identities actually differ.

The route callback closes over the route, never the source State or BuildContext. Source disposal neither performs inherited lookup nor tries to notify a sibling popup synchronously. A latest valid capture already queued during that final source frame can still publish after source disposal because the route independently owns it. The snapshot remains then, and updates above the target Navigator continue through the normal popup context. A disposed route drops pending data and disposes its notifier; a stale callback becomes a no-op. An old route cannot overwrite a replacement route because no shared mutable current-capture channel exists. Closing-but-not-disposed routes can receive compatible appearance updates until their own teardown, independently of the new route's initial capture.

Post-frame scheduling here is always initiated by source dependency processing during a frame. If implementation later exposes `_queueThemes` outside that path, it must request a frame as appropriate rather than assume `addPostFrameCallback` schedules one. Initial `open` data is synchronous and does not need such scheduling.

### Stable content placement

Inside the existing revealed branch, retain this stable sequence:

```text
Flow
└─ ValueListenableBuilder<_SourceThemes>
   └─ current.capture.wrap(stableChild)
      └─ _MountedMenuPolicy(route: this, builder: originalBuilder)
```

Use the ValueListenableBuilder `child` parameter for one stable `_MountedMenuPolicy` widget, rather than reconstructing or keying user content from a capture identity. The captured wrappers sit outside the policy/content subtree; the builder's own context consequently sees carried themes while ModalRoute/Navigator/PopScope still resolve to the popup. Compatible wrappers update their inherited widgets and notify interested descendants. A true inherited change may rebuild consumers; this is correct, and is distinct from rebuilding content for every motion frame. Hidden preparation still builds only the existing shrink branch. The policy-ready post-frame protocol remains unchanged.

### Topology contract

An open route accepts value changes only while the nearest theme runtime-type sequence matches its initial sequence. A changed sequence retains the last accepted snapshot for that route; a newly opened route captures the new sequence. This explicitly preserves the old fixed-kind continuity tradeoff with a small check, rather than silently remounting the editor when a theme is inserted or removed. The limit must appear in the probe's documentation and test names. Do not throw during ordinary app build or introduce an application-wide registry.

This check is necessary but cannot guarantee arbitrary custom `InheritedTheme.wrap` behavior: a custom theme may change wrapper runtime type or child topology depending on values. State preservation is guaranteed only for stable SDK/custom wrap topology. The bridge does not deeply clone mutable theme data, resolve all custom theme values at the source, or prove hostile implementations safe.

### Explicit non-theme policy

The root popup inherits target/root `MediaQuery`, `Localizations`, `Directionality`, Actions, Focus, ModalRoute and Navigator live. Source-local overrides of these values are deliberately not copied in this unit. That means a source-local RTL or locale override alone does not change popup direction/locale. A caller requiring a page-specific override may explicitly wrap its menuBuilder result. Do not describe this limited policy as generic inherited-context parity or as final locale/RTL product behavior.

Keeping destination MediaQuery is substantive: view dimensions, insets, keyboard state, text scale, platform brightness and accessibility flags remain live without a source refresh or surviving source Element. Copying all source MediaQuery fields would mix source layout consumption with fullscreen presentation geometry. Root locale/delegate updates continue naturally; no extra Localizations loader can delay first policy mounting. Arbitrary providers remain explicit caller data, or shared app ancestors above root Navigator.

This design hides capture, dependency wiring, coalescing and lifetime safety behind the existing source API. The only exposed complexity is the actual context boundary and the bounded stable-kind contract. Per boundary-discipline, validation occurs at capture/publication; motion and content do not know about theme subscriptions.

## Synthesis decision

Candidate A proposes itself as the base. The parent comparison must record its actual decision; this document does not manufacture agreement with another candidate or another model.

## Tradeoffs accepted

- We accept two bounded ancestor traversals per source dependency invalidation in exchange for public SDK capture rather than a bespoke theme-cloning engine. Neither traversal runs on a motion tick.
- We accept one-frame publication latency for live local appearance in exchange for safe route notification after the source build phase. Initial presentation captures synchronously.
- We accept fixed captured kinds for each open presentation in exchange for preserving content State and the current small wrapper model. Reopen adopts a new topology.
- We accept destination semantics for all non-theme inherited channels in exchange for live root system integration and preserving actual popup route policy ownership.
- We accept SDK snapshot semantics, including retained original theme widget references, in exchange for removing stale source-context reads; this is not a claim that no captured widget can retain a closure or subtree reference.

## Alternatives considered

1. **One-shot capture at open:** genuinely simpler route-only data, same tiny caller interface and excellent detach safety. It loses the explicitly planned live local theme behavior; SDK root updates alone do not replace that behavior. It could become the product policy only by consciously revising the prior requirement, so it is not the preferred replacement here.
2. **Source-owned portal/inherited subtree plus root projection:** keeps arbitrary inherited dependencies live with less selective cloning, but transports content ownership back under the source and must reconstruct destination modal/focus/policy semantics and source-loss lifetime. The caller interface can look small while hiding a substantially deeper reparenting protocol; it breaks the strongest existing root-route invariants.
3. **One mutable carrier shared across every session route:** exposes no new public parameters, but creates shared capture ownership and lets an old queued source update affect a newly opened route or unrelated closing presentation. Route-local pending snapshots are simpler to reason about and type-localize stale callback safety.

## Falsifiable validation

Run new WidgetsApp-only tests before implementation to demonstrate the missing behavior, then unchanged legacy suites after implementation:

1. A source-local DefaultTextStyle, IconTheme and one custom InheritedTheme appear in the root popup, including source under a nested Navigator. The popup builder still resolves its own ModalRoute and the root Navigator; its PopScope veto remains effective.
2. Change a local theme value while the menu remains open. After post-frame publication, the popup observes the new value, the stateful editor's identity/init/dispose counts stay stable, focus stays with its node, and no framework build-phase exception occurs. Several updates before publication produce the latest value.
3. A shared custom theme above root Navigator updates with source unchanged, proving the capture cutoff did not freeze it. A captured local override of the same type deliberately continues to shadow that root value.
4. Remove only the source: popup content, modal policy, latest queued capture and subsequent root environment updates survive. Disposing the popup before a queued publication gives no exception; reopening cannot receive an older route's pending value.
5. Change a source-local theme-kind sequence while open: last compatible snapshot and editor State remain; the next new route gets the changed kind sequence. Distinguish this from compatible ordinary value refresh.
6. Hidden pointer preparation captures but mounts neither builder nor PopScope. A value change before reveal appears on its first real mount; removal during preparation follows existing lifecycle policy without querying an inactive context.
7. Root MediaQuery metrics/text scaling/accessibility, root locale and root Directionality change while open and after source removal. Consumers see destination updates. Deliberately distinct source-local versions are not copied. Ordinary source-local provider lookup from popup context fails/uses its documented absence; explicit re-provisioning works.
8. No motion frame alone recaptures themes or notifies theme content. Existing replay/async/scene metrics, handbacks, measured timings and clocks are unchanged.

These tests must assert observed inherited values, identity and policy, not mirror private helper calls or count arbitrary implementation traversals. Localizations async behavior and multi-View migration remain separate unproved contracts.

## Open questions and risks

- Should a future product API intentionally transport source-local Directionality/locale, or keep this destination-context policy? This unit documents the bounded default without blocking its theme experiment.
- Is fixed-kind retention the eventual product behavior when users dynamically change inherited topology, or should such a change dismiss/recreate a presentation? Historical behavior supports retention, but a larger promise needs a separate state-preserving design and evidence.
- Can custom theme wrap implementations in real consumers change topology for ordinary value updates? The generic SDK capture boundary cannot guarantee their State continuity; inspect actual custom MorphTheme.wrap before promotion.

## Next implementation step

First add a failing source-local theme value refresh test with retained editor State and popup PopScope, then implement the private source dependency capture and route-owned post-frame publication without touching motion or first-mount policy.

## Red-flag screen

No new public staging methods, framework transport types, registry, duplicated theme-kind declaration, cross-file capture protocol, shared mutable current capture, or second product wrapping API is added. The private capture helper owns dependency knowledge and the route owns publication knowledge. The principal residual complication is deliberate fixed-kind validation; it protects the same content continuity invariant as the historical carrier instead of adding speculative generic context machinery. The candidate is source-derived and synthesized by one runner, not an independent multi-model consensus.
