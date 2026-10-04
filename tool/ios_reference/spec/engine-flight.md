# Engine flight springs passport (liquid, glacial, instant)

Status: tuning read live; ported (engine default everywhere).

## Native

`AnimationKit.MorphAnimationSettings.liquidMorph` (eject / absorb springs,
speed 0.7 that DIVIDES time) [tuning; dump
/tmp/morph-native/menu-settings-dump.txt, volatile].

## Spec

- `MorphMotion.liquid` (THE default: controller, showMorph*, MorphTheme
  unset): open 0.35/0.75 (eject 0.5/0.75 / 0.7; overshoots ~3 percent, p
  peaks 1.028), close 0.49/0.80 (absorb 0.7/0.8 / 0.7; undershoots ~1.5
  percent = the handoff latch's zero crossing).
- `glacial` = liquid with every response x5 (a magnifier for the eye, not
  a design value).
- `instant` = 281 ms critically damped both ways (reduced motion, tests) -
  NOT a cut.
- Frame geometry: center AND size extrapolate linearly with the raw value
  above 1, so the liquid open's ~3 percent progress overshoot applies to
  each axis's source-to-target travel. The concentric radius extrapolates
  on the same value, bounded by zero and half the live shortest side;
  opacity, reveal scale, color and elevation remain clamped, as does the
  border side interpolation of uniform shapes.
  Negative values keep the source size and radius while the center
  extrapolates; dimensions never become negative. Unsupported shapes use
  ShapeBorder.lerp with the nonnegative raw value.
- The landing is the close spring's own undershoot; nothing added (UIKit
  adds nothing). A close from rest starts still.
- Reversal = retarget from (value, velocity); UIKit does the same (a close
  mid-open fits only with velocity carried).
- Other measured flight motions: context menu `measuredMotion` 0.284/0.81
  both ways (context-menu.md); scrim springs via `MorphScrimMotion`.
- Spring vocabulary: `MorphSpring(response, dampingRatio)`, k = (2 pi /
  response)^2, c = 4 pi zeta / response, mass 1; `toMotion()` is a motor
  SpringMotion over the exact description (NOT CupertinoMotion, which
  truncates to whole ms and maps zeta > 1 to 1 / (2 - zeta)).

## Fixtures

Menu fixtures (`ios27{,-device}/menu`) carry the progress the springs were
read against; menu_button_test replays them.
`ios27-device/context_menu/morph.json` records container size overshoot:
ctxd-l-1 grows from an 83.2 x 80 blob to 250 x 208, peaking at
253.16 x 210.18 (width travel progress 1.0189448441247). The engine frame
test pins that width; a liquid open test pins ~1.028 size travel progress.

## morph

lib/src/spring.dart, lib/src/motion.dart (`MorphMotion.springs`, `values`),
lib/src/controller.dart (handoff latch). Tests: morph_controller_test,
morph_frame_test, morph_contract_asserts_test.
`morph_flight_overshoot_test` checks the shuttle, skin mirror blob and
shared element against the raw-value rect before the route's settle latch,
then checks the settled route and close handoff. The shuttle and skin use
the same rect/radius helpers; shared elements extrapolate their own
endpoint rects, and the settled route adopts content only at spring rest.

## Gaps

None; the engine also accepts any motor Motion.
