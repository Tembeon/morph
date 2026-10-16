# P2 source environment: how the current path works

Read-only grounding against `65b080d3` and the installed Flutter 3.47.2 source. No tests, source edits, devices, or nested agents. File/line references below describe inspected code; proposed behavior is explicitly marked as inference. Local SDK root: `/opt/homebrew/Caskroom/flutter/3.19.1/flutter/packages/flutter/lib/src/`.

## Overview

The prototype preserves motion and menu content lifetime across source/root-popup ownership, but does not preserve source-local inherited environment. `ProbeMenuSourceState.open` passes `widget.menuBuilder` unchanged into a new `ProbeMenuRoute`, then pushes onto the root Navigator (`example/lib/proto/menu_route_probe.dart:140–146`). When revealed, `_MountedMenuPolicy.build` invokes that builder using its own context inside the popup (`:891–917`, `:994`). A WidgetBuilder closure does not itself carry the ancestor lookup scope of the site where it was supplied.

That placement is useful: Navigator/ModalRoute lookups and PopScope registration belong to the presentation rather than to the original source page. What is absent is an explicit policy for selected inherited data, particularly local appearance and direction overrides. A negative `/usr/bin/grep` over the actual probe confirmed there is no InheritedTheme/CapturedThemes/DefaultTextStyle/IconTheme/MediaQuery/Localizations/Directionality bridge at this revision.

## Key concepts

- **Source context:** the mounted `ProbeMenuSourceState` context. It can be under a nested Navigator and local appearance/environment overrides.
- **Presentation context:** the context passed by `_MountedMenuPolicy.build`. The nearest modal scope is the root popup; the nearest Navigator is the presentation Navigator unless the consumer builds another nested Navigator inside the content.
- **CapturedThemes:** SDK object holding nearest ancestor InheritedTheme widget of each runtime type between a source and an ancestor cutoff. It does not hold a live subscription to that source context.
- **Local snapshot versus shared ancestor:** an override between source and root Navigator can be captured; shared ancestors above that Navigator are still naturally inherited by popup descendants, provided a captured local theme of the same type does not shadow them.
- **Dependency versus lookup:** `InheritedTheme.capture` walks ancestor elements without `dependOnInheritedWidgetOfExactType`; `Directionality.of`, `MediaQuery.of`, `Localizations.of`, `DefaultTextStyle.of`, and `IconTheme.of` register inherited dependencies on the context that reads them.

## How it works

The current tree relationship is:

```text
shared app environment
└─ root Navigator
   └─ Overlay
      ├─ source page → local environment → optional nested Navigator → ProbeMenuSource
      └─ root popup modal scope → reveal gate → Flow → _MountedMenuPolicy → menuBuilder(context)
```

### Current route and content lifetime

`open` returns an existing nonclosing route without creating/rebuilding content; a replacement route gets the builder present on the source widget at that open call (`:142–145`, `:557–561`). There is no source `didUpdateWidget` forwarding replacement menuBuilder into an already open route.

Pointer-mode popup installation is early, but the content branch is a `SizedBox.shrink` until `_revealed` is true (`:558`, `:904–913`). `_MountedMenuPolicy` mounts only when revealed. It waits until a post-frame callback to mark policy ready (`:975–989`), giving PopScope and scoped willPop callbacks a chance to attach before a deferred permission attempt resumes (`:663–668`). A source-context wrapper must not accidentally mount the builder during hidden preparation or replace this state on every motion sample.

Source disposal clears `present` and `sourceEligible` and disposes only the source clock (`:381–386`). A live route remains in `_routes` and keeps the session alive; session final cleanup waits until there is neither source clock nor route (`:389–411`). Thus a correct captured data bridge can outlive the source element. Calling source-context inherited lookups from the route after source disposal would violate this existing lifetime boundary.

Flutter itself supplies the modal scope, Actions, FocusScope, and route page context under the target Navigator (`widgets/routes.dart:1185–1236`). `ModalRoute.of` resolves through the nearest `_ModalScopeStatus` (`:1296–1318`). `PopScopeState.didChangeDependencies` registers with `ModalRoute.of(context)` (`widgets/pop_scope.dart:194–201`). `Navigator.of(context)` resolves the nearest ancestor Navigator, or the furthest with `rootNavigator: true` (`widgets/navigator.dart:2939–2955`). Capturing appearance widgets does not replace those route identities.

### InheritedTheme capture/wrap

`InheritedTheme.capture(from: sourceContext, to: rootNavigator.context)` is a public widgets-layer API. `to` must be an ancestor; it is excluded from the walk. `to: null` instead captures all the way to root (`widgets/inherited_theme.dart:70–87`, `:100–107`). The walk keeps only the first theme per runtime type (`:108–116`). `CapturedThemes.wrap` later creates wrappers around a child using each captured theme's own `wrap` implementation (`:133–156`). The capture itself does not call those wrap implementations or run the child builder.

The SDK explicitly documents that themes are frozen until captured again (`:77–81`). This is a capture of theme widget references, not a deep clone of arbitrary mutable theme payloads (`:93–125`, `:134–140`). Correct custom InheritedTheme implementations should provide immutable theme data and a sound `wrap` implementation. `wrap` runs with a destination context; a custom implementation may itself read that context, so the bridge must not promise arbitrary third-party data is deeply frozen or origin-resolved.

DefaultTextStyle (`widgets/text.dart:55`) and IconTheme (`widgets/icon_theme.dart:24`) extend InheritedTheme. Their wrap implementations preserve the text properties and icon data (`text.dart:205–216`, `icon_theme.dart:90–93`). Capture avoids manually listing every present/future theme type, which also matches the planned `MorphTheme extends InheritedTheme` (`docs/architecture/foundation-sketch.md:191–196`). IconTheme.of still calls `data.resolve(context)` in its destination context (`icon_theme.dart:64–79`); capture of a data object is not identical to pre-resolving every dynamic value at the source.

