import UIKit
import QuartzCore

final class RecordingWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        if event.type == .touches, let touches = event.allTouches {
            for touch in touches {
                let p = touch.location(in: self)
                if Recorder.shared.touchDumps {
                    if touch.phase == .ended { Recorder.shared.scheduleDump(after: [0.05, 0.3, 0.6, 1.5]) }
                    if touch.phase == .began { Recorder.shared.scheduleDump(after: [0.25, 0.6]) }
                }
                Recorder.shared.log([
                    "k": "touch",
                    "t": touch.timestamp,
                    "phase": touch.phase.rawValue,
                    "x": p.x,
                    "y": p.y,
                ])
            }
        }
        super.sendEvent(event)
    }
}

/// Samples the presentation geometry of tracked UIKit internals every display frame.
///
/// One recorder for every probe family. The scene picks the mode:
/// - "menu": morph-container layer rows (`L` with lid/path/cls), animation rows, window
///   signature rows, a rescan every frame;
/// - single-control scenes (sw, swOn, st, st5, sl*, gb*): control layer rows (`L` with p/c),
///   `state`, `evt` and `flex` rows, lens `frame` rows;
/// - segmented / tabbar / other: lens `frame` rows only.
/// Every display-link tick also logs a `dl` row (timestamp, targetTimestamp, duration and
/// the previous tick's own cost) so the achieved frame rate is known.
final class Recorder: NSObject {
    static let shared = Recorder()

    enum Mode { case lens, controls, menu }

    private let env = ProcessInfo.processInfo.environment
    private(set) var mode: Mode = .lens
    private(set) var touchDumps = false
    private var lastTickCost: Double = 0

    private var link: CADisplayLink?
    private weak var window: UIWindow?
    private var handle: FileHandle?
    private var buffer = Data()
    private var tracked: [UIView] = []
    private var lastScan: CFTimeInterval = 0
    private var lastFlush: CFTimeInterval = 0
    private var lastSignature: [Int: String] = [:]
    private var pattern = try! NSRegularExpression(pattern: "^_UILiquidLensView$")

    static let lensPattern = "LiquidLens|SelectionView|SelectionIndicator|Knob|Thumb|_UISwitch|Platter|MorphingPlatter|ContextMenu"
    static let controlsPattern = "^_UILiquidLensView$"
    static let menuPattern = "MagicMorph|MorphAnimationContainer|TransformView|_UIContextMenuView|_UIContextMenuListView|_UIContextMenuCell$|^UIButton$|_UIButtonBarButton|_UIReparentingView|_UIContextMenuContainerView|PlatterTransitionView|UIVisualEffectView|_UISystemBackgroundView|FlexInteraction|_UIPortalView"

    static func mode(for scene: String) -> Mode {
        if scene == "menu" { return .menu }
        if Scenes.isSingleControl(scene) { return .controls }
        return .lens
    }

