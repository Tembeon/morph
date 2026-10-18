# P2: dozing route clocks and frame-clock continuity

2026-10-18 and 2026-10-19, bases `1822d6b2` and `7ed8e5f3`. Flutter 3.47.2 stable, host `flutter_test`.

## Why

Clause C of the P2 predicate asks for an exact time transfer when clocks doze. The product menu host dozes while a finger rests on the menu and the next change is due later, for example a submenu card after `hoverOpenDelay`. The prototype route and source clocks always reported no wake time, so they sampled every frame and the real route never dozed. Clause C could not be checked there.

## Change

The probe's route and source clocks now doze on `MorphMenuMotion.wakeTime`, converted to the owner's local time by `ProbeMenuTransfer.wakeTime`. This matches the product host.

That exposed a defect. Commands issued outside a frame read the clock's last sampled time. During a doze that time lags by the whole doze. Escape stamped the close, and a covering route stamped the pointer cancel, 66.7 ms in the past at 60 Hz and 33.3 ms at 120 Hz in the test scene. The close would jump on its first frame. All eight doze cases failed this way before the fix.

Off-frame commands now read `resumeAt(now())`, which includes elapsed doze time. This covers the route close, the pointer cancel and ownership acquire.

A review found a second, older defect. Pointer input between frames advances the model past the clock's last sample, and the close already used that sample, so a close right after a move started before the move. The new cancel path had the same flaw. `ProbeMenuTransfer` now never starts an open, close or cancellation before the model's own time, and reports the time it used as `commandTime`. The `.close` and `.cancelInput` samples carry that time, which is what the replay oracle already assumed. Without a doze and without input between frames, every command time is unchanged.

## Checks

- `example/test/proto/menu_route_doze_test.dart`, doze cases. Eight cases, 60/120 Hz by 1x/5x by Escape/cover. A finger rests on a submenu row and the route stops sampling for at least four frames before the card is due. The command time equals the last frame time plus elapsed wall time over dilation, within 1e-6 s. From the close command on, each step through closing, landing, hand-back and the source tail advances by the frame-clock interval over dilation, within 1e-6 s.
- The same file, between-frame cases. Four cases, 60/120 Hz by Escape/cover. A move between frames advances the model past the last frame, and the following command never starts before the move.
- `example/test/proto/menu_route_replay_test.dart` checks every pair of consecutive non-settled motion frames in all 20 recorded replays. Motion time advances by the frame-clock interval within 0.1 ms across route and source owners, including hand-back and reopen. The earlier oracle compared against canonical model time and could not see a skip.

## Receipts

- `negative_controls.py` applies three mutations one at a time, runs the two test files and restores the source. `negative-controls.log` holds its output. Shifting the hand-back anchor 8 ms early fails 28 cases. Removing the model-time floor fails the four between-frame cases. Closing on the last sampled time fails the four Escape doze cases.
- `host-tests.log` holds the full example run (464 passed) and `analyze.log` the package analysis. Its concurrent reporter names only some tests, so `targeted-tests.log` repeats the doze, between-frame, replay, frame-phase and P1 route files one at a time with every test named (72 passed).

## What this proves and what it does not

A route to source hand-back cannot start from a dozing clock in this design. The menu motion reports no wake time while closing, and the source clock is paused while the route owns the model. The reachable doze cases are off-frame commands during a route doze, which the doze cases cover.

A source to route acquire from a dozing source is not exercised. Its code reads the same doze-inclusive time, but no test shows it. Changing `timeDilation` during a transfer stays unsupported by the clock contract and untested.

The 120 Hz cases change the pump cadence only. The probe clocks keep their default `frameRate` of 60, so doze thresholds, wake margins and fallback pointer stamps use 60 Hz values in every case.

Clause A still matches native geometry only transitively. The route equals the product model at 1e-9, and product tests compare that model with device fixtures. Clause B covers the reduced flat bar only. The product bar and the liquid and fake tiers need device pixels and belong to units 5.3 and 6.
