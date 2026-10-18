import XCTest

final class MenuKeyboardUITests: XCTestCase {
    private enum Flow: String {
        case placement
        case selectionReopen
    }

    func testKeyboardPlacement() throws {
        try exercise(.placement)
    }

    func testKeyboardSelectionReopen() throws {
        try exercise(.selectionReopen)
    }

    private func exercise(_ flow: Flow) throws {
        continueAfterFailure = false
        let rows = ProcessInfo.processInfo.environment["PROBE_KEYBOARD_ROWS"] == "3" ? 3 : 10
        for mode in ["none", "show", "hide"] {
            let app = XCUIApplication()
            app.launchEnvironment["PROBE_SCENE"] = "menu-keyboard"
            app.launchEnvironment["PROBE_KEYBOARD"] = mode
            app.launchEnvironment["PROBE_KEYBOARD_ROWS"] = String(rows)
            app.launch()
            let button = app.buttons["nativeKeyboardMenu"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            if mode == "hide" {
                app.textFields["keyboardEditor"].tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            }
            button.tap()
            XCTAssertTrue(app.buttons["Native first"].waitForExistence(timeout: 5))
            var samples = [sample(app, phase: "before", rows: rows)]
            shot("\(mode)-before")
            if mode == "show" {
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
            } else if mode == "hide" {
                let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
                XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 8), .completed)
            } else {
                Thread.sleep(forTimeInterval: 4)
            }
            Thread.sleep(forTimeInterval: 1)
            samples.append(sample(app, phase: "after", rows: rows))
            shot("\(mode)-after")
            if flow == .selectionReopen {
                select(app, title: "Native first", count: 1)
                samples.append(sample(app, phase: "closed", rows: rows))
                shot("\(mode)-closed")
                XCTAssertTrue(button.isHittable)
                button.tap()
                XCTAssertTrue(app.buttons["Native first"].waitForExistence(timeout: 5))
                samples.append(sample(app, phase: "reopened", rows: rows))
                shot("\(mode)-reopened")
                select(app, title: "Native second", count: 2)
                samples.append(sample(app, phase: "closedAgain", rows: rows))
                shot("\(mode)-closedAgain")
                if mode == "show" {
                    app.typeText("native")
                    XCTAssertEqual((app.textFields["keyboardEditor"].value as? String)?.lowercased(), "native")
                    samples.append(sample(app, phase: "typed", rows: rows))
                    shot("\(mode)-typed")
                }
            }
            let data = try JSONSerialization.data(withJSONObject: ["mode": mode, "flow": flow.rawValue, "rowCount": rows, "samples": samples], options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "keyboard-\(mode)-geometry"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    private func select(_ app: XCUIApplication, title: String, count: Int) {
        let row = app.buttons[title]
        XCTAssertTrue(row.isHittable)
        row.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Native first"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertEqual(app.staticTexts["keyboardSelectionCount"].label, String(count))
    }

    private func sample(_ app: XCUIApplication, phase: String, rows count: Int) -> [String: Any] {
        func rect(_ value: CGRect) -> [Double] {
            [value.origin.x, value.origin.y, value.width, value.height].map(Double.init)
        }
        let started = CACurrentMediaTime()
        let sourceButton = app.buttons["nativeKeyboardMenu"]
        let source = rect(sourceButton.frame)
        let sourceHittable = sourceButton.isHittable
        let counter = app.staticTexts["keyboardSelectionCount"]
        let selectionCount: Any = counter.exists ? counter.label : NSNull()
        let editor = app.textFields["keyboardEditor"]
        let editorValue: Any = editor.exists ? (editor.value as? String ?? "") : NSNull()
        let keyboard = app.keyboards.firstMatch
        let keyboardExists = keyboard.exists
        let keyboardFrame: Any = keyboardExists ? rect(keyboard.frame) : NSNull()
        let titles = ["Native first", "Native second", "Native third"] + (count == 10 ? ["Native row 10"] : [])
        let rows: [[String: Any]] = titles.map { title in
            let row = app.buttons[title]
            let exists = row.exists
            return ["title": title, "exists": exists, "frame": exists ? rect(row.frame) as Any : NSNull()]
        }
        return ["phase": phase, "startTime": started, "endTime": CACurrentMediaTime(),
                "source": source, "sourceHittable": sourceHittable, "selectionCount": selectionCount, "editorValue": editorValue,
                "keyboardExists": keyboardExists, "keyboard": keyboardFrame, "rows": rows]
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
