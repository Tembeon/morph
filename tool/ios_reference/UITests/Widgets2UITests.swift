import XCTest

/// Device captures for the second widget pass (Widgets2.swift scenes): sheets, context menu
/// preview, page control, search. Same plumbing as ProbeUITests (timed pointer paths through
/// the XCUIDevice event synthesizer, PROBE_ONLY filter, one relaunch per capture).
final class Widgets2UITests: XCTestCase {
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

    // MARK: sheets (iPhone 16 Pro, 402 x 874: medium sheet top 415, grabber at 423, large top 62)

    func testW2Sheet() {
        let present = p(201, 300)
        let grab = p(201, 440)
        func open(_ extra: [String: String] = [:]) { tap(present); pause(1.3) }
        capture("sheet-present-tap", scene: "w2sheet") { open(); tap(p(201, 150)); pause(1.2) }
        capture("sheet-drag-up-slow", scene: "w2sheet") { open(); path(grab, pressFor: 0.15, [(p(201, 150), 1.2, 0.4)]); pause(1.2) }
        capture("sheet-drag-up-mid", scene: "w2sheet") { open(); path(grab, pressFor: 0.15, [(p(201, 300), 0.8, 0.5)]); pause(1.2) }
        capture("sheet-drag-up-past", scene: "w2sheet") { open(); path(grab, pressFor: 0.15, [(p(201, 30), 1.4, 0.4)]); pause(1.2) }
        capture("sheet-flick-up", scene: "w2sheet") { open(); path(grab, pressFor: 0.1, [(p(201, 360), 0.13, 0)]); pause(1.2) }
        capture("sheet-flick-up-slow", scene: "w2sheet") { open(); path(grab, pressFor: 0.1, [(p(201, 380), 0.3, 0)]); pause(1.2) }
        capture("sheet-drag-down-small", scene: "w2sheet") { open(); path(grab, pressFor: 0.15, [(p(201, 540), 0.6, 0.4)]); pause(1.2) }
        capture("sheet-drag-down-far", scene: "w2sheet") { open(); path(grab, pressFor: 0.15, [(p(201, 760), 1.0, 0.4)]); pause(1.2) }
        capture("sheet-flick-down", scene: "w2sheet") { open(); path(grab, pressFor: 0.1, [(p(201, 520), 0.13, 0)]); pause(1.2) }
        capture("sheet-flick-down-slow", scene: "w2sheet") { open(); path(grab, pressFor: 0.1, [(p(201, 500), 0.3, 0)]); pause(1.2) }
        capture("sheet-drag-reverse", scene: "w2sheet") { open(); path(grab, pressFor: 0.15, [(p(201, 200), 0.8, 0.2), (p(201, 600), 1.0, 0.2), (p(201, 440), 0.5, 0.3)]); pause(1.2) }
        let largeGrab = p(201, 85)
        capture("sheet-large-drag-down", scene: "w2sheet", extra: ["PROBE_START": "l"]) { open(); path(largeGrab, pressFor: 0.15, [(p(201, 420), 1.0, 0.4)]); pause(1.2) }
        capture("sheet-large-drag-down-mid", scene: "w2sheet", extra: ["PROBE_START": "l"]) { open(); path(largeGrab, pressFor: 0.15, [(p(201, 230), 0.8, 0.4)]); pause(1.2) }
        capture("sheet-large-drag-up", scene: "w2sheet", extra: ["PROBE_START": "l"]) { open(); path(largeGrab, pressFor: 0.15, [(p(201, 5), 0.8, 0.5)]); pause(1.2) }
        capture("sheet-large-flick-down", scene: "w2sheet", extra: ["PROBE_START": "l"]) { open(); path(largeGrab, pressFor: 0.1, [(p(201, 170), 0.13, 0)]); pause(1.2) }
        capture("sheet-large-flick-down-hard", scene: "w2sheet", extra: ["PROBE_START": "l"]) { open(); path(largeGrab, pressFor: 0.1, [(p(201, 300), 0.12, 0)]); pause(1.2) }
        capture("sheet-scroll-medium-up", scene: "w2sheet") { open(); path(p(201, 700), pressFor: 0.1, [(p(201, 250), 1.2, 0.4)]); pause(1.2) }
        capture("sheet-scroll-large-down", scene: "w2sheet", extra: ["PROBE_START": "l"]) { open(); path(p(201, 300), pressFor: 0.1, [(p(201, 650), 1.0, 0.4)]); pause(1.2) }
        capture("sheet-scroll-large-updown", scene: "w2sheet", extra: ["PROBE_START": "l"]) { open(); path(p(201, 500), pressFor: 0.1, [(p(201, 250), 0.6, 0.2), (p(201, 750), 1.2, 0.4)]); pause(1.2) }
        capture("sheet-l-drag-down", scene: "w2sheet", extra: ["PROBE_DETENTS": "l"]) { open(); path(largeGrab, pressFor: 0.15, [(p(201, 420), 1.0, 0.4)]); pause(1.2) }
        capture("sheet-l-flick-down", scene: "w2sheet", extra: ["PROBE_DETENTS": "l"]) { open(); path(largeGrab, pressFor: 0.1, [(p(201, 250), 0.13, 0)]); pause(1.2) }
        capture("sheet-zoom", scene: "w2sheet", extra: ["PROBE_ZOOM": "1"]) { open(); tap(p(201, 150)); pause(1.2) }
        capture("sheet-zoom-drag", scene: "w2sheet", extra: ["PROBE_ZOOM": "1"]) { open(); path(grab, pressFor: 0.15, [(p(201, 760), 1.0, 0.3)]); pause(1.2) }
        capture("sheet-hold", scene: "w2sheet") { open(); path(grab, pressFor: 0.8, []); pause(1.0) }
    }

