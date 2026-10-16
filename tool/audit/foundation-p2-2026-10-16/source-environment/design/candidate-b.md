# Candidate B: presentation-owned local-theme snapshot

Independent same-model design run against `65b080d3a0ff178d57509f2f5fc9613ef88fafce`. Read task, how/why grounding, architect runner/rationale/red flags, installed SDK framework dependency rules and the current probe source. This is a design artifact; no production/probe edits or tests were performed. The live-local requirement is deliberately challenged rather than silently discarded.

## Usage (caller's view)

The ordinary caller keeps exactly the current interface:

```dart
ProbeMenuSource(
  menuBuilder: (context) => MenuContents(),
)
```

An application-wide theme belongs above the root Navigator and remains live:

```dart
ApplicationGlassTheme(
  data: appTheme,
  child: WidgetsApp(
    color: const Color(0xff000000),
    builder: (context, child) => child!,
    home: ProbeMenuSource(
      menuBuilder: (context) => MenuContents(),
    ),
  ),
)
```

`ApplicationGlassTheme` denotes the consumer's own public `InheritedTheme`; it is not a proposed morph dependency or newly implemented prototype type. A source-local override becomes presentation data captured at creation:

```dart
DefaultTextStyle(
  style: localStyle,
  child: ProbeMenuSource(
    menuBuilder: (context) => StatefulEditorMenu(),
  ),
)
```

Changing `localStyle` after this presentation was created affects the source and the next newly created presentation. It does **not** update the currently open presentation. No refresh method or boolean mode is added. An app that requires an already open menu to react places that environment above the root Navigator, or explicitly passes a domain controller into its menu content; the latter is ordinary menu state, not a second theme-transport API.

## Problem

Root popup content needs the source's local appearance without accidentally inheriting the source page's ModalRoute, Navigator, Focus, TickerMode, MediaQuery or unrelated providers. The SDK gives a purpose-built immutable capture object. A live source bridge adds dependency registration, lifecycle and deferred-publication work even though the presentation already owns independent content lifetime. This candidate keeps that independence absolute: one presentation, one captured local environment. It matches the SDK capture semantics and avoids new synchronization entirely, at the concrete cost of the previous live-local promise recorded in `foundation-review.md:72` and old carrier behavior. That is a contract change, not an equivalent replacement.

## Shape

### Data and type sketch

No new file or public type is required. The changes belong in the existing `example/lib/proto/menu_route_probe.dart`:

```dart
class ProbeMenuSourceState extends State<ProbeMenuSource> {
  ProbeMenuRoute open() {
    // Return a current nonclosing presentation unchanged, as today.
    // For an actual new route, resolve rootNavigator once.
    // Capture source-local themes to that exact Navigator context.
    // Pass immutable capture and existing WidgetBuilder to the route.
    throw UnimplementedError();
  }
}

class ProbeMenuRoute extends PopupRoute<void> {
  ProbeMenuRoute._(
    _MenuSession session,
    WidgetBuilder builder,
    CapturedThemes themes,
  ) : throw UnimplementedError();

  final CapturedThemes _themes;
  final WidgetBuilder _builder;

  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // Existing hidden/revealed gate remains outside content mounting.
    // Only revealed content gets _themes.wrap(existing stable policy branch).
    // The builder context stays inside the popup modal scope.
    throw UnimplementedError();
  }
}
```

The signatures show ownership rather than compilable replacement class declarations. `CapturedThemes` is already a public SDK type; it is private route data and is not added to the caller API. There is no mutable capture registry, source-context field, notifier, revision number, route callback or extra controller.

The only acquisition site is a real new `open`: `final navigator = Navigator.of(context, rootNavigator: true)`, followed by `InheritedTheme.capture(from: context, to: navigator.context)`, then construction/push on that same Navigator. The SDK validates the ancestor boundary. Do not fall back to `to: null` if the topology is wrong; that would silently freeze shared app themes.

