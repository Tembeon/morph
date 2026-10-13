import UIKit
import ObjectiveC

/// Public-API animation tap of the lab (`animations` in a scenario): what
/// Core Animation runs on the tracked layers, what UIKit adds to any layer
/// and which property animators it creates. Everything here is read through
/// public CAAnimation / CALayer / UIViewPropertyAnimator API; the only
/// runtime use is exchanging the implementations of public selectors in
/// this app, for the run of a scenario that turns the option on.
final class AnimationTap {
    static let shared = AnimationTap()

    private var spec: LabScenario.Animations?
    private var seen: [String: String] = [:]
    private var pattern: NSRegularExpression?

    func start(_ spec: LabScenario.Animations) {
        self.spec = spec
        if let raw = spec.class { pattern = try? NSRegularExpression(pattern: raw) }
        if spec.added ?? true {
            exchange(CALayer.self, #selector(CALayer.add(_:forKey:)), #selector(CALayer.lab_tapAdd(_:forKey:)))
        }
        if spec.animators ?? true {
            exchange(UIViewPropertyAnimator.self, #selector(UIViewPropertyAnimator.startAnimation as (UIViewPropertyAnimator) -> () -> Void),
                     #selector(UIViewPropertyAnimator.lab_tapStartNow))
            exchange(UIViewPropertyAnimator.self, #selector(UIViewPropertyAnimator.startAnimation(afterDelay:)),
                     #selector(UIViewPropertyAnimator.lab_tapStart(afterDelay:)))
            springInitializers()
        }
        Recorder.shared.log(["k": "lab_anim_tap", "t": CACurrentMediaTime(), "depth": spec.depth ?? 2,
                             "added": spec.added ?? true, "animators": spec.animators ?? true, "class": spec.class ?? ""])
    }

    private func exchange(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let a = class_getInstanceMethod(cls, original), let b = class_getInstanceMethod(cls, replacement) else {
            Recorder.shared.log(["k": "lab_error", "e": "no method \(NSStringFromSelector(original))", "t": CACurrentMediaTime()])
            return
        }
        method_exchangeImplementations(a, b)
    }

    /// Wraps the public UISpringTimingParameters initializers to keep their
    /// arguments on the instance: the class reads back only
    /// `initialVelocity`. Receiver and result pass through as raw pointers
    /// so the initializer's ownership transfer stays untouched.
    private func springInitializers() {
        let cls: AnyClass = UISpringTimingParameters.self
        typealias Ratio = @convention(c) (UnsafeRawPointer, Selector, CGFloat, CGVector) -> UnsafeRawPointer?
        typealias Constants = @convention(c) (UnsafeRawPointer, Selector, CGFloat, CGFloat, CGFloat, CGVector) -> UnsafeRawPointer?
        typealias Bounce = @convention(c) (UnsafeRawPointer, Selector, Double, CGFloat, CGVector) -> UnsafeRawPointer?
        let ratio = #selector(UISpringTimingParameters.init(dampingRatio:initialVelocity:))
        if let method = class_getInstanceMethod(cls, ratio) {
            let original = unsafeBitCast(method_getImplementation(method), to: Ratio.self)
            let block: @convention(block) (UnsafeRawPointer, CGFloat, CGVector) -> UnsafeRawPointer? = { this, damping, velocity in
                let result = original(this, ratio, damping, velocity)
                AnimationTap.remember(result, ["dampingRatio": Double(damping), "dx": Double(velocity.dx), "dy": Double(velocity.dy)])
                return result
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        let constants = #selector(UISpringTimingParameters.init(mass:stiffness:damping:initialVelocity:))
        if let method = class_getInstanceMethod(cls, constants) {
            let original = unsafeBitCast(method_getImplementation(method), to: Constants.self)
            let block: @convention(block) (UnsafeRawPointer, CGFloat, CGFloat, CGFloat, CGVector) -> UnsafeRawPointer? = { this, mass, stiffness, damping, velocity in
                let result = original(this, constants, mass, stiffness, damping, velocity)
                AnimationTap.remember(result, ["mass": Double(mass), "stiffness": Double(stiffness), "damping": Double(damping),
                                               "dx": Double(velocity.dx), "dy": Double(velocity.dy)])
                return result
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        let bounce = #selector(UISpringTimingParameters.init(duration:bounce:initialVelocity:))
        if let method = class_getInstanceMethod(cls, bounce) {
            let original = unsafeBitCast(method_getImplementation(method), to: Bounce.self)
            let block: @convention(block) (UnsafeRawPointer, Double, CGFloat, CGVector) -> UnsafeRawPointer? = { this, duration, amount, velocity in
                let result = original(this, bounce, duration, amount, velocity)
                AnimationTap.remember(result, ["duration": duration, "bounce": Double(amount), "dx": Double(velocity.dx), "dy": Double(velocity.dy)])
                return result
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    private static let springKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    private static func remember(_ pointer: UnsafeRawPointer?, _ arguments: [String: Double]) {
        guard let pointer else { return }
        let object = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        objc_setAssociatedObject(object, springKey, arguments, .OBJC_ASSOCIATION_RETAIN)
    }

    // MARK: per-frame poll

    /// Logs the animations of the layers of [views] (and their sublayers
    /// `depth` levels down, plus any view whose class matches `class`)
    /// that are new or changed since the previous frame, and the keys that
    /// disappeared.
    func poll(_ views: [UIView], all: [UIView], now: CFTimeInterval) {
        guard let spec else { return }
        var roots = views
        if let pattern {
            roots += all.filter { view in
                let name = NSStringFromClass(type(of: view))
                return pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
            }
        }
        var current: [String: String] = [:]
        var visited = Set<ObjectIdentifier>()
        func walk(_ layer: CALayer, level: Int, path: String) {
            guard visited.insert(ObjectIdentifier(layer)).inserted else { return }
            for key in layer.animationKeys() ?? [] {
                guard let animation = layer.animation(forKey: key) else { continue }
                let id = "\(ObjectIdentifier(layer))/\(key)"
                let described = AnimationTap.describe(animation)
                let signature = AnimationTap.signature(described)
                current[id] = signature
                if seen[id] != signature {
                    var row = AnimationTap.host(layer)
                    row["k"] = "lab_anim"
                    row["src"] = "poll"
                    row["t"] = now
                    row["path"] = path
                    row["key"] = key
                    row["anim"] = described
                    Recorder.shared.log(row)
                }
            }
            guard level < (spec.depth ?? 2) else { return }
            for (index, child) in (layer.sublayers ?? []).enumerated() { walk(child, level: level + 1, path: "\(path)/\(index)") }
        }
        for view in roots { walk(view.layer, level: 0, path: NSStringFromClass(type(of: view))) }
        for id in seen.keys where current[id] == nil {
            Recorder.shared.log(["k": "lab_anim", "src": "gone", "t": now, "id": id])
        }
        seen = current
    }

    // MARK: add-time capture

    fileprivate func added(_ animation: CAAnimation, key: String?, layer: CALayer) {
        let now = CACurrentMediaTime()
        var row = AnimationTap.host(layer)
        row["k"] = "lab_anim"
        row["src"] = "add"
        row["t"] = now
        row["key"] = key ?? ""
        row["anim"] = AnimationTap.describe(animation)
        if let path = (animation as? CAPropertyAnimation)?.keyPath, !path.isEmpty {
            row["model"] = AnimationTap.value(layer.value(forKeyPath: path))
            if let presentation = layer.presentation() { row["presentation"] = AnimationTap.value(presentation.value(forKeyPath: path)) }
        }
        row["main"] = Thread.isMainThread
        AnimationTap.emit(row)
    }

    fileprivate func animator(_ animator: UIViewPropertyAnimator, event: String, delay: Double? = nil) {
        var row: [String: Any] = ["k": "lab_animator", "e": event, "t": CACurrentMediaTime(), "id": "\(ObjectIdentifier(animator))",
                                  "cls": NSStringFromClass(type(of: animator)), "duration": animator.duration,
                                  "interruptible": animator.isInterruptible, "scrubsLinearly": animator.scrubsLinearly,
                                  "userInteraction": animator.isUserInteractionEnabled, "manualHitTesting": animator.isManualHitTestingEnabled,
                                  "fraction": animator.fractionComplete, "reversed": animator.isReversed, "state": animator.state.rawValue,
                                  "running": animator.isRunning, "delay": animator.delay]
        if let delay { row["startDelay"] = delay }
        if let timing = animator.timingParameters { row["timing"] = AnimationTap.timing(timing) }
        AnimationTap.emit(row)
    }

    private static func emit(_ row: [String: Any]) {
        if Thread.isMainThread { Recorder.shared.log(row) } else { DispatchQueue.main.async { Recorder.shared.log(row) } }
    }

    // MARK: description

    static func host(_ layer: CALayer) -> [String: Any] {
        var row: [String: Any] = ["layer": NSStringFromClass(type(of: layer)), "lid": "\(ObjectIdentifier(layer))"]
        if let name = layer.name { row["name"] = name }
        if let view = layer.delegate as? UIView {
            row["view"] = NSStringFromClass(type(of: view))
            if let id = view.accessibilityIdentifier { row["viewId"] = id }
        } else if let superlayer = layer.superlayer {
            row["super"] = NSStringFromClass(type(of: superlayer))
            if let view = superlayer.delegate as? UIView { row["superView"] = NSStringFromClass(type(of: view)) }
        }
        return row
    }

    static func describe(_ animation: CAAnimation) -> [String: Any] {
        var row: [String: Any] = ["cls": NSStringFromClass(type(of: animation)), "beginTime": animation.beginTime,
                                  "duration": animation.duration, "speed": animation.speed, "timeOffset": animation.timeOffset,
                                  "repeatCount": animation.repeatCount, "autoreverses": animation.autoreverses,
                                  "fillMode": animation.fillMode.rawValue, "removedOnCompletion": animation.isRemovedOnCompletion]
        if let function = animation.timingFunction { row["timingFunction"] = controlPoints(function) }
        if let property = animation as? CAPropertyAnimation {
            row["keyPath"] = property.keyPath ?? ""
            row["additive"] = property.isAdditive
            row["cumulative"] = property.isCumulative
        }
        if let basic = animation as? CABasicAnimation {
            if let x = basic.fromValue { row["fromValue"] = value(x) }
            if let x = basic.toValue { row["toValue"] = value(x) }
            if let x = basic.byValue { row["byValue"] = value(x) }
        }
        if let spring = animation as? CASpringAnimation {
            row["mass"] = spring.mass
            row["stiffness"] = spring.stiffness
            row["damping"] = spring.damping
            row["initialVelocity"] = spring.initialVelocity
            row["settlingDuration"] = spring.settlingDuration
            row["perceptualDuration"] = spring.perceptualDuration
            row["bounce"] = spring.bounce
            row["allowsOverdamping"] = spring.allowsOverdamping
        }
        if let keyframe = animation as? CAKeyframeAnimation {
            row["calculationMode"] = keyframe.calculationMode.rawValue
            if let values = keyframe.values { row["values"] = values.prefix(64).map { value($0) }; row["valueCount"] = values.count }
            if let times = keyframe.keyTimes { row["keyTimes"] = times.prefix(64).map { $0.doubleValue } }
            if let functions = keyframe.timingFunctions { row["timingFunctions"] = functions.prefix(64).map { controlPoints($0) } }
        }
        if let group = animation as? CAAnimationGroup { row["children"] = (group.animations ?? []).map { describe($0) } }
        if let transition = animation as? CATransition {
            row["type"] = transition.type.rawValue
            if let subtype = transition.subtype { row["subtype"] = subtype.rawValue }
        }
        return row
    }

    /// A stable text form of a described animation: `animation(forKey:)`
    /// hands out a fresh copy on every call, so identity cannot tell a
    /// changed animation from the same one.
    static func signature(_ value: Any) -> String {
        if let row = value as? [String: Any] {
            return "{" + row.keys.sorted().map { "\($0):\(signature(row[$0]!))" }.joined(separator: ",") + "}"
        }
        if let list = value as? [Any] { return "[" + list.map { signature($0) }.joined(separator: ",") + "]" }
        return "\(value)"
    }

    static func controlPoints(_ function: CAMediaTimingFunction) -> [Double] {
        var first: [Float] = [0, 0]
        var second: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &first)
        function.getControlPoint(at: 2, values: &second)
        return [Double(first[0]), Double(first[1]), Double(second[0]), Double(second[1])]
    }

    static func value(_ raw: Any?) -> Any {
        guard let raw else { return NSNull() }
        if let number = raw as? NSNumber { return number.doubleValue }
        if let boxed = raw as? NSValue {
            let type = String(cString: boxed.objCType)
            if type.contains("CGPoint") { let p = boxed.cgPointValue; return [p.x, p.y] }
            if type.contains("CGSize") { let s = boxed.cgSizeValue; return [s.width, s.height] }
            if type.contains("CGRect") { let r = boxed.cgRectValue; return [r.minX, r.minY, r.width, r.height] }
            if type.contains("CATransform3D") {
                let m = boxed.caTransform3DValue
                return [m.m11, m.m12, m.m13, m.m14, m.m21, m.m22, m.m23, m.m24, m.m31, m.m32, m.m33, m.m34, m.m41, m.m42, m.m43, m.m44]
            }
            if type.contains("CGAffineTransform") { let t = boxed.cgAffineTransformValue; return [t.a, t.b, t.c, t.d, t.tx, t.ty] }
        }
        if CFGetTypeID(raw as CFTypeRef) == CGColor.typeID {
            let color = raw as! CGColor
            return (color.components ?? []).map { Double($0) }
        }
        return String(describing: raw).prefix(160).description
    }

    static func timing(_ parameters: UITimingCurveProvider) -> [String: Any] {
        var row: [String: Any] = ["cls": NSStringFromClass(type(of: parameters)), "curveType": parameters.timingCurveType.rawValue]
        if let cubic = parameters.cubicTimingParameters {
            row["curve"] = cubic.animationCurve.rawValue
            row["controlPoints"] = [cubic.controlPoint1.x, cubic.controlPoint1.y, cubic.controlPoint2.x, cubic.controlPoint2.y]
        }
        if let spring = parameters.springTimingParameters {
            row["initialVelocity"] = [spring.initialVelocity.dx, spring.initialVelocity.dy]
            if let arguments = objc_getAssociatedObject(spring, springKey) as? [String: Double] { row["spring"] = arguments }
        }
        return row
    }
}

extension CALayer {
    @objc dynamic func lab_tapAdd(_ animation: CAAnimation, forKey key: String?) {
        AnimationTap.shared.added(animation, key: key, layer: self)
        lab_tapAdd(animation, forKey: key)
    }
}

extension UIViewPropertyAnimator {
    @objc dynamic func lab_tapStartNow() {
        AnimationTap.shared.animator(self, event: "start")
        lab_tapStartNow()
    }

    @objc dynamic func lab_tapStart(afterDelay delay: TimeInterval) {
        AnimationTap.shared.animator(self, event: "start", delay: delay)
        lab_tapStart(afterDelay: delay)
    }
}
