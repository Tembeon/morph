import UIKit
import SwiftUI
import ObjectiveC

/// Liquid Glass MERGE probes (UIGlassContainerEffect / GlassEffectContainer).
///
/// Scenes:
/// - merge: static pages of pairs. Column 1 = capsules 60x44, column 2 = circles 44x44, rows =
///   gaps (MergeLayout.gaps). One container per pair. A tap on the background at x < 24
///   advances to the next spacing page (PROBE_SPACINGS, default 0,10,20,40,80).
///   PROBE_API=uikit|swiftui, PROBE_BG=grey|stripes, PROBE_TINT=1 tints the glass magenta.
/// - mergeDyn: one container (PROBE_SPACING), a fixed capsule and a draggable one; a background
///   tap at x < 24 sweeps the right capsule with UIView.animate (in, then out on the next tap).
/// - mergeID: SwiftUI glassEffectID morph, one capsule <-> two; a background tap toggles.
/// Every page / frame logs `sdf` rows (CASDF* layer properties) through the Recorder.
enum MergeLayout {
    static let gaps: [CGFloat] = [40, 30, 20, 15, 10, 6, 3, 0, -5]
    static let rowY0: CGFloat = 150
    static let rowPitch: CGFloat = 80
    static let capsuleCX: CGFloat = 110
    static let circleCX: CGFloat = 300
    static let capsule = CGSize(width: 60, height: 44)
    static let circle = CGSize(width: 44, height: 44)

    static var spacings: [CGFloat] {
        let raw = ProcessInfo.processInfo.environment["PROBE_SPACINGS"] ?? "0,10,20,40,80"
        return raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { CGFloat($0) }
    }

    struct Pair {
        let kind: String
        let gap: CGFloat
        let size: CGSize
        let cx: CGFloat
        let cy: CGFloat
        var left: CGRect { CGRect(x: cx - gap / 2 - size.width, y: cy - size.height / 2, width: size.width, height: size.height) }
        var right: CGRect { CGRect(x: cx + gap / 2, y: cy - size.height / 2, width: size.width, height: size.height) }
    }

    static var pairs: [Pair] {
        var out: [Pair] = []
        for (i, g) in gaps.enumerated() {
            let y = rowY0 + CGFloat(i) * rowPitch
            out.append(Pair(kind: "capsule", gap: g, size: capsule, cx: capsuleCX, cy: y))
            out.append(Pair(kind: "circle", gap: g, size: circle, cx: circleCX, cy: y))
        }
        return out
    }
}

enum MergeEnv {
    static let env = ProcessInfo.processInfo.environment
    static var tinted: Bool { env["PROBE_TINT"] == "1" }
    static var tint: UIColor { UIColor(red: 1, green: 0, blue: 1, alpha: 1) }
    static var bg: String { env["PROBE_BG"] ?? "grey" }
    static var api: String { env["PROBE_API"] ?? "uikit" }
}

