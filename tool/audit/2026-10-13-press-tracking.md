# Press tracking across the widget layer (2026-10-13)

Read-only audit of how every control in `lib/src/widgets/` follows a touch,
against UIKit's `UIControl` tracking model and against each other. Branch
`audit/glass-composition` at 1e88c73. No code was changed and no test was
run. Native numbers are quoted only from the passports in
`tool/ios_reference/spec/` or from lib dartdoc that cites a measurement;
everything else is marked UNMEASURED.

## TL;DR

- There are two tracking families. Seven controls (glass button, segmented
  control, switch, slider, stepper, page control, tab bar) share
  `MorphControlHost` (control_host.dart) on top of `MorphTouchListener`
  (touch_listener.dart): one primary pointer, arena ownership after
  150 ms or a drag along the control's axis, cancel on scroll. The other
  ten (alert, bar items, date picker label, menu button and menu rows,
  context menu, navigation edge pop, push zoom, search field, sheet,
  search tab bar circles) each hand-roll their own `Listener` /
  `GestureDetector` logic, with different delays, slops, bounds and
  pointer bookkeeping.
- What a user sees most: inside a scroll view the glass-family controls
  react at contact (lift, glow, lens lift, highlight) and then drop when
  the list takes the touch, because only the tab bar, the date picker
  label and the search field set `delaysInScrollable`. UIKit holds a
  touch back from scroll-view content (`delaysContentTouches`); the 150 ms
  morph uses for that is NOT measured on the device anywhere in the repo.
- Likely bugs: (1) the menu button opens its menu on a release anywhere,
  however far the finger slid off; (2) an alert whose content scrolls
  (its card is a `ListView`) tracks on a raw `Listener` outside the arena,
  so a finger that scrolls the alert and lifts over an action CHOOSES it;
  (3) the segmented control, the switch and the page control commit on a
  release anywhere on screen, so sliding away never cancels; (4) the search
  field tracks no pointer id, so a second finger corrupts the first
  finger's tap test.
- The extended tracking bounds differ per control in morph: 70 pt around
  the glass button and bar capsules, 0 for the date picker label, alert
  actions and stepper, unbounded for segmented / switch / page control /
  menu button, and an 18 pt travel test for the search field and the sheet
  grabber. The passports measure only the stepper (no slop, stepper.md:
  44-47) and state the button's 70 (glass-button.md:27) without a
  recording that releases outside.
- Proposal: one `MorphPress` primitive (arena ownership + extended bounds
  + keyboard + semantics in one widget, a pure `MorphPressTracker` under
  it) that `MorphControlHost` adopts unchanged first, then alert, menu
  button, bar items, date picker label and search field move onto. Seven
  iPhone captures are needed before the bounds and delays are filled in.
- Stretch / lean / rubber band: buttons, bar capsules, alert platter,
  segmented lens, tab bar, switch, slider, push zoom, context menu growth
  are measured and ported. NOT ported or not measured: the sheet's ~2
  percent stretch below its smallest detent (passport says not
  reproduced), the menu's stretch toward a dragging finger (morph leans
  at most 2 px from unmeasured constants; the lab scenario
  `menu-drag-out.json` from 8550478 exists but has not been run), any
  lean of the menu button or search field under a dragging finger.

## The UIKit model being compared against

Documented behaviour of `UIControl` / `UIScrollView` (Apple docs, not
measured in this repo unless a passport line is cited):

- A control tracks ONE touch (`beginTrackingWithTouch`,
  `continueTrackingWithTouch`, `endTrackingWithTouch`,
  `cancelTrackingWithEvent`); `isTouchInside` and the touch-up-inside /
  touch-up-outside / drag-exit / drag-enter events are computed against
  the bounds EXTENDED by a margin (folklore: 70 pt). `isHighlighted`
  follows drag-exit / drag-enter, so sliding back re-highlights.
