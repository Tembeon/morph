import XCTest

/// Device passes of the adaptive bar brightness scene "abright"
/// (spec/adaptive-brightness-capture.md). The system appearance is the owner's: PROBE_DARK is
/// never set. Each capture launches the scene, taps the content to start its script (the app
/// times its steps from that touch, the test from the tap's return), and, when the pass takes
/// screenshots, attaches one 0.7 s before the end of every step ("<rec>-<nnn>-<action>").
/// TEST_RUNNER_PROBE_AB_TAG names the appearance in the record names (light / dark),
/// TEST_RUNNER_PROBE_ONLY selects captures by name, TEST_RUNNER_PROBE_AB_FINE = "<lower>,<upper>"
/// centres the fine staircases (default the scroll pocket's 0.40, 0.70).
final class AdaptiveBrightnessUITests: XCTestCase {
    struct Step {
        var at: Double
        var action: String
        var dwell: Double
    }

    override func setUp() { continueAfterFailure = true }

    private let env = ProcessInfo.processInfo.environment
    private var tag: String { env["PROBE_AB_TAG"].flatMap { $0.isEmpty ? nil : $0 } ?? "sys" }
    private var only: Set<String> {
        Set((env["PROBE_ONLY"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    private var fine: (Double, Double) {
        let v = (env["PROBE_AB_FINE"] ?? "").split(separator: ",").compactMap { Double($0) }
        return v.count == 2 ? (v[0], v[1]) : (0.40, 0.70)
    }

    private func g(_ v: Double) -> String { String(format: "%.6f", v) }

    /// Steps run one after another from 0, each for its dwell.
    private func seq(_ items: [(String, Double)]) -> [Step] {
        var t = 0.0
        return items.map { item in
            defer { t += item.1 }
            return Step(at: t, action: item.0, dwell: item.1)
        }
    }

    private func wait(until uptime: Double) {
        let left = uptime - ProcessInfo.processInfo.systemUptime
        if left > 0 { Thread.sleep(forTimeInterval: left) }
    }

    private func capture(_ name: String, extra: [String: String] = [:], args: [String] = [], steps: [Step], shots: Bool, after: ((XCUIApplication) -> Void)? = nil) {
        let rec = "ab-\(tag)-\(name)"
        if !only.isEmpty && !only.contains(name) && !only.contains(rec) { return }
        let app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "abright"
        app.launchEnvironment["PROBE_REC"] = rec
        app.launchEnvironment["PROBE_TRACK"] = "^NOTHING$"
        app.launchEnvironment["PROBE_SCRIPT"] = steps.map { "\($0.action)@\(String(format: "%.3f", $0.at))" }.joined(separator: ";")
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launchArguments = args
        app.launch()
        Thread.sleep(forTimeInterval: 2.5)
        NSLog("PROBE capture begin \(rec) steps \(steps.count) duration \(String(format: "%.1f", (steps.last.map { $0.at + $0.dwell } ?? 0)))")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.42)).tap()
        let t0 = ProcessInfo.processInfo.systemUptime
        if shots {
            for (i, s) in steps.enumerated() {
                wait(until: t0 + s.at + s.dwell - 0.7)
                let a = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
                a.name = String(format: "%@-%03d-%@", rec, i, s.action.replacingOccurrences(of: ":", with: "="))
                a.lifetime = .keepAlways
                add(a)
            }
        }
        wait(until: t0 + (steps.last.map { $0.at + $0.dwell } ?? 0))
        after?(app)
        Thread.sleep(forTimeInterval: 1.0)
        NSLog("PROBE capture end \(rec)")
        app.terminate()
    }

    private func coarse() -> [Step] {
        let up = (1...32).map { ("grey:\(g(Double($0) / 32))", 2.5) }
        let down = (0...31).reversed().map { ("grey:\(g(Double($0) / 32))", 2.5) }
        return seq([("grey:0", 5.0)] + up + down)
    }

    /// 1/128 steps over +- 3/32 around `centre`, approached from the dark side (rising) or the
    /// light side (falling).
    private func fineStairs(_ centre: Double, rising: Bool) -> [Step] {
        let values = (0...24).map { centre - 3.0 / 32 + Double($0) / 128 }.map { min(max($0, 0), 1) }
        let ordered = rising ? values : values.reversed()
        return seq([(rising ? "grey:0" : "grey:1", 5.0)] + ordered.map { ("grey:\(g($0))", 2.5) })
    }

    private func steps() -> [Step] {
        seq([("grey:0", 4.0)] + [1, 0, 1, 0, 1, 0, 0.3, 0.8, 0.3, 0.8, 0.3, 0.8, 0.3].map { ("grey:\(g($0))", 4.0) })
    }

    private func hold() -> [Step] {
        let fromDark = [("grey:0", 8.0)] + (0..<12).map { ("grey:\(g($0 % 2 == 0 ? 0.45 : 0.65))", 2.5) }
        let fromLight = [("grey:1", 8.0)] + (0..<12).map { ("grey:\(g($0 % 2 == 0 ? 0.65 : 0.45))", 2.5) }
        return seq(fromDark + fromLight)
    }

    // P1 and P1b: every bar at once (tab bar, navigation bar, toolbar) over solid greys.
    func testABStairs() {
        capture("stairs", steps: coarse(), shots: true)
        capture("fine-lower", steps: fineStairs(fine.0, rising: false), shots: true)
        capture("fine-upper", steps: fineStairs(fine.1, rising: true), shots: true)
    }

    // P2: a floating toolbar without a tab bar.
    func testABToolbarStairs() {
        capture("toolbar-stairs", extra: ["PROBE_AB_BARS": "toolbar"], steps: coarse(), shots: true)
    }

    // P3 and P4 with the scroll pocket (scroll host) and without it (static host). Filmed.
    func testABSteps() {
        capture("steps", steps: steps(), shots: false)
        capture("steps-static", extra: ["PROBE_AB_HOST": "static"], steps: steps(), shots: false)
        capture("hold", steps: hold(), shots: false)
        capture("hold-static", extra: ["PROBE_AB_HOST": "static"], steps: hold(), shots: false)
    }

    // P5: luma weights from colours, approached from black and from white.
    func testABColours() {
        var items: [(String, Double)] = []
        let colours: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 1, 1], [1, 0, 1], [1, 1, 0]]
        for base in [0.0, 1.0] {
            items.append(("grey:\(g(base))", 5.0))
            for level in [1.0, 0.5] {
                for c in colours {
                    items.append(("rgb:\(c.map { g($0 * level) }.joined(separator: ","))", 2.5))
                    items.append(("grey:\(g(base))", 2.5))
                }
            }
        }
        capture("colours", steps: seq(items), shots: true)
    }

