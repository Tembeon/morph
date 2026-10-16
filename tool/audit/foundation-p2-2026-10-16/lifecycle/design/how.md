# P2 early-route lifecycle: architectural explanation

Read-only inspection at `d121d18628242bfb7fefe54cc8df347542c82c79`. No tests or heavy jobs run; behavior below is source-derived unless an existing test is named. Flutter references are the installed public SDK under `/opt/homebrew/Caskroom/flutter/3.19.1/flutter/packages/flutter/lib/src/widgets/` (actual pinned SDK is newer than the folder name).

## Overview

The prototype prepares a real root `PopupRoute` immediately on source pointer-down, then delays menu content and focus until the measured model says the menu opens. This splits navigation lifetime from presentation lifetime. It preserves the original held pointer because Flutter cancels pointers already recorded by the Navigator when a new route is pushed. The source child Listener pushes before the ancestor Navigator records this same down.

This is a deliberate real-route tradeoff: the root route becomes current and observers see it during the invisible arming interval. Those SDK events cannot honestly be postponed while retaining an already-installed real route. The unresolved correctness issue is different: dismissal policy supplied by `menuBuilder` does not exist until reveal, and even the route's SDK modal scope does not exist synchronously at push time.

## Key Concepts

- `_MenuSession` owns the complete model, canonical time mapping, global raw-pointer routing, source/route clock transfer and active route identity (`example/lib/proto/menu_route_probe.dart:156`).
- `ProbeMenuRoute` is a normal pageless `PopupRoute` with an externally projected animation. `_revealed` controls content and `requestFocus`; `_pendingBarrier` controls whether the hidden barrier accepts hit testing (`menu_route_probe.dart:400,584,693,700`).
- There are at least three boundaries: route installation, first modal-scope mount, and menu-builder mount after reveal. Calling these all “mounted” hides the actual bug.
- SDK `PopScope` registers a `PopEntry` only in `didChangeDependencies` (`pop_scope.dart:194-201`). `WillPopScope` similarly registers its callback in `didChangeDependencies` (`will_pop_scope.dart:53-60`). A builder that has never run cannot contribute either policy.
- `_DismissAttempt` coalesces mounted asynchronous policy requests; identity invalidation and one successful claim protect against stale permissions and duplicate SDK consumers (`menu_route_probe.dart:390,444-559`). This protocol currently assumes the SDK scope already exists.

## How It Works

### Source-down preparation and pointer lifetime

The source Listener first sends the down into `_MenuSession.handlePointer`, then calls `open()` if this source owns the pointer and has no active route (`menu_route_probe.dart:133-141`). `open()` explicitly resolves `Navigator.of(context, rootNavigator: true)` (`114-120`). `install()` creates the route clock; `didPush()` acquires the complete model and pauses the source clock (`608-626,242-261`).

The source's Listener runs during hit-test dispatch before the ancestor Navigator Listener. Flutter `_afterNavigation` invokes `_cancelActivePointers` (`navigator.dart:5161`), and the ancestor records downs in `_activePointers` only in `_handlePointerDown` (`5898-5924`). This exact ordering is why early push preserves the originating pointer. Pushing at the measured hold deadline would cancel it: the existing negative control proves down→cancel rather than down→move→up (`example/test/proto/menu_route_input_test.dart:166-220`).

The session also installs a global pointer route (`menu_route_probe.dart:185-187`). `_pointer` suppresses duplicate downs and unrelated pointer continuations (`360-377`), while the transfer lease ensures only the active model owner mutates state (`menu_transfer_probe.dart:80-96`). Pointer move/up therefore survive even though the source is now below a modal route.

### What becomes real immediately

Flutter assigns the Navigator, calls `install` and `didPush`, queues observer notifications and flushes history synchronously during push (`navigator.dart:3252-3310,4584-4595,4621-4654`). `Route.isCurrent` reads the top present history entry (`581-594`), rather than animation progress or visual content. The prepared popup is consequently current immediately; the home root route is not current. Generic observers receive push and top-change now. The popup's zero-duration SDK controller and custom `_pushSignal` do not postpone these notifications.

`RouteObserver<R>` has a useful but precise filter: it sends the previous subscriber `didPushNext` only if both pushed and previous routes are `R` (`routes.dart:2500-2509`). `RouteObserver<ModalRoute>` therefore sees the hidden popup, while `RouteObserver<PageRoute>` ignores it because `PopupRoute` is not a `PageRoute`. This is SDK behavior, not a guarantee that every app observer ignores popups. A cancelled hold can legitimately produce an observer push/pop pair without ever showing menu content.

### Reveal, content build and focus

During hidden arming, `buildPage` creates the paint layer and a `_revealed` listener but returns `SizedBox.shrink` instead of calling `_builder` (`menu_route_probe.dart:709-729`). At measured model opening, `syncInputPhase` invokes `_reveal` (`326-357`), which changes the notifier and calls `changedInternalState` (`687-690`). A later widget build mounts the builder subtree. The reveal flag changing synchronously does not mean its descendants have completed mount synchronously.

`requestFocus` is false while hidden and true after reveal (`584`). The SDK consults this property before setting its modal focus scope as first focus (`routes.dart:1136-1138,1159-1168`). Existing coverage proves home primary focus remains while hidden and menu autofocus takes over after reveal (`menu_route_input_test.dart:223-267`). It does not prove home traversal behaves as if no route exists: the SDK independently sets `focusScopeNode.skipTraversal = !route.isCurrent` (`routes.dart:1175-1177`). The home route loses current status during arming even while its existing focused node retains focus. Keyboard traversal, Escape before reveal, and accessibility semantics deserve separate explicit checks.

