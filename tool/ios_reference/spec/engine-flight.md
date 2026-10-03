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

## morph

lib/src/spring.dart, lib/src/motion.dart (`MorphMotion.springs`, `values`),
lib/src/controller.dart (handoff latch). Tests: morph_controller_test,
morph_frame_test, morph_contract_asserts_test.

## Gaps

None; the engine also accepts any motor Motion.
