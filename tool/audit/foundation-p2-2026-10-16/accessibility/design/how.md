# How grounding: prototype accessibility boundary

Read-only investigation at `65dce59fba3e5990153588c13e993b7de0bc8ee1`.
Project rules, testing rules, how and pstack-runtime read. No source/test edits, test jobs, network, private Apple material, GUI or device access. Direct inspection in delegated worker; no nested delegation.

## Overview

The source, visible menu, retained closing content, Navigator focus scope and model sampling lease are different lifetimes. Pointer admission now handles those distinctions, but it does not establish a semantics policy. The current pointer prototype lacks a semantic source activation path, retains an eager modal semantics blocker during hidden preparation, and has no explicit route semantics boundary.

Facts below come from our prototype and the installed public Flutter SDK source at `/opt/homebrew/Caskroom/flutter/3.19.1/flutter/packages/flutter/lib/src/`. No native accessibility behavior is established by this investigation.

## Key concepts

- `ProbeMenuSource.build` uses a bare `Listener` in measured-pointer mode, so its callbacks are raw binding pointer callbacks. `Listener` creates `RenderPointerListener`; it does not register a semantics tap handler. In command mode, `GestureDetector(onTap: open)` does provide a semantic tap via the SDK recognizer's semantics delegate. Neither path supplies a useful source name/button role itself.
- `ProbeMenuSourceState.open()` pushes a real root popup. In pointer mode, `_MenuSession.acquire()` deliberately does **not** call `transfer.open()`: the existing raw interaction owns the eventual opening. Calling `open()` alone from a new semantic tap would create a hidden preparation route without opening the model. A semantic command must explicitly open the current model through the existing domain command/clock boundary, present/reveal it, and resume the correct clock. It must not create artificial binding pointer events.
- `ProbeMenuRoute.requestFocus` is false until revealed. The SDK `_ModalScope` still marks only the current route as participating in focus traversal; an early hidden popup is already current even if it declines a focus request. Fixing semantics does not erase the observer/currentness/traversal cost of early push.

## How it works today

### Hidden preparation and barrier

`buildModalBarrier()` in pointer mode produces `IgnorePointer(ignoring: !revealed && !pendingBarrier, child: ModalBarrier(dismissible: false, semanticsLabel: ...))` inside `_MenuHitGate`.

In SDK `widgets/modal_barrier.dart:209–270`, `ModalBarrier` always wraps its content in `BlockSemantics`. Setting `dismissible: false` removes its own accessible label and tap/dismiss actions, regardless of the non-null label, but **does not** remove that outer semantics blocker. `IgnorePointer` in this SDK blocks semantic user actions while retaining the subtree's non-action properties; its `visitChildrenForSemantics` still visits the child. Therefore the current hidden preparation has a blocker that can remove earlier lower-page nodes even while ordinary pointer hit testing passes through. The exact assembled semantics tree is to be reproduced by SemanticsTester rather than inferred solely from widget structure.

The SDK's outer route barrier wrapper also uses `IgnorePointer` while the route animation is not forward/completed. This is an action policy, not removal of barrier labels/blocking.

### Route scope and naming

Our `buildPage()` returns a Stack with painter and lazily revealed Flow, with no `Semantics(scopesRoute: true)` or `namesRoute` annotation. SDK `_ModalScope` and `_buildModalScope` add focus/actions/restoration/ordinal sort wrappers, but do not add route scope/name semantics. `RawDialogRoute.buildPage` explicitly adds `Semantics(scopesRoute: true, explicitChildNodes: true)`; this is evidence that inheriting `PopupRoute` alone does not supply that boundary. A route name is a separate consumer naming decision; copying a hard-coded English prototype label is not a localization solution.

### Retained Flow, closing and handback

`_MenuContentFlow` is deliberately kept mounted to preserve policy/content state. The delegate paints the child only while its lease is current, at the model transform and opacity. On lease loss it returns without `paintChild`.

