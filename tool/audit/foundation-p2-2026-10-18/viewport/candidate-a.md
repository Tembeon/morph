# Candidate A: extend the geometry snapshot

Independent same-model design run, 2026-10-18. Design only; no implementation or tests. Grounding: `how.md`, `why-history.md`, current `_readGeometry`/`_MenuGeometry`/admission and production placement. Architect runner and red-flags references applied.

## Usage (caller’s view)

Existing calls remain sufficient; there is no viewport argument or notification API:

```dart
ProbeMenuSource.measured(
  key: sourceKey, button: localButton, menuBuilder: buildMenu,
);
sourceKey.currentState!.open(); // Measures actual presentation view at admission.
ProbeMenuSource(
  button: recordedButton, bounds: recordedBounds, menuBuilder: buildMenu,
);
// Fixed recording fixture retains its existing zero-padding behavior.
```

Raw input and semantic activation use their existing admission path. A caller can consume local MediaQuery padding for its own layout; doing so does not erase root-popup system obstructions. An idle, fully closed source recaptures changed availability on the next open using the same model. While active, an observed effective change retires the source endpoint; the existing shown popup retains its pinned model and time until completion.

## Problem

The source→overlay mapping is correct, but measured placement still receives zero padding. FlutterView metrics are physical, overlay transforms are logical, and an offset/resized/scaled overlay may already exclude system edges. Production relayout is idle-only; changing active placement would introduce an unmeasured motion policy. Add one snapshot fact at the existing boundary, preserving whole-model ownership, rather than introduce a second environment lifecycle.

## Shape

Keep changes inside `menu_route_probe.dart`. Extend the immutable `_MenuGeometry` with `final Rect available`; derive `EdgeInsets get padding` from its bounds and available edges. Its existing `agrees` adds `available == other.available`, deliberately comparing the effective rectangle rather than raw view metrics or the global overlay transform. Existing raw transform-family validation remains exact.

```dart
Rect? _availableMenuRect({
  required FlutterView view,
  required Size overlaySize,
  required _UniformMap overlayToView,
  required Size minimum,
}) => throw UnimplementedError();

class _MenuGeometry {
  // Existing identity, source-map, shape and bounds fields remain.
  final Rect available;
  EdgeInsets get padding => throw UnimplementedError();
  bool agrees(_MenuGeometry other) => throw UnimplementedError();
}
```

`_readGeometry(session)` remains the single observation/validation boundary. Read `session.affinity.presentationView`; derive minimum width from current model tuning.menuWidth and minimum height from rowHeight + 2×verticalPadding. Validate finite positive DPR, finite positive physical size, finite nonnegative edge metrics and minimum dimensions. Compute logical view size once. Each obstructed edge is `max(viewPadding.edge, viewInsets.edge) / DPR`, never their sum. Reject an empty/inverted safe view rectangle. Inverse-map its two corners through the already validated overlay→view uniform map, then intersect with `Offset.zero & overlay.size`. Require every derived edge, width, height and padding delta finite; require positive extent, at least the fixed menu width/minimum height, and complete inclusive containment of the mapped source button. Merely overlapping the source is insufficient. Return null before callbacks/push on any failure. No ancestor MediaQuery dependency is read from paint.

`admitGeometry()` uses its existing strict idle gate and passes `padding: current.padding` to the existing relayout alongside button/bounds/shape. Install the entire snapshot before readiness; after readiness, re-read geometry and recheck model/token/source authority as today. Any callback-time metrics/transform change must prevent stale push. `checkGeometry()` and existing source paint/input/clock/hand-back fences automatically compare availability. A changed active rectangle follows existing sticky retirement, deferred replacement, shown-popup continuation and tail abandonment. No model, transfer or clock API changes and no rebasing.

This has a deep unchanged public interface: one private projection function hides units, transformations, clipping and fit validation; one immutable snapshot owns all admitted placement facts (boundary-discipline, single-source-of-truth). Derived padding has no mutable synchronized copy. Red-flag screen: no new public stages, observer/cache, pass-through adapter, split writer or hand-maintained invalidation list.

## Synthesis decision

Reserved for the fresh arena judge; this runner selects no winner.

## Tradeoffs accepted

- Accept observation-based invalidation in exchange for preserving the existing lifetime and scheduling surface. Settled retained content has no immediate metrics notification guarantee.
- Accept conservative refusal of partially covered sources and too-small viewports in exchange for keeping measured menu dimensions unchanged.
- Accept old shown placement potentially remaining behind the keyboard in exchange for preserving old popup/model/time. This is host policy, not native IME following.

## Alternatives considered

A binding observer owned by each source session could trigger checks immediately on metrics changes, but adds subscribe/unsubscribe, scheduler-phase and stale-token obligations without solving root-transform-only changes. It hides prompt invalidation behind the same public surface but expands private lifecycle; this candidate defers that independent capability. Passing caller-supplied padding exposes coordinate and consumption policy to every caller and therefore loses interface depth.

## Open questions and risks

Would release behavior require immediate settled-popup reaction or native active keyboard movement? Either needs separate evidence and design. Can floating keyboards/nonrectangular display features be represented by edge metrics? This bounded rectangle policy makes no such coverage claim.

## Next implementation step

Implement projection and snapshot padding, then use existing measured harnesses to cover DPR1/2, all asymmetric safe/IME edges with max-not-sum, translated/scaled/already-safe smaller overlays, partially off-view roots, local fake/removed MediaQuery, exact fit versus narrow/short/empty/overflow rejection, covered source, readiness reentry, idle recapture and active shown/hidden/reserved/tail loss. Add raw-metrics-change/equal-effective-rect survival and root-motion changed/equal-effective-rect cases; rerun zero-inset fixed replay and measured tail pixels unchanged. No device/native parity claim follows from host passes.
