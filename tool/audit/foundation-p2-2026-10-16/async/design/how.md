# Overview

Checked at `9fcf9d19`: the prototype separates **permission to dismiss**, **the model's closing motion**, and **the route's logical pop**. The synchronous seam now prevents the old failure where motion had already begun closing when `PopScope` refused navigation. It does not yet implement asynchronous permission.

The hard constraint is causal time: a request may carry its measured deadline, but an approval delivered later cannot start an already-advanced driven model in the past. A correct async extension must preserve the synchronous fast path while naming a later close start for genuinely pending approval.

# Key concepts

- `MorphMenuMotion` owns all progress, kicks, timeline, fusion and pointer state. `_requestClose(t)` asks permission before `_close(t)` touches closing channels. Explicit `close(t)` is a command and bypasses admission.
- `ProbeMenuTransfer` keeps that complete model and grants one unique `ProbeMenuLease` permission to write. Canonical model time is `ownerLocalTime + offset`; changing presentation ownership changes the mapping, not the springs.
- `_MenuSession` installs admission, queues navigation work, drains it after model advance/input, and owns source/route clocks. It currently stores only `(route, admitted, time)` requests.
- `ProbeMenuRoute.didPop` first lets SDK local history consume the pop. Only an actual route pop marks it closing and commands motion if it is not already closing.
- SDK `popDisposition` is synchronous `PopScope` policy. Deprecated `willPop()` runs deprecated scoped `WillPopCallback` callbacks and awaits each. Neither is a model animation API.

# How it works

## Checked current path

An outside release or action selection schedules `_requestClose` on `MorphTimeline`. `runDue(frameTime)` executes each due event at its original event deadline before sampling the final frame. Admission reads the current route's `popDisposition`. If allowed and no local history is present, it returns true so `_close(deadline)` executes within that same timeline traversal. The host then drains its recorded request and calls `Navigator.pop`. This preserves exact measured replay timings even when the display frame occurs after the deadline.

For a synchronous refusal, admission returns false, leaving the model opening, and the host later reports `onPopInvokedWithResult(false, null)`. For local history, admission records an allowed SDK attempt but returns false to the model; `LocalHistoryRoute.didPop` removes its top entry and returns false. The menu must remain open. An action callback may already have fired before the later close request; refusing dismissal does not undo the selected action.

`NavigatorState.maybePop` captures the current route entry, awaits `willPop`, checks that Navigator is still mounted and that the last present entry is still the captured entry, then rereads `popDisposition`. It invokes `pop` only for the current allowed disposition. In contrast, `Navigator.pop` targets the current top entry directly and bypasses these permission checks. A generic unguarded `navigator.pop()` after awaiting permission could therefore close a covering/replacement route.

## Why past close is invalid

`MorphMenuMotion.advance(t)` ignores `t < _now`. However, public `close(t)` subsequently calls `_close(t)` anyway. `_sample(t)` integrates kicks only when `t > _sampleTime`; it cannot integrate backward. `_close(t)` then reads analytic progress/opacity at that past time but combines them with the already integrated current kick state, retargets closing channels, and schedules delayed closing impulses in the old timeline. This is neither a replay nor a faithful current-time close. `MorphTimeline.at` also executes an already-due newly scheduled event at its current timeline time rather than reconstructing elapsed driven integration.

Therefore letting opening and interaction continue while awaiting permission is incompatible with promising the physical closing reaction happened at the original deadline. A snapshot/rewind/replay system would be needed to reconstruct that alternative history, and it would still not restore frames the user has already seen.

## Proposed behavior, not current code

Keep three meanings explicit: `requestedAt` is the immutable measured dismissal deadline; `acceptedAt` is when permission resolves; `closeStartedAt` is the causal motion time used for mutation. A synchronous allowed request can retain `closeStartedAt == requestedAt`. A genuinely async allowed request should sample the current owner's time and close from current state, with `closeStartedAt >= latest model time`. Preserve `requestedAt` as provenance, not a backdated retarget command. Refusal leaves the opening model and interactions live.

An outstanding request needs identity tied to the route and its ownership/navigation generation. Disposal, replacement, relinquishment and actual programmatic pop invalidate it. A cover/uncover cycle must also be observable: a final `isCurrent` check alone misses a route that was covered and returned while awaiting. `didChangeNext` is the SDK hook for next-route changes; incrementing an epoch there can make that policy falsifiable. Source widget loss is different: current code intentionally keeps an already-presented route alive without a source, so source unmount alone should not accidentally cancel a valid route permission unless that becomes an explicit policy.

# Where

- `lib/src/widgets/menu_motion.dart:15` admission installer; `:2462` explicit close; `:2756` advance; `:2901` driven kick integration; `:3046` request before mutation; `:3051` close internals.
- `lib/src/widgets/timeline.dart` deadline-preserving synchronous event drain.
- `example/lib/proto/menu_transfer_probe.dart` unique lease and clock mapping.
- `example/lib/proto/menu_route_probe.dart:211` admission installation; `:324` host drain; `:470` route pop after local-history handling.
- `example/lib/proto/motion_clock_probe.dart:63` latest sampled time; `:205` resume anchor. A fresh async approval timestamp is not automatically represented by `clock.time` when settled. `resumeAt` only adds elapsed doze time directly; ordinary idle time requires an explicit clock/motion policy.
- Local SDK `navigator.dart:5582` maybePop; `routes.dart:934` local-history willPop, `:951` local-history didPop, `:2005` scoped callbacks, `:2034` PopScope disposition, `:2183` scoped-callback presence, `:2194` next-route changes.

# Gotchas

- `willPop()` is asynchronous even if there are no scoped callbacks. Always routing through it would insert an async boundary and lose exact synchronous deadline handling. The route subclass can inspect protected, deprecated `hasScopedWillPopCallback` to keep a measured synchronous fast path; label this as temporary SDK compatibility evidence, not a new recommended app API.
- `ModalRoute.willPop` snapshots the callback list and awaits each. A callback can unmount/register new policy, throw, or trigger navigation. Revalidate route identity, lifecycle epoch, ownership and current `popDisposition` after await. A thrown callback must not accidentally authorize closing.
- `hasScopedWillPopCallback` can change when descendants build without rebuilding transitions. The early hidden route has not built menu content, so a permission decision before the reveal's first build may miss `PopScope`/`WillPopScope` registration. This needs a first-build test and explicit readiness handling.
- Local history may change during an await. Recheck `willHandlePopInternally` before permitting motion closing; the SDK pop may consume local history and return false. Programmatic pops preserve SDK behavior, including bypassing PopScope and consuming local history first.
- SDK `maybePop` does not coalesce simultaneous requests. Coalescing belongs to the prototype's request protocol. Decide whether repeated input shares one pending permission or invalidates it; do not accidentally call an app's async guard once per frame/event.
- SDK's check of the final last entry does not itself detect temporary cover/uncover. Epoch invalidation is a stricter proposed policy requiring tests, not a claim about existing `maybePop` semantics.
- `_closeAdmission` must not mutate the model while its timeline is draining. A request record/decision followed by host draining is the existing safe boundary; nested close/advance inside an async callback continuation must still occur outside model traversal.

No repository files changed; no tests, devices or external sources used. These conclusions come from the checked local implementation and SDK source, with proposed behavior labeled above.