Escape normally invokes the nearest `_DismissModalAction`, which resolves `Navigator.of(context).maybePop()` (`routes.dart:975-989`). Before reveal focus still belongs to the underlying subtree, so the action scope and Navigator can differ from the popup's eventual menu subtree. Do not infer early Escape behavior from the existing mounted-menu Escape test.

### Dismissal before either mount boundary

1. Immediately after source-down/push, the route exists but `_ModalScope` has not built. SDK `ModalRoute.willPop` asserts `_scopeKey.currentState != null` (`routes.dart:2005-2007`). The prototype always calls `super.willPop()` in `_resolvePermission` (`menu_route_probe.dart:504`) and catches/reports errors (`521-530`). Thus an immediate `maybePop` can produce a reported assertion and reject instead of a clean declared early dismissal outcome. This is a concrete source-proven defect, awaiting a focused reproduction; it is not fixed by looking at `hasScopedWillPopCallback`.
2. After first modal-scope mount, while held below the opening deadline, the SDK scope exists but `_builder` has not run. `hasScopedWillPopCallback` is false and `popDisposition` has no registered PopEntry veto. The route is not first, so default disposition is `pop` (`navigator.dart:382-389`; `routes.dart:2034-2041`). `maybePop` can therefore close without consulting a `PopScope(canPop:false)` or `WillPopScope` that would later be returned by the builder. This is a genuine policy gap if the declared contract promises that builder policy governs the whole prepared route. The SDK cannot discover a nonexistent descendant; the prototype must define its own readiness/arming semantics.
3. Between `_revealed=true` and the next builder mount there is another unregistered-policy interval. A same-turn model or SDK command must not be assumed to see policy merely because `requestFocus` is now true.

The mounted async protocol remains sound within its already-tested boundary: it checks current route and lease before answering, discards results after cover/uncover, replaces/removes/unmounts, rechecks current PopScope before consuming a model request, and preserves SDK local history (`menu_route_probe.dart:444-579`; async tests `397-443,485-514`). The remaining post-issued SDK-success window is separately documented; this investigation adds no new guarantee there.

The existing “early outside” test is after `tester.tapAt` then `pump(10ms)` (`menu_route_input_test.dart:358-362`). Its measured early dismissal deadline occurs after opening and ordinary content mount. It is not evidence for immediate source-down Back or a builder that has never mounted. The async harness explicitly waits for animation completion (`menu_route_async_test.dart:76-81`), so its tests also do not cover these windows.

### Nested Navigator behavior

Opening always targets root. Existing nested coverage asserts two root pushes, one nested push, and root popup ownership (`menu_route_probe_test.dart:120-153`). That test uses the default tap-driven path, not the early raw-pointer path. Raw-pointer early push inside nested Navigator should be separately exercised: the source Listener precedes both ancestor Navigator Listeners, but that ordering claim presently comes from source, not the existing nested test.

The inner page remains current within its own Navigator; the root page containing it becomes non-current within root. Only root observers see the popup. An imperative `Navigator.of(innerSourceContext).maybePop()` still targets the inner Navigator and is not redirected by the existence of a root popup. This is normal lookup behavior and requires an explicit API/documentation decision, not rewriting Flutter's stack semantics. System Back routing via nested Router/BackButtonDispatcher arrangements is not covered by the simple WidgetsApp harness.

## Where Things Live

- `example/lib/proto/menu_route_probe.dart`: all preparation/reveal, route policy, clocks and ownership coordination.
- `example/lib/proto/menu_transfer_probe.dart`: complete model leases, canonical clock offsets, carried contour.
- `example/test/proto/menu_route_input_test.dart`: pointer-preservation negative control, hidden focus/content, cancel-before-hold, mounted PopScope cases.
- `example/test/proto/menu_route_probe_test.dart`: root-vs-nested selection, mounted focus/PopScope behavior and route teardown.
- `example/test/proto/menu_route_async_test.dart`: async policy coalescing, cancellation and causal close time, all beginning after menu mount.
- Public SDK `navigator.dart`: push/history/observers, current-entry query, `maybePop`, active-pointer cancellation.
- Public SDK `routes.dart`, `pop_scope.dart`, `will_pop_scope.dart`: modal scope/build/focus, RouteObserver filter and policy registration.

## Gotchas

- Delaying observer callbacks or falsifying `isCurrent` would break the contract of a real route. If invisible preparation must remain entirely invisible to navigation, early real push is the wrong architecture; preserving pointer stream by another mechanism would need separate measured proof.
- The product contract must choose what Back means while arming: cancel preparation without building menu, reject/defer until policy readiness, or eagerly mount policy/content. The present code implicitly mixes these states. Arbitrary not-yet-built widget policy, deferred builder invocation, and immediate policy-aware dismissal cannot all be provided automatically.
- `requestFocus:false` preserves current focus; it does not make the hidden popup navigation-neutral or preserve underlying route traversal participation.
- The global pointer handler does not check `activeRoute.isCurrent` before forwarding input (`menu_route_probe.dart:360-385`). Close admission checks current status (`227`) but model pointerDown can still update highlight/glow/kicks when a different route covers it (`menu_motion.dart:2522-2540`). This is a concrete unguarded mutation path; user-visible severity and proper treatment of an already-held pointer require a focused test, not an assertion that all covered input is safe.
- The source position is documented as root Navigator coordinates. The nested test uses coincident full-screen geometry, so it does not establish automatic coordinate conversion for offset/transformed nested Navigators.
- No production host, exported API, measurement, timer, motion constant or device state was changed by this inspection.
