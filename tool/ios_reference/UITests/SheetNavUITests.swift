import XCTest

/// Device captures for the SheetNav.swift scenes: zoom transitions from a source (sheet and
/// push, interactive dismissals) and the back button long-press menu. Same plumbing as
/// Widgets2UITests (synthesized pointer paths, PROBE_ONLY filter, one relaunch per capture).
final class SheetNavUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private let env = ProcessInfo.processInfo.environment
    private var only: Set<String> {
        Set((env["PROBE_ONLY"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    private var app = XCUIApplication()
    private var stepHz: Double { Double(env["PROBE_STEP_HZ"] ?? "") ?? 30 }

    private func capture(_ rec: String, scene: String, extra: [String: String] = [:], settle: Double = 1.5, _ body: () -> Void) {
        if !only.isEmpty && !only.contains(rec) { return }
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = scene
        app.launchEnvironment["PROBE_REC"] = rec
        app.launchEnvironment["PROBE_TRACK"] = "^NOTHING$"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        Thread.sleep(forTimeInterval: 2.0)
        NSLog("PROBE capture begin \(rec)")
        body()
        Thread.sleep(forTimeInterval: settle)
        NSLog("PROBE capture end \(rec)")
        app.terminate()
    }

    private func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    struct Stroke { var points: [(Double, CGPoint)]; var liftAt: Double }

    private func synth(_ strokes: [Stroke], name: String = "sn") {
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
        wait(for: [done], timeout: 60)
    }

    private func tap(_ p: CGPoint, hold: Double = 0.06) { synth([Stroke(points: [(0, p)], liftAt: hold)], name: "tap") }

    private func line(_ a: CGPoint, _ b: CGPoint, from t0: Double, over d: Double) -> [(Double, CGPoint)] {
        let steps = max(1, Int((d * stepHz).rounded()))
        return (1...steps).map { i in
            let f = Double(i) / Double(steps)
            return (t0 + d * f, CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        }
    }

    private func path(_ start: CGPoint, pressFor: Double, _ legs: [(CGPoint, Double, Double)]) {
        var pts: [(Double, CGPoint)] = [(0, start)]
        if pressFor > 0 { pts.append((pressFor, start)) }
        var t = pressFor
        var cur = start
        for (to, dur, hold) in legs {
            pts += line(cur, to, from: t, over: dur)
            t += dur
            if hold > 0 { t += hold; pts.append((t, to)) }
            cur = to
        }
        synth([Stroke(points: pts, liftAt: t + 0.001)], name: "path")
    }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    // iPhone 16 Pro, 402 x 874: source capsule centered at (201, 300); medium sheet top ~415.

    func testSNZoom() {
        let src = p(201, 300)
        capture("zoom-tap-open-dim", scene: "snzoom") { tap(src); pause(1.6); tap(p(201, 150)); pause(1.2) }
        capture("zoom-drag-cancel", scene: "snzoom") { tap(src); pause(1.6); path(p(201, 520), pressFor: 0.1, [(p(201, 600), 0.6, 0.3)]); pause(1.2) }
        capture("zoom-drag-dismiss", scene: "snzoom") { tap(src); pause(1.6); path(p(201, 520), pressFor: 0.1, [(p(201, 820), 1.0, 0.3)]); pause(1.2) }
        capture("zoom-drag-hold-up", scene: "snzoom") { tap(src); pause(1.6); path(p(201, 520), pressFor: 0.1, [(p(201, 760), 0.8, 0.2), (p(201, 520), 0.8, 0.3)]); pause(1.2) }
        capture("zoom-flick", scene: "snzoom") { tap(src); pause(1.6); path(p(201, 520), pressFor: 0.08, [(p(201, 680), 0.12, 0)]); pause(1.2) }
        capture("zoom-card-dim", scene: "snzoom", extra: ["PROBE_SRC": "card"]) { tap(src); pause(1.6); tap(p(201, 150)); pause(1.2) }
        capture("zoom-glass-dim", scene: "snzoom", extra: ["PROBE_SRC": "glass"]) { tap(src); pause(1.6); tap(p(201, 150)); pause(1.2) }
        capture("zoom-large-drag", scene: "snzoom", extra: ["PROBE_START": "l"]) { tap(src); pause(1.6); path(p(201, 200), pressFor: 0.1, [(p(201, 700), 1.0, 0.3)]); pause(1.2) }
    }

    func testSNPush() {
        let src = p(201, 300)
        capture("push-zoom-back", scene: "snpush") { tap(src); pause(1.6); tap(p(40, 84)); pause(1.2) }
        capture("push-zoom-swipe-down", scene: "snpush") { tap(src); pause(1.6); path(p(201, 400), pressFor: 0.1, [(p(201, 700), 0.8, 0.3)]); pause(1.2) }
        capture("push-zoom-swipe-cancel", scene: "snpush") { tap(src); pause(1.6); path(p(201, 400), pressFor: 0.1, [(p(201, 470), 0.5, 0.3)]); pause(1.2) }
        capture("push-zoom-edge", scene: "snpush") { tap(src); pause(1.6); path(p(2, 450), pressFor: 0.05, [(p(300, 450), 0.8, 0.3)]); pause(1.2) }
    }

    func testSNBack() {
        let back = p(50, 84)
        capture("back-hold-open", scene: "snback", settle: 1.0) { path(back, pressFor: 1.2, []); pause(1.6); tap(p(300, 700)); pause(1.2) }
        capture("back-select-root", scene: "snback", settle: 1.0) {
            path(back, pressFor: 1.2, [])
            pause(1.6)
            let e = app.buttons["Mailboxes"]
            if e.exists { e.tap() } else { NSLog("PROBE no Mailboxes button") }
            pause(1.5)
        }
        capture("back-select-inbox", scene: "snback", settle: 1.0) {
            path(back, pressFor: 1.2, [])
            pause(1.6)
            let e = app.buttons["Inbox"]
            if e.exists { e.tap() } else { NSLog("PROBE no Inbox button") }
            pause(1.5)
        }
        capture("back-slide", scene: "snback", settle: 1.0) { path(back, pressFor: 0.9, [(p(90, 240), 0.5, 0.3)]); pause(1.5) }
        capture("back-tap", scene: "snback", settle: 1.0) { tap(back); pause(1.5) }
        capture("back-hold-away", scene: "snback", settle: 1.0) { path(back, pressFor: 1.0, [(p(250, 500), 0.4, 0.3)]); pause(1.5); tap(p(300, 700)); pause(1.0) }
        capture("back-hold-row2", scene: "snback", settle: 1.0) { path(back, pressFor: 1.0, []); pause(1.5); tap(p(80, 192)); pause(1.5) }
        for ms in [250, 350, 450, 550, 700] {
            capture("back-hold-\(ms)", scene: "snback", settle: 1.0) { path(back, pressFor: Double(ms) / 1000, []); pause(1.4); tap(p(300, 700)); pause(1.0) }
        }
        capture("back-hold-dark", scene: "snback", extra: ["PROBE_DARK": "1"], settle: 1.0) { path(back, pressFor: 1.2, []); pause(1.6); tap(p(300, 700)); pause(1.2) }
    }
}
