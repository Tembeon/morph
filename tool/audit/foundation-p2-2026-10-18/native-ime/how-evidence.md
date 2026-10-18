# How: native menu / keyboard endpoint evidence

## Overview

The repeated tall-menu runs support one bounded fact: for this public `UIButton.menu` scene, the four observed accessibility row frames have identical settled endpoints when the keyboard appears or disappears. They do not establish that the menu never moves between those endpoints. This review read the harness and raw JSON and independently recomputed the arithmetic; it did not run the phone or inspect body pixels.

## How It Works

[`App.swift`](../../../ios_reference/Sources/App.swift) selects a plain `UIWindow` and [`MenuKeyboardScene`](../../../ios_reference/Sources/MenuKeyboard.swift) before the existing recording-window path. The scene installs a public `UIMenu`, observes public keyboard notifications, and schedules a first-responder change six seconds after `.menuActionTriggered`. [`MenuKeyboardUITests.swift`](../../../ios_reference/UITests/MenuKeyboardUITests.swift) launches separate none/show/hide scenes; hide starts with the keyboard present. Each geometry sample brackets all sequential XCUI queries with `CACurrentMediaTime()` start/end times. App events use the same public monotonic clock on the same device, not host-wall time. Frames are UIKit/XCUI points in this full-screen portrait scene; 3× scale is recorded separately and is not multiplied into the point comparisons.

[`run.py`](run.py) takes the device lock, builds/tests serially, exports named XCTest attachments, and copies each app event file. All seven command receipts are zero in [device3](device3-commands.json), [device4](device4-commands.json), and [device5](device5-commands.json). [`analyze.py`](analyze.py) joins each mode's geometry and events, requires an accepted responder command and completed show/hide notification, and rejects overlapping sample/transition ordering. Raw event times are monotonic; in every measured mode `menuTriggered < before.start`. Before/end and after/start enclose the entire sequence of queries, rather than pretending each snapshot is instantaneous.

## Verified Facts

Independent subtraction from raw geometry/events reproduces these positive timing margins in seconds (`commandBegin − before.end`; `after.start − keyboardDid`):

| Run | Show: before / after | Hide: before / after |
|---|---:|---:|
| device3, 3 rows | 3.931696 / 0.654301 | 3.602919 / 1.156089 |
| device4, 10 rows | 3.712666 / 0.886228 | 3.330521 / 1.466591 |
| device5, 10 rows | 3.750346 / 0.848258 | 3.380655 / 1.371214 |

- In all nine mode runs the observed row frame coordinate deltas and source delta are exactly zero. The source is `[161, 406, 80, 48]` before/after and across initial-placement controls. Device3 observes all three rows; device4/5 observe rows 1, 2, 3, and 10, not all ten rows.
- In both tall runs, show retains first-row Y410 and last-row bottom `788 + 42 = 830`. The public did-show notification reports keyboard `[0,573,402,301]`: the observed row envelope extends `830 − 573 = 257 pt` into that keyboard region. XCUI's keyboard element instead reports `[0,590,402,226]`; the 257 figure uses the notification, not that accessibility frame. It is a geometric extent, not a pixel visibility or hit-testing measurement.
- Opening with the keyboard already present places the first observed row at approximately Y135, compared with Y410 without it: `135 − 410 = −275 pt` in both tall runs. Hiding it afterward leaves the observed endpoints unchanged. Device3's short menu ends at Y541, above the notification keyboard top Y573, so it is a nondiscriminating control for keyboard overlap.
- Tall-run menu-trigger records agree on iOS27.0.1, bounds402×874 pt, display scale3, safe-area `[0,62,0,34]`, Reduce Motion false, and content-size category L. This is repetition within one environment, not coverage of other devices, orientations, keyboards, or accessibility settings. Anchors: [device4 analysis](device4/analysis.json), [device5 analysis](device5/analysis.json), and their sibling raw geometry/event files.

## Inference and Unknowns

These endpoints support placement depending on the keyboard state at presentation, with no settled row repositioning after a subsequent show/hide in this scene. They do not prove an internal snapshot mechanism or justify a universal native policy. Missing evidence remains: transient trajectories, optical menu-body geometry/pixels, continuous existence between samples, unobserved rows 4–9, context-menu presentation, dismissal and close landing, and Flutter parity. No Dart behavior change follows directly from this measurement.