    // P6: the statistic (white share of the width) and each band's sampled extent (an edge
    // moving through the band).
    func testABCoverage() {
        var left: [(String, Double)] = [("left:0", 5.0)]
        for f in [0.25, 0.5, 0.75, 1] { left += [("left:\(g(f))", 2.5), ("left:0", 2.5)] }
        left.append(("left:1", 5.0))
        for f in [0.75, 0.5, 0.25, 0] { left += [("left:\(g(f))", 2.5), ("left:1", 2.5)] }
        capture("split-width", extra: ["PROBE_AB_CONTENT": "split"], steps: seq(left), shots: true)
        let depths = stride(from: 12.0, through: 240.0, by: 12.0).map { $0 }
        let bottom = [("edge:5000", 5.0)] + depths.map { ("edge:\(g(-$0))", 2.5) } + depths.reversed().map { ("edge:\(g(-$0))", 2.5) } + [("edge:5000", 2.5)]
        let top = [("edgeb:0", 5.0)] + depths.map { ("edgeb:\(g($0))", 2.5) } + depths.reversed().map { ("edgeb:\(g($0))", 2.5) } + [("edgeb:0", 2.5)]
        capture("edge-bottom", extra: ["PROBE_AB_CONTENT": "split"], steps: seq(bottom), shots: true)
        capture("edge-top", extra: ["PROBE_AB_CONTENT": "split"], steps: seq(top), shots: true)
        capture("edge-bottom-toolbar", extra: ["PROBE_AB_CONTENT": "split", "PROBE_AB_BARS": "toolbar"], steps: seq(bottom), shots: true)
    }

    // P7: bands of a known luma scrolled under the bars, then a finger fling each way. Filmed.
    func testABScroll() {
        let fling: (XCUIApplication) -> Void = { app in
            NSLog("PROBE fling up")
            app.swipeUp(velocity: .fast)
            Thread.sleep(forTimeInterval: 4)
            NSLog("PROBE fling down")
            app.swipeDown(velocity: .fast)
            Thread.sleep(forTimeInterval: 4)
        }
        let stripes = seq([("top", 3.0), ("scroll:300,6", 7.0), ("scroll:-300,6", 7.0), ("scroll:1200,4", 5.0), ("scroll:-1200,4", 5.0)])
        capture("stripes-300", extra: ["PROBE_AB_CONTENT": "stripes:300"], steps: stripes, shots: false, after: fling)
        capture("stripes-100", extra: ["PROBE_AB_CONTENT": "stripes:100"], steps: stripes, shots: false, after: fling)
        capture("stripes-mid", extra: ["PROBE_AB_CONTENT": "stripes:300:0.3,0.8"], steps: stripes, shots: false)
        capture("ladder", extra: ["PROBE_AB_CONTENT": "ladder:300"], steps: seq([("top", 3.0), ("scroll:150,66", 68.0), ("scroll:-150,66", 68.0)]), shots: false)
    }

    // P9: the search tab circle and the bottom search field. Filmed.
    func testABSearch() {
        let short = seq([0, 1, 0, 1, 0].map { ("grey:\(g($0))", 4.0) })
        capture("search-tab", extra: ["PROBE_AB_BARS": "search"], steps: short, shots: false)
        capture("search-toolbar", extra: ["PROBE_AB_BARS": "searchbar"], steps: short, shots: false)
    }

    // P10 (optional, not stock): the UIKit default that enables the scroll pocket's luma
    // tracking, set for the probe process only (argument domain). Filmed.
    func testABPocketFlag() {
        let args = ["-CalistogaAllowLumaTracking", "YES"]
        capture("flag-steps", args: args, steps: steps(), shots: false)
        capture("flag-hold", args: args, steps: hold(), shots: false)
    }
}
