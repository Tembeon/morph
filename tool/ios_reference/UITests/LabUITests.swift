import XCTest
import UIKit

final class LabUITests: XCTestCase {
    private var app = XCUIApplication()
    private var journal: [[String: Any]] = []

    override func setUp() { continueAfterFailure = false }

    func testScenario() throws {
        let env = ProcessInfo.processInfo.environment
        let raw = try XCTUnwrap(env["PROBE_LAB_JSON"])
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let spec = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try XCTUnwrap(spec["steps"] as? [[String: Any]])
        let side = env["PROBE_LAB_SIDE"] ?? "native"
        app = XCUIApplication(bundleIdentifier: side == "native" ? "dev.tembeon.morph.probe" : "dev.tembeon.morphExample")
        app.launchEnvironment["PROBE_SCENE"] = env["PROBE_LAB_SCENE"] ?? "lab"
        app.launchEnvironment["PROBE_LAB_JSON"] = raw
        app.launchEnvironment["PROBE_REC"] = "lab"
        app.launchEnvironment["PROBE_DARK"] = (spec["appearance"] as? String) == "dark" ? "1" : "0"
        if let extra = spec["probeEnv"] as? [String: String] {
            for (key, value) in extra { app.launchEnvironment[key] = value }
        }
        app.launch()
        journal.append(["k": "lab_environment", "t": CACurrentMediaTime(), "rm": UIAccessibility.isReduceMotionEnabled,
                        "rt": UIAccessibility.isReduceTransparencyEnabled])
        Thread.sleep(forTimeInterval: 2)
        let canvas = try XCTUnwrap(spec["canvas"] as? [String: Double])
        XCTAssertEqual(app.frame.width, canvas["width"]!, accuracy: 0.1)
        XCTAssertEqual(app.frame.height, canvas["height"]!, accuracy: 0.1)
        for step in steps {
            let id = try XCTUnwrap(step["id"] as? String)
            let action = try XCTUnwrap(step["action"] as? String)
            mark(id, "begin", action)
            switch action {
            case "gesture":
                try synth(step["paths"] as? [[String: Any]] ?? [step], name: id)
            case "wait":
                Thread.sleep(forTimeInterval: (step["seconds"] as? Double) ?? 1)
            case "background":
                XCUIDevice.shared.press(.home)
                Thread.sleep(forTimeInterval: (step["seconds"] as? Double) ?? 1)
                app.activate()
            case "shot":
                let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
                attachment.name = "lab-\(id)"
                attachment.lifetime = .keepAlways
                add(attachment)
            default:
                XCTFail("unknown action \(action)")
            }
            mark(id, "end", action)
            Thread.sleep(forTimeInterval: (step["after"] as? Double) ?? 0)
        }
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: journal, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "lab-runner-events"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func mark(_ id: String, _ phase: String, _ action: String) {
        journal.append(["id": id, "phase": phase, "action": action, "t": CACurrentMediaTime()])
        NSLog("LAB \(id) \(phase) \(action)")
    }

    private func synth(_ paths: [[String: Any]], name: String) throws {
        let pathClass = try XCTUnwrap(NSClassFromString("XCPointerEventPath"))
        let recordClass = try XCTUnwrap(NSClassFromString("XCSynthesizedEventRecord"))
        typealias InitPath = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
        typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
        typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
        typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias Synth = @convention(c) (AnyObject, Selector, AnyObject, @convention(block) (Bool, NSError?) -> Void) -> Void
        func allocate(_ cls: AnyClass) -> AnyObject { (cls as! NSObject.Type).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue() }
        func implementation<T>(_ object: AnyObject, _ selector: Selector, _ type: T.Type) -> T {
            unsafeBitCast(method_getImplementation(class_getInstanceMethod(object_getClass(object)!, selector)!), to: type)
        }
        let initRecord = NSSelectorFromString("initWithName:interfaceOrientation:")
        let raw = allocate(recordClass)
        let record = implementation(raw, initRecord, InitRecord.self)(raw, initRecord, name as NSString, 1)
        let initPath = NSSelectorFromString("initForTouchAtPoint:offset:")
        let move = NSSelectorFromString("moveToPoint:atOffset:")
        let lift = NSSelectorFromString("liftUpAtOffset:")
        let add = NSSelectorFromString("addPointerEventPath:")
        for path in paths {
            let points = try XCTUnwrap(path["points"] as? [[String: Double]])
            let first = try XCTUnwrap(points.first)
            var origin = CGPoint.zero
            if let anchor = path["anchor"] as? [String: Any] {
                let query: XCUIElementQuery
                if let id = anchor["identifier"] as? String {
                    query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", id))
                } else {
                    query = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", anchor["label"] as! String))
                }
                XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 5))
                let elements = query.allElementsBoundByIndex.filter { $0.frame.width > 0 && $0.frame.height > 0 }
                let element = try XCTUnwrap(anchor["last"] as? Bool == true ? elements.last : elements.first)
                let frame = element.frame
                origin = CGPoint(x: frame.minX + frame.width * ((anchor["fx"] as? Double) ?? 0.5),
                                 y: frame.minY + frame.height * ((anchor["fy"] as? Double) ?? 0.5))
                journal.append(["k": "lab_anchor", "id": name, "x": origin.x, "y": origin.y, "t": CACurrentMediaTime()])
            }
            func point(_ value: [String: Double]) -> CGPoint { CGPoint(x: origin.x + value["x"]!, y: origin.y + value["y"]!) }
            let object = allocate(pathClass)
            let finger = implementation(object, initPath, InitPath.self)(object, initPath, point(first), first["t"]!)
            for point in points.dropFirst() {
                implementation(finger, move, Move.self)(finger, move, CGPoint(x: origin.x + point["x"]!, y: origin.y + point["y"]!), point["t"]!)
            }
            implementation(finger, lift, Lift.self)(finger, lift, (path["upAt"] as? Double)!)
            implementation(record, add, Add.self)(record, add, finger)
        }
        let synthesizer = try XCTUnwrap(XCUIDevice.shared.perform(NSSelectorFromString("eventSynthesizer"))?.takeUnretainedValue())
        let selector = NSSelectorFromString("synthesizeEvent:completion:")
        let done = expectation(description: name)
        var failure: NSError?
        var succeeded = false
        let callback: @convention(block) (Bool, NSError?) -> Void = { success, error in
            succeeded = success
            failure = error
            done.fulfill()
        }
        implementation(synthesizer, selector, Synth.self)(synthesizer, selector, record, callback)
        wait(for: [done], timeout: 60)
        XCTAssertTrue(succeeded, "\(String(describing: failure))")
    }
}