    func start(scene: String, window: UIWindow) {
        self.window = window
        mode = Recorder.mode(for: scene)
        let raw = env["PROBE_TRACK"] ?? (mode == .menu ? Recorder.menuPattern : mode == .controls ? Recorder.controlsPattern : Recorder.lensPattern)
        pattern = try! NSRegularExpression(pattern: raw)
        touchDumps = mode == .menu && env["PROBE_DUMPS"] == "1"
        let recName = env["PROBE_REC"] ?? scene
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("rec-\(recName).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        var startRow: [String: Any] = ["k": "start", "t": CACurrentMediaTime(), "scene": scene, "rec": recName, "scale": window.screen.scale,
                                       "maxfps": window.screen.maximumFramesPerSecond, "w": window.bounds.width, "h": window.bounds.height]
        #if targetEnvironment(simulator)
        startRow["sim"] = true
        #endif
        for (k, v) in env where k.hasPrefix("PROBE_") { startRow["env_" + k] = v }
        log(startRow)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        if let pat = ProcessInfo.processInfo.environment["PROBE_SETTINGS"] {
            let text = SettingsDump.run(pattern: pat)
            try? text.write(to: docs.appendingPathComponent("settings.txt"), atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dumpTree(name: "tree-\(scene).txt")
            self?.dumpClasses(name: "classes-\(scene).txt")
        }
    }

    private var dumpCount = 0
    private var lastWindowSig = ""

    func scheduleDump(after delays: [Double]) {
        for d in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                guard let self else { return }
                self.dumpCount += 1
                self.dumpTree(name: String(format: "tree-%03d.txt", self.dumpCount))
            }
        }
    }

    private func nonFinite(_ d: Double) -> Any { mode == .menu ? "\(d)" : -9999 }

    private func clean(_ v: Any) -> Any {
        switch v {
        case let d as Double: return d.isFinite ? d : nonFinite(d)
        case let f as Float: return f.isFinite ? Double(f) : nonFinite(Double(f))
        case let c as CGFloat: return c.isFinite ? Double(c) : nonFinite(Double(c))
        case let i as Int: return i
        case let b as Bool: return b
        case let s as String: return s
        case let s as Substring: return String(s)
        case let a as [Any]: return a.map { clean($0) }
        case let m as [String: Any]: return m.mapValues { clean($0) }
        case let n as NSNumber: return n.doubleValue.isFinite ? n : nonFinite(n.doubleValue)
        case is NSNull: return v
        default: return "\(v)"
        }
    }

    func log(_ raw: [String: Any]) {
        let object = clean(raw)
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        buffer.append(data)
        buffer.append(0x0A)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let began = CACurrentMediaTime()
        let now = link.timestamp
        log(["k": "dl", "t": now, "tt": link.targetTimestamp, "d": link.duration, "c": round3(lastTickCost * 1000)])
        if now - lastScan > (mode == .menu ? 0.0 : 0.25) {
            lastScan = now
            tracked = allWindows().flatMap { collect(in: $0) }
            if mode == .controls {
                roots = allWindows().flatMap { collectRoots(in: $0) }
                flexViews = roots.flatMap { collectFlex($0) }
            }
            if mode == .menu {
                let sig = allWindows().map { "\(NSStringFromClass(type(of: $0))):\($0.subviews.count)" }.joined(separator: ",")
                if sig != lastWindowSig {
                    lastWindowSig = sig
                    log(["k": "windows", "t": now, "sig": sig])
                    if touchDumps { scheduleDump(after: [0.02]) }
                }
            }
        }
        if mode == .controls {
            for root in roots { sampleControlLayers(root, now: now) }
            for v in flexViews { sampleFlex(v, now: now) }
        }
        if mode == .menu { sampleMenuLayers(now: now) }
        for view in tracked {
            guard let entry = sample(view) else { continue }
            let id = ObjectIdentifier(view).hashValue
            let signature = entry.description
            if lastSignature[id] == signature { continue }
            lastSignature[id] = signature
            var row = entry
            row["k"] = "frame"
            row["t"] = now
            row["id"] = id
            log(row)
        }
        if buffer.count > 16_384 || now - lastFlush > 0.3 { lastFlush = now; flush() }
        lastTickCost = CACurrentMediaTime() - began
    }

    func flush() {
        handle?.write(buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private func allWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }

    private func collect(in view: UIView) -> [UIView] {
        var out: [UIView] = []
        let name = NSStringFromClass(type(of: view))
        if pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil {
            out.append(view)
        }
        for sub in view.subviews { out += collect(in: sub) }
        return out
    }

    private func sample(_ view: UIView) -> [String: Any]? {
        guard let window = view.window,
              let pres = view.layer.presentation(),
              let windowPres = window.layer.presentation() else { return nil }
        let box = pres.convert(pres.bounds, to: windowPres)
        let tf = pres.transform
        var row: [String: Any] = [
            "cls": NSStringFromClass(type(of: view)),
            "x": round2(box.midX), "y": round2(box.midY),
            "w": round2(box.width), "h": round2(box.height),
            "bw": round2(pres.bounds.width), "bh": round2(pres.bounds.height),
            "a": round3(Double(pres.opacity)),
            "sx": round4(tf.m11), "sy": round4(tf.m22), "tx": round2(tf.m41), "ty": round2(tf.m42),
        ]
        if view.isHidden { row["hidden"] = true }
        if mode == .menu { menuExtras(view, pres, &row) }
        if let parent = view.superview { row["parent"] = NSStringFromClass(type(of: parent)) }
        row["ctl"] = owner(of: view)
        if NSStringFromClass(type(of: view)) == "_UILiquidLensView" { lensExtras(view, windowPres, &row) }
        return row
    }

    private func menuExtras(_ view: UIView, _ pres: CALayer, _ row: inout [String: Any]) {
        let tf = pres.transform
        row["cr"] = round2(pres.cornerRadius)
        if tf.m12 != 0 || tf.m21 != 0 || tf.m34 != 0 || tf.m43 != 0 { row["m"] = [tf.m11, tf.m12, tf.m21, tf.m22, tf.m34, tf.m41, tf.m42, tf.m43].map { round4($0) } }
        let st = pres.sublayerTransform
        if !CATransform3DIsIdentity(st) { row["st"] = [round4(st.m11), round4(st.m22), round2(st.m41), round2(st.m42), round4(st.m34)] }
        if let fl = pres.filters as? [NSObject], !fl.isEmpty {
            var fs: [String: Any] = [:]
            for f in fl {
                let name = (Probe.object(f, "name") as? String) ?? "\(f)"
                for key in ["inputRadius"] where name.lowercased().contains("blur") {
                    do {
                        if let v = (pres.value(forKeyPath: "filters.\(name).\(key)") as? NSNumber) { fs[name + "." + key] = round4(v.doubleValue) }
                    }
                }
            }
            if !fs.isEmpty { row["flt"] = fs }
        }
        logAnimations(view.layer, depth: 0)
    }

    private func lensExtras(_ view: UIView, _ windowPres: CALayer, _ row: inout [String: Any]) {
            if let lifted = Probe.scalar(view, "lifted") { row["lifted"] = lifted }
            if let lp = Probe.object(view, "liftProgress") {
                if let v = Probe.scalar(lp, "value") { row["lp"] = round4(v) }
                if let v = Probe.scalar(lp, "presentationValue") { row["lpp"] = round4(v) }
            }
            if env["PROBE_LENS_ANIMS"] == "1" { logAnimations(view.layer, depth: 0) }
            if let flex = Probe.object(view, "flexInteraction") {
                for key in ["scaleX", "scaleY", "driftX", "driftY", "translationY"] {
                    if let o = Probe.object(flex, key) {
                        if let v = Probe.scalar(o, "value") { row["f_" + key] = round4(v) }
                        if let v = Probe.scalar(o, "presentationValue") { row["p_" + key] = round4(v) }
                    }
                }
                if let p = Probe.point(flex, "translation") {
                    row["f_tx"] = round2(p.x)
                    row["f_ty"] = round2(p.y)
                }
                if let p = Probe.point(flex, "internalTranslation") {
                    row["f_itx"] = round2(p.x)
                    row["f_ity"] = round2(p.y)
                }
                if let vi = Probe.object(flex, "velocityIntegrator") {
                    if let v = Probe.vector(vi, "velocity") { row["vi_vx"] = round2(v.dx); row["vi_vy"] = round2(v.dy) }
                    if let v = Probe.point(vi, "position") { row["vi_x"] = round2(v.x); row["vi_y"] = round2(v.y) }
                    if let v = Probe.vector(vi, "acceleration") { row["vi_ax"] = round2(v.dx); row["vi_ay"] = round2(v.dy) }
                    if let v = Probe.vector(vi, "offset") { row["vi_ox"] = round2(v.dx); row["vi_oy"] = round2(v.dy) }
                }
            }
            if let cw = Probe.object(view, "contentWrapper") as? UIView, let cp = cw.layer.presentation() {
                let t = cp.transform
                row["cw"] = [round4(t.m11), round4(t.m22), round2(t.m41), round2(t.m42), round2(cp.bounds.width), round2(cp.bounds.height), round2(cp.position.x), round2(cp.position.y)]
            }
            if let g = Probe.object(view, "glass") as? UIView, let gp = g.layer.presentation() {
                let t = gp.transform
                let gb = gp.convert(gp.bounds, to: windowPres)
                row["gl"] = [round4(t.m11), round4(t.m22), round2(gb.midX), round2(gb.midY), round2(gb.width), round2(gb.height), round3(Double(gp.opacity))]
            }
            var subs: [[String: Any]] = []
            for sub in view.subviews {
                guard let sp = sub.layer.presentation() else { continue }
                let sb = sp.convert(sp.bounds, to: windowPres)
                subs.append([
                    "cls": NSStringFromClass(type(of: sub)),
                    "x": round2(sb.midX), "y": round2(sb.midY), "w": round2(sb.width), "h": round2(sb.height),
                    "a": round3(Double(sp.opacity)), "sx": round4(sp.transform.m11), "sy": round4(sp.transform.m22),
                ])
            }
            row["subs"] = subs
    }

    private var roots: [UIView] = []
    private let maxDepth = Int(ProcessInfo.processInfo.environment["PROBE_DEPTH"] ?? "6") ?? 6
    private var flexViews: [UIView] = []

    private func collectFlex(_ v: UIView) -> [UIView] {
        var out: [UIView] = []
        if Probe.object(v, "flexInteraction") != nil || Probe.object(v, "_flexInteraction") != nil { out.append(v) }
        for s in v.subviews { out += collectFlex(s) }
        return out
    }

    private func sampleFlex(_ v: UIView, now: CFTimeInterval) {
        guard let flex = Probe.object(v, "flexInteraction") ?? Probe.object(v, "_flexInteraction") else { return }
        var row: [String: Any] = ["cls": NSStringFromClass(type(of: v))]
        for key in ["scaleX", "scaleY", "driftX", "driftY", "translationY"] {
            if let o = Probe.object(flex, key) {
                if let x = Probe.scalar(o, "value") { row["f_" + key] = round4(x) }
                if let x = Probe.scalar(o, "presentationValue") { row["p_" + key] = round4(x) }
            }
        }
        if let p = Probe.point(flex, "translation") { row["f_tx"] = round2(p.x); row["f_ty"] = round2(p.y) }
        if let p = Probe.point(flex, "internalTranslation") { row["f_itx"] = round2(p.x); row["f_ity"] = round2(p.y) }
        if let lp = Probe.object(v, "liftProgress") {
            if let x = Probe.scalar(lp, "value") { row["lp"] = round4(x) }
            if let x = Probe.scalar(lp, "presentationValue") { row["lpp"] = round4(x) }
        }
        let key = "flex" + String(ObjectIdentifier(v).hashValue)
        let sig = row.keys.sorted().map { "\($0)=\(row[$0]!)" }.joined(separator: ",")
        if layerSig[key] == sig { return }
        layerSig[key] = sig
        row["k"] = "flex"; row["t"] = now; row["id"] = ObjectIdentifier(v).hashValue
        log(row)
    }
    private var layerSig: [String: String] = [:]

    private func collectRoots(in view: UIView) -> [UIView] {
        if let id = view.accessibilityIdentifier, id.hasPrefix("c_") { return [view] }
        return view.subviews.flatMap { collectRoots(in: $0) }
    }

    private func rgba(_ c: CGColor?) -> [Double]? {
        guard let c = c, let conv = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let comps = conv.components else { return nil }
        return comps.map { (Double($0) * 1000).rounded() / 1000 }
    }

    private func sampleControlLayers(_ root: UIView, now: CFTimeInterval) {
        guard let window = root.window, let windowPres = window.layer.presentation() else { return }
        var state: [String: Any] = ["k": "state", "t": now]
        if let s = root as? UISwitch { state["on"] = s.isOn }
        if let s = root as? UISlider { state["v"] = Double(s.value) }
        if let s = root as? UIStepper { state["v"] = s.value }
        if let c = root as? UIControl { state["hl"] = c.isHighlighted; state["tr"] = c.isTracking }
        let ssig = "\(state["on"] ?? "")|\(state["v"] ?? "")|\(state["hl"] ?? "")|\(state["tr"] ?? "")"
        if layerSig["__state"] != ssig { layerSig["__state"] = ssig; log(state) }
        func walk(_ layer: CALayer, _ path: String, _ depth: Int) {
            if depth > maxDepth { return }
            let pres = layer.presentation() ?? layer
            let box = pres.convert(pres.bounds, to: windowPres)
            let tf = pres.transform
            var row: [String: Any] = [
                "x": round2(box.midX), "y": round2(box.midY), "w": round2(box.width), "h": round2(box.height),
                "bw": round2(pres.bounds.width), "bh": round2(pres.bounds.height),
                "a": round3(Double(pres.opacity)), "sx": round4(tf.m11), "sy": round4(tf.m22),
                "tx": round2(tf.m41), "ty": round2(tf.m42), "cr": round2(pres.cornerRadius),
            ]
            if pres.isHidden { row["hid"] = true }
            if let bg = rgba(pres.backgroundColor) { row["bg"] = bg }
            if let sh = layer as? CAShapeLayer, let pp = sh.presentation() { if let f = rgba(pp.fillColor) { row["fill"] = f } }
            let sig = row.keys.sorted().map { "\($0)=\(row[$0]!)" }.joined(separator: ",")
            if layerSig[path] != sig {
                layerSig[path] = sig
                row["k"] = "L"; row["t"] = now; row["p"] = path
                var cls = NSStringFromClass(type(of: layer))
                if let d = layer.delegate as? UIView { cls += "/" + NSStringFromClass(type(of: d)) }
                row["c"] = cls
                log(row)
            }
            for (i, sub) in (layer.sublayers ?? []).enumerated() { walk(sub, path + "." + String(i), depth + 1) }
        }
        walk(root.layer, "0", 0)
    }

    private var seenAnims = Set<ObjectIdentifier>()
    private var menuLayerSig: [ObjectIdentifier: String] = [:]
    private var describedClasses = Set<String>()
    private var layerIds: [ObjectIdentifier: Int] = [:]

    private func layerRoots() -> [CALayer] {
        var roots: [CALayer] = []
        func find(_ v: UIView) {
            let n = NSStringFromClass(type(of: v))
            if n.contains("_UIMorphAnimationContainerView") { roots.append(v.layer); return }
            if n.contains("_UIContextMenuContainerView") { roots.append(v.layer); return }
            v.subviews.forEach(find)
        }
        allWindows().forEach(find)
        return roots
    }

    private func sampleMenuLayers(now: CFTimeInterval) {
        guard let window, let wp = window.layer.presentation() else { return }
        var classesOut = ""
        func visit(_ l: CALayer, _ path: String, _ depth: Int) {
            guard depth < 14 else { return }
            let cn = NSStringFromClass(type(of: l))
            if !describedClasses.contains(cn) {
                describedClasses.insert(cn)
                if cn.contains("SDF") || cn.contains("Morph") || cn.contains("InProcess") || cn.contains("Portal") || cn.contains("Pivot") { classesOut += describe(type(of: l)) }
            }
            if let p = l.presentation() {
                let oid = ObjectIdentifier(l)
                let lid = layerIds[oid] ?? { let n = layerIds.count + 1; layerIds[oid] = n; return n }()
                let box = p.convert(p.bounds, to: wp)
                let tf = p.transform
                var row: [String: Any] = ["k": "L", "lid": lid, "cls": cn, "path": path,
                    "x": round2(box.midX), "y": round2(box.midY), "w": round2(box.width), "h": round2(box.height),
                    "bw": round2(p.bounds.width), "bh": round2(p.bounds.height), "px": round2(p.position.x), "py": round2(p.position.y),
                    "a": round3(Double(p.opacity)), "cr": round2(p.cornerRadius),
                    "tf": [tf.m11, tf.m12, tf.m21, tf.m22, tf.m41, tf.m42, tf.m43, tf.m34].map { round4($0) }]
                if p.isHidden { row["hid"] = true }
                if let v = p.value(forKey: "cornerRadii") as? NSValue, String(cString: v.objCType).hasPrefix("{CACornerRadii") {
                    var raw = [Double](repeating: 0, count: 8)
                    let size = MemoryLayout<Double>.size * 8
                    raw.withUnsafeMutableBytes { buf in val_getValue(v, buf.baseAddress!, size) }
                    if raw.contains(where: { $0 != 0 }) { row["radii"] = raw.map { round2($0) } }
                }
                if let d = l.delegate as? UIView { row["view"] = NSStringFromClass(type(of: d)) }
                if let nm = l.name { row["name"] = String(nm.prefix(120)) }
                if let fl = l.filters as? [NSObject], !fl.isEmpty {
                    var names: [String] = []
                    for f in fl {
                        let nm = (Probe.object(f, "name") as? String) ?? "?"
                        names.append(nm)
                        if nm == "gaussianBlur" || nm.lowercased().contains("blur") {
                            if let v = p.value(forKeyPath: "filters.\(nm).inputRadius") as? NSNumber { row["blur"] = round4(v.doubleValue) }
                        }
                    }
                    row["flt"] = names
                }
                if cn.contains("SDF") {
                    for key in ["smoothness", "gaussianRadius", "effectOffset", "mergeElements", "contentsZeroValueDistance", "contentsOneValueDistance", "gradientOvalization"] {
                        if let v = Probe.scalar(p, key) { row["sdf_" + key] = round4(v) }
                    }
                    for key in ["mode", "operation"] {
                        if let v = Probe.object(p, key) as? String { row["sdf_" + key] = v }
                    }
                    if let e = Probe.object(p, "effect") { row["sdf_effect"] = String(String(describing: e).prefix(80)) }
                }
                let st = p.sublayerTransform
                if !CATransform3DIsIdentity(st) { row["st"] = [st.m11, st.m12, st.m21, st.m22, st.m41, st.m42, st.m34].map { round4($0) } }
                let sig = row.description
                if menuLayerSig[oid] != sig {
                    menuLayerSig[oid] = sig
                    row["t"] = now
                    log(row)
                }
            }
            for (i, sl) in (l.sublayers ?? []).enumerated() { visit(sl, path + "/" + String(i), depth + 1) }
        }
        for (i, r) in layerRoots().enumerated() { visit(r, "R" + String(i), 0) }
        if !classesOut.isEmpty {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("layer-classes.txt")
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(classesOut.data(using: .utf8)!); h.closeFile() }
            else { try? classesOut.write(to: url, atomically: true, encoding: .utf8) }
        }
    }

    private func describeValue(_ v: Any?) -> Any {
        guard let v else { return NSNull() }
        if let n = v as? NSNumber { return n.doubleValue }
        if let val = v as? NSValue {
            let t = String(cString: val.objCType)
            if t.contains("CGRect") { let r = val.cgRectValue; return [r.minX, r.minY, r.width, r.height] }
            if t.contains("CGPoint") { let p = val.cgPointValue; return [p.x, p.y] }
            if t.contains("CGSize") { let z = val.cgSizeValue; return [z.width, z.height] }
            if t.contains("CATransform3D") { let m = val.caTransform3DValue; return [m.m11, m.m12, m.m21, m.m22, m.m41, m.m42, m.m43, m.m34] }
            return "\(val)"
        }
        return String(describing: v).prefix(200).description
    }

    private func logAnimations(_ layer: CALayer, depth: Int) {
        guard depth < 6 else { return }
        for key in layer.animationKeys() ?? [] {
            guard let anim = layer.animation(forKey: key) else { continue }
            let oid = ObjectIdentifier(anim)
            if seenAnims.contains(oid) { continue }
            seenAnims.insert(oid)
            var row: [String: Any] = ["k": "anim", "t": CACurrentMediaTime(), "layer": NSStringFromClass(type(of: layer)), "lname": layer.name ?? "", "key": key, "cls": NSStringFromClass(type(of: anim)), "depth": depth,
                                      "begin": anim.beginTime, "dur": anim.duration, "speed": anim.speed, "lbounds": [layer.bounds.width, layer.bounds.height]]
            var owner: UIView? = layer.delegate as? UIView
            if owner == nil { var l: CALayer? = layer.superlayer; while let c = l, owner == nil { owner = c.delegate as? UIView; l = c.superlayer } }
            if let o = owner { row["view"] = NSStringFromClass(type(of: o)) }
            if let a = anim as? CAPropertyAnimation { row["kp"] = a.keyPath ?? ""; row["additive"] = a.isAdditive }
            if let a = anim as? CABasicAnimation {
                row["from"] = describeValue(a.fromValue); row["to"] = describeValue(a.toValue); row["by"] = describeValue(a.byValue)
                if let tfn = a.timingFunction { var c1: [Float] = [0, 0]; var c2: [Float] = [0, 0]; tfn.getControlPoint(at: 1, values: &c1); tfn.getControlPoint(at: 2, values: &c2); row["tf"] = [c1[0], c1[1], c2[0], c2[1]] }
            }
            if let a = anim as? CASpringAnimation {
                row["mass"] = a.mass; row["stiff"] = a.stiffness; row["damp"] = a.damping; row["v0"] = a.initialVelocity; row["settle"] = a.settlingDuration
            }
            if let a = anim as? CAKeyframeAnimation {
                row["nvals"] = a.values?.count ?? 0
                if let vs = a.values, vs.count <= 400 { row["vals"] = vs.map { describeValue($0) } }
                row["ktimes"] = a.keyTimes?.map { $0.doubleValue } ?? []
            }
            if let g = anim as? CAAnimationGroup { row["sub"] = g.animations?.map { "\(($0 as? CAPropertyAnimation)?.keyPath ?? "?")" } ?? [] }
            log(row)
        }
        for sub in layer.sublayers ?? [] { logAnimations(sub, depth: depth + 1) }
    }

    private var ownerCache: [ObjectIdentifier: String] = [:]

    private func owner(of view: UIView) -> String {
        let key = ObjectIdentifier(view)
        if let c = ownerCache[key] { return c }
        var v: UIView? = view
        var result = "?"
        while let cur = v {
            if let id = cur.accessibilityIdentifier, !id.isEmpty { result = id; break }
            if cur is UITabBar { result = "tabbar"; break }
            v = cur.superview
        }
        ownerCache[key] = result
        return result
    }

    private func describe(_ cls: AnyClass) -> String {
        var out = ""
        var c: AnyClass? = cls
        while let cur = c, NSStringFromClass(cur) != "UIView", NSStringFromClass(cur) != "NSObject", NSStringFromClass(cur) != "UIResponder" {
            out += "== class \(NSStringFromClass(cur))\n"
            var n: UInt32 = 0
            if let ivars = class_copyIvarList(cur, &n) {
                for i in 0..<Int(n) {
                    let iv = ivars[i]
                    let name = ivar_getName(iv).map { String(cString: $0) } ?? "?"
                    let enc = ivar_getTypeEncoding(iv).map { String(cString: $0) } ?? "?"
                    out += "  ivar \(name) \(enc) @\(ivar_getOffset(iv))\n"
                }
                free(ivars)
            }
            if let props = class_copyPropertyList(cur, &n) {
                for i in 0..<Int(n) {
                    out += "  prop \(String(cString: property_getName(props[i]))) \(property_getAttributes(props[i]).map { String(cString: $0) } ?? "")\n"
                }
                free(props)
            }
            if let methods = class_copyMethodList(cur, &n) {
                for i in 0..<Int(n) {
                    let m = methods[i]
                    out += "  meth \(NSStringFromSelector(method_getName(m))) \(method_getTypeEncoding(m).map { String(cString: $0) } ?? "")\n"
                }
                free(methods)
            }
            c = class_getSuperclass(cur)
        }
        return out
    }

    private func dumpClasses(name: String) {
        var out = ""
        var seen = Set<String>()
        func visitObject(_ obj: AnyObject, depth: Int) {
            guard depth < 3, let cls = object_getClass(obj) else { return }
            let cname = NSStringFromClass(cls)
            if seen.contains(cname) { return }
            seen.insert(cname)
            out += describe(cls)
            var c: AnyClass? = cls
            while let cur = c, NSStringFromClass(cur) != "UIView", NSStringFromClass(cur) != "NSObject" {
                var n: UInt32 = 0
                if let ivars = class_copyIvarList(cur, &n) {
                    for i in 0..<Int(n) {
                        let enc = ivar_getTypeEncoding(ivars[i]).map { String(cString: $0) } ?? ""
                        if enc.hasPrefix("@") && !enc.contains("UIView") && !enc.contains("NS") && !enc.contains("CA") {
                            if let o = object_getIvar(obj, ivars[i]) as AnyObject? { visitObject(o, depth: depth + 1) }
                        }
                    }
                    free(ivars)
                }
                c = class_getSuperclass(cur)
            }
        }
        for v in tracked { visitObject(v, depth: 0) }
        for w in allWindows() {
            func walk(_ v: UIView) {
                let n = NSStringFromClass(type(of: v))
                if n.contains("TabBar") || n.contains("Segment") || n.contains("Platter") { visitObject(v, depth: 1) }
                v.subviews.forEach(walk)
            }
            walk(w)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? out.write(to: docs.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func dumpTree(name: String) {
        var out = ""
        func walk(_ v: UIView, _ depth: Int) {
            let f = v.convert(v.bounds, to: nil)
            let L = v.layer
            var extra = " a=\(v.alpha) L=\(NSStringFromClass(type(of: L))) cr=\(L.cornerRadius)"
            if v.isHidden { extra += " HIDDEN" }
            if let fl = L.filters, !fl.isEmpty { extra += " filters=\(fl.map { "\($0)" })" }
            if let lbl = v as? UILabel { extra += " text=\(lbl.text ?? "")" }
            out += String(repeating: "  ", count: depth) + "\(NSStringFromClass(type(of: v))) \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))\(v.accessibilityIdentifier.map { " #\($0)" } ?? "")\(extra)\n"
            let cn = NSStringFromClass(type(of: v))
            if cn.contains("MagicMorph") || cn.contains("_UIContextMenuView") || cn.contains("ContextMenuListView") || cn.contains("ReparentingView") || cn.contains("UIButton") {
                func lwalk(_ l: CALayer, _ d: Int) {
                    guard d < 8 else { return }
                    var info = "\(NSStringFromClass(type(of: l))) name=\(l.name ?? "-") \(Int(l.frame.minX)),\(Int(l.frame.minY)) \(Int(l.bounds.width))x\(Int(l.bounds.height)) op=\(l.opacity) cr=\(l.cornerRadius) hid=\(l.isHidden)"
                    if let fl = l.filters, !fl.isEmpty { info += " filters=\(fl)" }
                    if let keys = l.animationKeys() { info += " anims=\(keys)" }
                    out += String(repeating: "  ", count: depth + 1) + "  [L] " + String(repeating: " ", count: d) + info + "\n"
                    for sl in l.sublayers ?? [] where sl.delegate as? UIView == nil { lwalk(sl, d + 1) }
                }
                lwalk(v.layer, 0)
            }
            for s in v.subviews { walk(s, depth + 1) }
        }
        for w in allWindows() { walk(w, 0) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? out.write(to: docs.appendingPathComponent(name), atomically: true, encoding: .utf8)
        flush()
    }

    private func val_getValue(_ v: NSValue, _ p: UnsafeMutableRawPointer, _ size: Int) { v.getValue(p, size: size) }

    private func round2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }
    private func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
    private func round4(_ v: CGFloat) -> Double { (Double(v) * 10000).rounded() / 10000 }
    private func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
}

/// Reads private getters without KVC, which throws on non-object or missing keys.
enum Probe {
    static func returnType(_ obj: AnyObject, _ sel: Selector) -> String? {
        guard let cls = object_getClass(obj), let m = class_getInstanceMethod(cls, sel) else { return nil }
        let raw = method_copyReturnType(m)
        defer { free(raw) }
        return String(cString: raw)
    }

    static func scalar(_ obj: AnyObject, _ name: String) -> Double? {
        let sel = NSSelectorFromString(name)
        guard let type = returnType(obj, sel), let cls = object_getClass(obj), let m = class_getInstanceMethod(cls, sel) else { return nil }
        let imp = method_getImplementation(m)
        switch type {
        case "d":
            return unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Double).self)(obj, sel)
        case "f":
            return Double(unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Float).self)(obj, sel))
        case "B", "c":
            return unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Bool).self)(obj, sel) ? 1 : 0
        case "q", "l":
            return Double(unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Int).self)(obj, sel))
        default:
            return nil
        }
    }

    static func point(_ obj: AnyObject, _ name: String) -> CGPoint? {
        let sel = NSSelectorFromString(name)
        guard let type = returnType(obj, sel), type.hasPrefix("{CGPoint"),
              let cls = object_getClass(obj), let m = class_getInstanceMethod(cls, sel) else { return nil }
        return unsafeBitCast(method_getImplementation(m), to: (@convention(c) (AnyObject, Selector) -> CGPoint).self)(obj, sel)
    }

    static func vector(_ obj: AnyObject, _ name: String) -> CGVector? {
        let sel = NSSelectorFromString(name)
        guard let type = returnType(obj, sel), type.hasPrefix("{CGVector"),
              let cls = object_getClass(obj), let m = class_getInstanceMethod(cls, sel) else { return nil }
        return unsafeBitCast(method_getImplementation(m), to: (@convention(c) (AnyObject, Selector) -> CGVector).self)(obj, sel)
    }

    static func object(_ obj: AnyObject, _ name: String) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard let type = returnType(obj, sel), type.hasPrefix("@"),
              let cls = object_getClass(obj), let m = class_getInstanceMethod(cls, sel) else { return nil }
        return unsafeBitCast(method_getImplementation(m), to: (@convention(c) (AnyObject, Selector) -> AnyObject?).self)(obj, sel)
    }
}
