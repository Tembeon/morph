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
        app = env["PROBE_BUNDLE"].flatMap { $0.isEmpty ? nil : XCUIApplication(bundleIdentifier: $0) } ?? XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = scene
        app.launchEnvironment["PROBE_REC"] = rec
        app.launchEnvironment["PROBE_TRACK"] = "^NOTHING$"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        if let spinner = env["PROBE_SPINNER"], !spinner.isEmpty { app.launchEnvironment["PROBE_SPINNER"] = spinner }
        app.launch()
        Thread.sleep(forTimeInterval: 2.5)
        if let bundle = env["PROBE_BUNDLE"], !bundle.isEmpty {
            // morph's search_date_scenes.dart board: a row per scene, light at x 100, dark at x 300.
            let scenes = ["search", "tab", "tabauto", "date", "time", "both", "alert", "sheet", "time12"]
            var key = scene == "x3search" ? (extra["PROBE_SEARCH"] ?? "toolbar") : (extra["PROBE_DMODE"] ?? "date")
            if scene == "x3alert" { key = extra["PROBE_ALERT"] ?? "alert" }
            if key == "time", extra["PROBE_LOCALE"]?.contains("h12") == true { key = "time12" }
            let row = scenes.firstIndex(of: key == "toolbar" ? "search" : key) ?? 0
            tap(p(extra["PROBE_DARK"] == "1" ? 300 : 100, 150 + 70 * CGFloat(row)))
            Thread.sleep(forTimeInterval: 1.5)
        }
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

    // MARK: screen-recording schedules (device; film with MorphRecorder while this runs)

    /// The search and date picker schedules filmed against morph's
    /// search_date_video_test.dart: same coordinates (window-size based), same order,
    /// light then dark (PROBE_VIDEO_DARK=0/1 picks one; default both).
    func testX3Video() {
        let modes = (env["PROBE_VIDEO_DARK"]).flatMap { $0.isEmpty ? nil : [$0] } ?? ["0", "1"]
        for dark in modes {
            let tag = dark == "1" ? "-dark" : ""
            capture("vid-search\(tag)", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar", "PROBE_TBITEMS": "1", "PROBE_DARK": dark], settle: 1.0) {
                let s = screen
                let field = p(s.width / 2, s.height - 52)
                path(field, pressFor: 0.5, []); pause(2.0)
                app.typeText("It"); pause(1.0)
                let clear = app.buttons["Clear text"].firstMatch
                NSLog("PROBE clear \(clear.exists ? clear.frame : .zero)")
                tap(clear.exists ? p(clear.frame.midX, clear.frame.midY) : p(s.width - 8 - 48 - 12 - 23, s.height - 328 - 10 - 24)); pause(1.2)
                app.typeText("Item 1"); pause(0.8)
                path(p(s.width / 2, 420), pressFor: 0.05, [(p(s.width / 2, 220), 0.4, 0)]); pause(1.2)
                closeSearch(); pause(1.6)
                path(p(s.width / 2, 300), pressFor: 0.05, [(p(s.width / 2, 120), 0.4, 0)]); pause(1.0)
                tap(field, hold: 0.08); pause(0.5); closeSearch(); pause(1.6)
            }
            capture("vid-tab\(tag)", scene: "x3search", extra: ["PROBE_SEARCH": "tabauto", "PROBE_DARK": dark], settle: 1.0) {
                let s = screen
                tap(p(s.width - 21 - 31, s.height - 21 - 31)); pause(2.2)
                app.typeText("It"); pause(1.0)
                closeSearch(); pause(1.8)
                tap(p(28 + 24, s.height - 28 - 24)); pause(2.0)
                tap(p(s.width - 21 - 31, s.height - 21 - 31)); pause(0.25)
                tap(p(28 + 24, s.height - 28 - 24)); pause(2.0)
            }
            capture("vid-tabmanual\(tag)", scene: "x3search", extra: ["PROBE_SEARCH": "tab", "PROBE_DARK": dark], settle: 1.0) {
                let s = screen
                tap(p(s.width - 21 - 31, s.height - 21 - 31)); pause(2.0)
                tap(p(s.width / 2 + 30, s.height - 28 - 24)); pause(2.0)
                closeSearch(); pause(1.8)
                tap(p(28 + 24, s.height - 28 - 24)); pause(2.0)
            }
            capture("vid-date\(tag)", scene: "x3date", extra: ["PROBE_DARK": dark], settle: 1.0) {
                let s = screen
                let label = p(s.width / 2, 300)
                path(label, pressFor: 0.6, []); pause(1.4)
                for b in app.buttons.allElementsBoundByIndex.prefix(12) { NSLog("PROBE button \(b.label) \(b.frame)") }
                let next = app.buttons["Next Month"].firstMatch
                let prev = app.buttons["Previous Month"].firstMatch
                let nextAt = next.exists ? p(next.frame.midX, next.frame.midY) : p(316.3, 340.8)
                let prevAt = prev.exists ? p(prev.frame.midX, prev.frame.midY) : p(273, 340.8)
                tap(nextAt); pause(1.0)
                tap(nextAt); pause(1.0)
                tap(prevAt); pause(1.0)
                tap(prevAt); pause(1.0)
                tap(p(222.3, 506.8)); pause(1.2)
                tap(p(s.width / 2, s.height - 120)); pause(1.4)
                synth([Stroke(points: [(0, label)], liftAt: 0.06), Stroke(points: [(0, p(s.width / 2, s.height - 120))], liftAt: 0.16)], name: "openclose")
                pause(1.4)
                synth([Stroke(points: [(0, label)], liftAt: 0.06), Stroke(points: [(0, p(s.width / 2, s.height - 120))], liftAt: 0.06), Stroke(points: [(0, label)], liftAt: 0.12)], name: "reopen")
                pause(1.4)
                tap(p(s.width / 2, s.height - 120)); pause(1.4)
            }
            capture("vid-time\(tag)", scene: "x3date", extra: ["PROBE_DMODE": "time", "PROBE_DARK": dark], settle: 1.0) {
                let s = screen
                tap(p(s.width / 2, 300)); pause(1.4)
                path(p(100, 410), pressFor: 0.05, [(p(100, 346), 0.3, 0)]); pause(1.6)
                path(p(172, 410), pressFor: 0.05, [(p(172, 470), 0.3, 0)]); pause(1.6)
                tap(p(s.width / 2, s.height - 120)); pause(1.4)
            }
            capture("vid-both\(tag)", scene: "x3date", extra: ["PROBE_DMODE": "both", "PROBE_DARK": dark], settle: 1.0) {
                let s = screen
                tap(p(s.width / 2 - 37, 300)); pause(1.4)
                tap(p(s.width / 2 + 59.5, 300)); pause(1.6)
                tap(p(s.width / 2, s.height - 120)); pause(1.4)
            }
        }
    }

    // MARK: timing, keyboard, wheels and alert passes (device; PROBE_BUNDLE runs them on morph's board)

    /// One tap as a stroke starting `at` seconds into its record.
    private func tapStroke(_ q: CGPoint, at: Double, hold: Double = 0.06) -> Stroke {
        Stroke(points: [(at, q)], liftAt: at + hold)
    }

    /// Two taps in ONE synthesized record, the second starting `gap` seconds after the
    /// first lifts. The synthesizer starts every stroke of a record at the previous
    /// stroke's lift whatever its planned offset, so the gap is a FILLER stroke held
    /// `gap` seconds at the inert point `filler` (the logged touch rows tell what was
    /// delivered).
    private func twoTaps(_ a: CGPoint, _ b: CGPoint, gap: Double, filler: CGPoint, name: String) {
        let lift = 0.0667
        synth([tapStroke(a, at: 0, hold: lift),
               Stroke(points: [(lift + 0.01, filler)], liftAt: lift + 0.01 + gap),
               tapStroke(b, at: lift + 0.02 + gap, hold: lift)], name: name)
    }

    func testX3Timing() {
        let gaps = (env["PROBE_GAPS"] ?? "0.12,0.25").split(separator: ",").compactMap { Double($0) }
        for gap in gaps {
            let g = String(format: "%03d", Int((gap * 1000).rounded()))
            capture("tm-tab-in-\(g)", scene: "x3search", extra: ["PROBE_SEARCH": "tabauto"], settle: 1.0) {
                let s = screen
                twoTaps(p(s.width - 52, s.height - 52), p(52, s.height - 52), gap: gap, filler: p(s.width / 2, 110), name: "tabin")
                pause(2.5)
            }
            capture("tm-tab-out-\(g)", scene: "x3search", extra: ["PROBE_SEARCH": "tabauto"], settle: 1.0) {
                let s = screen
                tap(p(s.width - 52, s.height - 52)); pause(2.2)
                closeSearch(); pause(1.8)
                twoTaps(p(52, s.height - 52), p(s.width - 52, s.height - 52), gap: gap, filler: p(s.width / 2, 110), name: "tabout")
                pause(2.5)
            }
            capture("tm-date-oc-\(g)", scene: "x3date", settle: 1.0) {
                let s = screen
                twoTaps(p(s.width / 2, 300), p(s.width / 2, s.height - 120), gap: gap, filler: p(s.width / 2, 150), name: "openclose")
                pause(2.0)
            }
            capture("tm-date-co-\(g)", scene: "x3date", settle: 1.0) {
                let s = screen
                tap(p(s.width / 2, 300)); pause(1.4)
                twoTaps(p(s.width / 2, s.height - 120), p(s.width / 2, 300), gap: gap, filler: p(s.width / 2, 150), name: "closeopen")
                pause(2.0)
                tap(p(s.width / 2, s.height - 120)); pause(1.4)
            }
        }
    }

    private func logWheels(_ tag: String) {
        for (i, w) in app.pickerWheels.allElementsBoundByIndex.enumerated() {
            NSLog("PROBE wheel \(tag) \(i) \(w.frame) value=\(w.value as? String ?? "?")")
        }
    }

    /// Still screenshots (lossless attachments) of the search keyboard and the time wheels,
    /// and the 12-hour wheels' behaviour (drags through 12 and on the AM/PM column).
    func testX3Shots() {
        let modes = (env["PROBE_VIDEO_DARK"]).flatMap { $0.isEmpty ? nil : [$0] } ?? ["0", "1"]
        for dark in modes {
            let tag = dark == "1" ? "-dark" : ""
            capture("kb-search\(tag)", scene: "x3search", extra: ["PROBE_SEARCH": "toolbar", "PROBE_TBITEMS": "1", "PROBE_DARK": dark], settle: 0.5) {
                let s = screen
                tap(p(s.width / 2, s.height - 52), hold: 0.08); pause(2.0); shot("kb-empty\(tag)")
                app.typeText("It"); pause(1.2); shot("kb-typed\(tag)")
                closeSearch(); pause(1.2)
            }
            capture("wh-24\(tag)", scene: "x3date", extra: ["PROBE_DMODE": "time", "PROBE_DARK": dark], settle: 0.5) {
                let s = screen
                tap(p(s.width / 2, 300)); pause(1.6); shot("wheels-24\(tag)"); logWheels("24\(tag)")
                tap(p(s.width / 2, s.height - 120)); pause(1.2)
            }
            capture("wh-12\(tag)", scene: "x3date", extra: ["PROBE_DMODE": "time", "PROBE_DARK": dark, "PROBE_LOCALE": "en_US@hours=h12", "PROBE_SCRIPT": "tree-wh12\(tag)@4.6"], settle: 0.5) {
                let s = screen
                tap(p(s.width / 2, 300)); pause(1.6); shot("wheels-12\(tag)"); logWheels("12\(tag)")
                if dark == "0" {
                    let wheels = app.pickerWheels.allElementsBoundByIndex
                    if wheels.count >= 3 {
                        let h = wheels[0].frame, ap = wheels[2].frame
                        // hours 7 -> 12 and past: five rows up, slowly, held before the lift
                        path(p(h.midX, h.midY + 40), pressFor: 0.05, [(p(h.midX, h.midY + 40 - 162), 1.2, 0.4)]); pause(1.6)
                        shot("wheels-12-hour"); logWheels("12-hour")
                        path(p(ap.midX, ap.midY + 20), pressFor: 0.05, [(p(ap.midX, ap.midY + 20 - 34), 0.5, 0.3)]); pause(1.6)
                        shot("wheels-12-ampm"); logWheels("12-ampm")
                        path(p(h.midX, h.midY - 40), pressFor: 0.05, [(p(h.midX, h.midY - 40 + 96), 0.8, 0.4)]); pause(1.6)
                        shot("wheels-12-back"); logWheels("12-back")
                    }
                }
                tap(p(s.width / 2, s.height - 120)); pause(1.2)
            }
        }
    }

    /// The alert and the action sheet popover appearing and leaving (film it): the Show
    /// button at the scene's center x, 600 pt down.
    func testX3AlertVideo() {
        let modes = (env["PROBE_VIDEO_DARK"]).flatMap { $0.isEmpty ? nil : [$0] } ?? ["0", "1"]
        for dark in modes {
            let tag = dark == "1" ? "-dark" : ""
            capture("vid-alert\(tag)", scene: "x3alert", extra: ["PROBE_DARK": dark], settle: 0.8) {
                let s = screen
                let cy = (62 + s.height - 34) / 2
                tap(p(s.width / 2, 600)); pause(1.6); shot("alert-open\(tag)")
                tap(p(s.width / 2, cy + 92)); pause(1.4)
            }
            capture("vid-ash\(tag)", scene: "x3alert", extra: ["PROBE_ALERT": "sheet", "PROBE_DARK": dark], settle: 0.8) {
                let s = screen
                tap(p(s.width / 2, 600)); pause(1.6); shot("ash-open\(tag)")
                tap(p(s.width / 2, 120)); pause(1.4)
            }
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