    func testW2SheetFlicks() {
        let present = p(201, 300)
        let grab = p(201, 440)
        func open() { tap(present); pause(1.3) }
        for v in [600, 700, 800, 900, 1000, 1100, 1200, 1300, 1700] {
            let d = CGFloat(v) * 0.12
            capture("sheet-fu-\(v)", scene: "w2sheet") { open(); path(grab, pressFor: 0.1, [(p(201, 440 - 12), 0.03, 0), (p(201, 440 - 12 - d), 0.12, 0)]); pause(1.2) }
            capture("sheet-fd-\(v)", scene: "w2sheet") { open(); path(grab, pressFor: 0.1, [(p(201, 440 + 12), 0.03, 0), (p(201, 440 + 12 + d), 0.12, 0)]); pause(1.2) }
            capture("sheet-lfd-\(v)", scene: "w2sheet", extra: ["PROBE_START": "l"]) { open(); path(p(201, 85), pressFor: 0.1, [(p(201, 97), 0.03, 0), (p(201, 97 + d), 0.12, 0)]); pause(1.2) }
        }
        capture("sheet-grab-tap", scene: "w2sheet") { open(); tap(grab); pause(1.2); tap(p(201, 85)); pause(1.2) }
        capture("sheet-body-tap", scene: "w2sheet") { open(); tap(p(201, 700)); pause(1.2) }
        capture("sheet-fd-lift-mid", scene: "w2sheet") { open(); path(p(201, 700), pressFor: 0.1, [(p(201, 712), 0.03, 0), (p(201, 712 + 130), 0.12, 0)]); pause(1.2) }
    }

    // MARK: context menu (card 120 x 80 at 201, 300)

    func testW2Ctx() {
        let card = p(201, 300)
        capture("ctx-hold-release", scene: "w2ctx") { path(card, pressFor: 1.0, []); pause(1.5); tap(p(201, 820)); pause(1.2) }
        capture("ctx-hold-short", scene: "w2ctx") { path(card, pressFor: 0.3, []); pause(1.2) }
        capture("ctx-hold-select", scene: "w2ctx") { path(card, pressFor: 1.0, [(p(201, 430), 0.5, 0.3)]); pause(1.5) }
        capture("ctx-hold-bottom", scene: "w2ctx", extra: ["PROBE_CY": "700"]) { path(p(201, 700), pressFor: 1.0, []); pause(1.5); tap(p(201, 120)); pause(1.2) }
        capture("ctx-hold-big", scene: "w2ctx", extra: ["PROBE_CW": "300", "PROBE_CH": "200"]) { path(card, pressFor: 1.0, []); pause(1.5); tap(p(201, 820)); pause(1.2) }
    }