final class MergeBackground: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        if MergeEnv.bg == "stripes" {
            let tile: CGFloat = 16
            let r = UIGraphicsImageRenderer(size: CGSize(width: tile, height: tile))
            let img = r.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: tile, height: tile))
                UIColor.black.setFill()
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: tile / 2, y: 0)); p.addLine(to: CGPoint(x: 0, y: tile / 2)); p.close()
                p.move(to: CGPoint(x: tile, y: 0)); p.addLine(to: CGPoint(x: tile, y: tile / 2)); p.addLine(to: CGPoint(x: tile / 2, y: tile)); p.addLine(to: CGPoint(x: 0, y: tile)); p.close()
                p.fill()
            }
            backgroundColor = UIColor(patternImage: img)
        } else {
            backgroundColor = UIColor(white: 0.5, alpha: 1)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - SDF layer reader

enum SDFDump {
    static func props(_ obj: AnyObject, depth: Int = 0) -> [String: Any] {
        var out: [String: Any] = [:]
        var c: AnyClass? = object_getClass(obj)
        while let cur = c {
            let cn = NSStringFromClass(cur)
            if cn == "CALayer" || cn == "NSObject" || cn == "CAShapeLayer" { break }
            var n: UInt32 = 0
            if let list = class_copyPropertyList(cur, &n) {
                for i in 0..<Int(n) {
                    let name = String(cString: property_getName(list[i]))
                    if out[name] != nil || name.lowercased().contains("delegate") || name.hasPrefix("_") { continue }
                    if let v = read(obj, name, depth: depth) { out[name] = v }
                }
                free(list)
            }
            c = class_getSuperclass(cur)
        }
        return out
    }

    static func read(_ obj: AnyObject, _ name: String, depth: Int) -> Any? {
        let sel = NSSelectorFromString(name)
        guard let cls = object_getClass(obj), let m = class_getInstanceMethod(cls, sel), method_getNumberOfArguments(m) == 2 else { return nil }
        let raw = method_copyReturnType(m)
        let enc = String(cString: raw)
        free(raw)
        let imp = method_getImplementation(m)
        switch enc {
        case "d": return unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Double).self)(obj, sel)
        case "f": return Double(unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Float).self)(obj, sel))
        case "B", "c": return unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Bool).self)(obj, sel)
        case "q", "l", "Q", "L": return unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Int).self)(obj, sel)
        case "i", "I": return Int(unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Int32).self)(obj, sel))
        default:
            if enc.hasPrefix("{CGRect") { let r = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> CGRect).self)(obj, sel); return [r.minX, r.minY, r.width, r.height] }
            if enc.hasPrefix("{CGPoint") { let p = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> CGPoint).self)(obj, sel); return [p.x, p.y] }
            if enc.hasPrefix("{CGSize") { let s = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> CGSize).self)(obj, sel); return [s.width, s.height] }
            if enc.hasPrefix("@") {
                guard let o = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> AnyObject?).self)(obj, sel) else { return nil }
                if let s = o as? String { return s }
                if let num = o as? NSNumber { return num }
                if let a = o as? [AnyObject] { return a.prefix(6).map { "\($0)".prefix(100).description } }
                let cn = NSStringFromClass(type(of: o))
                if depth < 2, cn.hasPrefix("CA") || cn.contains("SDF") || cn.contains("Glass") {
                    var d = props(o, depth: depth + 1)
                    d["__class"] = cn
                    return d
                }
                return "<\(cn)>"
            }
            return nil
        }
    }

    static func interesting(_ cn: String) -> Bool {
        cn.contains("SDF") || cn.contains("Glass") || cn.contains("Backdrop") || cn.contains("Lensing")
    }

    /// Rows for every interesting layer in the window.
    static func rows(window: UIWindow, presentation: Bool) -> [[String: Any]] {
        var out: [[String: Any]] = []
        let wl: CALayer = presentation ? (window.layer.presentation() ?? window.layer) : window.layer
        func visit(_ l: CALayer, _ path: String, _ depth: Int) {
            guard depth < 40 else { return }
            let cn = NSStringFromClass(type(of: l))
            if interesting(cn) {
                let p: CALayer = presentation ? (l.presentation() ?? l) : l
                let box = p.convert(p.bounds, to: wl)
                var row: [String: Any] = ["cls": cn, "path": path,
                                          "x": box.minX, "y": box.minY, "w": box.width, "h": box.height,
                                          "cr": p.cornerRadius, "a": Double(p.opacity), "hid": p.isHidden]
                if let d = l.delegate as? UIView { row["view"] = NSStringFromClass(type(of: d)) }
                if let nm = l.name { row["name"] = nm }
                row["props"] = props(p)
                out.append(row)
            }
            for (i, s) in (l.sublayers ?? []).enumerated() { visit(s, path + "/" + String(i), depth + 1) }
        }
        visit(window.layer, "W", 0)
        return out
    }

    static func describeClassesOnce(window: UIWindow) {
        var seen = Set<String>()
        var text = ""
        func visit(_ l: CALayer) {
            let cn = NSStringFromClass(type(of: l))
            if interesting(cn) && !seen.contains(cn) {
                seen.insert(cn)
                var c: AnyClass? = type(of: l)
                while let cur = c, NSStringFromClass(cur) != "CALayer" {
                    text += "== class \(NSStringFromClass(cur))\n"
                    var n: UInt32 = 0
                    if let ps = class_copyPropertyList(cur, &n) {
                        for i in 0..<Int(n) { text += "  prop \(String(cString: property_getName(ps[i]))) \(property_getAttributes(ps[i]).map { String(cString: $0) } ?? "")\n" }
                        free(ps)
                    }
                    if let ms = class_copyMethodList(cur, &n) {
                        for i in 0..<Int(n) { text += "  meth \(NSStringFromSelector(method_getName(ms[i])))\n" }
                        free(ms)
                    }
                    c = class_getSuperclass(cur)
                }
            }
            l.sublayers?.forEach(visit)
        }
        visit(window.layer)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? text.write(to: docs.appendingPathComponent("merge-layer-classes.txt"), atomically: true, encoding: .utf8)
    }

    static func dumpPage(window: UIWindow, tag: String) {
        let rows = rows(window: window, presentation: false)
        Recorder.shared.log(["k": "sdfpage", "t": CACurrentMediaTime(), "tag": tag, "layers": rows])
        Recorder.shared.flush()
    }
}

