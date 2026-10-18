# Candidate B: attachment-owned viewport observer

Independent same-model architect attempt, 2026-10-18. Design only; no application edits or tests. Grounded in `how.md`, `why-history.md`, the current admission/painter fences and production idle-only relayout. This deliberately adds a notification owner, rather than relying exclusively on snapshot observations.

## Usage (caller's view)

```dart
ProbeMenuSource.measured(
  button: const Rect.fromLTWH(24, 80, 44, 44),
  onMotionReady: (motion) { /* same measured model */ },
)

// Existing source/controller callers remain unchanged.
sourceKey.currentState!.open();
// Raw pointer and semantic callers use the same existing admission path.
```

A source opens only when its complete button and the model's fixed minimum menu dimensions fit inside the actual overlay's available rectangle. Already resized overlays reserve no additional keyboard space. No consumer handles a metrics listener, DPR, generation, or MediaQuery padding.

## Problem

A snapshot-based admission can place a newly opened menu correctly, but a settled open route need not tick when physical view metrics change. B offers a bounded notification path that observes this loss after the next layout even under a locally frozen or stripped MediaQuery. It does not animate an old menu around the keyboard: the old shown popup keeps its original model, placement and time; its source authority is retired using the existing policy.

## Shape

All types remain private in `example/lib/proto/menu_route_probe.dart`; no production API or new module.

```dart
class _PlacementViewport {
  const _PlacementViewport(this.available, this.padding);
  final Rect available; // finite, positive, overlay-local intersection
  final EdgeInsets padding; // derived once, nonnegative and finite

  static _PlacementViewport? read(
    FlutterView view,
    RenderBox overlay,
    _UniformMap overlayToView,
  ); // pure metric/projection validation after attached/layout checks
}

class _MenuGeometry {
  // Existing identities, source map/button/bounds/shape remain.
  final _PlacementViewport viewport;
  bool agrees(_MenuGeometry other);
  // Existing equality AND exact effective available-rect equality.
  // Never raw metrics, DPR, observer generation or root-global map equality.
}

class _ViewportWatch with WidgetsBindingObserver {
  _ViewportWatch(this.session); // installs observer once for this attachment
  final _MenuSession session; // immutable target, never a current-session getter
  int _generation = 0;
  bool _queued = false;
  bool _disposed = false;
  void didChangeMetrics();
  void dispose(); // idempotent unregister; pending callbacks become inert
}
```

The source State owns exactly one watch per measured attachment. Install it after publishing that session and its geometry callbacks; dispose it before retiring/replacing the attachment, and in State disposal. Fixed fixtures create no watch. This makes its immutable target and disposal boundary visible beside existing affinity ownership, per separate-before-serializing-shared-state. No global cache, per-view registry, new ticker or observer-owned motion exists.

`_PlacementViewport.read` performs these steps, per boundary-discipline:

1. Read `session.affinity.overlayView` physicalSize, devicePixelRatio, viewPadding and viewInsets. Reject nonfinite/negative metrics and nonpositive DPR/size. Physical dimensions and insets become logical coordinates by dividing by DPR exactly once.
2. For each edge use `max(viewPadding.edge, viewInsets.edge)`, not their sum and not descendant `MediaQuery.padding`. Build the view-logical safe rectangle; reject inversion or emptiness.
3. Inverse-map its two corners through the already validated positive-uniform overlay→view map. Reject nonfinite derived results. Intersect with `Offset.zero & overlay.size`; reject empty intersection.
4. Derive padding from that intersection relative to actual overlay bounds. Reject nonfinite deltas. Require effective width at least `motion.tuning.menuWidth`, and height at least `motion.tuning.rowHeight + 2 * motion.tuning.verticalPadding`; reject nonfinite/invalid tuning thresholds. Require the full measured button inside the effective rectangle, with inclusive edges.