    /// The pre-open growth of the held preview: hold lengths around the threshold on previews of
    /// four sizes (small, the 120 x 80 default, portrait, large), and a long hold before the close.
    func testW2CtxGrowth() {
        let card = p(201, 300)
        let sizes: [(String, String, String)] = [("s", "60", "40"), ("m", "120", "80"), ("t", "80", "160"), ("l", "300", "200")]
        for (name, w, h) in sizes {
            let extra = ["PROBE_CW": w, "PROBE_CH": h]
            for hold in [0.3, 0.6, 0.8, 1.2] {
                let ms = Int((hold * 1000).rounded())
                capture("ctxg-\(name)-\(ms)", scene: "w2ctx", extra: extra) {
                    path(card, pressFor: hold, [])
                    pause(1.4)
                    tap(p(201, 820))
                    pause(1.2)
                }
            }
        }
    }

    /// Where a release stops cancelling and starts opening the menu (0.3 s cancels, 0.6 s opens).
    func testW2CtxCommit() {
        let card = p(201, 300)
        for (name, w, h) in [("m", "120", "80"), ("l", "300", "200")] {
            for hold in [0.35, 0.4, 0.43, 0.46, 0.5, 0.55] {
                let ms = Int((hold * 1000).rounded())
                capture("ctxc-\(name)-\(ms)", scene: "w2ctx", extra: ["PROBE_CW": w, "PROBE_CH": h]) {
                    path(card, pressFor: hold, [])
                    pause(1.4)
                    tap(p(201, 820))
                    pause(1.2)
                }
            }
        }
    }

    /// The whole context-menu morph on one recording: preview, menu, and the dimming
    /// UIVisualEffectView with its backdrop filter inputs, for the spring per part.
    func testW2CtxDim() {
        let card = p(201, 300)
        let track = "_UIContextMenu|Platter|Dimming|_UIPreview|_UIMorph|MagicMorph|Portal|_UIReparenting|TransformView|ContextMenuContainer|_UIContentPlatter|UIVisualEffect|_UIVisualEffect|Backdrop"
        for (name, w, h) in [("m", "120", "80"), ("l", "300", "200")] {
            for run in 1...2 {
                capture("ctxd-\(name)-\(run)", scene: "w2ctx", extra: ["PROBE_CW": w, "PROBE_CH": h, "PROBE_W2TRACK": track, "PROBE_W2FILTERS": "1"]) {
                    path(card, pressFor: 1.0, [])
                    pause(1.4)
                    tap(p(201, 820))
                    pause(1.2)
                }
            }
        }
    }

    /// The dimming in each appearance: PROBE_DARK forces the window's style.
    func testW2CtxDimLook() {
        let card = p(201, 300)
        let track = "_UIContextMenu|Dimming|ContextMenuContainer|UIVisualEffect|_UIVisualEffect|Backdrop"
        for (look, dark) in [("dark", "1"), ("light", "0")] {
            for run in 1...2 {
                capture("ctxd-\(look)-l-\(run)", scene: "w2ctx", extra: ["PROBE_CW": "300", "PROBE_CH": "200", "PROBE_W2TRACK": track, "PROBE_W2FILTERS": "1", "PROBE_DARK": dark]) {
                    path(card, pressFor: 1.0, [])
                    pause(1.4)
                    tap(p(201, 820))
                    pause(1.2)
                }
            }
        }
    }

    // MARK: page control (5 pages, 126 x 25 at 201, 400)