### Flow and lifetime

1. A real source hit/programmatic call selects its presentation Navigator, captures local theme widgets once, and constructs a new popup.
2. Early pointer-mode installation still has zero content-builder calls while hidden. Capturing ancestor widget references is not mounting content.
3. Reveal mounts the same policy/content subtree under the captured wrapper chain. The chain never changes for that presentation, so ordinary motion frames and source theme updates cannot replace editor State or PopScope.
4. Popup descendants inherit root modal identity, Focus/Actions, current root MediaQuery, root localization and direction normally. Only local `InheritedTheme` instances below the cutoff shadow root values of the same theme runtime type.
5. Source disposal needs no detach protocol for this feature: the capture owns widget/data references, not a source BuildContext. Route clocks, selected-action semantics, input revocation and close-policy lifetime stay unchanged.
6. A new presentation obtains a new snapshot. Reusing a nonclosing presentation does not recapture. Reversing/closing behavior follows existing route-creation rules, not a new environment epoch.

This is one file and one private field. Interface depth is high: the unchanged two-widget caller hides Navigator-boundary acquisition and deferred content mounting, while the SDK owns capture/wrap behavior. The immutability of `_themes` encodes the invariant rather than duplicating a revision protocol (`encode-lessons-in-structure`, `single source of truth`).

### Explicit non-theme policy

- Root MediaQuery stays live, including view size, keyboard insets, text scaling, brightness and accessibility flags. Source-local MediaQuery overrides are not copied. No speculative per-field merge.
- Root Localizations and root Directionality stay live. Source-local locale, delegates and explicit RTL/LTR overrides are not copied. Consumers requiring them in menu content must provide an explicit content scope; no automatic `Localizations.override` with asynchronous resource loading.
- Arbitrary providers and custom InheritedWidget scopes are not transported. Shared services can be above root Navigator or explicit content dependencies.
- ModalRoute/Navigator/PopScope/Focus/TickerMode remain destination-owned. No transplanted source route identities or source TickerMode snapshot.
- A captured local theme may itself contain already-resolved data derived from upstream state. That local snapshot can shadow future upstream changes of the same type. “Root stays live” applies to uncaptured shared ancestor inheritance and destination reads; it is not a promise to recompute the contents of a frozen local theme.
- Third-party theme `wrap` implementations still run in the destination environment. This is SDK widget capture, not deep serialization or freezing arbitrary mutable payloads.

## Concrete evidence against apparently live alternatives

**Route-owned direct cross-tree subscriptions are invalid.** An appealing alternative is for a popup boundary to walk the source ancestors and call its own `dependOnInheritedElement` on those elements. The public method does record the dependency, but installed SDK `widgets/framework.dart:6428–6447` asserts in `InheritedElement.notifyClients` that every dependent really is its descendant. `:6280–6283` also asserts an inherited element has no remaining dependents when deactivated. The popup belongs to a sibling route branch. This technique violates framework invariants; no custom Element should smuggle a foreign dependency into them.

**Source-owned OverlayPortal is a different identity contract.** It naturally retains source inherited environment, but the content then remains in the source element ancestry. Its own ModalRoute/PopScope/Focus lookups cannot become the destination popup's merely because rendering targets the root overlay. Recreating Flutter's private modal scope or building duplicate route-policy trees would lose the current small public SDK boundary. It is not an acceptable graft to this probe.

These observations leave an actual source observation/publication bridge as the honest live alternative. They do not prove live updates impossible or undesirable; they show that “just let the route observe the source” hides real additional machinery.

## Falsifiable evaluation

The following are candidate B's acceptance tests, using WidgetsApp without Material/Cupertino and the real source/root popup harness:

| Experiment | Required B result |
|---|---|
| Local DefaultTextStyle and custom InheritedTheme below nested Navigator | Initial root popup sees nearest source-local values |
| Same theme above root Navigator changes while popup open | Popup sees new value through ordinary destination inheritance |
| Root MediaQuery insets/text scale/accessibility or localization changes | Popup sees current destination values without reopening |
| Source local theme value changes while popup open | Popup retains initial local value; source updates |
| New presentation after prior close | New local value is captured |
| Theme change during hidden preparation | First revealed content still uses creation snapshot |
| Remove source and its local theme ancestors while menu remains open | No source lookup/assertion; menu/editor State survives |
| Replace local theme type chain while menu remains open | Existing popup wrapper topology stays unchanged; next presentation gets new chain |
| Source has provider/local Directionality/Localizations/MediaQuery | None crosses implicitly; root counterpart remains observable |
| Menu has PopScope and editor FocusNode | Popup owns PopScope route; state/focus survive motion samples |

Two deliberate counterexamples reject B under the current agreed live contract: change only a local theme's value after reveal, then inspect popup; and change that value between hidden preparation and first reveal. Both should fail a test expecting the new local value. These failures must be recorded as requirement conflicts, never redefined away in a green suite.

The case for choosing B is falsifiable: if all actual required live themes are above root Navigator, while no accepted caller needs local updates in an open presentation, the simpler snapshot has sufficient behavior. Existing plans and old tests currently provide evidence **against** that premise. Without a conscious requirement change, B should lose synthesis despite its lower implementation complexity.

## Red-flag screen

- No shallow public helper, hand-synced theme-type list, global registry or duplicate theme transport path.
- One presentation owns one environment snapshot; source and route cannot race to write it.
- No source/route notification ordering contract leaks into callers.
- Theme topology remains fixed by construction; a copied SDK wrapper chain cannot replace itself during local value changes.
- The central defect relative to the task is a visible behavioral contract gap, not hidden implementation fragility. It is substantial: old live-local support would regress.

## Synthesis decision

Not filled in by this candidate. Compare against source-driven live capture on correctness before counting helper classes. B is suitable only if the live-local promise is withdrawn; with that promise retained, use it as the rejected simpler alternative and preserve its immutable-after-detach principle in the live design.

## Tradeoffs accepted

- We accept stale source-local appearance during a presentation in exchange for no cross-branch subscription, post-frame publication or detached-context risk.
- We accept that changes before first reveal still use creation-time appearance in exchange for a single acquisition boundary with no deferred source access.
- We accept explicit consumer content scopes for source-local non-theme data in exchange for correct root system and modal integration.
- We accept immutable theme payload and valid custom wrap behavior as SDK contracts in exchange for using the SDK's capture algorithm unchanged.

## Alternatives considered

1. **Source-driven live capture plus deferred route publication:** preserves recorded behavior and unchanged caller API, but owns a source subscription lifetime and a second update boundary. More machinery than B, deeper functionality; strongest alternative and likely synthesis winner under the existing requirements.
2. **Source-owned portal content:** retains automatic live source context, but wrong destination modal identity for PopScope/Focus and ordinary route lookups. Fixing those identities would introduce framework-like scope machinery and expose a less predictable caller contract.
3. **Route-owned cross-tree inherited dependencies:** superficially very small and immediate, but contradicts actual SDK descendant/deactivation invariants. Rejected before implementation.
4. **Caller-managed refresh/controller:** shifts synchronization onto every caller and makes theme freshness a separate application protocol. Lower interface depth despite easy internals; rejected.

## Open questions and risks

Is the already recorded live-local promise still required? The prior plan and current task say yes, so this candidate cannot be selected unchanged. Could source-local locale/direction ever be a product requirement? That needs its own explicit bridge/loading contract regardless of snapshot versus live themes; this candidate does not settle it by copying arbitrary scopes.

## Next implementation step

Build the initial-capture/root-live/source-detach tests and retain the live-local update counterexample as a failing requirement discriminator before deciding whether snapshot-only behavior is admissible.
