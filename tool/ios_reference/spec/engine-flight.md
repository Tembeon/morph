# Engine flight springs passport (liquid, glacial, instant)

Status: tuning read live; ported (the vessel flight under the button menu
and the context menu). No test replays the liquid springs against a
recording (see Fixtures).

## Native

`AnimationKit.MorphAnimationSettings.liquidMorph` (eject / absorb springs,
speed 0.7 that DIVIDES time) [tuning; dump
/tmp/morph-native/menu-settings-dump.txt, volatile].

## Spec

- `MorphMotion.liquid` (the default of `MorphController` and of
  `showMorph` without a motion; the button menu passes the same eject /
  absorb springs from `MorphMenuTuning`): open 0.35/0.75 (eject 0.5/0.75 /
  0.7; overshoots ~3 percent, p peaks 1.028), close 0.49/0.80 (absorb
  0.7/0.8 / 0.7; undershoots ~1.5 percent = the handoff latch's zero
  crossing).
- `glacial` = liquid with every response x5 (a magnifier for the eye, not
  a design value).
- `instant` = 281 ms critically damped both ways (reduced motion, tests) -
  NOT a cut.
- Geometry: the flight carries the progress only. Its one target,
  `MorphTargetSpec.vessel`, lets the content (menu, context menu) draw its
  own geometry from that progress; the menu passports hold the size laws.
- The landing is the close spring's own undershoot; nothing added (UIKit
  adds nothing). A close from rest starts still.
- Reversal = retarget from (value, velocity); UIKit does the same (a close
  mid-open fits only with velocity carried).
- Other measured flight motions: context menu `measuredMotion` 0.284/0.81
  both ways (context-menu.md); scrim springs via `MorphScrimMotion`.
- Spring vocabulary: `MorphSpring(response, dampingRatio)`, k = (2 pi /
  response)^2, c = 4 pi zeta / response, mass 1; `description` is the
  exact Flutter `SpringDescription`, run by `SpringSimulation` in
  `MorphController` and `MorphSpringState` (NOT CupertinoMotion, which
  truncates to whole ms and maps zeta > 1 to 1 / (2 - zeta)).

## Fixtures

Menu fixtures (`ios27{,-device}/menu`) carry the progress the springs were
read against. No current test loads their open and close rows
(center3-*, pos-*, *-dismiss); the liquid springs rest on the tuning read
alone.
`ios27-device/context_menu/morph.json` records container size overshoot:
ctxd-l-1 grows from an 83.2 x 80 blob to 250 x 208, peaking at
253.16 x 210.18 (width travel progress 1.0189448441247).
morph_context_menu_test replays ctxd-m-1 and ctxd-l-1 on the context
menu's own measured springs and checks that the liquid springs miss the
same close frames (fit error > 0.015).

## morph

All internal (lib/morph.dart exports none): lib/src/motion/spring.dart
(`MorphSpring`), lib/src/motion.dart (`MorphMotion.liquid`, `glacial`,
`instant`), lib/src/controller.dart (`MorphController`, handoff latch),
lib/src/flight.dart and lib/src/show.dart (the vessel flight,
`showMorph`). Tests: morph_context_menu_test, menu_context_motion_test.

## Gaps

- No replay of the liquid open and close against the menu recordings.
- The flight takes a `MorphMotion` (two `MorphSpring`s), not an arbitrary
  motion.