The dimensions come from the actual session model's tuning, not copied default constants. Admission continues using the same model and existing idle gate, then calls `relayout(..., padding: current.viewport.padding)`. Install the accepted geometry before readiness, and reread after user reentry as today. The projection function needs no inherited dependency getter and can run at existing paint/input fences. Nonuniform, reflected, rotated or perspective maps remain invalid.

Observer pseudocode:

```text
didChangeMetrics:
  if disposed: return
  generation += 1
  if queued: return
  queued = true
  scheduleFrame()  // one wake-up, no continuous polling
  addPostFrameCallback:
    queued = false
    if disposed or !session.sourceAttached(): return
    observed = generation
    session.checkGeometry() // fresh metrics + post-layout render boxes
    if !disposed and generation != observed and !queued:
      queue another post-frame check using the same captured session
```

The generation coalesces notification work; it never decides geometric validity. Callback scheduling should be one small private helper so the last branch does not fabricate another metrics notification. Every queued closure retains the same watch/session. Disposal is sticky, so an old callback cannot check or invalidate a replacement. An inactive source is skipped rather than treated as lost; its ordinary activate/admission/paint checks retain authority. A notification itself does not read stale layout, run readiness, call relayout, setState or detach under tree lock. The post-frame check may invoke the existing deferred replacement path; it never opens anything.

Existing synchronous fences remain mandatory: metrics can change during readiness, a source frame can hand back before the observer's callback, and root transforms can change without any metrics notification. Active effective-rect change uses `loseGeometry`; fully rested idle change remains recapturable on next admission. Raw metrics changes with identical effective rectangle do nothing. Overlay movement matters only when it changes the effective rectangle. A shown popup may consequently remain visually overlapped by the keyboard; this prototype does not promise IME avoidance after opening.

## Synthesis decision

Pending independent judge. Prefer B only if prompt post-layout observation of an otherwise idle popup is a required prototype contract. Its public interface is as small as A's; its additional internal owner buys a stronger notification guarantee, not better admission mathematics.

## Tradeoffs accepted

- We accept observer registration, queued-frame lifecycle and test cost in exchange for checking an idle open popup after physical metrics notifications without a permanent ticker.
- We accept next-layout notification latency in exchange for avoiding retirement based only on pre-layout overlay bounds. Existing synchronous fences can still observe and retire earlier; this is not transactionally coalesced platform geometry.
- We accept conservative admission and old-popup retained placement in exchange for preserving measured dimensions, whole-model time and the existing transfer owner.

## Alternatives considered

Pure fresh snapshot fences hide the same coordinate work with fewer private mechanisms, but intentionally leave a nonobserved idle menu's changed viewport unnoticed until another event/frame. A shared view-level observer registry saves duplicate registrations at the cost of fan-out ownership and stale-subscriber hazards; reject it for this bounded prototype. Neither alternative needs public metrics knobs.

## Red-flag screen

One projection authority, one geometry equality, one State-owned watch per attachment and one existing admission path. The watch schedules observations only; geometry/session owns validity and transfer remains the sole motion writer. No hand-synced thresholds or raw-metric shadow snapshot. The extra watcher is justified only by its stronger observable contract; otherwise subtract it and choose snapshot-only.

## Risks and verification

Does this stronger notification contract merit its lifetime surface now? The judge can answer without blocking on user input. Verify physical status/home insets and keyboard on all four edges; already safe resized roots; offset/scale and DPR 1/2; removed/faked MediaQuery; empty, too narrow/short and covered-source decline; idle same-model recapture; equal effective rect despite changed raw metrics; root movement preserving/changing intersection; notification while hidden/shown/reserved/source tail; settled-open observation without ticker; coalesced notifications and disposal/reattachment before callback; readiness reentry changing metrics; same-frame hand-back/paint fences; unchanged zero-inset replay and tail pixels. No native keyboard policy claim or P3 closure follows from these host tests.

## Next implementation step

Implement and unit-exercise the private projection and effective-rect equality first, then integrate the attachment watch and existing fences without changing model/clock/transfer code.