Stopping capture at the target Navigator matters. A theme above that cutoff remains shared and can update normally, because it was never wrapped into a snapshot. If a local theme of the same type is captured below the cutoff, its data shadows later changes of that same upstream type. Capturing to null would unnecessarily freeze shared app appearance as well. Recapturing during every frame would turn an open presentation's snapshot into implicit live source linkage, spend repeated tree walks, and fail after source detach. These are implementation consequences; the desired snapshot/update policy remains a product decision.

### Directionality

Directionality is an inherited widget but not an InheritedTheme (`widgets/basic.dart:171`). `Directionality.of` registers a dependency and returns the nearest value (`:196–199`); updates notify when textDirection changes (`:223–224`). Theme capture alone therefore does not carry a source-local RTL/LTR override into a root popup.

Localizations itself introduces a Directionality wrapper from its resolved WidgetsLocalizations resources (`widgets/localizations.dart:726–744`). If a bridge recreates Localizations and also preserves explicit source direction, wrapper order matters: the intended explicit Directionality override must be inside the recreated Localizations wrapper or the latter will shadow it. A blanket snapshot of Directionality.of(source) can also freeze a value that originally came from shared root localization; detection of an actual local override versus shared root data is therefore meaningful.

### MediaQuery

MediaQuery is an InheritedModel, not an InheritedTheme (`widgets/media_query.dart:1276`). `.of` subscribes to all data; aspect-specific accessors rebuild only for that aspect (`:1244–1265`, `:1567–1573`, `:1620–1628`). WidgetsApp normally provides shared view data and keeps metrics current (`:1271–1275`). Root popup descendants naturally observe that target environment. A source-local MediaQuery override is not automatically copied.

Inference: blindly copying full source `MediaQueryData` would mix distinct things. A source subtree may have consumed padding or supplied local size; a fullscreen root popup should not accidentally inherit that reduced coordinate environment. Conversely text scale/brightness/accessibility overrides can be deliberate consumer preferences. A full snapshot would also hold old view size, keyboard insets, and system flags across future changes, including after source detach. The right policy requires tests that separate shared live view data from explicit local overrides; no current code or SDK API resolves that product choice automatically. This read-only pass does not select a per-field merge policy.

### Localizations

Localizations is a StatefulWidget that creates a private inherited resources scope, not an InheritedTheme (`widgets/localizations.dart:479`, `:739–744`). `.of<T>` and `.maybeLocaleOf` subscribe to that scope (`:589–592`, `:619–622`). A local source localization override is therefore absent from root popup lookups today.

`Localizations.override(context: sourceContext, child: ...)` is a public factory. It immediately reads/copies the source delegates list and captures the supplied/current locale (`:521–539`, `:597–601`), and creates a new Localizations widget. It does not preserve the old private resources scope or reuse arbitrary loaded resources. New localized resources may need asynchronous loading; while its own locale is unresolved, its build returns a SizedBox (`:730–731`). Blanket override can freeze a previously shared app locale/delegate choice and unexpectedly affect menu content/policy mount timing. A local-only localization bridge must state its loading and update contract rather than imply simple value wrapping.

### Arbitrary inherited data and route identity

Facts: theme capture only carries InheritedTheme; ordinary custom providers, source-page ModalRoute, source Navigator, Actions, Focus, and Localizations are not copied by it. The route already receives the consumer's builder closure, and that closure can explicitly capture values/controllers as ordinary Dart state.

Inference: copying source-context lookup identity wholesale would undermine the existing route policy work. The clean boundary is to keep a destination builder context for ModalRoute/Navigator/PopScope and deliberately transport selected appearance/environment values. This does not automatically transport provider/state-management scopes. The consumer can place shared providers above the root Navigator or supply captured values explicitly. Avoid promising that an arbitrary subtree is transplanted into a route with all source dependencies intact.

## Where things live

| Responsibility | Inspected location |
|---|---|
| Root push and builder capture | `example/lib/proto/menu_route_probe.dart:140–146` |
| Source detach/session lifetime | same file `:381–411` |
| Hidden preparation and actual content mount | same file `:891–917`, `:961–1003` |
| Deferred first policy mount | same file `:657–681` |
| SDK theme capture | SDK `widgets/inherited_theme.dart:70–156` |
| SDK destination modal scope | SDK `widgets/routes.dart:1185–1236` |
| PopScope registration | SDK `widgets/pop_scope.dart:194–201` |
| Non-theme environment | SDK `widgets/basic.dart:171–224`, `media_query.dart:1244–1278`, `localizations.dart:521–539` |

## Gotchas / limits

1. A correct initial snapshot is not evidence for live local theme updates; InheritedTheme.capture registers no inherited dependencies by itself.
2. A shared root theme can remain live while local overrides freeze. That distinction needs separate tests; one all-root or all-local fixture cannot demonstrate it.
3. Source detach must not cause later reads from the disposed element, and content mount/disposal must remain independent from source.
4. Context bridge wrappers must not key/replace the builder subtree on each model frame or sample ownership change.
5. Holding a captured builder may retain values its closure references. Theme capture can remove explicit source-context retention in the bridge; it cannot prohibit user closures from retaining their own state.
6. MediaQuery, localization loading, custom provider transport, global mutable theme payloads, multi-View migration, and full accessibility behavior are not proven by adding CapturedThemes alone.
7. This grounding ran no runtime checks. The baseline's local-environment loss follows directly from the inspected widget topology; each chosen replacement contract still needs an executable counterexample and regression checks.
