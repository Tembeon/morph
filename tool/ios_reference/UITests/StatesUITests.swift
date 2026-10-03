import XCTest

/// Device captures of control STATES (States.swift scenes) and the device checks of the
/// controls first measured on the simulator (stepper, progress view, activity indicator).
/// Screenshots are attachments of the result bundle (export with xcresulttool). Same
/// plumbing as Widgets2UITests: PROBE_ONLY filter, one relaunch per capture, PROBE_DARKS
/// (default "1,0") = the appearances the disabled pass runs.
final class StatesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private let env = ProcessInfo.processInfo.environment
    private var only: Set<String> {
        Set((env["PROBE_ONLY"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    private var app = XCUIApplication()
    private var darks: [String] { (env["PROBE_DARKS"] ?? "1,0").split(separator: ",").map(String.init) }

    private func capture(_ rec: String, scene: String, extra: [String: String] = [:], settle: Double = 1.5, _ body: () -> Void) {
        if !only.isEmpty && !only.contains(rec) { return }
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = scene
        app.launchEnvironment["PROBE_REC"] = rec
        app.launchEnvironment["PROBE_TRACK"] = "^NOTHING$"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        Thread.sleep(forTimeInterval: 2.5)
        NSLog("PROBE capture begin \(rec)")
        body()
        Thread.sleep(forTimeInterval: settle)
        NSLog("PROBE capture end \(rec)")
        app.terminate()
    }

    private func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    private func shot(_ name: String) {
        let a = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        NSLog("PROBE shot \(name) at \(CACurrentMediaTime())")
    }

    struct Stroke { var points: [(Double, CGPoint)]; var liftAt: Double }

    private func synth(_ strokes: [Stroke], name: String = "x4") {
        wait(for: [synthStart(strokes, name: name)], timeout: 60)
    }

    private func synthStart(_ strokes: [Stroke], name: String = "x4") -> XCTestExpectation {
        let pathCls: AnyClass = NSClassFromString("XCPointerEventPath")!
        let recCls: AnyClass = NSClassFromString("XCSynthesizedEventRecord")!
        typealias InitPath = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
        typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
        typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
        typealias InitRec = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias Synth = @convention(c) (AnyObject, Selector, AnyObject, @convention(block) (Bool, NSError?) -> Void) -> Void
        func alloc(_ cls: AnyClass) -> AnyObject { (cls as! NSObject.Type).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue() }
        func imp<T>(_ obj: AnyObject, _ sel: Selector, _ t: T.Type) -> T {
            unsafeBitCast(method_getImplementation(class_getInstanceMethod(object_getClass(obj)!, sel)!), to: t)
        }
        let selInitRec = NSSelectorFromString("initWithName:interfaceOrientation:")
        let recRaw = alloc(recCls)
        let record = imp(recRaw, selInitRec, InitRec.self)(recRaw, selInitRec, name as NSString, 1)
        let selInitPath = NSSelectorFromString("initForTouchAtPoint:offset:")
        let selMove = NSSelectorFromString("moveToPoint:atOffset:")
        let selLift = NSSelectorFromString("liftUpAtOffset:")
        let selAdd = NSSelectorFromString("addPointerEventPath:")
        for stroke in strokes {
            let raw = alloc(pathCls)
            let path = imp(raw, selInitPath, InitPath.self)(raw, selInitPath, stroke.points[0].1, stroke.points[0].0)
            for (offset, point) in stroke.points.dropFirst() { imp(path, selMove, Move.self)(path, selMove, point, offset) }
            imp(path, selLift, Lift.self)(path, selLift, stroke.liftAt)
            imp(record, selAdd, Add.self)(record, selAdd, path)
        }
        let synthesizer = XCUIDevice.shared.perform(NSSelectorFromString("eventSynthesizer"))!.takeUnretainedValue()
        let selSynth = NSSelectorFromString("synthesizeEvent:completion:")
        let done = expectation(description: "synth \(name)")
        let block: @convention(block) (Bool, NSError?) -> Void = { ok, error in
            if !ok || error != nil { NSLog("PROBE synth failed \(name): \(String(describing: error))") }
            done.fulfill()
        }
        imp(synthesizer, selSynth, Synth.self)(synthesizer, selSynth, record, block)
        return done
    }

    private func tap(_ p: CGPoint, hold: Double = 0.06) { synth([Stroke(points: [(0, p)], liftAt: hold)], name: "tap") }

    private func line(_ a: CGPoint, _ b: CGPoint, from t0: Double, over d: Double) -> [(Double, CGPoint)] {
        let steps = max(1, Int((d * 30).rounded()))
        return (1...steps).map { i in
            let f = Double(i) / Double(steps)
            return (t0 + d * f, CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        }
    }

    private func element(_ id: String) -> CGRect {
        let e = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: 5), "missing \(id)")
        NSLog("PROBE \(id) frame \(e.frame)")
        return e.frame
    }

    // MARK: disabled look

    /// Each scene: a deep dump at 1.0 s, the screenshot at rest, then the disabled twins are
    /// enabled (toggle) and disabled again, 2 s apart, so the V/anim rows show whether the
    /// change animates; a second dump after the re-disable.
    /// Screenshots at rest (disabled twins disabled), after the first toggle (all enabled)
    /// and after the second (disabled again); the script times above leave a margin of
    /// about 2 s on either side whatever the launch latency.
    private func trio(_ name: String) {
        pause(0.2); shot(name)
        pause(6.3); shot(name + "-enabled")
        pause(3.0); shot(name + "-again")
        pause(1.0)
    }

    func testDisabled() {
        for d in darks {
            let tag = d == "1" ? "dark" : "light"
            let script = "dump:rest@1.0;toggle@8.0;dump:enabled@9.5;toggle@11.0;dump:again@12.5"
            capture("dis-controls-\(tag)", scene: "x4dis", extra: ["PROBE_DARK": d, "PROBE_SCRIPT": script, "PROBE_X3DEPTH": "12"]) { trio("dis-controls-\(tag)") }
            capture("dis-bars-\(tag)", scene: "x4disbars", extra: ["PROBE_DARK": d, "PROBE_SCRIPT": script, "PROBE_X3TRACK": "BarButton|_UIButtonBar|UIToolbar|UINavigationBar|_UIBar|Glass|UILabel|UIImageView"]) { trio("dis-bars-\(tag)") }
            capture("dis-tab-\(tag)", scene: "x4distab", extra: ["PROBE_DARK": d, "PROBE_SCRIPT": script, "PROBE_X3TRACK": "TabBar|_UITab|UILabel|UIImageView|Platter|LiquidLens"]) { trio("dis-tab-\(tag)") }
            for v in ["row", "col"] {
                capture("dis-alert\(v)-\(tag)", scene: "x4disalert",
                        extra: ["PROBE_DARK": d, "PROBE_ALERTV": v, "PROBE_X3TRACK": "Alert|_UIInterfaceAction|UILabel|Platter|Glass",
                                "PROBE_SCRIPT": "show@0.3;dump:rest@1.6;toggle@8.0;dump:enabled@9.5;toggle@11.0;dump:again@12.5"]) { trio("dis-alert\(v)-\(tag)") }
            }
        }
    }

    // MARK: device checks of simulator-only controls

    func testStepperDevice() {
        capture("stepper-plus-tap", scene: "st5") {
            let f = element("c_st5")
            tap(CGPoint(x: f.midX + f.width / 4, y: f.midY), hold: 0.09)
        }
        capture("stepper-plus-hold2500", scene: "st5") {
            let f = element("c_st5")
            tap(CGPoint(x: f.midX + f.width / 4, y: f.midY), hold: 2.5)
        }
        capture("stepper-minus-press-slide", scene: "st5") {
            let f = element("c_st5")
            let a = CGPoint(x: f.midX - f.width / 4, y: f.midY)
            let b = CGPoint(x: f.maxX + 23, y: f.midY)
            let pts: [(Double, CGPoint)] = [(0, a), (0.3, a)] + line(a, b, from: 0.3, over: 0.8)
            synth([Stroke(points: pts + [(1.5, b)], liftAt: 1.5)], name: "slide")
        }
        for d in darks {
            let tag = d == "1" ? "dark" : "light"
            capture("stepper-pressed-\(tag)", scene: "st5", extra: ["PROBE_DARK": d]) {
                let f = element("c_st5")
                let done = synthStart([Stroke(points: [(0, CGPoint(x: f.midX + f.width / 4, y: f.midY))], liftAt: 1.2)], name: "held")
                pause(0.5)
                shot("stepper-plus-pressed-\(tag)")
                wait(for: [done], timeout: 10)
            }
        }
    }

    func testProgressDevice() {
        capture("progress2", scene: "w2progress", extra: ["PROBE_AI": "0", "PROBE_SCRIPT": "progress:0.3@1;progress:1.0@2;progress:0.0@3.5;progress:0.05@5"], settle: 1.0) { pause(6.0) }
        capture("progress3", scene: "w2progress", extra: ["PROBE_AI": "0", "PROBE_PV0": "0.5", "PROBE_SCRIPT": "progress:0.52@1;progress:0.0@2;progress:0.5@3.5;progress:0.45@5"], settle: 1.0) { pause(6.0) }
        capture("progress-additive", scene: "w2progress", extra: ["PROBE_AI": "0", "PROBE_SCRIPT": "progress:0.9@1;progress:0.4@1.25;progress:0.6@3.0;progress:1.0@3.1"], settle: 1.0) { pause(5.0) }
    }

    func testActivityDevice() {
        capture("activity-startstop", scene: "x4ind",
                extra: ["PROBE_SETTINGS": "ActivityIndicator|Progress", "PROBE_X3DEPTH": "6",
                        "PROBE_SCRIPT": "dump:running@1.0;stop@2.0;dump:stopped@3.0;start@4.0;hide:0@5.5;stop@6.0;dump:stoppedvisible@7.0;start@8.0"],
                settle: 1.0) { pause(9.0) }
        for d in darks {
            let tag = d == "1" ? "dark" : "light"
            capture("ref-indicators-\(tag)", scene: "x4ind", extra: ["PROBE_DARK": d, "PROBE_SCRIPT": "dump:\(tag)@1.0"]) { pause(0.2); shot("indicators-\(tag)") }
        }
    }

    // MARK: disabled touches

    /// A disabled control under a finger: the disabled tab item (tap + hold; the lens rows
    /// show whether it lifts or selects), the disabled glass button, switch knob and segment
    /// (hold 0.8 s; the x3_dis_* V rows show any lift or highlight).
    func testDisabledTouch() {
        capture("dis-tab-touch", scene: "x4distab", extra: ["PROBE_X3TRACK": "TabBar|_UITab|LiquidLens|Platter"]) {
            let bar = app.tabBars.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            let radio = bar.buttons.element(boundBy: 2).frame
            NSLog("PROBE radio frame \(radio)")
            tap(CGPoint(x: radio.midX, y: radio.midY), hold: 0.08)
            pause(1.5)
            tap(CGPoint(x: radio.midX, y: radio.midY), hold: 0.8)
            pause(1.5)
        }
        capture("dis-controls-touch", scene: "x4dis", extra: ["PROBE_X3DEPTH": "12"]) {
            for id in ["x3_dis_glass", "x3_dis_prominent", "x3_dis_swOff", "x3_dis_seg", "x3_dis_slider", "x3_dis_stepper"] {
                let f = element(id)
                tap(CGPoint(x: id.hasSuffix("seg") ? f.maxX - 30 : f.midX, y: f.midY), hold: 0.8)
                pause(1.2)
            }
        }
    }

    // MARK: Reduce Motion

    /// Live PTSettings of the motion families plus the accessibility flags (start row rm /
    /// rmXfade / rt): run once with Reduce Motion OFF (rm-settings-off) and once ON
    /// (rm-settings-on, PROBE_RMTAG=on) and diff the two settings files.
    func testSettingsDump() {
        let tag = env["PROBE_RMTAG"] ?? "off"
        capture("rm-settings-\(tag)", scene: "segmented",
                extra: ["PROBE_SETTINGS": "Morph|Lens|Flex|Glass|Sheet|Alert|Menu|TabBar|Search|Zoom|Navigation|Transition|ContextMenu|Popover|DatePicker|PageControl|Switch|Slider|Stepper|ActivityIndicator|Progress|Toolbar|Bar"]) { pause(0.5) }
    }

    // MARK: overlay platters

    /// The compact date picker's overlay platter open, light and dark (lossless shot +
    /// a tree dump about 1.5 s after the open), for the platter color.
    func testDateOverlay() {
        for d in darks {
            let tag = d == "1" ? "dark" : "light"
            capture("date-overlay-\(tag)", scene: "x3date", extra: ["PROBE_DARK": d, "PROBE_SCRIPT": "tree-open-\(tag)@5.0"]) {
                let s = app.windows.firstMatch.frame
                tap(CGPoint(x: s.width / 2, y: 300))
                pause(1.6)
                shot("date-overlay-\(tag)")
                pause(1.5)
                tap(CGPoint(x: s.width / 2, y: s.height - 120))
                pause(1.2)
            }
        }
    }
}
