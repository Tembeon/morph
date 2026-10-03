import XCTest

/// Device captures of the MENU API (Menus.swift, scenes x5menu with PROBE_MENU). Same
/// plumbing as StatesUITests; PROBE_DARKS ("1,0") picks the appearances of the look pass.
final class MenuAPIUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private let env = ProcessInfo.processInfo.environment
    private var only: Set<String> {
        Set((env["PROBE_ONLY"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    private var app = XCUIApplication()
    private var darks: [String] { (env["PROBE_DARKS"] ?? "1,0").split(separator: ",").map(String.init) }
    static let track = "ContextMenu|MagicMorph|MorphAnimation|TransformView|Platter|Reparenting|Portal|Separator|Submenu|Palette|ListView|_UIContextMenuCell|UICollectionView$|_UIScrollView|Header|Section"

    private func capture(_ rec: String, menu: String, extra: [String: String] = [:], settle: Double = 1.5, _ body: () -> Void) {
        if !only.isEmpty && !only.contains(rec) { return }
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "x5menu"
        app.launchEnvironment["PROBE_MENU"] = menu
        app.launchEnvironment["PROBE_REC"] = rec
        app.launchEnvironment["PROBE_TRACK"] = MenuAPIUITests.track
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

    private func synth(_ strokes: [Stroke], name: String = "x5") {
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

    private func tap(_ p: CGPoint, hold: Double = 0.08) { synth([Stroke(points: [(0, p)], liftAt: hold)], name: "tap") }

    private func line(_ a: CGPoint, _ b: CGPoint, from t0: Double, over d: Double) -> [(Double, CGPoint)] {
        let steps = max(1, Int((d * 30).rounded()))
        return (1...steps).map { i in
            let f = Double(i) / Double(steps)
            return (t0 + d * f, CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        }
    }

    /// Press at `start`, hold `pressFor`, then legs of (target, duration, holdAfter); lift.
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

    private var buttonCenter: CGPoint {
        let e = app.descendants(matching: .any)["x5btn"].firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: 5))
        let f = e.frame
        NSLog("PROBE x5btn frame \(f)")
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// Logs every hittable element of the open menu (label + frame) for the analysis.
    private func logElements(_ tag: String) {
        for e in app.descendants(matching: .any).allElementsBoundByIndex where !e.label.isEmpty && e.frame.width > 0 {
            NSLog("PROBE el \(tag) \(e.elementType.rawValue) '\(e.label)' \(e.frame) sel=\(e.isSelected)")
        }
    }

    private func frameOf(_ label: String) -> CGRect? {
        let e = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        return e.exists ? e.frame : nil
    }

    private func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    private let outside = CGPoint(x: 201, y: 820)

    // MARK: look pass (light + dark): open, dump, shot, element list

    func testMenuLook() {
        for d in darks {
            let tag = d == "1" ? "dark" : "light"
            for m in ["sub", "rich1", "rich2", "tall", "resize", "deferred", "swiftui"] {
                capture("ml-\(m)-\(tag)", menu: m, extra: ["PROBE_DARK": d, "PROBE_SCRIPT": "dump:open@5.5"]) {
                    tap(buttonCenter)
                    pause(1.6)
                    shot("ml-\(m)-\(tag)")
                    logElements("\(m)-\(tag)")
                    pause(1.5)
                    if m == "sub", let more = frameOf("More") {
                        tap(center(more)); pause(1.6); shot("ml-sub-open-\(tag)"); logElements("subopen-\(tag)")
                        if let deeper = frameOf("Deeper") { tap(center(deeper)); pause(1.6); shot("ml-sub-deeper-\(tag)"); logElements("subdeeper-\(tag)") }
                    }
                    if m == "swiftui", let more = frameOf("More") {
                        tap(center(more)); pause(1.6); shot("ml-swiftui-sub-\(tag)"); logElements("swsub-\(tag)")
                    }
                    tap(outside)
                }
            }
        }
    }

    // MARK: motion pass (dark, touch dumps after every lift)

    func testMenuMotion() {
        let dumps = ["PROBE_DUMPS": "1", "PROBE_DARK": "1"]
        capture("mm-sub-tap", menu: "sub", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            tap(CGPoint(x: 201, y: 238)); pause(1.8)
            shot("mm-sub-open-dark")
            pause(0.5)
            tap(outside); pause(1.2)
        }
        capture("mm-sub-slide", menu: "sub", extra: dumps) {
            let b = buttonCenter
            path(b, pressFor: 0.6, [(CGPoint(x: 201, y: 238), 0.5, 1.4)])
            pause(1.6)
            shot("mm-sub-slide-dark")
            tap(outside); pause(1.2)
        }
        capture("mm-rich1-select", menu: "rich1", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            tap(CGPoint(x: 201, y: 224)); pause(1.5)
            shot("mm-rich1-date-dark")
            tap(CGPoint(x: 201, y: 266)); pause(1.5)
            tap(CGPoint(x: 201, y: 329)); pause(1.5)
            shot("mm-rich1-toggled-dark")
            tap(outside); pause(1.2)
        }
        capture("mm-resize", menu: "resize", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            tap(CGPoint(x: 201, y: 154.7)); pause(1.5)
            tap(CGPoint(x: 201, y: 154.7)); pause(1.5)
            shot("mm-resize-grown-dark")
            tap(CGPoint(x: 201, y: 196.7)); pause(1.5)
            tap(outside); pause(1.2)
        }
        capture("mm-tall-scroll", menu: "tall", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            path(CGPoint(x: 201, y: 560), pressFor: 0.05, [(CGPoint(x: 201, y: 260), 0.5, 0.4)])
            pause(1.5)
            shot("mm-tall-scrolled-dark")
            path(CGPoint(x: 201, y: 300), pressFor: 0.05, [(CGPoint(x: 201, y: 600), 0.15, 0)])
            pause(1.8)
            tap(CGPoint(x: 380, y: 840)); pause(1.2)
        }
        capture("mm-swiftui", menu: "swiftui", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            tap(CGPoint(x: 198, y: 703.7)); pause(1.5)
            tap(CGPoint(x: 198, y: 703.7)); pause(1.5)
            shot("mm-swiftui-count-dark")
            tap(CGPoint(x: 256, y: 565)); pause(1.5)
            shot("mm-swiftui-volume-dark")
            tap(CGPoint(x: 198, y: 805.7)); pause(1.8)
            shot("mm-swiftui-more-dark")
            tap(CGPoint(x: 380, y: 860)); pause(1.2)
        }
        capture("mm-deferred", menu: "deferred", extra: dumps.merging(["PROBE_DEFER": "2.0"]) { $1 }) {
            tap(buttonCenter); pause(0.8)
            shot("mm-deferred-loading-dark")
            pause(2.5)
            tap(outside); pause(1.2)
        }
        capture("mm-palette", menu: "rich2", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            tap(CGPoint(x: 201, y: 176.7)); pause(1.5)
            shot("mm-palette-green-dark")
            tap(CGPoint(x: 201, y: 498.7)); pause(1.5)
        }
    }

    // MARK: motion pass 2: submenu back / deeper / select / slide, light look, SwiftUI

    func testMenuMotion2() {
        let dumps = ["PROBE_DUMPS": "1", "PROBE_DARK": "1"]
        let more = CGPoint(x: 201, y: 238)
        capture("mm-sub-back", menu: "sub", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            tap(more); pause(1.5)
            tap(CGPoint(x: 201, y: 232.5)); pause(1.5)
            shot("mm-sub-back-dark")
            tap(outside); pause(1.2)
        }
        capture("mm-sub-deeper", menu: "sub", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            tap(more); pause(1.5)
            tap(CGPoint(x: 201, y: 378.5)); pause(1.8)
            shot("mm-sub-deeper-dark")
            tap(outside); pause(1.2)
        }
        capture("mm-sub-select", menu: "sub", extra: dumps) {
            tap(buttonCenter); pause(1.5)
            tap(more); pause(1.5)
            tap(CGPoint(x: 201, y: 294.5)); pause(1.5)
        }
        capture("mm-sub-slide2", menu: "sub", extra: dumps) {
            path(buttonCenter, pressFor: 0.6, [(more, 0.3, 1.5), (CGPoint(x: 201, y: 336.5), 0.4, 0.3)])
            pause(1.5)
        }
        capture("mm-sub-open-light", menu: "sub", extra: ["PROBE_DARK": "0"]) {
            tap(buttonCenter); pause(1.5)
            tap(more); pause(1.6)
            shot("mm-sub-open-light")
            tap(CGPoint(x: 201, y: 378.5)); pause(1.6)
            shot("mm-sub-deeper-light")
            tap(outside); pause(1.2)
        }
        capture("mm-swiftui2", menu: "swiftui", extra: dumps) {
            let b = app.descendants(matching: .any)["x5btn"].firstMatch
            XCTAssertTrue(b.waitForExistence(timeout: 5))
            b.tap(); pause(1.6)
            shot("mm-swiftui2-open-dark")
            logElements("sw2")
            let count = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Count'")).firstMatch
            if count.exists {
                let c = center(count.frame)
                NSLog("PROBE count frame \(count.frame)")
                tap(c); pause(1.5); tap(c); pause(1.5)
                shot("mm-swiftui2-count-dark")
                logElements("sw2count")
            }
            if let t = frameOf("Show hidden") { tap(center(t)); pause(1.5); shot("mm-swiftui2-toggle-dark") }
            tap(CGPoint(x: 380, y: 860)); pause(1.2)
        }
    }
}
