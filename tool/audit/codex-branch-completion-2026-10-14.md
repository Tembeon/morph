# Interrupted Claude branches: completion, 2026-10-14

Scope: finish the four agents interrupted by the session limit, integrate them
into `wip/measured-liquid-glass`, and continue physical-device checks. The owner temporarily replaced the iPhone with a Pixel
6a; Pixel validation is complete. The returned iPhone supplies the UIKit
follow-up captures during the autonomous continuation on 2026-10-15.
No release to `main`, tag or push is part of this work.

Final status, 2026-10-15: all assigned branches are integrated, all required
device follow-ups are complete, and the final source checkpoint is `5e163f5f`.
The root suite passes 2,352 tests (two intentional skips), the example suite
passes 90, and format, analysis, dartdoc and all three native release builds
pass. The iPhone is free with the ordinary final gallery installed. Known
NEAR classifications and unsupported API gaps remain explicit in passports.

## Preserved and integrated work

- Context menus: `worktree-agent-a287832b3ca02ff82`, through `51616142`.
  Shared menu controller, rows, blob morph, composite preview, custom preview
  and accessory; eight commits preserved by merge.
- Search and tab bars: `worktree-agent-a958794b6d28dc670`, through `00904f22`.
  Stacked search, manual search tab role, minimize rules and controlled search;
  six commits preserved by merge.
- Navigation bars: `worktree-agent-a41eb6f5957868ba8`, through `fdcc6da4`.
  Title bounds, hiding, vertical scroll indicator. Five uncommitted gallery
  and count changes preserved in `93618e83` before merging.
- Navigation transitions: `worktree-agent-af36cf383ec30c339`, through `107aebd3`.
  Continuous card corners, under-page dim, content back swipe and gesture
  arbitration; three commits preserved by merge.
- Sheets were already merged into `338ae8a2`; the stopped `sheets-device`
  session had prepared a 68-line capture test but had not run it. The
  previously uncommitted test is also preserved and integrated.

Search/scaffold conflicts were resolved by retaining both stacked search's
presentation and toolbar search's animated bar hiding. Neither moves the
content twice. Documentation and migration entries from both branches remain.

## Host verification

The combined root suite completed: 2,293 passed, two intentionally skipped and
five count regressions. All glyph pixel tests passed with their original
thresholds. The count failures were fixed, not accepted by raising ceilings.
Two orphaned testers from the interrupted sessions were terminated before the
single combined run.

Follow-up fixes:
- Live hit testing for the hiding bar instead of a rebuilding value builder.
- Controlled toolbar hiding updates deferred out of ancestor builds.
- Stacked search shares its query controller at rest and mirrors its close
  button and field layout in right-to-left text.
- Six unnecessary proxy builds removed from the scaffold's indicator and hiding
  layout. The extended viewport keeps the scroll view mounted during hiding.
- The navigation dim draws black directly, with the former opacity layer's
  exact eight-bit alpha, avoiding extra layer wrappers. The clip reads the
  page's final layout size when painting and hit testing.
- The native sheet plan's medium screenshot is now scheduled before switching
  to the large detent.

Verification after fixes: all 153 focused performance, lifecycle and integration
checks passed; the final navigation recheck passed 81 tests. The card's actual
paint alpha is checked with the original `1e-3` tolerance (against the renderer's
quantized alpha), and all lifecycle ceilings stay at their integrated values.
Analysis reports zero issues. The example suite passed all 90 tests.

The two intentionally changed golden cells (`m/nav-bar/scroll` and
`m/context-menu/hold-close`, flat and fake) were compared with the pre-branch
version. They show the new scroll indicator and unified menu animation. Only
those four hash sequences were updated; the other 38 sequences stayed exact.
Temporary diagnostic code was restored. Captures and logs are in
`/tmp/morph-codex-goldens-{base,current}` and `/tmp/morph-codex-*.log`.

Code checkpoint: `0dd81ce2`.

## Pixel 6a

Real Vulkan/Impeller liquid and flat modes, automatic performance governor,
Thermal Status 0, no fixed clocks. Navigation: three repeats of six motions;
changed controls: three repeats of ten matrix cells per tier. The liquid
control raster p95 is 9.31–13.60 ms, below 16.67 ms. Transitional first-use
frames still occasionally miss the budget; this is not a claim of zero jank.

The first navigation run's steady/title energy varied; a five-repeat comparison
in reverse source order checked it again:

| scene | raster p95 before / after (ms) | rail power before / after (mW) |
|---|---|---|
| steady, liquid | 10.74 / 10.94 | 760 / 693 |
| steady, flat | 8.05 / 7.06 | 531 / 525 |
| title, liquid | 11.34 / 11.41 | 644 / 651 |
| title, flat | 8.35 / 7.63 | 526 / 559 |

These are bounded scene measurements, including whole-device power rails;
small differences are not statistically established improvements. No sustained
regression was confirmed. Source before fixes: `708e9103`; after: `0dd81ce2`.
Trace data stays in `/tmp/morph-perf/bench/codex-*`; reports sit under
`tool/ios_reference/perf/2026-10-14-bench-codex-*`.

76 navigation snapshots were compared. 48 are exact; differences are localized
mostly to animated glyph/title samples (the two-frame, real-time title capture
is not a frozen phase). Largest mean RGB byte difference is 0.080 out of 255;
this is descriptive, not a replacement golden tolerance or UIKit certification.
Comparison data: `/tmp/morph-codex-navigation-pixel-comparison.json`.

The forced-liquid profile autodemo visited all 22 gallery pages, reached
`AUTODEMO done` and logged no framework exceptions. A normal release APK was
then built and installed, leaving the gallery on the Pixel. Its lock is released.


## UIKit follow-up and device-derived corrections

The owner enabled UI Automation and entered the required passcode. No phone
settings were changed by the agent. Search follow-up passed both stacked and
toolbar activation/close with keyboard-disappearance assertions. Native badge,
minimize and all 13 sheet-plan scenarios ran successfully. The minimize helper
was corrected to reselect Search and minimize again before its final circle tap;
that real scenario passed and supplied five retained screenshots.

The iPhone measurements now confirm:
- Badges stay crisp above the lifted lens, growing only with the bar: count
  18.33 -> 19.29 pt, dot 18 -> 18.94 pt. The port draws one badge above glass
  content instead of refracting two copies. Placement remains the declared
  approximation against a 24 pt glyph box.
- A tap on the already-selected minimized Search circle expands the bar
  without changing its page; the port previously ignored it.
- Medium-only sheet keyboard values 435.67 -> 763.67 -> 435.67; medium/large
  435.67 -> 778 -> 435.67; small/medium/large 200 -> 778 -> 200, without a
  detent callback. Device held stretches confirm 100 / 78 pt rubber-band room;
  background flips at value 602.67 (drag docking progress 0.5025).
- Navigation dim is black alpha 0.1 with opacity following page cover
  linearly, on programmatic push, edge pop and content pop. The former 0.11
  was a single-frame simulator estimate. The direct paint still preserves
  the renderer's exact eight-bit alpha.
- Content-pop touch slop is 30 pt radial travel (29.67–30 measured in the
  first four angle/slow captures); 29 degrees begins, 30 does not. The port
  follows that bracket; the angle boundary remains declared NEAR. Deeper
  horizontal controls retain their drag, including at the leading end.
- The complete 126-case native title matrix ran without XCTest. Its 62
  visible single-line title frames fit the placement rule within 0.5 pt
  (worst left edge 0.17 pt), including wide leading groups. A zero-width
  label is excluded as not visible. Own numeric geometry is committed;
  raw UIKit rows and screenshots stay private. Small-room title drop and
  automatic button-overflow priorities remain explicit unported rules.

Further outcome analysis keeps the release policy explicit as APPROXIMATION:
edge rel35-60 pops at x 126.67 (0.3151 W); content c25/c26 pop at
0.3839/0.3806 W, c27/c29 return at 0.3690/0.3624 W, but c20 returns at
0.3980 W. This non-monotonic set cannot establish a new threshold. Coordinate
drags reach x 213 (0.5299 W) in both runs; an initial 0.3 s press pops,
0.6 s returns. No threshold was guessed. The private probe now observes
velocity and state in gesture target callbacks (including end/cancel),
rather than relying on display-link samples missing terminal states. It
builds successfully and is ready for the next unobstructed phone run.

The new admission test checks only the measured begin-angle boundary. Its
cleanup exposed a separate Flutter cancellation bug: accepted PointerCancel
was reported through drag onEnd, committing a current page past the threshold.
The host now follows the raw cancellation and returns the current page, while
preserving the existing own-route policy when a push interrupts the gesture.
Both edge/content cancellation regressions and all 30 navigation bookkeeping
checks pass; production ceilings remain unchanged. Cancellation checkpoint:
e64ee857.

