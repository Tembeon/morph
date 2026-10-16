# P2: root PopupRoute and source hand-back

Date: 2026-10-16. Base: `9c41085d` on `wip/measured-liquid-glass`. Flutter 3.47.2 stable (`d3b14c876900e553bc736ca19295fc09e3853e8e`), Dart 3.13.2. Host: macOS `flutter_test`. Exact source/evidence hashes are in `artifacts.json`.

Status: the first real root-Navigator menu lifecycle experiment passes. **P2 remains open.** Recorded gesture replay through this route, bar contour continuity and device performance/fidelity are still required. Production code, exports, measured tuning and replay tolerances are unchanged by this experiment. No device was acquired or launched.

## Work state

- [x] Ground: existing menu motion, the first ownership prototype, source lifetime, SDK `PopupRoute` / `TransitionRoute` and Navigator finalization.
- [x] Implement the accepted ownership shape outside `lib/`: one model, one writer, stopped outgoing clock and an absolute-time anchor for the incoming clock.
- [x] Run 15 real Navigator scenarios, three new clock-boundary checks, all 106 prototype checks and 117 existing regression checks.
- [ ] Recorded pointer timestamps, hold/drag/selection and deferred/submenu content through the new route.
- [ ] Actual bar group contour, source layout changes/theme capture and source-loss dissolve.
- [ ] Complete clock integration for both P1 driver candidates, coherent publication phase P3 and device gates.

## Files and reproduction

- `example/lib/proto/menu_route_probe.dart`: a reduced `ProbeMenuSource` and a real `ProbeMenuRoute extends PopupRoute<void>` on the root Navigator. The private shared session outlives an unmounted source when a route still owns the model.
- `example/lib/proto/motion_clock_probe.dart`: `pause()` explicitly relinquishes sampling; `resumeAt()` replaces the previous frame-only resumption method. Raw engine timestamps support resuming between frames without reading a frame-only adjusted timestamp.
- `example/test/proto/menu_route_probe_test.dart`: 15 Navigator scenarios.
- `example/test/proto/motion_clock_probe_test.dart`: three additional scheduling checks, alongside the original 16 clock comparisons.
- `example/test/proto/menu_transfer_probe_test.dart`: the same 33 ownership checks use the renamed absolute-time method.
- `host-tests.log`: 106 passing prototype checks; `regression-tests.log`: 117 existing checks; `analyze.log`: clean package analysis. Terminal padding is trimmed from the analyzer log; test logs are unchanged.

From `example/`:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 30s test/proto
```

From the package root:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/menu_button_test.dart test/menu_drag_out_test.dart test/menu_source_test.dart test/menu_fusion_test.dart test/morph_clock_test.dart test/motion_route_ownership_test.dart test/sheet_zoom_test.dart
nice -n 10 flutter analyze --no-pub
```

Earlier P1 and first-P2 reports remain historical evidence for their recorded sources (`5586e8c5` and `9c41085d`). Their clock files predate this extension. Existing owner work in bar buttons, their passport and capture harness stays outside the prototype change. Full package/example suites were not run; no production path imports these prototypes.

## Ownership and SDK behavior

The source selects `Navigator.of(context, rootNavigator: true)`. A nested Navigator test observes the new popup on the root, leaving the nested route stack unchanged. Opening an already open menu returns the existing route.

Each source or route has a distinct identity lease. Acquisition commands the same model at its previous owner's local time, translates its canonical time to the incoming clock, pauses the outgoing clock and publishes the ownership change. A reopened route invalidates and finalizes the previous closing route; the previous painter and content flow check the lease and cannot draw the newly owned model.

On logical pop, the route publishes reverse status and returns the result with ordinary Navigator semantics. The SDK barrier and modal scope release input and focus while measured closing continues. At the first sampled closing progress at or below zero, the source resumes from the current frame's absolute timestamp. The captured before/after frames are equal. The route publishes dismissed and Navigator disposes it, while the complete source model is still unsettled. The source finishes the landing tail and stops all motion callbacks.

