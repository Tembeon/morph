# How: source space, presentation affinity and geometry

Read-only grounding at `d9973893a0cd91c7eff6c68efe6571594033c81c`, 2026-10-17. Applied the local how explainer path directly as the delegated explainer; no further delegation, source edits, test runs, GUI or device work. Read repository rules, testing rules, menu passport and foundation architecture. SDK statements below come from the installed Flutter source, not external web research. No private native material was read.

## Overview

The current P2 probe transfers one entire measured menu model between source and real root `PopupRoute`. It deliberately has fixed geometry. This is stated in `ProbeMenuSource`'s constructor and the route reports: the `button` rectangle, `bounds` and neighbor shapes are experiment inputs, not a live source link. A source under a translated or scaled ancestor is therefore outside this probe's proved geometry contract. The production menu motion's `relayout` only accepts updates in its idle phase; live geometry cannot be bolted on by calling it during opening or closing.

There is a narrower lifetime problem worth proving first. A `GlobalKey` can move the same source State to another root Navigator or FlutterView without disposing its `_MenuSession`. The session then updates the source's mutable view id while the presented route, its clock and paint coordinate space remain attached to their original Navigator. Current hand-back checks only whether a source clock exists. That is insufficient evidence that the source is still a compatible landing site. This is a concrete identity mismatch in the code, with runtime failure still requiring a new harness; it must not be reported as an already reproduced test failure.

## Key concepts

* The **source attachment** is the source's current mounted element, source FlutterView and selected root Navigator. The probe presently records only a mutable view id.
* The **presentation attachment** is the actual Navigator that owns the route and the FlutterView rendering that Navigator's overlay. Its lifetime continues after source loss or reparenting.
* The **model space** is the logical coordinate space used by the fixed button, bounds and pointer positions. The probe implicitly equates source local paint coordinates, root-overlay local coordinates and global logical pointer coordinates. These coincide in the existing full-window, untransformed harness.
* A **transfer lease** decides who may mutate/sample the model. It does not prove input entitlement or compatibility of paint coordinates. Reparenting does not invalidate a lease automatically.

## How it works now

`ProbeMenuSourceState.initState` creates `_MenuSession` and its source clock once. Geometry, factory, neighbors and callbacks are captured from the original widget into final fields. There is no `didUpdateWidget` geometry path. Meanwhile the actual source `Positioned` reads the latest `widget.button`, so changing that widget argument can move the physical hit region while the model and source painter retain the original rectangle. That is another fixed-input limitation, distinct from a source attachment change.

`didChangeDependencies` calls `View.of(context)` and overwrites `_MenuSession._viewId`. A changed id revokes the current held pointer. It also captures local themes and sends them only to existing routes whose Navigator matches the source's newly selected root Navigator. This theme guard already recognizes that a route belongs to one particular presentation host; the corresponding input and landing guard is absent.

`_prepare` returns an existing nonclosing route or reservation before looking up the current root Navigator. A retained source moved elsewhere can therefore still receive the old route through `open()`. A new route's clock is bound to its actual `navigator` in `install`; moving the source never moves that SDK route. Its `_sourcePage` is also the original root page identity.

Raw pointer routing uses a global binding route. New down requires `event.viewId == _viewId`, then either current menu entitlement or an eligible source hit. The transfer adapter sends `event.position` directly to the pure motion. Because the source's view id is mutable, a move from view A to view B permits a new B event while `activeRoute` still belongs to A. Conversely, a legitimate event over the retained popup in A is rejected. The retained `_PointerSequence` includes its original view id and the change revokes an existing sequence, which is good but only covers the old held sequence; it does not fix subsequent acquisition.

`land(route, localTime)` asks only whether `sourceClock != null`, resumes that clock and transfers the entire model at its continuous canonical time. A reparented source still has that clock. The probe may thus paint old-root coordinates in a new root/view on the first closing zero crossing. Before hand-back the source painter does not own the model, so the mismatch can stay invisible until landing. A source move while it already owns a live tail has the same coordinate issue immediately.

Reservations add a second lifetime to cover. The reservation's transfer and pointer sequence remain immutable, but continuation and promotion must not treat a source in another presentation space as a valid attachment. Retiring only `activeRoute` leaves a reserved next route or committed pending opening capable of using the changed source.

## SDK grounding

`View.of`/`maybeOf` register an inherited dependency on FlutterView **identity**, not view metrics (`widgets/view.dart:121–157`). GlobalKey reactivation refreshes inherited dependencies and calls `didChangeDependencies` when the element had dependencies (`widgets/framework.dart:4757–4780`). This source already has a View dependency, so reparenting supplies a useful refresh seam. `Navigator.of(rootNavigator: true)` itself walks ancestors; it does not create an inherited Navigator identity subscription (`widgets/navigator.dart:2947`). Recompute both identities together during attachment refresh, and validate the live attachment again at operations that can be reentrant.

