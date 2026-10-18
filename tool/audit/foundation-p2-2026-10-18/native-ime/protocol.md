# Native menu / keyboard observation

- [x] Read existing lab/protocol and check device availability.
- [x] Trace historical claim: context-menu.md line143 is morph implementation description from b16747ffa, not direct UIKit keyboard evidence.
- [x] Build an isolated public UIKit scene and XCTest driver.
- [x] Acquire atomic device lock, run real iPhone, collect public geometry/keyboard events and screenshots.
- [x] Read evidence, distinguish baseline/show/hide, repeat if needed; no assumed native outcome.
- [x] Update spec/plan, deslop + no-comments, scoped local commit.

Shape: plain UIWindow + UIViewController bypasses existing runtime recorder. UITextField and UIButton(menu:, showsMenuAsPrimaryAction) use public API. UIControl.menuActionTriggered schedules public first-responder change after6s, leaving time to sample settled open menu before it. No settings changes, simulator or macOS GUI. Test outputs only own semantic labels, CGRects, keyboard existence and public keyboard notifications. No private symbol/layer dumps.

Observe three modes at fixed source Y430: unchanged keyboard baseline; show keyboard after menu trigger; start with keyboard then hide after menu trigger. Capture all three row frames and keyboard/source frames before and after. Require real menu and show/hide transition control, but do not assert that the menu must move/stay/dismiss. Endpoint geometric equality uses max absolute coordinate delta <=1pt as an observation classification, not a renderer/native-fidelity gate. Frame-by-frame motion is not claimed.

Throughput: one native build/test job at a time, nice10. Implement only measurement harness first; no package/Flutter behavior change based on the old unmeasured claim.

Snapshot start/end times must bracket the delayed keyboard command: before.end < commandBegin, after.start > keyboardDid transition. Missing rows/keyboards serialize null, not an XCUI frame query on absent elements. If phase ordering or keyboard transition is missing, the run is inconclusive for placement.

Three-row device3 passes and brackets real keyboard transitions, but its menu already fits above keyboard. Retain it as a control. Discriminating device4 uses --rows 10, records first three plus last row, and includes public environment/scale/safe area/read-only Reduce Motion. Native row deltas alone do not prove optical-body continuity or transient motion; screenshots and before-keyboard initial placement are checked separately.

Completed: generic build2 + device3 (3 rows), device4/device5 (10 rows), all three modes per device run. Final root analyzer0, shader offline gate0, invalid interval rejected2. Source/core/owner/main hashes checked separately in manifest. Library behavior remains unchanged; close landing/context-menu/Flutter integration are not measured.
