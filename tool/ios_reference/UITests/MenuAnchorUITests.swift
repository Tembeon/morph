import XCTest

/// Films the glass button menu's unfold for the screen recorder (2026-10-03): a bottom-centre
/// button with ten rows opening up, the top corners, and the centre menu. Each scene opens and
/// dismisses twice with slow gaps; the layers are logged to rec-anchor-<name>.jsonl alongside.
final class MenuAnchorUITests: XCTestCase {
    private var app = XCUIApplication()

    private func scene(_ rec: String, _ extra: [String: String], cycles: Int = 2) {
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "menu"
        app.launchEnvironment["PROBE_REC"] = "anchor-\(rec)"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        Thread.sleep(forTimeInterval: 2.0)
        let b = app.buttons["inlineMenu"]
        XCTAssertTrue(b.waitForExistence(timeout: 5))
        let f = b.frame
        NSLog("PROBE anchor \(rec) button \(f)")
        let screen = app.windows.firstMatch.frame
        let outside = CGPoint(
            x: f.midX < screen.midX ? screen.maxX - 30 : screen.minX + 30,
            y: f.midY < screen.midY ? screen.maxY - 60 : screen.minY + 120)
        for _ in 0..<cycles {
            tap(CGPoint(x: f.midX, y: f.midY), hold: 0.06)
            Thread.sleep(forTimeInterval: 1.5)
            tap(outside, hold: 0.06)
            Thread.sleep(forTimeInterval: 1.5)
        }
        app.terminate()
    }

    private func tap(_ p: CGPoint, hold: Double) {
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
        start.press(forDuration: hold)
    }

    /// The same scenes with the layer log off (it costs the screen recording frames), three
    /// cycles each.
    func testAnchorFilm() {
        let scenes: [(String, [String: String])] = [
            ("bottom10", ["PROBE_POS": "bottom", "PROBE_ITEMS": "10"]),
            ("bottom3", ["PROBE_POS": "bottom"]),
            ("tl3", ["PROBE_POS": "tl"]),
            ("center3", [:]),
        ]
        for (name, extra) in scenes {
            scene("film-\(name)", extra.merging(["PROBE_TRACK": "^NoLayerMatchesThis$"]) { a, _ in a }, cycles: 3)
        }
    }

    /// A tall menu opening down from the top-left corner, filmed with the layer log off.
    func testAnchorTall() {
        scene("film-tl10", ["PROBE_POS": "tl", "PROBE_ITEMS": "10", "PROBE_TRACK": "^NoLayerMatchesThis$"], cycles: 3)
    }

    func testAnchor() {
        let only = Set((ProcessInfo.processInfo.environment["PROBE_ONLY"] ?? "").split(separator: ",").map(String.init))
        let scenes: [(String, [String: String])] = [
            ("bottom10", ["PROBE_POS": "bottom", "PROBE_ITEMS": "10"]),
            ("tl3", ["PROBE_POS": "tl"]),
            ("tr3", ["PROBE_POS": "tr"]),
            ("center3", [:]),
            ("bottom3", ["PROBE_POS": "bottom"]),
        ]
        for (name, extra) in scenes where only.isEmpty || only.contains(name) {
            scene(name, extra)
        }
    }
}
