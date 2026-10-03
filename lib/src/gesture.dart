/// Building blocks for driving a morph with YOUR OWN gesture.
///
/// A prebuilt drag widget is intentionally absent: gesture policy (what
/// to drag, when to close) is an application decision and differs per
/// call site. The recommended mechanics live on the flight:
/// [MorphFlight.beginDrag] / [MorphFlight.dragBy] /
/// [MorphFlight.endDrag] - the whole container follows the finger 1:1
/// as one rigid body, and releasing decides commit by momentum
/// projection. The app supplies only the gesture (a pan detector on its
/// content) and, optionally, its own commit rule via `endDrag(commit:)`.
///
/// Expert path - scrubbing the morph VALUE itself (exposes the
/// fade-through midstates when frozen under a finger, so it suits only
/// short, fast scrubs such as predictive back):
///  - onPanStart: controller.beginScrub();
///  - onPanUpdate: project the delta onto the morph trajectory, divide
///    by its length -> updateScrub(value); beyond `[0, 1]` apply
///    [morphRubberband];
///  - onPanEnd: valueVelocity = projected velocity / travel length;
///    [morphProjectValue] decides "close or return";
///    controller.open/close(velocity: valueVelocity).
library;

/// The canonical overdrag resistance formula (rubber-banding):
/// f(x) = x*d*c / (d + c*x). Monotonic, asymptotically approaches d,
/// resistance is felt from the very first pixel (slope c at zero).
/// c = 0.55 is the classic iOS coefficient.
double morphRubberband(
  double x, {
  required double dimension,
  double coefficient = 0.55,
}) {
  if (x <= 0) {
    return 0;
  }
  return x * dimension * coefficient / (dimension + coefficient * x);
}

/// Momentum projection (WWDC18 "Designing Fluid Interfaces"): where the
/// value would coast to under natural deceleration. The "close or
/// return" decision is made from the projection, not from the current
/// position.
double morphProjectValue(
  double value,
  double velocityPerSecond, {
  double decelerationRate = 0.998,
}) {
  return value +
      velocityPerSecond / 1000 * decelerationRate / (1 - decelerationRate);
}

/// Default commit threshold for [MorphFlight.endDrag]: releasing with a
/// projected displacement farther than this (in px, any direction)
/// commits the close flight. Distance-based and direction-agnostic:
/// flinging the card anywhere reads as "throw it away".
const double morphDragCommitDistance = 140;

/// Default commit threshold on the release velocity (px/s): a hard fling
/// commits even when the projected distance stays short.
const double morphDragCommitVelocity = 1000;

/// The arm ramp for the commit cue: 0 below [morphDragCommitDistance],
/// smoothstepping to 1 over the next 60 px. Past the threshold the card
/// visibly "arms" - extra recede, thinner scrim, a slight lean toward
/// home - so the hand knows a release will close. A pure, reversible
/// function of the displacement: backing off disarms the same way.
double morphDragArm(double distance) {
  final double t = (distance - morphDragCommitDistance) / 60;
  if (t <= 0) {
    return 0;
  }
  if (t >= 1) {
    return 1;
  }
  return t * t * (3 - 2 * t);
}

/// How far the container has "receded into the hand" during a free
/// drag: a smooth asymptotic fraction (0 at rest, approaching 1) of the
/// displacement distance. Drives the subtle scale-down and the scrim
/// dimming while dragging - both stay pure functions of the
/// displacement, so interruption continuity holds by construction.
double morphDragRecede(double distance, {double dimension = 400}) {
  if (distance <= 0) {
    return 0;
  }
  return distance / (distance + dimension);
}

/// The scrim attenuation of a live drag: the factor the displacement
/// multiplies into the scrim opacity - thinning with [morphDragRecede]
/// and thinning further as [morphDragArm] rises. The one implementation
/// of the composition, shared by the shuttle and the settled route
/// page, so a drag dims identically on both sides of the second latch.
double morphDragScrimFactor(double recede, double arm) {
  return (1 - 0.5 * recede) * (1 - 0.35 * arm);
}

/// The container scale of a live drag: a subtle recede into the hand,
/// deepened by the arm cue. Shared by the shuttle and the settled route
/// page for the same reason as [morphDragScrimFactor].
double morphDragScale(double recede, double arm) {
  return 1 - 0.08 * recede - 0.05 * arm;
}
