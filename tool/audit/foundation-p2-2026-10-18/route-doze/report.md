# P2: dozing route clocks and frame-clock continuity

2026-10-18, base `1822d6b2`. Flutter 3.47.2 stable, host `flutter_test`.

## Why

Clause C of the P2 predicate asks for an exact time transfer when clocks doze. The product menu host dozes while a finger rests on the menu and the next change is due later, for example a submenu card after `hoverOpenDelay`. The prototype route and source clocks always reported no wake time, so they sampled every frame and the real route never dozed. Clause C could not be checked there.

## Change

The probe's route and source clocks now doze on `MorphMenuMotion.wakeTime`, converted to the owner's local time by `ProbeMenuTransfer.wakeTime`. This matches the product host.

That exposed a defect. Commands issued outside a frame read the clock's last sampled time. During a doze that time lags by the whole doze. Escape stamped the close, and a covering route stamped the pointer cancel, 66.7 ms in the past at 60 Hz and 33.3 ms at 120 Hz in the test scene. The close would jump on its first frame. All eight new cases failed this way before the fix.

Off-frame commands now read `resumeAt(now())`, which includes elapsed doze time and equals the last frame time while the clock ticks. This covers the route close, the pointer cancel (`cancelPointer` now takes the owner's local time) and ownership acquire. Without a doze nothing changes, and the previous 354 prototype checks still pass.

## New checks

- `example/test/proto/menu_route_doze_test.dart` has eight cases, 60/120 Hz by 1x/5x by Escape/cover. A finger rests on a submenu row and the route stops sampling for at least four frames before the card is due. The command time equals the last frame time plus elapsed wall time over dilation, within 1e-6 s. Every following frame through closing, landing, hand-back and the source tail advances by the frame interval over dilation, within 1e-6 s.
- `example/test/proto/menu_route_replay_test.dart` now checks every pair of consecutive non-settled motion frames in all 20 recorded replays. Motion time advances by the frame-clock interval within 0.1 ms across route and source owners, including hand-back and reopen. The earlier oracle compared against canonical model time and could not see a skip.
- Negative control. Shifting the hand-back anchor by 8 ms fails all 28 cases. The anchor is restored.

Example suite 452 passed (362 prototype checks), `flutter analyze` clean.

## What this proves and what it does not

A route to source hand-back cannot start from a dozing clock in this design. The menu motion reports no wake time while closing, and the source clock is paused while the route owns the model. The doze cases that remain reachable are off-frame commands during a route doze, which the new tests cover.

A source to route acquire from a dozing source is not exercised by a test. It now reads the same doze-inclusive time. Changing `timeDilation` during a transfer stays unsupported by the clock contract and untested.

Clause A still matches native geometry only transitively. The route equals the product model at 1e-9, and product tests compare that model with device fixtures. Clause B covers the reduced flat bar only. The product bar and the liquid and fake tiers need device pixels and belong to units 5.3 and 6.