SDK `rendering/flow.dart:352–461` records a child's paint transform even when `paintChild(opacity: 0)` returns without drawing. RenderFlow does not override semantic child visitation to filter unpainted children. Its default container child visitation retains the mounted child. A paint pass that omits the child clears its stored transform, not its mounted subtree. The source therefore needs an explicit semantics lifetime decision: optical opacity, pointer hit gating, Flow paint omission, and sampling ownership are not a reliable semantics exclusion policy.

Flow's repaint listener calls `markNeedsPaint`, not `markNeedsSemanticsUpdate`; `applyPaintTransform` reads the last stored paint transform. This is a reason to test transformed semantic bounds during animation and handback; code inspection alone does not establish whether ancestor/layer changes schedule enough semantic updates in every case. Do not claim dynamic semantic geometry is correct merely because a repaint moves pixels.

`_MenuHitGateRender` only overrides `hitTest`, so it never gates semantics. During reverse, SDK `_ModalScope` sets its IgnorePointer and disables focus requests; that still retains labels. Old menu labels and the barrier's BlockSemantics may therefore survive logical pop while content remains mounted for visual closing. Explicitly excluding hidden/closing semantics can preserve mounted editor/PopScope state while releasing semantic modality.

### Accessible dismissal

Use a normal semantic action calling the live route's `navigator.maybePop()` after validating revealed/current/nonclosing/nondisposed identity. SDK `NavigatorState.maybePop` awaits route `willPop`, rechecks mounted Navigator and history identity, then checks `popDisposition`, performs `pop`, or reports `onPopInvokedWithResult(false, result)`. Our existing route permission protocol deduplicates asynchronous decisions and revalidates its active lease; PopScope is already integrated there.

A semantic handler that calls `navigator.pop()` directly bypasses the policy consultation and should not be used. A handler that only calls `route.willPop()` never performs Navigator's pop step. Keeping `ModalBarrier(dismissible: false)` while adding a separate semantic dismiss action preserves the measured raw-pointer barrier behavior; making the barrier dismissible also installs its tap recognizer, so it is not a semantics-only substitution.

## Smaller public SDK mechanisms

1. Explicit source `Semantics(button: true, label: consumer label, onTap: domain open command)` without manufacturing PointerEvents; avoid duplicate semantic actions in command mode.
2. `ExcludeSemantics(excluding: hidden || closing, child: ...)` around the barrier branch to remove its BlockSemantics during those lifetimes. Preserve the actual barrier widget/hit path for measured pointer admission. Verify lower-page restoration in the assembled tree.
3. A stable `Semantics(scopesRoute: true, explicitChildNodes: true)` around visible route content; a consumer-supplied route label/name when appropriate. Gate the semantics subtree separately from mounted content lifetime.
4. A revealed/current guarded semantic dismiss action through `maybePop`; do not replace the existing asynchronous admission protocol.
5. Test semantic bounds at visible opening samples, logical close and lease handback; if stale geometry reproduces, choose the smallest explicit semantics invalidation boundary. Do not add a render tree framework in advance of evidence.

## Verification to make claims concrete

- Closed source has one labelled button/tap action and semantic activation opens/reveals the measured-pointer mode once.
- Hidden prep retains lower-page semantic labels/actions; revealed menu blocks them; logical close restores them before retained visual tail disposal.
- Visible route has one route scope/name if named; menu child actions remain and do not duplicate.
- Semantic dismiss obeys PopScope veto, asynchronous policy deduplication, cover/removal invalidation and current route identity; repeated actions do not pop underlying pages.
- Closing retained child labels/actions are excluded without rebuilding/discarding policy or editor state.
- Paint transform/opacity alone is not accepted as proof of semantic geometry or exclusion.

## Limits

No SemanticsTester execution by this worker; parent owns the single test job. No VoiceOver/TalkBack/native announcement order, assistive focus restoration, large text, contrast or Reduce Motion proof. Source geometry remains fixed and does not prove cross-root or multi-View support. Full production action semantics/menu item roles and localization remain outside this reduced host unless explicitly exercised.
