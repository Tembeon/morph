import XCTest

/// Simulator captures for the third widget pass (Extras.swift scenes): the compact date
/// picker's popover and the search field's touch. Same plumbing as Widgets2UITests.
final class ExtrasUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private let env = ProcessInfo.processInfo.environment
    private var only: Set<String> {
        Set((env["PROBE_ONLY"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    private var app = XCUIApplication()
    private var stepHz: Double { Double(env["PROBE_STEP_HZ"] ?? "") ?? 30 }

    private func capture(_ rec: String, scene: String, extra: [String: String] = [:], settle: Double = 1.8, _ body: () -> Void) {
        if !only.isEmpty && !only.contains(rec) { return }
        app = env["PROBE_BUNDLE"].map { XCUIApplication(bundleIdentifier: $0) } ?? XCUIApplication()
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

    struct Stroke { var points: [(Double, CGPoint)]; var liftAt: Double }

    private func synth(_ strokes: [Stroke], name: String = "w2") {
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

    /// Press at `start`, wait `pressFor`, then legs of (target, duration, holdAfter); lift after the last hold.
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

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    // MARK: compact date picker (iPhone 18 Pro Max, 440 x 956: picker 115 x 34 centered at 220, 300)

    func testX3Date() {
        let picker = p(220, 300)
        capture("date-open", scene: "x3date", extra: ["PROBE_SCRIPT": "tree-rest@1.0;tree-open@4.3"]) {
            tap(picker); pause(1.6); shot("date-open"); tap(p(220, 880)); pause(1.4)
        }
        capture("date-open-dark", scene: "x3date", extra: ["PROBE_DARK": "1", "PROBE_SCRIPT": "tree-open@4.3"]) {
            tap(picker); pause(1.6); shot("date-open-dark"); tap(p(220, 880)); pause(1.4)
        }
        capture("date-time", scene: "x3date", extra: ["PROBE_DMODE": "time", "PROBE_SCRIPT": "tree-time@4.3"]) {
            tap(picker); pause(1.6); shot("date-time"); tap(p(220, 880)); pause(1.4)
        }
        capture("date-low", scene: "x3date", extra: ["PROBE_PY": "760", "PROBE_SCRIPT": "tree-open@4.3"]) {
            tap(p(220, 760)); pause(1.6); shot("date-low"); tap(p(220, 120)); pause(1.4)
        }
        capture("date-left", scene: "x3date", extra: ["PROBE_PX": "90", "PROBE_SCRIPT": "tree-open@4.3"]) {
            tap(p(90, 300)); pause(1.6); shot("date-left"); tap(p(220, 880)); pause(1.4)
        }
        capture("date-pick", scene: "x3date", extra: ["PROBE_SCRIPT": "tree-pick@5.6"]) {
            tap(picker); pause(1.4); tap(p(222.3, 506.8)); pause(1.6); tap(p(316, 341)); pause(1.4)
        }
        capture("date-right", scene: "x3date", extra: ["PROBE_PX": "360", "PROBE_SCRIPT": "tree-right@4.3"]) {
            tap(p(360, 300)); pause(1.6); shot("date-right"); tap(p(220, 880)); pause(1.4)
        }
        capture("date-both", scene: "x3date", extra: ["PROBE_DMODE": "both", "PROBE_SCRIPT": "tree-both@1.0"]) {
            shot("date-both")
        }
        capture("date-hold", scene: "x3date") {
            path(picker, pressFor: 0.6, []); pause(1.6); tap(p(220, 880)); pause(1.4)
        }
    }

    // MARK: search field touch (toolbar placement, capsule 28..412 x 880..928)

    func testX3Search() {
        capture("search-tap", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar"]) {
            tap(p(220, 904), hold: 0.08); pause(1.6); shot("search-focused")
        }
        capture("search-hold", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar"]) {
            path(p(220, 904), pressFor: 0.5, []); pause(1.6)
        }
        capture("search-close", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar"]) {
            tap(p(220, 904)); pause(1.6); tap(p(408, 575)); pause(1.6)
        }
    }

    // MARK: alert buttons (3 actions: OK 448..496, Delete 504..552, Cancel 560..608 on x 76..364)

    func testX3Alert() {
        capture("alert-press", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3"]) {
            pause(0.8); path(p(220, 472), pressFor: 0.6, []); pause(1.2)
        }
        capture("alert-hold-tree", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3;tree-hold1@4.7;tree-hold2@5.1;tree-hold3@5.5"]) {
            pause(0.8); path(p(220, 472), pressFor: 1.6, []); pause(1.2)
        }
        capture("alert-slide", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3"]) {
            pause(0.8); path(p(220, 472), pressFor: 0.3, [(p(220, 528), 0.3, 0.3), (p(220, 700), 0.3, 0.2)]); pause(1.2)
        }
        capture("alert-tap", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3"]) {
            pause(0.8); tap(p(220, 584)); pause(1.2)
        }
        capture("ash-tap-out", scene: "x3alert", extra: ["PROBE_ALERT": "sheet", "PROBE_SCRIPT": "show@0.3"]) {
            pause(1.6); tap(p(220, 120)); pause(1.2)
        }
        capture("alert-pref-dark", scene: "x3alert", extra: ["PROBE_DARK": "1", "PROBE_ACTIONS": "2", "PROBE_PREFERRED": "1", "PROBE_SCRIPT": "show@0.3;tree-prefdark@1.6"]) {
            pause(1.4); shot("alert-pref-dark")
        }
    }

    // MARK: device-geometry captures (any screen: coordinates from the window size)

    private var screen: CGSize { app.windows.firstMatch.frame.size }

    private func closeSearch() {
        let kb = app.keyboards.firstMatch
        let top = kb.exists ? min(kb.frame.minY, screen.height - 328) : screen.height - 328
        NSLog("PROBE keyboard top \(top)")
        tap(p(screen.width - 8 - 24, top - 10 - 24))
    }

    func testX3Device() {
        capture("search-tap", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar"]) {
            let s = screen
            tap(p(s.width / 2, s.height - 52), hold: 0.08); pause(2.0); closeSearch(); pause(1.6)
        }
        capture("search-tap-items", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar", "PROBE_TBITEMS": "1"]) {
            let s = screen
            tap(p(s.width / 2, s.height - 52), hold: 0.08); pause(2.0); closeSearch(); pause(1.6)
        }
        capture("search-hold", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar"]) {
            let s = screen
            path(p(s.width / 2, s.height - 52), pressFor: 0.5, []); pause(2.0); closeSearch(); pause(1.6)
        }
        capture("search-type-clear", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar"]) {
            let s = screen
            tap(p(s.width / 2, s.height - 52), hold: 0.08); pause(2.0)
            app.typeText("It"); pause(1.0)
            let clear = app.buttons["Clear text"].firstMatch
            NSLog("PROBE clear exists \(clear.exists) \(clear.exists ? clear.frame : .zero)")
            if clear.exists { tap(p(clear.frame.midX, clear.frame.midY)) }
            pause(1.2); closeSearch(); pause(1.6)
        }
        capture("search-tab", scene: "x3search", extra: ["PROBE_SEARCH": "tab"]) {
            let s = screen
            let b = app.buttons["Search"].firstMatch
            let f = b.exists ? b.frame : CGRect(x: s.width - 21 - 62, y: s.height - 21 - 62, width: 62, height: 62)
            NSLog("PROBE search tab frame \(f)")
            tap(p(f.midX, f.midY)); pause(2.0)
            let field = app.searchFields.firstMatch
            if field.exists { NSLog("PROBE field \(field.frame)"); tap(p(field.frame.midX, field.frame.midY)) }
            pause(2.0); closeSearch(); pause(2.0)
        }
        capture("search-tabauto", scene: "x3search", extra: ["PROBE_SEARCH": "tabauto"]) {
            let s = screen
            tap(p(s.width - 21 - 31, s.height - 21 - 31)); pause(2.5)
            closeSearch(); pause(2.5)
        }
        var cy: CGFloat { (62 + screen.height - 34) / 2 }
        var cx: CGFloat { screen.width / 2 }
        capture("alert-press", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3"]) {
            pause(0.8); path(p(cx, cy - 20), pressFor: 0.6, []); pause(1.2)
        }
        capture("alert-slide", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3"]) {
            pause(0.8); path(p(cx, cy - 20), pressFor: 0.3, [(p(cx, cy + 36), 0.3, 0.3), (p(cx, cy + 208), 0.3, 0.2)]); pause(1.2)
        }
        capture("alert-lean", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3"]) {
            pause(0.8); path(p(cx, cy - 20), pressFor: 0.3, [(p(cx + 120, cy - 20), 0.5, 0.3), (p(cx - 120, cy + 92), 0.6, 0.3), (p(cx, cy + 92), 0.3, 0.2)]); pause(1.2)
        }
        capture("alert-tap", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3"]) {
            pause(0.8); tap(p(cx, cy + 92)); pause(1.2)
        }
        capture("alert-tap-out", scene: "x3alert", extra: ["PROBE_SCRIPT": "show@0.3"]) {
            pause(0.8); tap(p(cx, 140)); pause(1.2)
        }
        capture("ash-tap-out", scene: "x3alert", extra: ["PROBE_ALERT": "sheet", "PROBE_SCRIPT": "show@0.3"]) {
            pause(1.6); tap(p(cx, 120)); pause(1.2)
        }
        capture("ash-press", scene: "x3alert", extra: ["PROBE_ALERT": "sheet", "PROBE_SCRIPT": "show@0.3"]) {
            pause(1.6)
            let ok = app.buttons["OK"].firstMatch
            let f = ok.exists ? ok.frame : CGRect(x: cx - 100, y: 400, width: 200, height: 48)
            NSLog("PROBE ash ok \(f)")
            path(p(f.midX, f.midY), pressFor: 0.6, [(p(f.midX, f.midY + 60), 0.3, 0.3)]); pause(1.2)
        }
    }
}