/// Per-frame sampler of the SDF layers for the dynamic scenes.
final class SDFFrameSampler: NSObject {
    static let shared = SDFFrameSampler()
    private var link: CADisplayLink?
    private var sig: [String: String] = [:]
    var extra: (() -> [String: Any])?

    func start() {
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        if let e = extra?() { Recorder.shared.log(["k": "gv", "t": link.timestamp].merging(e) { a, _ in a }) }
        for row in SDFDump.rows(window: window, presentation: true) {
            let key = row["path"] as? String ?? "?"
            let s = "\(row)"
            if sig[key] == s { continue }
            sig[key] = s
            var r = row
            r["k"] = "sdf"
            r["t"] = link.timestamp
            Recorder.shared.log(r)
        }
    }
}

// MARK: - Static pages

final class MergeScene: UIViewController {
    private var page = 0
    private let spacings = MergeLayout.spacings
    private var content: UIView?
    private let label = UILabel()
    private let model = MergeModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let bg = MergeBackground(frame: view.bounds)
        bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(bg)
        label.frame = CGRect(x: 30, y: 64, width: 340, height: 20)
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .black
        view.addSubview(label)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        view.addGestureRecognizer(tap)
        if MergeEnv.api == "swiftui" {
            model.spacing = spacings.first ?? 0
            let host = UIHostingController(rootView: MergePageView(model: model))
            host.view.backgroundColor = .clear
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addChild(host)
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
        show()
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: view)
        guard p.x < 24 else { return }
        if page + 1 < spacings.count { page += 1; show() }
    }

    private func show() {
        let s = spacings.isEmpty ? 0 : spacings[page]
        label.text = "api=\(MergeEnv.api) bg=\(MergeEnv.bg) tint=\(MergeEnv.tinted ? 1 : 0) spacing=\(Int(s)) page=\(page)"
        if MergeEnv.api == "swiftui" {
            model.spacing = s
        } else {
            content?.removeFromSuperview()
            let c = UIView(frame: view.bounds)
            c.isUserInteractionEnabled = false
            for pair in MergeLayout.pairs { c.addSubview(MergeScene.makeUIKitPair(pair, spacing: s)) }
            view.insertSubview(c, belowSubview: label)
            content = c
        }
        let pairs = MergeLayout.pairs.map { p -> [String: Any] in
            ["kind": p.kind, "gap": p.gap, "left": [p.left.minX, p.left.minY, p.left.width, p.left.height], "right": [p.right.minX, p.right.minY, p.right.width, p.right.height]]
        }
        Recorder.shared.log(["k": "page", "t": CACurrentMediaTime(), "page": page, "spacing": s, "api": MergeEnv.api, "bg": MergeEnv.bg, "tint": MergeEnv.tinted, "pairs": pairs])
        let tag = "page\(page)-s\(Int(s))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let w = self?.view.window else { return }
            if self?.page == 0 { SDFDump.describeClassesOnce(window: w) }
            SDFDump.dumpPage(window: w, tag: tag)
        }
    }

    static func makeGlass() -> UIGlassEffect {
        let g = UIGlassEffect(style: .regular)
        if MergeEnv.tinted { g.tintColor = MergeEnv.tint }
        g.isInteractive = false
        return g
    }

    static func makeUIKitPair(_ pair: MergeLayout.Pair, spacing: CGFloat) -> UIView {
        let ce = UIGlassContainerEffect()
        ce.spacing = spacing
        let box = pair.left.union(pair.right).insetBy(dx: -20, dy: -16)
        let container = UIVisualEffectView(effect: ce)
        container.frame = box
        for r in [pair.left, pair.right] {
            let g = UIVisualEffectView(effect: makeGlass())
            g.frame = r.offsetBy(dx: -box.minX, dy: -box.minY)
            g.cornerConfiguration = .capsule()
            container.contentView.addSubview(g)
        }
        return container
    }
}

final class MergeModel: ObservableObject {
    @Published var spacing: CGFloat = 0
}

struct MergePageView: View {
    @ObservedObject var model: MergeModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(MergeLayout.pairs.enumerated()), id: \.offset) { _, pair in
                GlassEffectContainer(spacing: model.spacing) {
                    HStack(spacing: pair.gap) {
                        glassShape(pair.size)
                        glassShape(pair.size)
                    }
                }
                .position(x: pair.cx, y: pair.cy)
            }
        }
        .id(model.spacing)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder func glassShape(_ size: CGSize) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .glassEffect(MergeEnv.tinted ? Glass.regular.tint(Color(MergeEnv.tint)) : Glass.regular, in: Capsule())
    }
}