`PointerEvent.position` is global logical pixels (`gestures/events.dart:309`), whereas `MorphMenuMotion` explicitly expects coordinates in its bounds space (`menu_motion.dart:1184`). `RenderBox.globalToLocal`/`localToGlobal` and `RenderObject.getTransformTo` are the SDK tools for conversion. `getTransformTo` requires the same render tree, can return a zero matrix for unavailable transforms and throws for unrelated trees (`rendering/object.dart:3664–3715`). It is not a cross-View mapping. A transformed rectangle also ceases to be a full description of a rotated/perspective surface; its bounding box does not preserve hit shape or geometry.

An element may be attached even when it is not painted; transform retrieval ignores `paintsChild`. The future source link needs explicit visibility and attachment policy as well as a matrix. Do not infer visibility from `attached` or a nonzero transform alone.

## Recommended next seam

First make one bounded experiment about **presentation affinity**, retaining fixed geometry and the existing pure model/clock/transfer adapter. Capture sufficient source/presentation attachment identity to stop mutable source state from silently redefining an existing presentation's input or landing space. Source view identity and selected Navigator must be checked against the actual presentation overlay's view; a source can be placed under a distinct nested View while an outer Navigator remains an element ancestor.

Moving the source away should behave like loss of this presentation's landing site. The old popup must retain its own clock, SDK policy, content and old-view menu input; it cannot pop a new root's page, accept the new view's pointer or hand its old coordinates to the moved source. Invalidate a held sequence and stale reservation, preserve already committed domain work according to existing source-loss rules, and let the old model complete in its original route. Keep the source reusable only once it has a clean compatible model for its new attachment. Exact implementation choice belongs to architect; do not add an all-purpose source registry or restart the old model merely to make a test pass.

Decide explicitly whether returning to the old attachment before closing permits landing again or whether loss is sticky for that presentation. Also decide what happens when the source owns a live landing tail during a move. Those choices need explicit tests. They cannot be hidden in a guard that only handles route-owned opening.

Only after that gate should the full source link measure a live RenderBox relative to its selected overlay, map pointers into that space, publish geometry after layout, and specify moving-source/insets/rotation behavior. The model's idle-only `relayout` means active retargeting is a separate measured-motion contract. No evidence currently permits retuning, silently rebuilding the active model or claiming transformed-source support.

## Concrete harness

Start with two independently keyed root Navigators in one WidgetsApp/FlutterView, both kept mounted. Put one `GlobalKey<ProbeMenuSourceState>` into either root page through a single parent state update. Both pages should be current within their own Navigator; this avoids confusing attachment loss with a cover. Assert identical source State before/after the move and observe both Navigator histories. Exercise hidden hold preparation, shown popup, closing before first zero, source-owned tail, and a held-reopen reservation.

For route-owned movement, assert no foreign-root pop/push, no old-coordinate hand-back to the new root, old popup content/policy stability, and exactly one terminal disposition of the old model. A fresh source operation must eventually produce a new popup on the new root. Include return-to-origin and reentrant source-move-from-sample cases. Existing `onSample`, model factory and independent reference motion can compare the old model's continuous time/channels without copying its implementation.

Use a genuine second View/render tree for the multi-View case: `ViewCollection`/`View`, `pumpWidget(..., wrapWithView: false)`, test FlutterViews and view-aware pointer delivery. The installed testing SDK exposes `TestPlatformDispatcher.addTestView`; determining a minimal usable view fixture is harness work. Merely sending a made-up `viewId` to a single rendered view proves a filter, not a View or Navigator boundary. Include source and root overlay in different Views if SDK composition supports that arrangement. Keep host proof distinct from a multiwindow device claim.

An independent offset/scale geometry counterexample is useful to demonstrate the deferred fixed-space limit, but must be labeled negative geometry evidence and cannot turn the affinity stage into an unbounded live-transform implementation. Keep all existing replay and flat-scene baselines unchanged.

## Where things live

* `example/lib/proto/menu_route_probe.dart`: source lifecycle, session, acquisition, popup ownership, reservation and `land`.
* `example/lib/proto/menu_transfer_probe.dart`: one-owner model plus local-to-canonical clock offset; pointer positions currently pass through unchanged.
* `lib/src/widgets/menu_motion.dart:1471`: explicit idle-only geometry updates.
* `docs/architecture/foundation-review.md:50` and `foundation-sketch.md:464`: future source-link geometry and source-loss contract, not an implemented probe capability.
* `example/test/proto/menu_held_reopen_test.dart`, `menu_route_lifecycle_test.dart`, `menu_route_probe_test.dart`: existing real Navigator/pointer/lifetime fixtures. They cover nesting, cover, loss and disposal; no inspected test currently reparents one retained source between two root Navigators or two real FlutterViews.

## Gotchas

Affine same-View reparenting can be unsafe even with unchanged view id. A source State remaining mounted is not a valid landing guarantee. Fresh source route eligibility does not validate the retained popup's attachment. A root Navigator may itself have an offset/scale, so “root” does not mean global logical coordinates. `View.of` does not notify on metrics changes; those belong to MediaQuery or a separate layout path. A source refresh can happen during build, so route semantic/theme publications and retirement still need the existing safe lifecycle sequencing rather than synchronous neighbor rebuilds.