Saved-geometry follow-up, 2026-10-15: all 13 available release curves agree
with the existing 0.3 s / 0.85 spring when onset and initial speed are fitted
(0.0027–0.0276 pt RMS). Fixing onset at 30 ms raises some errors to 1.85 pt;
onset and initial speed are coupled, so fitted speed is not a recognizer
velocity and cannot establish the commit cause. The private numerical report
is release-curve-fit.json beside the raw captures. This confirms where the
next measurement must focus: terminal gesture state and event-time velocity,
rather than guessing a different spring or distance threshold.

Offline follow-up, 2026-10-15: reading UIKit identifies a separate release
decision branch that projects progress using recent velocity and acceleration.
Its activation on this phone and its internal event-time inputs remain
unverified; static reachability does not establish which branch produced the
saved outcomes. No release-policy change is admitted from this finding.
The private probe now optionally reads existing movement-statistics getters
in gesture callbacks and a deferred terminal snapshot. It changes no UIKit
tuning or delegates and installs no hooks. Its test build succeeds; runtime
verification waits for the owner to close the system dialog. All derivation
notes, static outputs and diagnostic source remain only in ~/morph-re.
The next-run plan preserves the exact opt-in and required repeated cases.

The broad navigation test supplied 25 selected captures but reported three
Probe crashes. An angle refinement passed after fixing a floating-point capture
name (57 percent had been named 56). Retrying problematic captures reproduced
an abort on Apple's asynchronous renderer thread, with no recorder frame on the
crashing stack. A speculative recording-buffer lock did not resolve it and was
reverted. An isolated private clone keeps the same native UI while omitting the
unrelated deep bar-layer sampler. Its repeat timed out enabling UI Automation
before any scenario; the owner-dependent gate is not bypassed.
The failed broad run is not counted as a passing gate.

The live Flutter badge capture checks actual selection on contact/release and
requires the real liquid renderer. Its explicit result marker reports success.
However, a persistent local-network permission dialog obstructs the physical
screen; final film verification is pending the owner closing it. A release
build and a temporary swap under the registered Probe identity did not remove
the system dialog. No permission choice was made. Native data survived that
swap, and Probe was restored. Early profile PNGs show crisp badges, but the
blocked final films and blank snapshots are not counted as final parity proof.

Raw evidence: ~/morph-re/runs/codex-branch-followup-20261014/. The private
capture clone and crash reports stay outside all Git repositories.

Verification so far: 200 device-derived navigation/sheet/integration/count
checks passed, followed by 39 minimize/title checks after filtering the
zero-width title. Original count ceilings and pixel/replay tolerances remain.
Device-derived code checkpoint: `764c330c`.
Final root suite: 2,308 passed, two intentionally skipped, zero failures
(4m28s, /tmp/morph-codex-root-final.log). The earlier five count regressions
are all resolved with their original ceilings. The final example suite passed all 90 tests (41 s), and the final macOS
release gallery built successfully (24.7 MB), without launching a GUI.
Dartdoc reports zero warnings and errors. Final iOS release gallery: 19.6 MB;
Android universal release APK: 56.5 MB (all default ABIs). All builds succeeded.
Offline shader gate passed all configured backends. The prepared private
velocity/state probe builds. On the cancellation checkpoint, all 90 example
tests pass again and the macOS (24.7 MB), iOS (19.6 MB) and universal Android
(56.5 MB) release builds are refreshed successfully.
Final root rerun on e64ee857: 2,310 passed, two intentionally skipped,
zero failures (4m32s). The final analyzer reports zero issues. The two new
edge/content PointerCancel cases add the last two tests. All original
ceilings and pixel/replay tolerances remain.
The iPhone lock is released while awaiting owner action; recorders and Xcode
tests/diagnostics are stopped, and Probe is restored. The final normal iOS
gallery is installed and launched again; no system permission was answered.
The owner has a pending morning question to close the system dialog and unlock
the screen. Remaining physical checks: final visible badge/lens capture, event-time
release velocity/terminal-state repeats, native
problematic-navigation repeats and the true no-bounce strip case. The original
probe disabled alwaysBounceHorizontal only; wide content still bounced, so the
probe now also sets bounces=false for PROBE_HBOUNCE=0. The final gallery
autodemo on the iPhone waits for an unobstructed active screen; the earlier
Pixel autodemo is passed evidence for its recorded checkpoint, not a final
iPhone gate. No release, tag, push or owner permission change was performed.

## Resumed device checks and release prediction, 2026-10-15

The owner closed the local-network dialog and unlocked the iPhone. The
prepared native probe then passed its smoke test and three complete runs
of 14 selected captures each: 42 captures, zero test failures and no Probe
crashes. These include the previously crashing dark push and held page,
the true no-bounce horizontal strip, and the already-scrolled strip.
Both strips retain their scroll gesture without a content-pop callback.