The per-frame comparison uses an uninterrupted `MorphMenuMotion` with the same command and sample times. It checks progress, button/menu geometry, kicks, opacity and fusion radius at the existing strict 1e-9 / 1e-8 numerical tolerances. Every sample, including the zero-duration pump after logical pop and first source frame, must reach the reference: driven kicks depend on the integration partition. Skipping one reference sample produced a small kick mismatch in the initial harness; supplying the same sequence resolves it without changing either motion model or tolerance.

The 15 scenarios cover:

1. A source in a nested Navigator opens a root popup.
2. Continuous sampled model, equal hand-back frame, logical result before tail rest, disposal and zero idle callbacks.
3. Six reopen cases: 50/300/550 ms after closing at approximately 60/120 Hz; reopen takes from the closing route or the landing source as appropriate. Old-route sample count stops, content builds once per route.
4. SDK barrier dismissal and `PopScope` veto; focus/input release on the first closing frame.
5. Source unmount during presentation; the surviving route closes without touching its State and without handing back to it.
6. Forced `Navigator.removeRoute`; the source becomes idle and can present another menu.
7. Whole-Navigator disposal during motion releases both clock owners.
8. Ten seconds of settled idle before opening, closing or reopening do not become animation time.
9. Twenty open/pop/landing cycles, alternating early pop and settled presentation, leave no popup flow or active transient callback; all routes are disposed.
10. `EditableTextState`, text and focus survive animation and a covering route; content builds once, Escape begins closing, editor unmounts on disposal.

This is a widget-test editor, not an on-device native keyboard experiment. Twenty clean cycles establish the observed route/ticker behavior, not a heap-allocation or sustained-energy result.

## Clock refinement

The previous `resumeFromFrame` expected to run inside a frame. A real route also receives commands between frames. After idle, `currentSystemFrameTimeStamp` still describes the last rendered frame; treating it as the time of new input incorrectly includes the idle interval.

`resumeAt(absoluteStamp)` accepts an engine-clock instant. During hand-back on a frame, the caller uses that frame's system stamp. On route acquisition or programmatic dismissal, it uses current engine time; tests inject the binding's fake clock, while the prototype default follows the existing library policy using `Timeline.now`.

Doze now also records its raw engine timestamp, allowing the returned local anchor to include elapsed doze time outside a scheduler callback. Two explicit tests verify normal and 5x slowed time. A third verifies that `pause()` cancels a pending doze timer, produces no callbacks while relinquished, and resumes without counting the relinquished interval. The previous event-stamp/grid/ambient-mode comparisons remain green.

This resumption API is still a prototype. The dilation factor is held constant across each transfer. Real pointer-event occurrence time and delivery lag are not wired into this menu route; the source tap opens with an explicit command at delivery, and tests inject command delays rather than retune native timing. P1 still needs a complete comparison of the projection and SDK controller under the same event/time policy.

## Limits and next step

The route draws plain rounded rectangles and a fixed-size content flow at fixed source geometry. It does not draw fused liquid glass, actual bar groups, the source glyph, measured row layout, submenus or deferred content. Its content opacity can create ordinary SDK layers; this stand does not verify the production glass-layer invariants.

An unmounted source is detached from the session and its clock is disposed. The route retains the model and closes to rest, but the specified source-loss dissolve is not rendered. Forced removal resets a surviving source to a resting model without animation, following the SDK's immediate-removal path; this is distinct from measured closing. Dynamic source geometry and inherited theme capture are not implemented. Initial Pages/restoration/replace are not exposed by this prototype's private constructor and source-only push API; P1 covers those lifecycle obligations separately.

The experiment uses a separate SDK animation projection to exercise hand-back. It does not select that driver over SDK controller. Product rebuild ceilings, bar contour goldens, actual native pixels, Pixel 6a first-frame timing and energy remain unverified. Next is recorded-input replay through the route and actual bar contour continuity, followed by the device batch and P3 publication ordering. The prototype stays off `main`; the unit-0 plan does not require the production deslop/no-comments gate.
