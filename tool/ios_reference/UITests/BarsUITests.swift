import XCTest

/// Navigation bar / toolbar captures (scene `nav`, see Sources/Bars.swift).
///
/// PROBE_PLAN=bars runs testBars: self-driven scripts (PROBE_AUTO) and real touches - drags on
/// the list (large title collapse, partial release, fling), interactive edge-swipe pops
/// (commit, cancel), back button taps and holds, and screenshot attachments of the scroll
/// edge effect (soft / hard, light / dark). Touches go through the same event synthesizer as
/// ProbeUITests (30 Hz path points by default, PROBE_STEP_HZ).
final class BarsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private let env = ProcessInfo.processInfo.environment
    private var only: Set<String> {
        Set((env["PROBE_ONLY"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    private var app = XCUIApplication()
    private var stepHz: Double { Double(env["PROBE_STEP_HZ"] ?? "") ?? 30 }

    private func capture(_ rec: String, extra: [String: String] = [:], settle: Double = 2.5, _ body: () -> Void) {
        if !only.isEmpty && !only.contains(rec) { return }
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "nav"
        app.launchEnvironment["PROBE_REC"] = rec
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        Thread.sleep(forTimeInterval: settle)
        NSLog("PROBE capture begin \(rec)")
        body()
        Thread.sleep(forTimeInterval: 1.5)
        NSLog("PROBE capture end \(rec)")
        app.terminate()
    }

    private func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    struct Stroke { var points: [(Double, CGPoint)]; var liftAt: Double }

    private func synthStart(_ strokes: [Stroke], name: String) -> XCTestExpectation {
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

    private func synth(_ strokes: [Stroke], name: String) { wait(for: [synthStart(strokes, name: name)], timeout: 60) }

    private func line(_ a: CGPoint, _ b: CGPoint, from t0: Double, over d: Double) -> [(Double, CGPoint)] {
        let steps = max(1, Int((d * stepHz).rounded()))
        return (1...steps).map { i in
            let f = Double(i) / Double(steps)
            return (t0 + d * f, CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        }
    }

    /// Press at `start`, wait `pressFor`, then legs of (target, duration, holdAfter); lifts at the end.
    private func path(start: CGPoint, pressFor: Double, legs: [(CGPoint, Double, Double)]) -> Stroke {
        var pts: [(Double, CGPoint)] = [(0, start)]
        var t = pressFor
        var cur = start
        if pressFor > 0 { pts.append((pressFor, start)) }
        for (to, dur, hold) in legs {
            pts += line(cur, to, from: t, over: dur)
            t += dur
            cur = to
            if hold > 0 { t += hold; pts.append((t, cur)) }
        }
        return Stroke(points: pts, liftAt: t)
    }

    private func tap(_ p: CGPoint, hold: Double = 0.06) { synth([Stroke(points: [(0, p)], liftAt: hold)], name: "tap") }

    private func shot(_ name: String) {
        let a = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        NSLog("PROBE shot \(name)")
    }

    private var size: CGSize { app.windows.firstMatch.frame.size }

    private func pushByRow() {
        let row = app.cells["row3"]
        let p = row.exists ? CGPoint(x: row.frame.midX, y: row.frame.midY) : CGPoint(x: size.width / 2, y: 420)
        tap(p, hold: 0.06)
    }

    /// Scene navseg driven by touches: a tap pushes the next page, edge swipes and back
    /// button taps pop (bars.md "Per-segment transitions").
    func testNavSeg() {
        capture("navseg-touch", extra: ["PROBE_SCENE": "navseg", "PROBE_SEQ": "none"]) {
            let y = size.height * 0.5
            let mid = CGPoint(x: size.width / 2, y: size.height * 0.6)
            let back = CGPoint(x: 40, y: 84)
            tap(mid)
            pause(1.6)
            synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 280, y: y), 0.9, 0.2)])], name: "edge")
            pause(1.8)
            tap(mid)
            pause(1.6)
            synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 140, y: y), 0.6, 0.3), (CGPoint(x: 40, y: y), 0.4, 0.3)])], name: "edgecancel")
            pause(1.8)
            synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 280, y: y), 0.9, 0.2)])], name: "edge2")
            pause(1.8)
            for _ in 0..<4 {
                tap(mid)
                pause(1.6)
            }
            for _ in 0..<4 {
                tap(back)
                pause(1.6)
            }
        }
    }

    func testBars() {
        capture("bars-scroll-auto", extra: ["PROBE_AUTO": "scrollquick"]) { pause(6.5) }
        for style in ["soft", "hard"] {
            capture("bars-scroll-auto-\(style)", extra: ["PROBE_AUTO": "scrollquick", "PROBE_EDGE": style]) { pause(6.5) }
        }
        capture("bars-toolbar-auto", extra: ["PROBE_AUTO": "toolbar"]) { pause(9.5) }
        capture("bars-push-auto", extra: ["PROBE_AUTO": "push"]) { pause(6.0) }
        capture("bars-drag-collapse") {
            let x = size.width / 2
            synth([path(start: CGPoint(x: x, y: 640), pressFor: 0.15, legs: [(CGPoint(x: x, y: 440), 1.2, 0.6)])], name: "up")
            pause(1.5)
            synth([path(start: CGPoint(x: x, y: 440), pressFor: 0.15, legs: [(CGPoint(x: x, y: 640), 1.2, 0.6)])], name: "down")
            pause(1.5)
        }
        for d in [20.0, 35.0, 45.0] {
            capture("bars-drag-partial\(Int(d))") {
                let x = size.width / 2
                synth([path(start: CGPoint(x: x, y: 600), pressFor: 0.15, legs: [(CGPoint(x: x, y: 600 - d), 0.5, 0.4)])], name: "partial")
                pause(1.8)
            }
        }
        for d in [24.0, 28.0, 31.0, 40.0] {
            capture("bars-drag-partial\(Int(d))") {
                let x = size.width / 2
                synth([path(start: CGPoint(x: x, y: 600), pressFor: 0.15, legs: [(CGPoint(x: x, y: 600 - d), 0.5, 0.4)])], name: "partial")
                pause(1.8)
            }
        }
        for frac in [0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.6] {
            capture("bars-edge-slow\(Int(frac * 100))") {
                pushByRow()
                pause(1.6)
                let y = size.height * 0.5
                synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 3 + size.width * frac, y: y), 1.0, 0.4)])], name: "edgeslow")
                pause(1.8)
            }
        }
        for (name, dx, dur) in [("short", 50.0, 0.1), ("mid", 90.0, 0.25), ("slowshort", 60.0, 0.4), ("v350", 70.0, 0.2), ("v400", 80.0, 0.2), ("v450", 90.0, 0.2), ("v500", 100.0, 0.2)] {
            capture("bars-edge-flick-\(name)") {
                pushByRow()
                pause(1.6)
                let y = size.height * 0.5
                synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 3 + dx, y: y), dur, 0)])], name: "edgeflick")
                pause(1.8)
            }
        }
        for (name, back) in [("flickback3", 170.0), ("flickback4", 185.0)] {
            capture("bars-edge-\(name)") {
                pushByRow()
                pause(1.6)
                let y = size.height * 0.5
                synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 260, y: y), 0.7, 0.2), (CGPoint(x: back, y: y), 0.1, 0)])], name: name)
                pause(1.8)
            }
        }
        capture("bars-edge-flickback2") {
            pushByRow()
            pause(1.6)
            let y = size.height * 0.5
            synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 260, y: y), 0.7, 0.2), (CGPoint(x: 140, y: y), 0.1, 0)])], name: "edgeflickback2")
            pause(1.8)
        }
        capture("bars-edge-flickback") {
            pushByRow()
            pause(1.6)
            let y = size.height * 0.5
            synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 260, y: y), 0.7, 0.2), (CGPoint(x: 200, y: y), 0.1, 0)])], name: "edgeflickback")
            pause(1.8)
        }
        capture("bars-fling") {
            let x = size.width / 2
            synth([path(start: CGPoint(x: x, y: 700), pressFor: 0.05, legs: [(CGPoint(x: x, y: 450), 0.12, 0)])], name: "fling")
            pause(2.5)
        }
        capture("bars-edge-commit") {
            pushByRow()
            pause(1.6)
            let y = size.height * 0.5
            synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 280, y: y), 0.9, 0.2)])], name: "edge")
            pause(1.8)
        }
        capture("bars-edge-cancel") {
            pushByRow()
            pause(1.6)
            let y = size.height * 0.5
            synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 140, y: y), 0.6, 0.3), (CGPoint(x: 40, y: y), 0.4, 0.3)])], name: "edgecancel")
            pause(1.8)
        }
        capture("bars-edge-fling") {
            pushByRow()
            pause(1.6)
            let y = size.height * 0.5
            synth([path(start: CGPoint(x: 3, y: y), pressFor: 0.05, legs: [(CGPoint(x: 110, y: y), 0.18, 0)])], name: "edgefling")
            pause(1.8)
        }
        capture("bars-back-tap") {
            pushByRow()
            pause(1.6)
            tap(CGPoint(x: 50, y: 84), hold: 0.12)
            pause(1.6)
        }
        capture("bars-back-hold") {
            pushByRow()
            pause(1.6)
            synth([Stroke(points: [(0, CGPoint(x: 50, y: 84))], liftAt: 1.0)], name: "backhold")
            pause(1.2)
            shot("bars-back-hold-menu")
            tap(CGPoint(x: size.width / 2, y: size.height - 140), hold: 0.06)
            pause(1.4)
        }
        capture("bars-item-hold") {
            synth([Stroke(points: [(0, CGPoint(x: size.width - 40, y: 84))], liftAt: 0.8)], name: "itemhold")
            pause(1.4)
        }
        for dark in ["0", "1"] {
            for style in ["soft", "hard"] {
                capture("bars-ref-\(style)-d\(dark)", extra: ["PROBE_EDGE": style, "PROBE_DARK": dark]) {
                    let x = size.width / 2
                    shot("bars-\(style)-d\(dark)-top")
                    synth([path(start: CGPoint(x: x, y: 640), pressFor: 0.1, legs: [(CGPoint(x: x, y: 380), 1.0, 0.8)])], name: "scroll")
                    pause(1.2)
                    shot("bars-\(style)-d\(dark)-scrolled")
                }
            }
        }
    }
}
