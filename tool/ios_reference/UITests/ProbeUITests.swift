import XCTest

/// Drives real touches into the probe app so UIKit plays its genuine control motion.
///
/// One test per capture family (testLens, testControls, testMenu). Each capture relaunches
/// the app with PROBE_SCENE / PROBE_REC (+ scene options) so it lands in its own
/// Documents/rec-<name>.jsonl, plays its gestures, waits for the motion to settle and quits.
/// PROBE_ONLY (TEST_RUNNER_PROBE_ONLY through xcodebuild) = comma separated capture names to
/// run; empty runs all of the family.
///
/// Touches are synthesized as timed pointer paths (XCPointerEventPath through the
/// XCUIDevice event synthesizer), so drags can hold, reverse and release while moving with
/// exact timing. Offsets are seconds from the start of one synthesized record.
final class ProbeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private let env = ProcessInfo.processInfo.environment
    private var only: Set<String> {
        Set((env["PROBE_ONLY"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private var app = XCUIApplication()

    // MARK: capture plumbing

    private func capture(_ rec: String, scene: String, extra: [String: String] = [:], _ body: () throws -> Void) rethrows {
        if !only.isEmpty && !only.contains(rec) { return }
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = scene
        app.launchEnvironment["PROBE_REC"] = rec
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        Thread.sleep(forTimeInterval: 3.0)
        NSLog("PROBE capture begin \(rec)")
        try body()
        Thread.sleep(forTimeInterval: 1.8)
        NSLog("PROBE capture end \(rec)")
        app.terminate()
    }

    private func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    /// One finger: begins at the first point, moves through the rest, lifts at `liftAt`.
    struct Stroke {
        var points: [(Double, CGPoint)]
        var liftAt: Double
    }

    private func synth(_ strokes: [Stroke], name: String = "probe") {
        wait(for: [synthStart(strokes, name: name)], timeout: 60)
    }

    /// Starts a synthesized record and returns the expectation fulfilled when it has played.
    private func synthStart(_ strokes: [Stroke], name: String = "probe") -> XCTestExpectation {
        let pathCls: AnyClass = NSClassFromString("XCPointerEventPath")!
        let recCls: AnyClass = NSClassFromString("XCSynthesizedEventRecord")!
        typealias InitPath = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
        typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
        typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
        typealias InitRec = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias Synth = @convention(c) (AnyObject, Selector, AnyObject, @convention(block) (Bool, NSError?) -> Void) -> Void

        func alloc(_ cls: AnyClass) -> AnyObject {
            (cls as! NSObject.Type).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        }
        func imp<T>(_ obj: AnyObject, _ sel: Selector, _ t: T.Type) -> T {
            let cls: AnyClass = object_getClass(obj)!
            let m = class_getInstanceMethod(cls, sel)!
            return unsafeBitCast(method_getImplementation(m), to: t)
        }

        let selInitRec = NSSelectorFromString("initWithName:interfaceOrientation:")
        let recRaw = alloc(recCls)
        let record = imp(recRaw, selInitRec, InitRec.self)(recRaw, selInitRec, name as NSString, 1)
        let selInitPath = NSSelectorFromString("initForTouchAtPoint:offset:")
        let selMove = NSSelectorFromString("moveToPoint:atOffset:")
        let selLift = NSSelectorFromString("liftUpAtOffset:")
        let selAdd = NSSelectorFromString("addPointerEventPath:")
        for stroke in strokes {
            let first = stroke.points[0]
            let raw = alloc(pathCls)
            let path = imp(raw, selInitPath, InitPath.self)(raw, selInitPath, first.1, first.0)
            for (offset, point) in stroke.points.dropFirst() {
                imp(path, selMove, Move.self)(path, selMove, point, offset)
            }
            imp(path, selLift, Lift.self)(path, selLift, stroke.liftAt)
            imp(record, selAdd, Add.self)(record, selAdd, path)
        }
        let device = XCUIDevice.shared
        let synthesizer = device.perform(NSSelectorFromString("eventSynthesizer"))!.takeUnretainedValue()
        let selSynth = NSSelectorFromString("synthesizeEvent:completion:")
        let done = expectation(description: "synth \(name)")
        let block: @convention(block) (Bool, NSError?) -> Void = { ok, error in
            if !ok || error != nil { NSLog("PROBE synth failed \(name): \(String(describing: error))") }
            done.fulfill()
        }
        imp(synthesizer, selSynth, Synth.self)(synthesizer, selSynth, record, block)
        return done
    }

    private func tap(_ p: CGPoint, hold: Double = 0.06) {
        synth([Stroke(points: [(0, p)], liftAt: hold)], name: "tap")
    }

    /// Press at `a`, wait `pressFor`, move linearly to `b` over `moveFor` in 1/stepHz steps,
    /// hold `holdFor`, lift. holdFor 0 releases while moving (a fling).
    private func drag(_ a: CGPoint, _ b: CGPoint, pressFor: Double, moveFor: Double, holdFor: Double) {
        synth([Stroke(points: line(a, b, from: pressFor, over: moveFor), liftAt: pressFor + moveFor + holdFor)], name: "drag")
    }

    /// Point rate of synthesized moves (PROBE_STEP_HZ, default 30). On a device the event
    /// synthesizer replays dense paths late and in bursts (120 Hz points: a 1 s ramp arrived
    /// in 0.48 s with jumps; 60 Hz: 16 percent slow); at 30 Hz it is smooth and ~9 percent slow,
    /// and the touches still reach UIKit at 120 Hz (interpolated). Analyses read the logged
    /// touch rows, never the plan.
    private var stepHz: Double { Double(env["PROBE_STEP_HZ"] ?? "") ?? 30 }

    private func line(_ a: CGPoint, _ b: CGPoint, from t0: Double, over d: Double, includeStart: Bool = true) -> [(Double, CGPoint)] {
        let steps = max(1, Int((d * stepHz).rounded()))
        var out: [(Double, CGPoint)] = includeStart ? [(t0 == 0 ? 0 : 0, a)] : []
        if includeStart && t0 > 0 { out.append((t0, a)) }
        for i in 1...steps {
            let f = Double(i) / Double(steps)
            out.append((t0 + d * f, CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)))
        }
        return out
    }

    /// A multi-leg path: legs of (target, duration, holdAfter).
    private func path(start: CGPoint, pressFor: Double, legs: [(CGPoint, Double, Double)]) -> Stroke {
        var pts: [(Double, CGPoint)] = [(0, start)]
        var t = pressFor
        var cur = start
        if pressFor > 0 { pts.append((pressFor, start)) }
        for (to, dur, hold) in legs {
            pts += line(cur, to, from: t, over: dur, includeStart: false)
            t += dur
            cur = to
            if hold > 0 { t += hold; pts.append((t, cur)) }
        }
        return Stroke(points: pts, liftAt: t)
    }

    private func center(_ e: XCUIElement) -> CGPoint {
        let f = e.frame
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// Diagnostic: how the event synthesizer delivers moves at different point spacings.
    func testDragTiming() {
        capture("dragtiming", scene: "segmented") {
            let c = segCenters("seg5")
            let y = c[0].y + 300
            for hz in [120.0, 60.0, 30.0] {
                let a = CGPoint(x: 40, y: y), b = CGPoint(x: 340, y: y)
                let n = Int(hz * 1.0)
                var pts: [(Double, CGPoint)] = [(0, a), (0.2, a)]
                for i in 1...n { pts.append((0.2 + Double(i) / hz, CGPoint(x: a.x + (b.x - a.x) * Double(i) / Double(n), y: y))) }
                pts.append((1.6, b))
                synth([Stroke(points: pts, liftAt: 1.7)], name: "hz\(hz)")
                pause(1.0)
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let a = origin.withOffset(CGVector(dx: 40, dy: y)), b = origin.withOffset(CGVector(dx: 340, dy: y))
            a.press(forDuration: 0.2, thenDragTo: b, withVelocity: XCUIGestureVelocity(300), thenHoldForDuration: 0.4)
            pause(1.0)
        }
    }

    // MARK: lens: segmented control and tab bar

    private func segCenters(_ id: String) -> [CGPoint] {
        let seg = app.segmentedControls[id]
        XCTAssertTrue(seg.waitForExistence(timeout: 5), "no \(id)")
        let n = seg.buttons.count
        var pts = (0..<n).map { center(seg.buttons.element(boundBy: $0)) }
        if n == 0 { pts = [] }
        NSLog("PROBE \(id) centers \(pts) frame \(seg.frame)")
        return pts
    }

    private func tapSequence(_ pts: [CGPoint], _ seq: [Int], gap: Double = 1.6) {
        for i in seq {
            tap(pts[i], hold: 0.05)
            pause(gap)
        }
    }

    func testLens() {
        capture("segmented-seg2-taps", scene: "segmented") {
            let c = segCenters("seg2")
            tapSequence(c, [1, 0, 1, 0, 1, 0])
        }
        capture("segmented-seg3-taps", scene: "segmented") {
            let c = segCenters("seg3")
            tapSequence(c, [1, 2, 0, 2, 1, 0])
        }
        capture("segmented-seg5seg4-taps", scene: "segmented") {
            let c5 = segCenters("seg5")
            tapSequence(c5, [1, 4, 3, 0, 2, 4, 0])
            let c4 = segCenters("seg4")
            tapSequence(c4, [1, 3, 0])
        }
        capture("segmented-narrow-content-content4-taps", scene: "segmented") {
            let n = segCenters("segNarrow")
            tapSequence(n, [1, 2, 0])
            let c = segCenters("segContent")
            tapSequence(c, [1, 2, 0])
            let c4 = segCenters("segContent4")
            tapSequence(c4, [1, 2, 3, 0])
        }
        capture("segmented-seg2-hold1200", scene: "segmented") {
            let c = segCenters("seg2")
            tap(c[1], hold: 1.05)
            pause(1.6)
            tap(c[0], hold: 1.05)
        }
        capture("segmented-seg5-dragslow-from-selected", scene: "segmented") {
            let c = segCenters("seg5")
            var legs: [(CGPoint, Double, Double)] = []
            var x = c[0].x
            while x + 20 <= c[4].x + 20 {
                x += 20
                legs.append((CGPoint(x: x, y: c[0].y), 0.016, 0.089))
            }
            synth([path(start: c[0], pressFor: 0.3, legs: legs + [(CGPoint(x: x, y: c[0].y), 0.0083, 0.5)])])
            pause(1.6)
        }
        capture("segmented-seg5-scrub-offset-overrun-back", scene: "segmented") {
            let c = segCenters("seg5")
            let a = CGPoint(x: c[0].x - 16, y: c[0].y)
            let far = CGPoint(x: c[4].x + 60, y: c[0].y)
            let d1 = Double(far.x - a.x) / 150
            let d2 = Double(far.x - a.x) / 300
            synth([path(start: a, pressFor: 0.3, legs: [(far, d1, 0.6), (a, d2, 0.4)])])
            pause(1.6)
        }
        capture("segmented-seg5-release-choice-rubberband", scene: "segmented") {
            let c = segCenters("seg5")
            let pitch = c[1].x - c[0].x
            let y = c[0].y
            // (1) grab the selected segment 28 pt right of its center; release where the
            // finger is nearest segment 2 and the lens (finger - 28) nearest segment 1.
            let f1 = CGPoint(x: c[1].x + pitch * 0.69, y: y)
            synth([path(start: CGPoint(x: c[0].x + 28, y: y), pressFor: 0.3, legs: [(f1, 0.6, 0.5)])])
            pause(1.6)
            // (2) press a non-selected segment (4) and drag to segment 3.
            synth([path(start: c[4], pressFor: 0.3, legs: [(c[3], 0.4, 0.4)])])
            pause(1.6)
            // (3) left-end rubber band from the selected segment 3: excess 58 / 30 / 44 past
            // the first segment center.
            synth([path(start: c[3], pressFor: 0.3, legs: [
                (CGPoint(x: c[0].x - 58, y: y), 0.8, 0.7),
                (CGPoint(x: c[0].x - 30, y: y), 0.2, 0.7),
                (CGPoint(x: c[0].x - 44, y: y), 0.15, 0.7),
            ])])
            pause(1.6)
        }
        for (n, seq, hold) in [
            (2, [1, 0, 1, 0, 1, 0], -1),
            (3, [2, 0, 1, 2, 0, 1, 0], -1),
            (4, [1, 3, 0, 2, 0], 2),
            (5, [4, 1, 2, 0, 3, 0], -1),
        ] {
            capture("tabbar\(n)-taps", scene: "tabbar\(n)") {
                let bar = app.tabBars.firstMatch
                XCTAssertTrue(bar.waitForExistence(timeout: 5))
                let pts = (0..<bar.buttons.count).map { center(bar.buttons.element(boundBy: $0)) }
                NSLog("PROBE tabbar\(n) centers \(pts)")
                tapSequence(pts, seq, gap: 1.8)
                if hold >= 0 {
                    tap(pts[hold], hold: 1.0)
                    pause(1.8)
                    tap(pts[0], hold: 0.05)
                    pause(1.8)
                }
            }
        }
    }

    // MARK: controls

    private func control(_ scene: String) -> CGRect {
        let e = app.descendants(matching: .any)["c_" + scene]
        XCTAssertTrue(e.waitForExistence(timeout: 5), "no control \(scene)")
        NSLog("PROBE control \(scene) frame \(e.frame)")
        return e.frame
    }

    func testControls() {
        // Switch: 63 x 28, knob 37 x 24 inset 2 -> off knob center midX - 11, on midX + 11.
        func knob(_ f: CGRect, on: Bool) -> CGPoint { CGPoint(x: f.midX + (on ? 11 : -11), y: f.midY) }
        capture("switch-off-tap", scene: "sw") { let f = control("sw"); tap(knob(f, on: false), hold: 0.09) }
        capture("switch-on-tap", scene: "swOn") { let f = control("swOn"); tap(knob(f, on: true), hold: 0.09) }
        capture("switch-taps", scene: "sw") {
            let f = control("sw")
            for i in 0..<6 { tap(knob(f, on: i % 2 == 1), hold: 0.09); pause(1.4) }
        }
        capture("switch-off-hold800", scene: "sw") { let f = control("sw"); tap(knob(f, on: false), hold: 0.8) }
        for (name, dx, dur) in [("right50", 50.0, 0.64), ("right15", 15.0, 0.24), ("right8", 8.0, 0.128), ("left50", -50.0, 0.64), ("right100", 100.0, 0.64)] {
            capture("switch-off-drag-\(name)", scene: "sw") {
                let k = knob(control("sw"), on: false)
                drag(k, CGPoint(x: k.x + dx, y: k.y), pressFor: 0, moveFor: dur, holdFor: 0.3)
            }
        }
        capture("switch-off-fling40", scene: "sw") {
            let k = knob(control("sw"), on: false)
            drag(k, CGPoint(x: k.x + 40, y: k.y), pressFor: 0, moveFor: 0.064, holdFor: 0)
        }
        capture("switch-off-drag-there-back", scene: "sw") {
            let k = knob(control("sw"), on: false)
            synth([path(start: k, pressFor: 0, legs: [(CGPoint(x: k.x + 40, y: k.y), 0.4, 0), (CGPoint(x: k.x - 10, y: k.y), 0.48, 0.3)])])
        }

        // Slider: thumb travel = width - 37, thumb center = minX + 18.5 + v * (width - 37).
        func thumb(_ f: CGRect, _ v: Double) -> CGPoint { CGPoint(x: f.minX + 18.5 + v * (f.width - 37), y: f.midY) }
        capture("slider-w300-tap-thumb", scene: "sl300") { tap(thumb(control("sl300"), 0.3), hold: 0.09) }
        capture("slider-w300-taps-thumb", scene: "sl300") {
            let p = thumb(control("sl300"), 0.3)
            for _ in 0..<4 { tap(p, hold: 0.09); pause(1.2) }
        }
        capture("slider-w300-hold800-thumb", scene: "sl300") { tap(thumb(control("sl300"), 0.3), hold: 0.8) }
        capture("slider-w300-tap-track300", scene: "sl300") {
            let f = control("sl300")
            tap(CGPoint(x: f.minX + 230, y: f.midY), hold: 0.09)
        }
        let sliderDrags: [(String, Double, Double, Double)] = [
            ("drag-slow", 112.5, 1.0, 0.4),
            ("fling", 132.5, 0.096, 0),
            ("fling-medium", 60, 0.096, 0),
            ("fling-slow", 40, 0.16, 0),
            ("drag-pastend", 262.5, 0.8, 0.5),
            ("drag-pastend-small", 227.5, 0.6, 0.5),
            ("drag-pastend-mid", 242.5, 0.8, 0.5),
            ("drag-pastend-far", 269, 0.8, 0.5),
            ("drag-paststart", -157.5, 0.7, 0.5),
        ]
        for (name, dx, dur, hold) in sliderDrags {
            capture("slider-w300-\(name)", scene: "sl300") {
                let p = thumb(control("sl300"), 0.3)
                drag(p, CGPoint(x: p.x + dx, y: p.y), pressFor: 0, moveFor: dur, holdFor: hold)
            }
        }
        capture("slider-w300-drag-ontrack", scene: "sl300") {
            let f = control("sl300")
            drag(CGPoint(x: f.minX + 230, y: f.midY), CGPoint(x: f.minX + 270, y: f.midY), pressFor: 0, moveFor: 0.3, holdFor: 0.4)
        }
        capture("slider-w200-drag-slow", scene: "sl200") {
            let p = thumb(control("sl200"), 0.3)
            drag(p, CGPoint(x: p.x + 72.6, y: p.y), pressFor: 0, moveFor: 0.8, holdFor: 0.4)
        }
        capture("slider-ticks5-drag", scene: "slT5") {
            let p = thumb(control("slT5"), 0)
            drag(p, CGPoint(x: p.x + 111.5, y: p.y), pressFor: 0, moveFor: 0.8, holdFor: 0.4)
        }

        for (w, h) in [(44, 44), (60, 44), (120, 44), (200, 44), (300, 44), (200, 100)] {
            capture("button-glass-\(w)x\(h)-hold800", scene: "gb\(w)x\(h)") {
                let f = control("gb\(w)x\(h)")
                tap(CGPoint(x: f.midX, y: f.midY), hold: 0.8)
            }
        }
        capture("button-prominent-120x44-hold800", scene: "gbp120x44") {
            let f = control("gbp120x44")
            tap(CGPoint(x: f.midX, y: f.midY), hold: 0.8)
        }
        capture("button-glass-44x44-taps", scene: "gb44x44") {
            let f = control("gb44x44")
            for _ in 0..<4 { tap(CGPoint(x: f.midX, y: f.midY), hold: 0.08); pause(1.2) }
        }
        capture("button-glass-120x44-drag-off-back", scene: "gb120x44") {
            let f = control("gb120x44")
            let c = CGPoint(x: f.midX, y: f.midY)
            synth([path(start: c, pressFor: 0.3, legs: [(CGPoint(x: c.x + 150, y: c.y), 0.75, 0.4), (c, 0.75, 0.4)])])
        }
    }

    // MARK: menu

    private func menuButton() -> CGRect {
        let b = app.buttons["inlineMenu"]
        XCTAssertTrue(b.waitForExistence(timeout: 5))
        NSLog("PROBE inlineMenu frame \(b.frame)")
        return b.frame
    }

    private func outside(of f: CGRect) -> CGPoint {
        let screen = app.windows.firstMatch.frame
        let x = f.midX < screen.midX ? screen.maxX - 50 : screen.minX + 50
        let y = f.midY < screen.midY ? screen.maxY - 120 : screen.minY + 200
        return CGPoint(x: x, y: y)
    }

    private func openDismiss(_ f: CGRect, cycles: Int = 1, hold: Double = 0.1) {
        let c = CGPoint(x: f.midX, y: f.midY)
        for _ in 0..<cycles {
            tap(c, hold: hold)
            pause(1.6)
            tap(outside(of: f), hold: 0.06)
            pause(1.6)
        }
    }

    func testMenu() {
        capture("center3-tap", scene: "menu") { let f = menuButton(); tap(CGPoint(x: f.midX, y: f.midY), hold: 0.128) }
        capture("center3-quicktap", scene: "menu") { let f = menuButton(); tap(CGPoint(x: f.midX, y: f.midY), hold: 0.031) }
        capture("center3-hold700", scene: "menu") { let f = menuButton(); tap(CGPoint(x: f.midX, y: f.midY), hold: 0.736) }
        capture("center3-dismiss", scene: "menu") { openDismiss(menuButton()) }
        capture("center3-repeat", scene: "menu") { openDismiss(menuButton(), cycles: 4) }
        capture("center3-closemidopen", scene: "menu") {
            let f = menuButton()
            let c = CGPoint(x: f.midX, y: f.midY)
            let o = outside(of: f)
            synth([Stroke(points: [(0, c)], liftAt: 0.1), Stroke(points: [(0.125, o)], liftAt: 0.175)], name: "closemidopen")
            pause(1.6)
        }
        capture("center3-retap-midopen", scene: "menu") {
            let f = menuButton()
            let c = CGPoint(x: f.midX, y: f.midY)
            synth([Stroke(points: [(0, c)], liftAt: 0.1), Stroke(points: [(0.2, c)], liftAt: 0.26)], name: "retap")
            pause(1.6)
        }
        capture("center3-select", scene: "menu") {
            let f = menuButton()
            tap(CGPoint(x: f.midX, y: f.midY), hold: 0.1)
            pause(1.6)
            let share = app.buttons["Share"]
            var p = CGPoint(x: f.midX, y: f.midY - f.height * 0.667 + 10 + 21 + 42)
            if share.exists { p = center(share) }
            NSLog("PROBE share at \(p)")
            pause(0.8)
            tap(p, hold: 0.08)
            pause(1.6)
        }
        capture("center3-dragselect", scene: "menu") {
            let f = menuButton()
            let c = CGPoint(x: f.midX, y: f.midY)
            let row3 = CGPoint(x: f.midX, y: f.midY - 32.4 + 10 + 21 + 84)
            synth([path(start: c, pressFor: 0.7, legs: [(row3, 0.3, 0.3)])], name: "dragselect")
            pause(1.6)
        }
        capture("bottom3-dismiss", scene: "menu", extra: ["PROBE_POS": "bottom"]) { openDismiss(menuButton()) }
        for pos in ["tl", "tr", "bl", "br", "left"] {
            capture("pos-\(pos)-dismiss", scene: "menu", extra: ["PROBE_POS": pos]) { openDismiss(menuButton()) }
        }
        for items in [2, 5, 10] {
            capture("center-items\(items)-dismiss", scene: "menu", extra: ["PROBE_ITEMS": "\(items)"]) { openDismiss(menuButton()) }
        }
        for items in [1, 4, 8] {
            capture("tl-items\(items)-dismiss", scene: "menu", extra: ["PROBE_POS": "tl", "PROBE_ITEMS": "\(items)"]) { openDismiss(menuButton()) }
        }
        capture("wide3-dismiss", scene: "menu", extra: ["PROBE_WIDE": "1"]) { openDismiss(menuButton()) }
        capture("navbar3-dismiss", scene: "menu") {
            let bar = app.navigationBars.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            let b = bar.buttons.element(boundBy: bar.buttons.count - 1)
            NSLog("PROBE navbar button frame \(b.frame)")
            openDismiss(b.frame)
        }
        // 2026-10-05: UIBarButtonItem(menu:) without a primary action - tap timing over
        // several opens, a quick tap, a hold and a hold-slide onto a row.
        func navbarButton() -> CGRect {
            let bar = app.navigationBars.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            let b = bar.buttons.element(boundBy: bar.buttons.count - 1)
            NSLog("PROBE navbar button frame \(b.frame)")
            return b.frame
        }
        capture("navbar3-repeat", scene: "menu") { openDismiss(navbarButton(), cycles: 5) }
        capture("navbar3-quicktap", scene: "menu") { let f = navbarButton(); tap(CGPoint(x: f.midX, y: f.midY), hold: 0.031); pause(1.6) }
        capture("navbar3-hold700", scene: "menu") { let f = navbarButton(); tap(CGPoint(x: f.midX, y: f.midY), hold: 0.736); pause(1.6) }
        capture("navbar3-hold300", scene: "menu") { let f = navbarButton(); tap(CGPoint(x: f.midX, y: f.midY), hold: 0.3); pause(1.6) }
        capture("navbar3-dragselect", scene: "menu") {
            let f = navbarButton()
            let c = CGPoint(x: f.midX, y: f.midY)
            let row3 = CGPoint(x: f.midX - 100, y: f.minY + 10 + 21 + 84)
            synth([path(start: c, pressFor: 0.7, legs: [(row3, 0.3, 0.3)])], name: "dragselect")
            pause(1.6)
        }
    }

    // MARK: recapture (2026-10-02 open questions)

    private func tabCenters() -> [CGPoint] {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let pts = (0..<bar.buttons.count).map { center(bar.buttons.element(boundBy: $0)) }
        NSLog("PROBE tabbar centers \(pts) frame \(bar.frame)")
        return pts
    }

    func testRecapLens() {
        let speed = 200.0
        for n in [3, 5] {
            capture("tabbar\(n)-scrub-mid", scene: "tabbar\(n)") {
                let c = tabCenters()
                let y = c[0].y
                let off: CGFloat = 18
                let start = CGPoint(x: c[0].x + off, y: y)
                let far = CGPoint(x: c[n - 1].x + off, y: y)
                let rel = CGPoint(x: (c[1].x + c[2].x) / 2 + 8, y: y)
                synth([path(start: start, pressFor: 0.3, legs: [
                    (far, Double(far.x - start.x) / speed, 0.5),
                    (rel, Double(far.x - rel.x) / speed, 0.5),
                ])], name: "scrubmid")
            }
            capture("tabbar\(n)-scrub-pastright", scene: "tabbar\(n)") {
                let c = tabCenters()
                let y = c[0].y
                let last = c[n - 1].x
                synth([path(start: c[0], pressFor: 0.3, legs: [
                    (CGPoint(x: last, y: y), Double(last - c[0].x) / speed, 0.4),
                    (CGPoint(x: last + 30, y: y), 0.3, 0.5),
                    (CGPoint(x: last + 55, y: y), 0.25, 0.5),
                ])], name: "pastright")
            }
            capture("tabbar\(n)-scrub-pastleft", scene: "tabbar\(n)") {
                let c = tabCenters()
                let y = c[0].y
                let last = c[n - 1].x
                synth([path(start: c[0], pressFor: 0.3, legs: [
                    (CGPoint(x: last, y: y), Double(last - c[0].x) / speed, 0.4),
                    (CGPoint(x: c[0].x - 30, y: y), Double(last - c[0].x + 30) / speed, 0.5),
                    (CGPoint(x: c[0].x - 50, y: y), 0.2, 0.5),
                ])], name: "pastleft")
            }
        }
        capture("segmented-seg3-tap-selected", scene: "segmented") {
            let c = segCenters("seg3")
            for hold in [0.05, 0.3, 0.05, 0.3] { tap(c[0], hold: hold); pause(1.6) }
        }
        for n in [3, 5] {
            capture("tabbar\(n)-tap-selected", scene: "tabbar\(n)") {
                let c = tabCenters()
                for hold in [0.05, 0.3, 0.05, 0.3] { tap(c[0], hold: hold); pause(1.8) }
            }
        }
    }

    func testRecapControls() {
        func knob(_ f: CGRect) -> CGPoint { CGPoint(x: f.midX - 11, y: f.midY) }
        for (tag, fwd, back) in [("a", 20.0, -5.0), ("b", 8.0, 0.0), ("c", 30.0, 12.0), ("d", 40.0, -10.0), ("e", 40.0, 5.0)] {
            for rep in 1...3 {
                capture("switch-tb-\(tag)\(rep)", scene: "sw") {
                    let k = knob(control("sw"))
                    synth([path(start: k, pressFor: 0.1, legs: [
                        (CGPoint(x: k.x + fwd, y: k.y), 0.4, 0.25),
                        (CGPoint(x: k.x + back, y: k.y), 0.4, 0.3),
                    ])], name: "thereback")
                }
            }
        }
        func thumb(_ f: CGRect, _ v: Double) -> CGPoint { CGPoint(x: f.minX + 18.5 + v * (f.width - 37), y: f.midY) }
        for (w, dist) in [(300, 120.0), (200, 80.0)] {
            for v in [150.0, 250.0, 400.0] {
                capture("slider-w\(w)-glide-v\(Int(v))", scene: "sl\(w)", extra: ["PROBE_SLIDER_VALUE": "0.1"]) {
                    let p = thumb(control("sl\(w)"), 0.1)
                    drag(p, CGPoint(x: p.x + dist, y: p.y), pressFor: 0.05, moveFor: dist / v, holdFor: 0)
                }
            }
        }
    }

    /// Slider ends on narrow tracks (200 and 260 pt, centered on the 402 pt screen) so the
    /// finger can travel 40-80 pt past either end: slow legs to the end, past it, holds, back;
    /// presses on a thumb resting near or at an end; fast drags and a fling into the end; an
    /// off-center grab; full-range sweeps.
    func testSliderEnds() {
        func thumb(_ f: CGRect, _ v: Double) -> CGPoint { CGPoint(x: f.minX + 18.5 + v * (f.width - 37), y: f.midY) }
        func at(_ p: CGPoint, _ x: CGFloat) -> CGPoint { CGPoint(x: x, y: p.y) }
        let speed = 100.0
        func legs(_ start: CGPoint, _ xs: [CGFloat]) -> [(CGPoint, Double, Double)] {
            var cur = start.x
            var out: [(CGPoint, Double, Double)] = []
            for x in xs {
                out.append((at(start, x), Double(abs(x - cur)) / speed, 0.5))
                cur = x
            }
            return out
        }
        for w in [200, 260] {
            let scene = "sl\(w)"
            let past: [CGFloat] = w == 200 ? [40, 80] : [40, 60]
            capture("slider-w\(w)-end-max-slow", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0.5"]) {
                let f = control(scene)
                let p = thumb(f, 0.5)
                synth([path(start: p, pressFor: 0.1, legs: legs(p, [f.maxX, f.maxX + past[0], f.maxX + past[1], f.maxX, f.maxX - 60]))])
            }
            capture("slider-w\(w)-end-min-slow", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0.5"]) {
                let f = control(scene)
                let p = thumb(f, 0.5)
                synth([path(start: p, pressFor: 0.1, legs: legs(p, [f.minX, f.minX - past[0], f.minX - past[1], f.minX, f.minX + 60]))])
            }
            capture("slider-w\(w)-sweep", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0"]) {
                let f = control(scene)
                let p = thumb(f, 0)
                synth([path(start: p, pressFor: 0.1, legs: legs(p, [f.maxX + past[1], f.minX - 20]))])
            }
        }
        let scene = "sl200"
        capture("slider-w200-nearend-max", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0.9"]) {
            let f = control(scene)
            let p = thumb(f, 0.9)
            synth([path(start: p, pressFor: 0.1, legs: legs(p, [f.maxX + 80, p.x]))])
        }
        capture("slider-w200-nearend-min", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0.1"]) {
            let f = control(scene)
            let p = thumb(f, 0.1)
            synth([path(start: p, pressFor: 0.1, legs: legs(p, [f.minX - 80, p.x]))])
        }
        capture("slider-w200-atend-max", scene: scene, extra: ["PROBE_SLIDER_VALUE": "1"]) {
            let f = control(scene)
            let p = thumb(f, 1)
            synth([path(start: p, pressFor: 0.1, legs: legs(p, [f.maxX + 80, p.x - 60]))])
        }
        capture("slider-w200-offgrab-max", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0.5"]) {
            let f = control(scene)
            let p = thumb(f, 0.5)
            let g = at(p, p.x + 12)
            synth([path(start: g, pressFor: 0.1, legs: legs(g, [f.maxX + 80]))])
        }
        capture("slider-w200-fast-max", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0.5"]) {
            let f = control(scene)
            let p = thumb(f, 0.5)
            synth([path(start: p, pressFor: 0.1, legs: [(at(p, f.maxX + 60), 0.3, 0.6)])])
        }
        capture("slider-w200-fast-min", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0.5"]) {
            let f = control(scene)
            let p = thumb(f, 0.5)
            synth([path(start: p, pressFor: 0.1, legs: [(at(p, f.minX - 60), 0.3, 0.6)])])
        }
        capture("slider-w200-fling-max", scene: scene, extra: ["PROBE_SLIDER_VALUE": "0.5"]) {
            let f = control(scene)
            let p = thumb(f, 0.5)
            drag(p, at(p, f.maxX + 40), pressFor: 0.1, moveFor: 0.25, holdFor: 0)
        }
    }

    /// One launch per slider scene and appearance for a screen recording (PROBE_PLAN
    /// slidervideo): taps, a hold, slow and fast drags, a glide, a track tap and both ends on
    /// the 300 pt slider at 0.3, then a stepped drag on slT5. Gaps of 1.5 s let every motion
    /// settle so the film can be cut per gesture.
    func testSliderVideo() {
        func at(_ f: CGRect, _ v: Double) -> CGPoint { CGPoint(x: f.minX + 18.5 + v * (f.width - 37), y: f.midY) }
        func value(_ scene: String) -> Double {
            Double(app.descendants(matching: .any)["c_" + scene].normalizedSliderPosition)
        }
        for dark in ["0", "1"] {
            capture("slvid-w300-\(dark == "1" ? "dark" : "light")", scene: "sl300", extra: ["PROBE_DARK": dark]) {
                let f = control("sl300")
                pause(1.0)
                tap(at(f, 0.3), hold: 0.09)
                pause(1.5)
                tap(at(f, 0.3), hold: 0.8)
                pause(1.5)
                var p = at(f, value("sl300"))
                drag(p, CGPoint(x: p.x + 100, y: p.y), pressFor: 0.1, moveFor: 1.0, holdFor: 0.4)
                pause(1.5)
                p = at(f, value("sl300"))
                drag(p, CGPoint(x: p.x - 100, y: p.y), pressFor: 0.1, moveFor: 0.4, holdFor: 0)
                pause(1.5)
                tap(CGPoint(x: f.minX + 270, y: f.midY), hold: 0.09)
                pause(1.5)
                p = at(f, value("sl300"))
                synth([path(start: p, pressFor: 0.1, legs: [(CGPoint(x: f.maxX + 40, y: p.y), Double(f.maxX + 40 - p.x) / 150, 0.6)])])
                pause(1.5)
                p = at(f, value("sl300"))
                synth([path(start: p, pressFor: 0.1, legs: [(CGPoint(x: f.minX - 40, y: p.y), Double(p.x - f.minX + 40) / 150, 0.6)])])
                pause(1.5)
            }
            capture("slvid-t5-\(dark == "1" ? "dark" : "light")", scene: "slT5", extra: ["PROBE_DARK": dark]) {
                let f = control("slT5")
                pause(1.0)
                tap(at(f, 0), hold: 0.8)
                pause(1.5)
                var p = at(f, value("slT5"))
                drag(p, CGPoint(x: p.x + 200, y: p.y), pressFor: 0.1, moveFor: 1.6, holdFor: 0.4)
                pause(1.5)
                p = at(f, value("slT5"))
                drag(p, CGPoint(x: p.x - 45, y: p.y), pressFor: 0.1, moveFor: 0.6, holdFor: 0.4)
                pause(1.5)
            }
        }
    }

    /// Behaviour questions of 2026-10-03: the tab bar's slow lift regime (long tap runs with
    /// the lens layer's animations logged) and a touch outside a menu between the tap's
    /// release and the menu's appearance (second stroke of 10 to 200 ms, starting at the lift).
    func testBehaviours() {
        let anims = ["PROBE_LENS_ANIMS": "1"]
        capture("b-tabbar4-rerun", scene: "tabbar4", extra: anims) {
            let c = tabCenters()
            tapSequence(c, [1, 3, 0, 2, 0, 2, 0, 1, 3, 1, 0], gap: 1.8)
        }
        capture("b-tabbar5-many", scene: "tabbar5", extra: anims) {
            let c = tabCenters()
            tapSequence(c, [4, 1, 2, 0, 3, 0, 2, 4, 1, 3, 0, 4, 2, 1, 0], gap: 1.8)
        }
        capture("b-tabbar5-durations", scene: "tabbar5", extra: anims) {
            let c = tabCenters()
            for (i, hold) in [(1, 0.03), (0, 0.1), (2, 0.2), (0, 0.03), (3, 0.1), (0, 0.2), (4, 0.4), (0, 0.06)] {
                tap(c[i], hold: hold)
                pause(1.8)
            }
        }
        capture("b-tabbar4-pairs", scene: "tabbar4", extra: anims) {
            let c = tabCenters()
            tapSequence(c, [2, 0, 2, 1, 2, 3, 2, 0, 3, 1, 3, 0, 1, 0, 2], gap: 1.8)
        }
        capture("b-tabbar4-radio-first", scene: "tabbar4", extra: ["PROBE_TAB_ORDER": "2,0,1,3"]) {
            let c = tabCenters()
            tapSequence(c, [1, 0, 2, 3, 0, 3, 1, 2], gap: 1.8)
        }
        capture("b-tabbar4-no-radio", scene: "tabbar4", extra: ["PROBE_TAB_ORDER": "0,1,4,3"]) {
            let c = tabCenters()
            tapSequence(c, [2, 0, 2, 1, 3, 2, 0], gap: 1.8)
        }
        capture("b-tabbar3-pairs", scene: "tabbar3", extra: anims) {
            let c = tabCenters()
            tapSequence(c, [2, 0, 2, 1, 0, 1, 2, 0], gap: 1.8)
        }
        for ms in [10, 25, 50, 100, 200] {
            capture("b-menu-early-outside-\(ms)", scene: "menu") {
                let f = menuButton()
                let c = CGPoint(x: f.midX, y: f.midY)
                let o = outside(of: f)
                let d = Double(ms) / 1000
                synth([Stroke(points: [(0, c)], liftAt: 0.1), Stroke(points: [(0.125, o)], liftAt: 0.125 + d)], name: "early\(ms)")
                pause(1.6)
            }
        }
    }

    /// Tab bar look (2026-10-03): the held bar's brightening, the touch glow, the platter and
    /// the selected tint over time, in dark and light (PROBE_DARK), with every layer of the bar
    /// group logged per frame (PROBE_TABLAYERS). Filmed by the screen recorder alongside.
    func testTabLook() {
        for dark in ["1", "0"] {
            let tag = dark == "1" ? "dark" : "light"
            capture("look-tabbar3-\(tag)", scene: "tabbar3", extra: ["PROBE_DARK": dark, "PROBE_TABLAYERS": "1"]) {
                let c = tabCenters()
                pause(1.0)
                tap(c[1], hold: 0.06)
                pause(2.0)
                synth([Stroke(points: [(0, c[2])], liftAt: 1.5)], name: "hold-other")
                pause(2.0)
                synth([Stroke(points: [(0, c[2])], liftAt: 1.5)], name: "hold-selected")
                pause(2.0)
                tap(c[0], hold: 0.06)
                pause(2.0)
                tap(c[0], hold: 0.06)
                pause(2.0)
                drag(c[0], c[2], pressFor: 0.4, moveFor: 1.0, holdFor: 0.6)
                pause(2.0)
            }
        }
    }

    /// What turns the touch glow into its dragging state (scale 2, half opacity): distance from
    /// the touch-down or the finger leaving its tab. Slow drags (PROBE_STEP_HZ points) of 25 to
    /// 60 pt, inside one tab and across the boundary between two.
    func testTabGlowDrag() {
        capture("look-tabbar3-glowdrag", scene: "tabbar3", extra: ["PROBE_DARK": "1", "PROBE_TABLAYERS": "1"]) {
            let c = tabCenters()
            let y = c[0].y
            let moves: [(Double, Double)] = [
                (c[1].x, c[1].x + 25), (c[1].x - 20, c[1].x + 20), (c[0].x, c[0].x - 35),
                (c[1].x - 30, c[1].x + 30), (c[0].x + 10, c[0].x + 50), (c[1].x, c[1].x + 60),
            ]
            for (a, b) in moves {
                drag(CGPoint(x: a, y: y), CGPoint(x: b, y: y), pressFor: 0.4, moveFor: 0.8, holdFor: 0.5)
                pause(2.0)
            }
        }
    }

    func testRecapMenu() {
        // Separate synth calls: within one record the synthesizer starts the next stroke at the
        // previous lift, whatever the planned gap; the realized gap is read from the touch rows.
        // Overlapping strokes keep their planned offsets: a third, idle finger on the empty
        // background spans the whole record so the button stroke can start dt after the
        // outside lift.
        for dt in [0.08, 0.15, 0.25] {
            capture("center3-reopen3-\(Int(dt * 1000))", scene: "menu") {
                let f = menuButton()
                let c = CGPoint(x: f.midX, y: f.midY)
                let o = outside(of: f)
                let idle = CGPoint(x: 40, y: 760)
                for _ in 0..<2 {
                    tap(c, hold: 0.1)
                    pause(1.6)
                    synth([
                        Stroke(points: [(0, idle)], liftAt: 0.06 + dt + 0.2),
                        Stroke(points: [(0.01, o)], liftAt: 0.07),
                        Stroke(points: [(0.07 + dt, c)], liftAt: 0.07 + dt + 0.06),
                    ], name: "reopen3")
                    pause(1.8)
                    tap(o, hold: 0.06)
                    pause(1.6)
                }
            }
        }
        // Two synth requests in flight: the button tap is requested `s` seconds after the
        // outside tap was requested, without waiting for it to complete.
        for s in [0.10, 0.17, 0.27] {
            capture("center3-reopen4-\(Int(s * 1000))", scene: "menu") {
                let f = menuButton()
                let c = CGPoint(x: f.midX, y: f.midY)
                let o = outside(of: f)
                for _ in 0..<2 {
                    tap(c, hold: 0.1)
                    pause(1.6)
                    let e1 = synthStart([Stroke(points: [(0, o)], liftAt: 0.06)], name: "outside")
                    pause(s)
                    let e2 = synthStart([Stroke(points: [(0, c)], liftAt: 0.06)], name: "button")
                    wait(for: [e1, e2], timeout: 30)
                    pause(1.8)
                    tap(o, hold: 0.06)
                    pause(1.6)
                }
            }
        }
        for p in [0.0, 0.05, 0.12, 0.2, 0.35] {
            capture("center3-reopen2-\(Int(p * 1000))", scene: "menu") {
                let f = menuButton()
                let c = CGPoint(x: f.midX, y: f.midY)
                let o = outside(of: f)
                for _ in 0..<2 {
                    tap(c, hold: 0.1)
                    pause(1.6)
                    tap(o, hold: 0.06)
                    if p > 0 { pause(p) }
                    tap(c, hold: 0.06)
                    pause(1.8)
                    tap(o, hold: 0.06)
                    pause(1.6)
                }
            }
        }
        for dt in [0.08, 0.15, 0.25] {
            capture("center3-reopen-\(Int(dt * 1000))", scene: "menu") {
                let f = menuButton()
                let c = CGPoint(x: f.midX, y: f.midY)
                let o = outside(of: f)
                for _ in 0..<2 {
                    tap(c, hold: 0.1)
                    pause(1.6)
                    synth([Stroke(points: [(0, o)], liftAt: 0.06), Stroke(points: [(0.06 + dt, c)], liftAt: 0.06 + dt + 0.1)], name: "reopen")
                    pause(1.8)
                    tap(o, hold: 0.06)
                    pause(1.6)
                }
            }
        }
    }

    // MARK: static references

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(data: s.pngRepresentation, uniformTypeIdentifier: "public.png")
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        NSLog("PROBE shot \(name) at \(CACurrentMediaTime())")
    }

    /// Holds a finger at `p`, takes the screenshot `after` seconds into the hold, then lifts.
    private func shotHeld(_ p: CGPoint, after: Double, _ name: String) {
        let done = synthStart([Stroke(points: [(0, p)], liftAt: after + 1.6)], name: "held")
        pause(after)
        shot(name)
        wait(for: [done], timeout: 30)
    }

    /// PROBE_REF_DARK=1/0 forces the appearance of every reference (unset = the phone's own).
    func testReferences() {
        let rx = env["PROBE_REF_DARK"].map { ["PROBE_DARK": $0] } ?? [:]
        capture("ref-segmented", scene: "segmented", extra: rx) {
            let c = segCenters("seg3")
            shot("segmented-resting")
            shotHeld(c[0], after: 0.7, "segmented-held-selected")
        }
        capture("ref-tabbar3", scene: "tabbar3", extra: rx) {
            let c = tabCenters()
            shot("tabbar3-resting")
            shotHeld(c[0], after: 0.7, "tabbar3-held-selected")
            pause(1.6)
            shotHeld(c[1], after: 0.7, "tabbar3-held-other")
        }
        capture("ref-switch", scene: "sw", extra: rx) {
            let f = control("sw")
            shot("switch-off")
            shotHeld(CGPoint(x: f.midX - 11, y: f.midY), after: 0.7, "switch-off-knob-held")
            pause(1.6)
            shot("switch-on")
        }
        capture("ref-slider", scene: "sl300", extra: rx) {
            let f = control("sl300")
            shot("slider-resting")
            shotHeld(CGPoint(x: f.minX + 18.5 + 0.3 * (f.width - 37), y: f.midY), after: 0.7, "slider-thumb-held")
        }
        for (w, h) in [(120, 44), (44, 44)] {
            capture("ref-gb\(w)x\(h)", scene: "gb\(w)x\(h)", extra: rx) {
                let f = control("gb\(w)x\(h)")
                shot("glass-\(w)x\(h)-resting")
                shotHeld(CGPoint(x: f.midX, y: f.midY), after: 0.7, "glass-\(w)x\(h)-pressed")
            }
        }
        capture("ref-menu", scene: "menu", extra: rx) {
            let f = menuButton()
            shot("menu-button-resting")
            tap(CGPoint(x: f.midX, y: f.midY), hold: 0.1)
            pause(1.5)
            shot("menu-open")
        }
    }

    // MARK: liquid glass merge

    private let mergeAdvance = CGPoint(x: 12, y: 500)

    func testMerge() {
        let spacings = env["PROBE_SPACINGS"] ?? "0,10,20,40,80"
        let list = spacings.split(separator: ",").map { String($0) }
        let variants: [(String, String)] = [("grey", "1"), ("grey", "0"), ("stripes", "0")]
        for api in ["uikit", "swiftui"] {
            for (bg, tint) in variants {
                let rec = "merge-\(api)-\(bg)-t\(tint)"
                capture(rec, scene: "merge", extra: ["PROBE_API": api, "PROBE_BG": bg, "PROBE_TINT": tint, "PROBE_SPACINGS": spacings]) {
                    for (i, s) in list.enumerated() {
                        pause(1.6)
                        shot("\(rec)-s\(s)")
                        if i + 1 < list.count { tap(mergeAdvance, hold: 0.05) }
                    }
                }
            }
        }
    }

    func testMergeDyn() {
        for sp in ["20", "40"] {
            let rec = "mergedyn-s\(sp)"
            capture(rec, scene: "mergeDyn", extra: ["PROBE_SPACING": sp, "PROBE_TINT": "1"]) {
                shot("\(rec)-rest")
                tap(mergeAdvance, hold: 0.05)
                pause(0.8)
                shot("\(rec)-anim-in-mid")
                pause(1.8)
                shot("\(rec)-anim-in-end")
                tap(mergeAdvance, hold: 0.05)
                pause(2.6)
                let start = CGPoint(x: 210, y: 437)
                let gaps: [CGFloat] = [30, 20, 14, 10, 6, 3, 0, -5, 3, 6, 10, 14, 20, 30]
                var legs: [(CGPoint, Double, Double)] = []
                for g in gaps { legs.append((CGPoint(x: start.x - (60 - g), y: start.y), 0.5, 1.4)) }
                let stroke = path(start: start, pressFor: 0.3, legs: legs)
                let done = synthStart([stroke], name: "mergedrag")
                let t0 = Date()
                var tShot = 0.3
                for (i, g) in gaps.enumerated() {
                    tShot += 0.5
                    let at = (tShot + 0.6) * 1.09
                    let wait = at - Date().timeIntervalSince(t0)
                    if wait > 0 { pause(wait) }
                    shot("\(rec)-drag\(i)-g\(Int(g))")
                    tShot += 1.4
                }
                wait(for: [done], timeout: 60)
            }
        }
        capture("mergeid", scene: "mergeID", extra: ["PROBE_TINT": "1"]) {
            shot("mergeid-one")
            for dir in ["split", "join"] {
                tap(mergeAdvance, hold: 0.05)
                for k in 0..<3 { shot("mergeid-\(dir)-\(k)") }
                pause(1.5)
                shot("mergeid-\(dir)-end")
            }
        }
    }
}