// MARK: - Dynamic

final class MergeDynScene: UIViewController {
    private let container = UIVisualEffectView(effect: nil)
    private let fixed = UIVisualEffectView(effect: MergeScene.makeGlass())
    private let moving = UIVisualEffectView(effect: MergeScene.makeGlass())
    private var animIn = true
    private let cy: CGFloat = 437
    private let leftX: CGFloat = 60
    private let w: CGFloat = 60
    private let h: CGFloat = 44
    private var dragStartX: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        let bg = MergeBackground(frame: view.bounds)
        bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(bg)
        let spacing = CGFloat(Double(MergeEnv.env["PROBE_SPACING"] ?? "20") ?? 20)
        let ce = UIGlassContainerEffect()
        ce.spacing = spacing
        container.effect = ce
        container.frame = CGRect(x: 30, y: cy - 60, width: 360, height: 120)
        view.addSubview(container)
        fixed.frame = CGRect(x: leftX - 30, y: 60 - h / 2, width: w, height: h)
        moving.frame = CGRect(x: leftX - 30 + w + 60, y: 60 - h / 2, width: w, height: h)
        for v in [fixed, moving] {
            v.cornerConfiguration = .capsule()
            container.contentView.addSubview(v)
        }
        moving.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        Recorder.shared.log(["k": "dynsetup", "t": CACurrentMediaTime(), "spacing": spacing, "fixed": rect(fixed), "moving": rect(moving)])
        SDFFrameSampler.shared.extra = { [weak self] in
            guard let self, let wl = self.view.window?.layer.presentation() else { return [:] }
            var out: [String: Any] = [:]
            for (k, v) in [("fx", self.fixed), ("mv", self.moving)] {
                if let p = v.layer.presentation() { let b = p.convert(p.bounds, to: wl); out[k] = [b.minX, b.minY, b.width, b.height] }
            }
            return out
        }
        SDFFrameSampler.shared.start()
    }

    private func rect(_ v: UIView) -> [CGFloat] {
        let r = v.convert(v.bounds, to: nil)
        return [r.minX, r.minY, r.width, r.height]
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        if g.state == .began { dragStartX = moving.frame.minX }
        moving.frame.origin.x = dragStartX + g.translation(in: container).x
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        guard g.location(in: view).x < 24 else { return }
        let fixedRight = fixed.frame.maxX
        let target: CGFloat = animIn ? fixedRight - 10 : fixedRight + 60
        Recorder.shared.log(["k": "anim", "t": CACurrentMediaTime(), "dir": animIn ? "in" : "out", "to": target])
        UIView.animate(withDuration: 2.0, delay: 0, options: [.curveLinear]) {
            self.moving.frame.origin.x = target
        }
        animIn.toggle()
    }
}

final class MergeIDModel: ObservableObject {
    @Published var split = false
}

struct MergeIDView: View {
    @ObservedObject var model: MergeIDModel
    @Namespace private var ns

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 30) {
                    if model.split {
                        shape(60).glassEffectID("a", in: ns)
                        shape(60).glassEffectID("b", in: ns)
                    } else {
                        shape(150).glassEffectID("a", in: ns)
                    }
                }
            }
            .position(x: 201, y: 300)
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 30) {
                    shape(60).glassEffectUnion(id: "u", namespace: ns)
                    shape(60).glassEffectUnion(id: "u", namespace: ns)
                }
            }
            .position(x: 201, y: 560)
            GlassEffectContainer {
                HStack(spacing: 30) {
                    shape(60)
                    shape(60)
                }
            }
            .position(x: 201, y: 760)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    func shape(_ w: CGFloat) -> some View {
        Color.clear.frame(width: w, height: 44)
            .glassEffect(MergeEnv.tinted ? Glass.regular.tint(Color(MergeEnv.tint)) : Glass.regular, in: Capsule())
    }
}

final class MergeIDScene: UIViewController {
    private let model = MergeIDModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let bg = MergeBackground(frame: view.bounds)
        bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(bg)
        let host = UIHostingController(rootView: MergeIDView(model: model))
        host.view.backgroundColor = .clear
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        Recorder.shared.log(["k": "defaults", "t": CACurrentMediaTime(), "uikitContainerSpacing": UIGlassContainerEffect().spacing])
        SDFFrameSampler.shared.start()
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        guard g.location(in: view).x < 24 else { return }
        Recorder.shared.log(["k": "toggle", "t": CACurrentMediaTime(), "split": !model.split])
        withAnimation(.bouncy) { model.split.toggle() }
    }
}