- Inside a `UIScrollView`, `delaysContentTouches` (default YES) holds a
  touch back from the content until it has stayed still for a short delay
  (folklore: 150 ms); a scroll that starts first never reaches the
  control. After delivery, `touchesShouldCancelInContentView:` returns NO
  for a `UIControl`, so a scroll no longer takes the touch.
- Since iOS 6 a control's default action wins over an overlapping gesture
  recognizer on an ancestor (single tap on button / switch / stepper /
  segmented / page control; a swipe parallel to a slider's thumb or a
  switch's knob).

Measured in the passports:

| fact | source |
|------|--------|
| glass button stays lifted for the whole touch "even far outside"; `onPressed` fires when the finger lifts within 70 px | glass-button.md:25-27 (no fixture releases outside: `button-glass-120x44-drag-off-back` returns to the center before lifting, test/controls_test.dart:251-281) |
| stepper: leaving the control through its edge (x 248 = maxX, NO slop) drops the highlight; a release outside changes nothing; crossing the divider moves the highlight and the repeat without a step | stepper.md:44-47 [device] |
| tab bar: "Inside a Scrollable the WHOLE touch is held until owned: 0.15 s hold ... (UIKit delaysContentTouches)" | tab-bar.md:23-26 - the 0.15 s is NOT tagged as measured; no capture in the repo measures a scroll-view touch delay (`/usr/bin/grep -rn delaysContentTouches` finds only this line, segmented-control.md:68 and touch_listener.dart:196) |
| segmented: selects on touch-UP; a press on a non-selected segment does nothing until release; press on the selected segment lifts after 40 ms | segmented-control.md:20-27 [device] |
| tab bar selects on touch-DOWN; release picks the tab nearest the finger | tab-bar.md:23, 28-31 [device] |
| switch: tap toggles on RELEASE; drag commit / uncommit rules | switch.md:21-24 [device recapture] |
| slider: only the thumb is a handle; a track tap does nothing; pan after 11 pt | slider.md:23-24 |
| page control: a tap on either half steps on the LIFT; platter after 0.193 s | page-control.md:25-27 [device] |
| alert: the finger may slide between buttons; pressed fill 0.4 of its alpha | alerts.md:31-35 [device] |
| menu button: tap opens on release; hold opens after 0.22 s and the finger may slide onto a row; a held finger released without leaving the button chooses nothing | menu-button.md:84-88 [device] |
| menu rows: the device shows NO tap highlight on rows; morph still highlights | menu-api.md:451-453 (not ported) |
| context menu: commit at 0.42 s (0.400 cancels, 0.433 opens), open at 0.78 s | context-menu.md:19-27 [device] |
| search field: lifts on the glass-button model 0.05 s after contact; a held touch focuses when it lifts | search.md:29-30 [device] |
| date picker label: text dims toward ~0.5 under a touch on a 0.47 s curve | date-picker.md:20-22 [layout] |
| disabled controls show no reaction to a 0.8 s hold, except the tab bar's swell | states.md:46-50 [device] |
| sheet: a touch swells a floating sheet 1.00854 after 28 ms; grabber tap cycles detents 50 ms after the lift | sheets.md:36, 45 |
| bar back button: release before 0.4 s = tap; menu at 0.595 s; lifting ON the button after it opened fires the button; moved off leaves the menu open | bars.md:187-193 [device] |

## Control x behaviour

Legend. Arena: `MTL` = `MorphTouchListener` (joins the arena, owns after
150 ms or an axis drag past slop), `MTL+delay` = with `delaysInScrollable`
(nothing reported until owned), `raw` = plain `Listener` (never in the
arena, never cancelled by a scroll), `GD` = `GestureDetector` / Flutter
recognizers. "Release rule" = where the finger may lift and still commit.

| control | arena | contact in a scroll view | press feedback | slide off | slide back | release rule | scroll after ownership | 2nd finger | secondary button | keyboard |
|---|---|---|---|---|---|---|---|---|---|---|
| glass button | MTL | lifts + glows at once, drops on cancel | lift, glow, lean d abs(d)/10000 + stretch | stays lifted, keeps leaning | n/a (no visual edge) | within 70 of the box (glass_button.dart:51, 240) | blocked | ignored | ignored | Space/Enter, ring |
| bar items (capsule) | raw | (bars are not in scroll views) | glass-button model on the CAPSULE | stays lifted | n/a | within 70 of the CAPSULE, fires the button first pressed even if lifted over a sibling (bar_items.dart:1286-1311) | n/a (raw) | ignored (one per bar) | ignored | NONE (no focus) |
| segmented | MTL, axis h | press on selected lifts after 40 ms, then drops | lens lift on selected only | lens follows (selected) / nothing (others) | follows | ANYWHERE: slot nearest finger x, y ignored (lens_motion.dart:457-466) | blocked | ignored | ignored | arrows |
| tab bar | MTL+delay, axis h | nothing until owned | select on down, lift, swell, glow | lens scrubs, rubber band | follows | anywhere: nearest tab x | blocked | ignored | ignored | arrows |
| switch | MTL, axis h | knob lifts at once, drops | knob lift (small lens) | knob drags, rubber band | follows | ANYWHERE: toggles if never committed (switch_motion.dart:160-167) | blocked | ignored | ignored | Space/Enter |
| slider | MTL, axis h, onPointerLost reverts | thumb lifts at once, value reverts on loss | thumb lift | thumb keeps tracking (UIKit too) | follows | anywhere (drag), glide | blocked | ignored | ignored | arrows (keyboardStep) |
| stepper | MTL | highlight at once, drops | instant 8 % overlay, repeat 0.5 s | ends tracking at the edge, no slop (stepper.dart:236-243) | NO (pointer released) | inside the box | blocked | ignored | ignored | Space/Enter = plus, arrows |
| page control | MTL | nothing visible (platter 0.193 s > 150 ms) | platter after 0.193 s | scrub by x | follows | ANYWHERE: steps toward the side of x (page_control.dart:257-271) | blocked | ignored | ignored | arrows |
| menu button | MTL | scale after 15 ms (pressDelay), drops | scale only, no lean | stays pressed; hold timer keeps running | n/a | ANYWHERE: a tap opens on release however far off (menu_motion.dart:2029-2045) | blocked | ignored | ignored | NONE (Semantics onTap only) |
| menu rows | raw (+ scroll notification) | highlight at once | highlight pill, glow, lean <= 2 px | highlight follows | follows | row under the finger; outside the menu closes after 0.059 s | a content scroll cancels choice (menu.dart:1099-1112) | ignored | ignored | arrows, Enter/Space, Escape |
| context menu region | GD (tap + long press) + ownership recognizer (claimsOnDelay false) | tap-down at Flutter's 100 ms deadline | growth from 0.184 s | long press cancels past Flutter's slop (18) | no | commit at 0.42 s, open at 0.78 s | wandering held finger claimed | n/a | opens menu (opensOnSecondaryTap) | NONE (Semantics onLongPress) |
| date picker label | MTL+delay | nothing until owned | text dims | stays dimmed | stays dimmed | inside the EXACT box (date_picker.dart:497-505) | blocked | ignored | ignored | Space/Enter |
| search field | MTL+delay | nothing until owned | scale lift | stays lifted | n/a | travel from down < 18 (kTouchSlop), bounds ignored (search_field.dart:247-258) | blocked | NO pointer id: a 2nd finger overwrites `_downAt` | ignored | focusable as text |
| alert actions | raw | highlight + platter lift at once | platter lift + lean (pull 0.25), fill 0.4 | highlight moves between buttons | follows | inside an action's EXACT box (alert.dart:549-559) | NOT cancelled: the card is a ListView (alert.dart:1155) | ignored | ignored | Escape, Enter = preferred, Tab between actions |
| alert popover | raw | highlight at once | no lift (measured, alerts.md:45) | as alert | follows | as alert | as alert | ignored | ignored | as alert |
| sheet body | raw + vertical drag GD | swells on any touch, incl. a scroll inside | swell 1.00854 | drag moves height | n/a | grabber tap: travel < 18 and top band | n/a | ignored | NOT checked: a right click swells and taps the grabber (sheet.dart:557-566) | n/a |
| push zoom page | pan GD (13.5 pt slop, direction filter) | n/a | none until slop | page shrinks about the touch | follows | 132.5 pt / 1050 pt/s | n/a | n/a | primary only (pan default) | n/a |
| navigation edge pop | horizontal drag GD, 20 pt edge | n/a | none | page follows 1:1 | follows | 0.3 width / 1.06 widths/s | n/a | n/a | primary only | n/a |
| search tab bar circles | GD onTap | tap | NONE (no lift) | n/a | n/a | Flutter tap slop | n/a | n/a | n/a | NONE |
| list rows (reference) | GD | tap-down at 100 ms deadline | highlight | Flutter tap cancels past slop | no | Flutter tap | n/a | n/a | n/a | Space/Enter |

Notes on the table:

- "blocked" = after `MorphTouchRecognizer` claims the pointer (150 ms
  still, or a drag past slop along `dragAxis` when no enclosing
  scrollable scrolls on that axis), every other arena member is rejected:
  a list, a sheet's vertical drag, the push-zoom pan or the edge pop can
  no longer take that finger. That matches the documented UIKit rule for
  scroll views; for a SHEET pan or the push-zoom pan holding a control is
  UNMEASURED.
- `MorphTouchListener` adds every pointer to the arena, including ones the
  host then ignores (a slider track tap, a stepper touch with no half, a
  second finger). A finger resting 150 ms on a slider's TRACK therefore
  blocks the list from scrolling although the slider does nothing with
  it. UIKit would deliver that touch to the slider too (and the slider
  would not track it); whether the scroll view then still scrolls is
  UNMEASURED.
- Disabled: every MTL host passes `enabled: false`, so the touch never
  enters the arena and the host ignores it; the tab bar stays in the
  arena so it can swell (states.md:46-50 measured). Disabling mid-touch
  cancels (control_host.dart:194-198); the date picker label and search
  field do the same by hand; the alert, bar items and menu button rely on
  their own checks.

## Inconsistencies, ranked by how visible they are

1. **Flash at the start of a scroll (very visible, every list).** Glass
   button, segmented (selected segment), switch, slider, stepper and menu
   button react at contact inside a scroll view and drop when the scroll
   wins; the tab bar, date picker label and search field hold the whole
   touch back. A finger that starts a scroll on a button in a list lifts
   and glows it for one to several frames. Native: held back
   (delaysContentTouches), delay UNMEASURED. Fix: `delaysInScrollable`
   becomes the default; the 150 ms needs a capture (M1 below).
2. **Menu button opens on a release anywhere (visible, bug).**
   `MorphMenuMotion.pointerUp` opens on any non-hold release from the
   button (menu_motion.dart:2038-2045); `leftButton` is recorded but only
   consulted once the menu is already open. A user who presses, slides
   away to cancel and lifts gets a menu. UIKit's touch-up-inside would
   not fire past the extended bounds; the menu button's own release-
   outside rule is UNMEASURED (menu-button.md has hold and slide rules
   only).
3. **Alert actions are not cancelled by a scroll (bug, rare but
   destructive).** The alert tracks on a raw `Listener` (alert.dart:647)
   around a card whose content is a `ListView` (alert.dart:1155, scrolls
   when the text, fields or Dynamic Type overflow the screen). A finger
   that lands on an action, scrolls the alert and lifts over any enabled
   action fires it (alert.dart:589-598), and the platter leans with the
   scroll. The menu rows already solve this with a scroll notification
   (menu.dart:1099-1112).
4. **No way to cancel by sliding away: segmented, switch, page control
   (visible to iOS users who cancel that way, likely bugs).** Segmented
   picks the slot nearest the finger's x even 300 pt below the control;
   the switch toggles on any release of a drag that never committed; the
   page control steps toward the side of x. Glass button and bar items
   use 70, alert / date picker / stepper use the exact box. Native release-
   outside rules for these three are UNMEASURED (M2).
5. **Date picker label (moderate).** The dim stays while the finger is
   outside and the commit bound is the exact box (no 70); the glass button
   next to it in a form accepts a release 70 pt away. Native UNMEASURED.
6. **Three different touch-down delays (moderate, felt not seen).** 0 ms
   (MTL without delay, raw listeners), 100 ms (`TapGestureRecognizer`
   deadline: context menu growth, list rows), 150 ms (MTL ownership).
   List rows highlight on tap-down after 100 ms; lists.md:106-108 already
   lists the native highlight timing as open.
7. **Lean / stretch coverage differs among glass-model surfaces
   (moderate).** Glass button, bar capsules and alert platter lean after
   the finger; the menu button and the search field only scale; the
   search tab bar circles do not react at all. Whether the native menu
   button, search field and tab-bar circles lean is UNMEASURED.
8. **Menu rows highlight under the finger (moderate, documented).** The
   device shows no tap highlight on rows (menu-api.md:451-453); morph
   highlights at contact.
9. **Keyboard (low on phones, high on desktop / web).** Glass button,
   segmented, tab bar, switch, slider, stepper, page control, date picker
   label, alert actions and list rows go through `MorphControlFocus`. Bar
   items, the menu button, the context menu region and the search tab bar
   circles are not focusable at all; only Semantics actions reach them. No
   control shows its press look on Space / Enter (native iPad behaviour
   UNMEASURED).
10. **Bar items activate the first-pressed button anywhere in its capsule
    + 70 (low).** Sliding from one bar button onto a sibling in the same
    capsule and lifting fires the first one. Native UNMEASURED.
11. **Stepper does not re-highlight on slide-back (low).** It releases the
    pointer at the edge (measured: no slop, no step on a release outside);
    whether UIKit re-highlights a re-entering finger is UNMEASURED.
12. **Pointer bookkeeping (low, bugs).** Search field: no pointer id, a
    second finger's down replaces `_downAt`, so the first finger's lift is
    tested against the wrong origin (search_field.dart:239-258). Sheet: no
    button filter on `_down`, a secondary click swells the sheet and can
    cycle detents (sheet.dart:557-581).
13. **Holding a control blocks ancestor pans (low, unmeasured).** After
    150 ms a held glass button inside a sheet or a zoom-pushed page keeps
    the sheet drag, push-zoom pan and edge pop from starting. Raw-listener
    controls (alert, bar items) never block. Native UNMEASURED.

Bugs by confidence: 2 and 3 are bugs on any reading of UIKit; 12 is a bug;
4 is very likely a bug (UIKit's touch-up-inside semantics) but needs M2
before choosing the bound; 1 is a fidelity gap whose number needs M1.

## Proposal: one press-tracking primitive

The glass-family path already works (`MorphTouchListener` +
`MorphControlHost`). The proposal folds the remaining hand-rolled paths
into it and adds the two concepts it lacks: extended bounds with
enter / exit, and the press policy as data.

```dart
/// What the control does with a touch; one value per control, from its
/// passport.
@immutable
class MorphPressPolicy {
  const MorphPressPolicy({
    this.holdBackInScrollable = true,   // delaysContentTouches
    this.ownershipDelay = morphTouchOwnershipDelay, // M1
    this.dragAxis,                       // claims a drag along the axis
    this.trackingSlop = 70,              // M2, per control; 0 = exact box
    this.trackingShape,                  // null = the render box
    this.buttons = kPrimaryButton,
    this.secondary = false,              // context menu's right click
  });
  ...
}

/// A pure tracker: one pointer, inside / outside against the extended
/// bounds, drag-exit / drag-enter edges. No widgets, replayable from
/// fixtures like the motions.
class MorphPressTracker {
  MorphPressTracker(this.policy);
  void down(double t, Offset local, Size size);
  void move(double t, Offset local);          // emits exit / enter
  MorphPressEnd up(double t, Offset local);   // inside or outside
  void cancel(double t, MorphPressLoss why);  // scroll, platform, disabled
  bool get inside;
}

/// The control side: what the host implements (MorphControlHost already
/// has these four, plus the two edges).
abstract interface class MorphPressTarget {
  void pressBegan(double t, Offset local);
  void pressMoved(double t, Offset local, {required bool inside});
  void pressExited(double t);
  void pressEntered(double t);
  void pressEnded(double t, Offset local, {required bool inside});
  void pressCancelled(double t, MorphPressLoss why);
}

/// The one widget: MorphControlFocus (Space / Enter / arrows, ring) +
/// Semantics (onTap) + MorphTouchListener (arena, hold-back) + the
/// tracker, plus a ScrollNotification listener for a scrollable INSIDE
/// the target (alert card, menu rows) that cancels like an outer scroll.
class MorphPress extends StatefulWidget {
  const MorphPress({
    required this.policy,
    required this.target,
    required this.child,
    this.enabled = true,
    this.onActivate,       // keyboard and semantics
    this.onStep,
    this.semanticLabel,
  });
}
```

Rules it would enforce for everyone: one pointer, primary button unless
the policy says otherwise, pointer ids always checked, cancel on disable,
a scroll (outer or inner) cancels before ownership and is blocked after,
keyboard activation through the same `onActivate` the tap uses.

Order of moves:

1. `MorphControlHost` builds `MorphPress` instead of `MorphTouchListener`
   + `MorphControlFocus`; behaviour unchanged except `holdBackInScrollable`
   (needs M1). Glass button is the reference and keeps its 70.
2. Alert actions (bug 3): the inner `ListView` scroll cancels; exact
   button boxes stay until M2 says otherwise.
3. Menu button (bug 2) and bar items (keyboard, sibling slide): the menu
   motion asks the tracker's `inside` at release; bar items get focus.
4. Search field and date picker label: replace the kTouchSlop travel test
   and the exact box with the policy's bounds; add pointer ids.
5. Segmented, switch, page control: release-outside cancel once M2 gives
   their bounds.
6. Sheet and context menu keep their recognizers (they are drags and
   holds, not presses) but take the button filter and pointer rules.

## What needs an iPhone measurement first

All on the iPhone 16 Pro with the device lock; probe scenes exist for
every control (README recapture lines in each passport).

- M1. Scroll-view touch delay: a glass button, a segmented control and a
  stepper inside a `UIScrollView`; still holds of 50 / 100 / 130 / 150 /
  170 / 200 ms, frame of first lift / highlight; quick swipes starting on
  them (does anything flash?). Replaces the unmeasured 150 ms
  (touch_listener.dart:10) and the tab bar's 0.15 s (tab-bar.md:24).
- M2. Extended tracking bounds: press, slide off by 30 / 50 / 60 / 70 /
  80 / 100 pt in each direction, release; per control: glass button
  (confirms glass-button.md:27), menu button tap, bar button (and onto a
  sibling in the same capsule), alert action, date picker label,
  segmented (non-selected and selected), switch tap-drag-away
  perpendicular, page control, search field. Record the highlight /
  lift edges too (drag-exit, drag-enter).
- M3. Slide-back: stepper and alert action, leave and re-enter, release
  inside.
- M4. Scroll after ownership: hold a glass button 300 ms in a scroll view,
  then drag; repeat in a sheet (sheet pan) and on a zoom-pushed page.
- M5. Context menu hold tolerance: how far a held finger may wander
  before the 0.42 s commit is lost.
- M6. Press lean on the glass menu button, the search field and the
  search tab bar circles (button-glass drag-off-back protocol).
- M7. Keyboard on iPad (optional): does Space show the press look.

## Stretch, pull, lean, squash: what iOS does and what morph ports

| element | native (passport) | morph |
|---|---|---|
| glass button | drag-off LEAN tx = d abs(d) / 10000 px plus a stretch along the drag; stays lifted far outside (glass-button.md:25-27) | ported: `MorphGlassButtonMotion.leanDivisor` 10000, `leanStretch` 0.0064 (glass_button.dart:43-48), replayed by `_leanReplay` |
| bar capsules | press lifts the capsule on the glass-button model, 1 + 16/w (bars.md:43) | ported: bar items drive a `MorphGlassButtonMotion` per capsule (bar_items.dart:1210), lean included |
| alert platter | the whole platter lifts with the button model; a dragging finger pulls it with `platterPull` 0.25 and `platterStretch` 0.6 [device: 0.4 pt lean per 120 pt drag] (alerts.md:31-34) | ported (alert.dart:432-433, 702) |
| action sheet popover | does NOT lift under a touch [device] (alerts.md:45) | ported (no press on a popover, alert.dart:576) |
| segmented lens | drag of the selected segment; rubber band past the end CENTERS (12, 0.55) (segmented-control.md:22-25) | ported (`MorphLensTuning.segmented`, lens_motion.dart `_follow`) |
| tab bar | scrub rubber band (4.55, 0.95); whole bar swells 14.6 px while pressed (tab-bar.md:28-37) | ported |
| switch | knob rubber band (12, 0.54); knob lift / stretch on the small lens (switch.md:24-26, lens-and-flex.md:56-61) | ported |
| slider | past an end the WHOLE track stretches: near edge 13/0.74, far edge 0.357 of it, height thins (slider.md:30-32); thumb small-lens stretch | ported |
| sheet | floating sheet swells 1.00854 under a touch (sheets.md:36); the drag moves the height point for point with "nothing above the largest detent, a slide below the smallest" (sheets.md:37-38); ~2 percent vertical stretch of a sheet pulled below its smallest detent (sheets.md:97) | swell ported (`MorphSheetTuning.pressScale`, sheet_motion.dart:134); the 2 percent stretch is listed under "Not reproduced" (sheets.md:93-97); nothing above the largest detent, as measured |
| sheet zoom scrub | drag down from the smallest detent: top 1.115 per pt, sides in 0.275 (sheets.md:58-63) | ported (`MorphZoomTuning.scrubFrame`) |
| menu (open) | NOT in any passport: no capture of the menu following or stretching toward a finger dragged off it | morph leans the menu toward the finger by 0.033 px per px from its center, clamped to 2 px per axis (menu_motion.dart:62-63, 2008-2014), constants with no measurement; no stretch. Scenario `tool/ios_reference/lab/scenarios/menu-drag-out.json` (8550478, "to replace the 2 px lean") is committed but not yet run |
| menu button (press) | passport has no lean or stretch for the press | scale only (menu.dart `_pressScale`) |
| context menu | growth while held: 0 until 0.184 s, 32 pt/s to 8 pt at 0.434, then 20 pt/s to 15 pt (context-menu.md:21-25); no stretch toward the finger measured | growth ported (`measuredHoldGrowth`) |
| push zoom page | drag shrinks the page about the touch point: down width 0.00078 / height 0.00154 per pt, center 0.61; sideways 0.00156 / 0.00168, center 0.95 (navigation-pages.md:116-124) | ported (push_zoom.dart, push_zoom_test) |
| nav bar edge swipe | shared capsules drift 0.5 x page progress toward their destination, cancel leans back (bars.md:180-185) | ported |
| stepper | NO motion of any kind (stepper.md:17, 41) | none, as measured |
| page control, date picker | no stretch in their passports | none |

So the owner's observation matches the passports: the two surfaces that
do not stretch like native are exactly the two whose stretch is either
documented-but-unported (sheet below its smallest detent, ~2 percent) or
never measured (the open menu toward a dragging finger). The next steps
are running `menu-drag-out.json` on the device and fitting the sheet's
below-detent stretch from the existing `ios27-device/sheet-drag`
recordings (sheets.md:66-70) or a new capture if those rows do not carry
the body height.