Event-time data confirms that the native projection branch is active.
All 33 release decisions match its prediction, including identical requested
paths with different outcomes. Reconstructing pan speed and its three-sample
velocity/acceleration history from delivered touch coordinates reproduces
the native statistics within 1e-5. Own numeric inputs and geometry are in
`test/fixtures/ios27-device/navigation/release-decision.json`; private runtime
rows, static derivations and diagnostic tools remain outside Git.

`MorphNavigationPopMotion` replaces the former distance/flick approximation
in both edge and content gestures. It preserves the last movement speed
during a hold and updates statistics on lift. Completion and return carry
that speed into the existing 0.3 / 0.85 spring. The old 2.9 multiplier fitted
a 50 ms touch-window estimate; it does not multiply the reconstructed pan
speed. Old tuning constants remain for source compatibility. Current-page
PointerCancel still returns, and an interrupted route retains its own-route
bookkeeping contract.

All 33 decisions, statistics and release curves replay in Dart. A retained
presentation sample exposes the next frame early and then holds; spring
comparison therefore brackets timestamp phase by one measured 120 Hz frame,
with geometry RMS outside that interval below 0.2 pt. Existing replay/pixel
tolerances and performance ceilings are unchanged. Two widget replays check
the same c25 path committing in one run and returning in another. All 96
focused predictor, route, card, cancellation, API and motion tests pass.

Six additional fast edge/content releases pass in three fresh runs. All
39 release outcomes match the native projection. The six fast releases
confirm an initial 4.25 speed boost while mean speed stays above 1.5 widths/s;
the predictor carries this speed into the spring too. Their terminal speed
measurements are retained as separate checks: coalesced fast event/touch
timestamps do not permit the same complete input reconstruction as the
33 slower captures. One XCTest initialization timeout occurred before any
fast scenario; a clean session and all subsequent runs passed. It is kept
as failed infrastructure evidence, not counted as a successful capture.

The final unobstructed Flutter release badge capture passes: its result is
complete with liquid_available=true; held count, held dot, drag and return
are visible in both the four screenshots and the 25-second physical film.
The count and dot stay crisp above the lens. A transient CoreDevice file-copy
disconnect was retried successfully; it does not invalidate the saved film
or completed app result. Badge placement keeps its declared glyph-box NEAR
classification.

The forced-liquid iPhone release autodemo visits all 22 gallery pages,
prints AUTODEMO done, exits normally and logs no framework exceptions.
Its console/syslog and result are retained privately. The final ordinary
iOS release gallery (19.6 MB) is installed and launched; autodemo defines
are absent. Original Probe is restored and its navtitle completion marker
survives, confirming the native documents remain. The iPhone lock is
released; recorders and device test sessions are stopped. Code checkpoint:
`2bdb3e47`. Its final full root run passes 2,351 tests with two intentional
skips; all 90 example tests, analysis, dartdoc and the iOS/macOS/Android
release builds pass. No original tolerance or count ceiling is raised.

A final coordinate-scale regression reproduces an additional edge case:
inside a 0.5-scale ancestor the predictor underestimates speed if it mixes
global pointer coordinates with the page's logical width. The listener now
uses the cached down-hit-test local coordinates, as the drag recognizer
does. The failing scaled-page test passes after this two-coordinate fix.

Final validation on `5e163f5f`: root 2,352 passed, two intentionally skipped,
zero failures (4m41s); all 90 example tests passed (43s). All 97 focused
navigation checks pass. Format and analysis are clean, dartdoc reports zero
warnings/errors, and release builds succeed: iOS 19.6 MB, macOS 24.7 MB,
universal Android APK 56.5 MB. The current ordinary iOS gallery is installed
and launched, then the temporary device lock is released. No device test or
recorder remains active. Host logs are `/tmp/morph-codex-final-scaled-*.log`,
with their status JSON and retained copies in the private owner-ready run.
All original count ceilings and replay/pixel tolerances stay unchanged.
All four interrupted branch tips and the saved sheet-device increment remain
ancestors of the final branch. No required owner action or device gate remains.

## Preserved history and cleanup

The four interrupted agent worktrees and the sheets-device worktree were clean,
contained no capture directories and were fully merged before removal. Their
branch tips remain reachable through the merge commits in
`wip/measured-liquid-glass`. Other historical or locked worktrees were left alone.
The temporary before-fix benchmark checkout was also removed after measurements.
Capture helper checkpoint: `7454a600`.