    func testW2Page() {
        capture("pc-tap-right", scene: "w2page") { tap(p(250, 400)); pause(1.0); tap(p(250, 400)); pause(1.0); tap(p(150, 400)); pause(1.0) }
        capture("pc-scrub", scene: "w2page") { path(p(160, 400), pressFor: 0.8, [(p(250, 400), 1.0, 0.3), (p(150, 400), 1.0, 0.3)]); pause(1.0) }
        capture("pc-scrub-far", scene: "w2page") { path(p(201, 400), pressFor: 0.8, [(p(380, 400), 1.0, 0.3)]); pause(1.0) }
        capture("pc-swipe", scene: "w2page") { path(p(170, 400), pressFor: 0.05, [(p(240, 400), 0.25, 0)]); pause(1.0) }
        capture("pc-hold", scene: "w2page") { path(p(201, 400), pressFor: 1.2, []); pause(1.0) }
    }

    // MARK: search

    func testW2Search() {
        capture("search-tab-tap", scene: "w2search", extra: ["PROBE_SEARCH": "tab"]) {
            let field = app.buttons["Search"].firstMatch
            let f = field.exists ? field.frame : CGRect(x: 330, y: 800, width: 50, height: 50)
            NSLog("PROBE search frame \(f)")
            tap(p(f.midX, f.midY)); pause(1.5)
            tap(p(201, 300)); pause(1.5)
        }
        capture("search-nav-tap", scene: "w2search", extra: ["PROBE_SEARCH": "nav"]) {
            let field = app.searchFields.firstMatch
            let f = field.exists ? field.frame : CGRect(x: 20, y: 150, width: 360, height: 36)
            NSLog("PROBE search frame \(f)")
            tap(p(f.midX, f.midY)); pause(1.5)
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { tap(p(cancel.frame.midX, cancel.frame.midY)) } else { tap(p(380, f.midY)) }
            pause(1.5)
        }
        capture("search-toolbar-tap", scene: "w2search", extra: ["PROBE_SEARCH": "toolbar"]) {
            let field = app.searchFields.firstMatch
            let f = field.exists ? field.frame : CGRect(x: 20, y: 800, width: 360, height: 48)
            NSLog("PROBE search frame \(f)")
            tap(p(f.midX, f.midY)); pause(1.5)
            tap(p(201, 300)); pause(1.5)
        }
    }

    // MARK: still references (attachments of the result bundle)

    /// PROBE_REF_DARK=1/0 forces the appearance of every reference (unset = the phone's own).
    func testW2Refs() {
        let rx = env["PROBE_REF_DARK"].map { ["PROBE_DARK": $0] } ?? [:]
        func shot(_ name: String) {
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            a.name = name
            a.lifetime = .keepAlways
            add(a)
        }
        capture("ref-sheet", scene: "w2sheet", extra: rx) { tap(p(201, 300)); pause(1.3); shot("sheet-medium"); path(p(201, 440), pressFor: 0.1, [(p(201, 120), 0.6, 0.3)]); pause(1.2); shot("sheet-large") }
        capture("ref-page", scene: "w2page", extra: rx) { shot("page-control") }
        capture("ref-page-prominent", scene: "w2page", extra: rx.merging(["PROBE_PCSTYLE": "prominent"]) { $1 }) { shot("page-control-prominent") }
        capture("ref-progress", scene: "w2progress", extra: rx) { shot("progress") }
        capture("ref-ctx", scene: "w2ctx", extra: rx) { path(p(201, 300), pressFor: 1.0, []); pause(1.0); shot("ctx-open"); tap(p(201, 820)) }
        capture("ref-search", scene: "w2search", extra: rx.merging(["PROBE_SEARCH": "tab"]) { $1 }) { shot("search-tab-rest") }
        capture("ref-alert", scene: "w2alert", extra: rx.merging(["PROBE_SCRIPT": "show@0.5"]) { $1 }) { pause(1.2); shot("alert") }
        capture("ref-actionsheet", scene: "w2alert", extra: rx.merging(["PROBE_ALERT": "sheet", "PROBE_SCRIPT": "show@0.5"]) { $1 }) { pause(1.2); shot("actionsheet") }
    }
}
