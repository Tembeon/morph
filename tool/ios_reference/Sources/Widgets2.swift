import UIKit
import QuartzCore
import ObjectiveC

/// Probe scenes for the second widget pass (sheets, search, page control, progress,
/// activity indicator, context menu preview, alerts). Scene names start with "w2".
///
/// Every scene runs `W2Sampler`: each display-link tick it walks every window and logs a
/// `V` row for each view whose class matches the scene's pattern (PROBE_W2TRACK overrides)
/// or that lies under a view with an accessibilityIdentifier starting "w2_" (to
/// PROBE_W2DEPTH levels), only when the row changed. Rows: cls, id (stable per view), par
/// (superview class), x/y/w/h (window bbox of the presentation layer), bw/bh, a (opacity),
/// ea (effective alpha up the chain), cr (corner radius), mc (masked corners), sx/sy/tx/ty
/// (transform), bg (rgba), hid. `anim` rows describe each new CAAnimation once.
/// PROBE_SCRIPT = "action@seconds;..." runs scripted actions after the scene appears
/// (present, dismiss, large, medium, tree, page:<n>, progress:<v>, focus, cancel, search).
enum Widgets2Scenes {
    static func make(_ name: String) -> UIViewController? {
        guard name.hasPrefix("w2") else { return nil }
        let env = ProcessInfo.processInfo.environment
        let pattern: String
        let vc: UIViewController
        switch name {
        case "w2sheet":
            pattern = "UITransitionView|DropShadow|Sheet|Dimming|Grabber|_UIPortal|Zoom|_UIRoundedRectShadow|_UIPresentation|UILayoutContainerView|_UIGlass|Glass"
            vc = SheetHostScene()
        case "w2page":
            pattern = "^NONE$"
            vc = PageControlScene()
        case "w2progress":
            pattern = "^NONE$"
            vc = ProgressScene()
        case "w2ctx":
            pattern = "_UIContextMenu|Platter|Dimming|_UIPreview|_UIMorph|MagicMorph|Portal|_UIReparenting|TransformView|ContextMenuContainer|_UIContentPlatter"
            vc = ContextScene()
        case "w2search":
            pattern = "Search|^UITabBar$|_UITabBar|_UITab|Platter|LiquidLens|_UIBarBackground|_UIButtonBar|UINavigationBar|_UINavigationBar|UIToolbar|_UIToolbar|Cancel|Close"
            vc = SearchScene.make(env["PROBE_SEARCH"] ?? "tab")
        case "w2alert":
            pattern = "Alert|_UIInterfaceAction|Dimming|Platter|_UIMorph|MagicMorph|TransitionView|_UIPopover|Popover|DropShadow"
            vc = AlertScene()
        default:
            pattern = "^NONE$"
            vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
        }
        W2Sampler.shared.start(pattern: env["PROBE_W2TRACK"] ?? pattern)
        return vc
    }
}

final class W2Sampler: NSObject {
    static let shared = W2Sampler()
    private var pattern: NSRegularExpression?
    private var link: CADisplayLink?
    private var sig: [ObjectIdentifier: String] = [:]
    private var ids: [ObjectIdentifier: Int] = [:]
    private var seenAnims = Set<ObjectIdentifier>()
    private var lsig: [ObjectIdentifier: String] = [:]
    private let rootDepth = Int(ProcessInfo.processInfo.environment["PROBE_W2DEPTH"] ?? "7") ?? 7
    private let logAnims = ProcessInfo.processInfo.environment["PROBE_W2ANIMS"] != "0"
    private let filterInputs = ProcessInfo.processInfo.environment["PROBE_W2FILTERS"] == "1"

    func start(pattern raw: String) {
        pattern = try? NSRegularExpression(pattern: raw)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        for w in windows() {
            guard let wp = w.layer.presentation() else { continue }
            walk(w, wp, now, 0, rooted: -1, alpha: 1)
        }
    }

    private func walk(_ v: UIView, _ wp: CALayer, _ now: CFTimeInterval, _ depth: Int, rooted: Int, alpha: Double) {
        guard depth < 60 else { return }
        let name = NSStringFromClass(type(of: v))
        let pres = v.layer.presentation() ?? v.layer
        let ea = alpha * Double(pres.opacity) * (v.isHidden ? 0 : 1)
        var r = rooted
        if r < 0, let id = v.accessibilityIdentifier, id.hasPrefix("w2_") { r = 0 }
        let inRoot = r >= 0 && r <= rootDepth
        let match = inRoot || pattern?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        if match { sample(v, pres, wp, now, name, ea) }
        for s in v.subviews { walk(s, wp, now, depth + 1, rooted: r >= 0 ? r + 1 : -1, alpha: ea) }
    }

    private func rgba(_ c: CGColor?) -> [Double]? {
        guard let c, let s = CGColorSpace(name: CGColorSpace.sRGB),
              let conv = c.converted(to: s, intent: .defaultIntent, options: nil), let comps = conv.components else { return nil }
        return comps.map { (Double($0) * 1000).rounded() / 1000 }
    }

    private func r2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }
    private func r4(_ v: CGFloat) -> Double { (Double(v) * 10000).rounded() / 10000 }

    private func sample(_ v: UIView, _ p: CALayer, _ wp: CALayer, _ now: CFTimeInterval, _ cls: String, _ ea: Double) {
        let oid = ObjectIdentifier(v)
        let id = ids[oid] ?? { let n = ids.count + 1; ids[oid] = n; return n }()
        let box = p.convert(p.bounds, to: wp)
        let tf = p.transform
        var row: [String: Any] = [
            "cls": cls, "id": id,
            "x": r2(box.midX), "y": r2(box.midY), "w": r2(box.width), "h": r2(box.height),
            "bw": r2(p.bounds.width), "bh": r2(p.bounds.height),
            "a": r4(CGFloat(p.opacity)), "ea": r4(CGFloat(ea)), "cr": r2(p.cornerRadius),
            "sx": r4(tf.m11), "sy": r4(tf.m22), "tx": r2(tf.m41), "ty": r2(tf.m42),
        ]
        if tf.m12 != 0 { row["rot"] = r4(atan2(tf.m12, tf.m11)) }
        if p.maskedCorners != [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] { row["mc"] = Int(p.maskedCorners.rawValue) }
        if let bg = rgba(p.backgroundColor), bg.count == 4, bg[3] > 0 { row["bg"] = bg }
        if let rr = radii(p) { row["radii"] = rr }
        if p.shadowOpacity > 0 { row["sh"] = [r4(CGFloat(p.shadowOpacity)), r2(p.shadowRadius), r2(p.shadowOffset.height)] }
        if v.isHidden { row["hid"] = true }
        if let par = v.superview { row["par"] = NSStringFromClass(type(of: par)) }
        if let aid = v.accessibilityIdentifier, !aid.isEmpty { row["aid"] = aid }
        if let pv = v as? UIProgressView { row["pv"] = Double(pv.progress) }
        if let pc = v as? UIPageControl { row["page"] = pc.currentPage }
        if let fl = p.filters as? [NSObject], !fl.isEmpty {
            let names = fl.map { (Probe.object($0, "name") as? String) ?? "?" }
            row["flt"] = names
            if filterInputs {
                var inputs: [String: Double] = [:]
                for n in names where n != "?" {
                    for key in ["inputRadius", "inputAmount", "inputScale", "inputBias"] {
                        if let num = p.value(forKeyPath: "filters.\(n).\(key)") as? NSNumber { inputs["\(n).\(key)"] = r4(CGFloat(num.doubleValue)) }
                    }
                }
                if !inputs.isEmpty { row["fin"] = inputs }
            }
        }
        let s = row.description
        if sig[oid] != s {
            sig[oid] = s
            row["k"] = "V"
            row["t"] = now
            Recorder.shared.log(row)
        }
        if logAnims { anims(v.layer, cls, id, now) }
        sublayers(v.layer, wp, id, now)
    }

    private func radii(_ p: CALayer) -> [Double]? {
        guard let v = p.value(forKey: "cornerRadii") as? NSValue, String(cString: v.objCType).hasPrefix("{CACornerRadii") else { return nil }
        var raw = [Double](repeating: 0, count: 8)
        raw.withUnsafeMutableBytes { buf in v.getValue(buf.baseAddress!, size: MemoryLayout<Double>.size * 8) }
        return raw.contains(where: { $0 != 0 }) ? raw.map { r2(CGFloat($0)) } : nil
    }

    private func sublayers(_ layer: CALayer, _ wp: CALayer, _ id: Int, _ now: CFTimeInterval) {
        func visit(_ l: CALayer, _ path: String, _ d: Int) {
            guard d <= 3 else { return }
            for (i, sl) in (l.sublayers ?? []).enumerated() where !(sl.delegate is UIView) {
                let p = sl.presentation() ?? sl
                let box = p.convert(p.bounds, to: wp)
                var row: [String: Any] = ["vid": id, "p": path + "." + String(i), "cls": NSStringFromClass(type(of: sl)),
                    "x": r2(box.midX), "y": r2(box.midY), "w": r2(box.width), "h": r2(box.height),
                    "a": r4(CGFloat(p.opacity)), "cr": r2(p.cornerRadius)]
                if let rr = radii(p) { row["radii"] = rr }
                if let nm = sl.name { row["name"] = String(nm.prefix(60)) }
                if p.isHidden { row["hid"] = true }
                if let bg = rgba(p.backgroundColor), bg.count == 4, bg[3] > 0 { row["bg"] = bg }
                if let fl = p.filters as? [NSObject], !fl.isEmpty { row["flt"] = fl.map { (Probe.object($0, "name") as? String) ?? "?" } }
                let key = ObjectIdentifier(sl)
                let s = row.description
                if lsig[key] != s {
                    lsig[key] = s
                    row["k"] = "VL"
                    row["t"] = now
                    Recorder.shared.log(row)
                }
                visit(sl, path + "." + String(i), d + 1)
            }
        }
        visit(layer, "0", 0)
    }

    private func value(_ v: Any?) -> Any {
        guard let v else { return NSNull() }
        if let n = v as? NSNumber { return n.doubleValue }
        if let val = v as? NSValue { return String(describing: val).prefix(160).description }
        return String(describing: v).prefix(120).description
    }

    private func anims(_ layer: CALayer, _ cls: String, _ id: Int, _ now: CFTimeInterval) {
        func visit(_ l: CALayer, _ d: Int) {
            guard d < 4 else { return }
            for key in l.animationKeys() ?? [] {
                guard let a = l.animation(forKey: key) else { continue }
                let oid = ObjectIdentifier(a)
                if seenAnims.contains(oid) { continue }
                seenAnims.insert(oid)
                var row: [String: Any] = ["k": "anim", "t": now, "view": cls, "id": id, "depth": d, "layer": NSStringFromClass(type(of: l)),
                                          "key": key, "cls": NSStringFromClass(type(of: a)), "begin": a.beginTime, "dur": a.duration, "speed": a.speed,
                                          "rep": a.repeatCount]
                if let pa = a as? CAPropertyAnimation { row["kp"] = pa.keyPath ?? ""; row["additive"] = pa.isAdditive }
                if let ba = a as? CABasicAnimation {
                    row["from"] = value(ba.fromValue); row["to"] = value(ba.toValue)
                    if let tfn = ba.timingFunction { var c1: [Float] = [0, 0]; var c2: [Float] = [0, 0]; tfn.getControlPoint(at: 1, values: &c1); tfn.getControlPoint(at: 2, values: &c2); row["tf"] = [c1[0], c1[1], c2[0], c2[1]] }
                }
                if let sa = a as? CASpringAnimation { row["mass"] = sa.mass; row["stiff"] = sa.stiffness; row["damp"] = sa.damping; row["v0"] = sa.initialVelocity }
                if let ka = a as? CAKeyframeAnimation {
                    if let vs = ka.values, vs.count <= 200 { row["vals"] = vs.map { value($0) } }
                    row["ktimes"] = ka.keyTimes?.map { $0.doubleValue } ?? []
                }
                if let g = a as? CAAnimationGroup { row["sub"] = g.animations?.map { ($0 as? CAPropertyAnimation)?.keyPath ?? "?" } ?? [] }
                Recorder.shared.log(row)
            }
            for s in l.sublayers ?? [] where !(s.delegate is UIView) { visit(s, d + 1) }
        }
        visit(layer, 0)
    }

    func tree(_ name: String) {
        var out = ""
        func walk(_ v: UIView, _ depth: Int) {
            let f = v.convert(v.bounds, to: nil)
            var extra = " a=\(v.alpha) cr=\(v.layer.cornerRadius) L=\(NSStringFromClass(type(of: v.layer)))"
            if v.isHidden { extra += " HIDDEN" }
            if let bg = v.backgroundColor { extra += " bg=\(bg)" }
            if let lbl = v as? UILabel { extra += " text=\(lbl.text ?? "")" }
            if let fl = v.layer.filters, !fl.isEmpty { extra += " filters=\(fl.count)" }
            out += String(repeating: "  ", count: depth) + "\(NSStringFromClass(type(of: v))) \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))\(v.accessibilityIdentifier.map { " #\($0)" } ?? "")\(extra)\n"
            for s in v.subviews { walk(s, depth + 1) }
        }
        for w in windows() { walk(w, 0) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? out.write(to: docs.appendingPathComponent(name), atomically: true, encoding: .utf8)
        Recorder.shared.flush()
    }
}

/// Runs PROBE_SCRIPT actions ("name@seconds;...") relative to the first appearance.
class W2ScriptedScene: UIViewController {
    let env = ProcessInfo.processInfo.environment
    private var scripted = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !scripted else { return }
        scripted = true
        let script = env["PROBE_SCRIPT"] ?? ""
        for item in script.split(separator: ";") {
            let parts = item.split(separator: "@")
            guard parts.count == 2, let at = Double(parts[1]) else { continue }
            let action = String(parts[0])
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                Recorder.shared.log(["k": "evt", "e": "script", "a": action, "t": CACurrentMediaTime()])
                self?.run(action)
            }
        }
    }

    func run(_ action: String) {
        if action.hasPrefix("tree") { W2Sampler.shared.tree("tree-\(action).txt") }
    }

    func label(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .preferredFont(forTextStyle: .body)
        return l
    }
}

// MARK: sheets

final class SheetHostScene: W2ScriptedScene, UISheetPresentationControllerDelegate {
    let button = UIButton(configuration: .glass())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let stripes = UIStackView()
        stripes.axis = .vertical
        stripes.distribution = .fillEqually
        stripes.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stripes)
        let colors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemIndigo, .systemPurple]
        for i in 0..<16 {
            let s = UIView()
            s.backgroundColor = colors[i % colors.count].withAlphaComponent(0.35)
            stripes.addArrangedSubview(s)
        }
        NSLayoutConstraint.activate([
            stripes.leadingAnchor.constraint(equalTo: view.leadingAnchor), stripes.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stripes.topAnchor.constraint(equalTo: view.topAnchor), stripes.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        var config = UIButton.Configuration.glass()
        config.title = "Present"
        button.configuration = config
        button.accessibilityIdentifier = "w2_present"
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.topAnchor, constant: CGFloat(Double(env["PROBE_BTN_Y"] ?? "") ?? 300)),
            button.widthAnchor.constraint(equalToConstant: 140), button.heightAnchor.constraint(equalToConstant: 48),
        ])
        button.addTarget(self, action: #selector(present(_:)), for: .touchUpInside)
    }

    @objc func present(_ sender: Any?) {
        Recorder.shared.log(["k": "evt", "e": "present", "t": CACurrentMediaTime()])
        let content = SheetContentScene()
        let style = env["PROBE_STYLE"] ?? "page"
        content.modalPresentationStyle = style == "form" ? .formSheet : .pageSheet
        if env["PROBE_ZOOM"] == "1" {
            content.preferredTransition = .zoom { [weak self] _ in self?.button }
        }
        if let sheet = content.sheetPresentationController {
            let detents = env["PROBE_DETENTS"] ?? "ml"
            var list: [UISheetPresentationController.Detent] = []
            if detents.contains("s") { list.append(.custom(identifier: .init("small")) { _ in 200 }) }
            if detents.contains("m") { list.append(.medium()) }
            if detents.contains("l") { list.append(.large()) }
            list.append(.custom(identifier: .init("probe")) { ctx in
                Recorder.shared.log(["k": "evt", "e": "detentContext", "max": ctx.maximumDetentValue,
                                     "medium": UISheetPresentationController.Detent.medium().resolvedValue(in: ctx) ?? -1,
                                     "large": UISheetPresentationController.Detent.large().resolvedValue(in: ctx) ?? -1, "t": CACurrentMediaTime()])
                return nil
            })
            sheet.detents = list
            sheet.prefersGrabberVisible = env["PROBE_GRABBER"] != "0"
            sheet.delegate = self
            if env["PROBE_UNDIMMED"] == "m" { sheet.largestUndimmedDetentIdentifier = .medium }
            if env["PROBE_SCROLLEXPAND"] == "0" { sheet.prefersScrollingExpandsWhenScrolledToEdge = false }
            if env["PROBE_EDGE"] == "1" { sheet.prefersEdgeAttachedInCompactHeight = true }
            if let start = env["PROBE_START"] { sheet.selectedDetentIdentifier = start == "l" ? .large : .medium }
        }
        present(content, animated: true)
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: UISheetPresentationController) {
        Recorder.shared.log(["k": "evt", "e": "detent", "v": sheet.selectedDetentIdentifier?.rawValue ?? "nil", "t": CACurrentMediaTime()])
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Recorder.shared.log(["k": "evt", "e": "dismissed", "t": CACurrentMediaTime()])
    }

    override func run(_ action: String) {
        super.run(action)
        let sheet = presentedViewController?.sheetPresentationController
        switch action {
        case "present": present(nil)
        case "dismiss": dismiss(animated: true)
        case "large": sheet?.animateChanges { sheet?.selectedDetentIdentifier = .large }
        case "medium": sheet?.animateChanges { sheet?.selectedDetentIdentifier = .medium }
        case "small": sheet?.animateChanges { sheet?.selectedDetentIdentifier = .init("small") }
        case "settings": dumpSheetSettings()
        default: break
        }
    }

    private func dumpSheetSettings() {
        let text = SettingsDump.run(pattern: env["PROBE_SETTINGS_RE"] ?? "Sheet|Presentation|Search|PageControl|Progress|ActivityIndicator|ContextMenu|Alert|Zoom|Grabber|Detent")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? text.write(to: docs.appendingPathComponent("settings-w2.txt"), atomically: true, encoding: .utf8)
    }
}

final class SheetContentScene: UIViewController, UITableViewDataSource {
    override func viewDidLoad() {
        super.viewDidLoad()
        let env = ProcessInfo.processInfo.environment
        if env["PROBE_SHEETBG"] == "1" { view.backgroundColor = .systemBackground }
        view.accessibilityIdentifier = "sheetContent"
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.backgroundColor = .clear
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        table.accessibilityIdentifier = "sheetTable"
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 40 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        var c = cell.defaultContentConfiguration()
        c.text = "Row \(indexPath.row)"
        cell.contentConfiguration = c
        return cell
    }
}

// MARK: small controls

final class PageControlScene: W2ScriptedScene {
    let pc = UIPageControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        pc.numberOfPages = Int(env["PROBE_PAGES"] ?? "5") ?? 5
        pc.currentPage = 0
        switch env["PROBE_PCSTYLE"] ?? "auto" {
        case "prominent": pc.backgroundStyle = .prominent
        case "minimal": pc.backgroundStyle = .minimal
        default: pc.backgroundStyle = .automatic
        }
        if let d = env["PROBE_PCTIMER"], let s = Double(d) { pc.progress = UIPageControlTimerProgress(preferredDuration: s) }
        pc.accessibilityIdentifier = "w2_pc"
        pc.addTarget(self, action: #selector(changed), for: .valueChanged)
        pc.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pc)
        NSLayoutConstraint.activate([
            pc.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pc.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 400),
        ])
        if let timer = pc.progress as? UIPageControlTimerProgress { timer.resumeTimer() }
    }

    @objc func changed() {
        Recorder.shared.log(["k": "evt", "e": "valueChanged", "v": pc.currentPage, "t": CACurrentMediaTime()])
    }

    override func run(_ action: String) {
        super.run(action)
        if action.hasPrefix("page:"), let n = Int(action.dropFirst(5)) { pc.currentPage = n }
        if action.hasPrefix("pagea:"), let n = Int(action.dropFirst(6)) { UIView.animate(withDuration: 0.3) { self.pc.currentPage = n } }
    }
}

final class ProgressScene: W2ScriptedScene {
    let pv = UIProgressView(progressViewStyle: .default)
    let bar = UIProgressView(progressViewStyle: .bar)
    let ai = UIActivityIndicatorView(style: .medium)
    let ail = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        pv.progress = Float(Double(env["PROBE_PV0"] ?? "") ?? 0.2)
        bar.progress = 0.2
        pv.accessibilityIdentifier = "w2_pv"
        bar.accessibilityIdentifier = "w2_bar"
        ai.accessibilityIdentifier = "w2_ai"
        ail.accessibilityIdentifier = "w2_ail"
        for (v, y) in [(pv as UIView, 300.0), (bar, 360.0), (ai, 440.0), (ail, 540.0)] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
            var cs = [v.centerXAnchor.constraint(equalTo: view.centerXAnchor), v.centerYAnchor.constraint(equalTo: view.topAnchor, constant: y)]
            if v is UIProgressView { cs.append(v.widthAnchor.constraint(equalToConstant: 300)) }
            NSLayoutConstraint.activate(cs)
        }
        if env["PROBE_AI"] != "0" { ai.startAnimating(); ail.startAnimating() }
    }

    override func run(_ action: String) {
        super.run(action)
        if action.hasPrefix("progress:"), let v = Float(action.dropFirst(9)) { pv.setProgress(v, animated: true); bar.setProgress(v, animated: true) }
        if action.hasPrefix("progressn:"), let v = Float(action.dropFirst(10)) { pv.setProgress(v, animated: false) }
        if action == "stop" { ai.stopAnimating(); ail.stopAnimating() }
        if action == "start" { ai.startAnimating(); ail.startAnimating() }
    }
}

// MARK: context menu

final class ContextScene: W2ScriptedScene, UIContextMenuInteractionDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let w = CGFloat(Double(env["PROBE_CW"] ?? "") ?? 120)
        let h = CGFloat(Double(env["PROBE_CH"] ?? "") ?? 80)
        let y = CGFloat(Double(env["PROBE_CY"] ?? "") ?? 300)
        let card = UIView()
        card.backgroundColor = .systemBlue
        card.layer.cornerRadius = 16
        card.accessibilityIdentifier = "w2_card"
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor), card.centerYAnchor.constraint(equalTo: view.topAnchor, constant: y),
            card.widthAnchor.constraint(equalToConstant: w), card.heightAnchor.constraint(equalToConstant: h),
        ])
        card.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        Recorder.shared.log(["k": "evt", "e": "configuration", "t": CACurrentMediaTime()])
        let count = Int(env["PROBE_ITEMS"] ?? "3") ?? 3
        let titles = ["Copy", "Share", "Delete", "Rename", "Duplicate", "Move"]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: (0..<min(6, count)).map { i in
                UIAction(title: titles[i], attributes: titles[i] == "Delete" ? .destructive : []) { _ in
                    Recorder.shared.log(["k": "evt", "e": "action", "t": CACurrentMediaTime(), "title": titles[i]])
                }
            })
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        Recorder.shared.log(["k": "evt", "e": "willDisplay", "t": CACurrentMediaTime()])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { W2Sampler.shared.tree("tree-ctx-open.txt") }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        Recorder.shared.log(["k": "evt", "e": "willEnd", "t": CACurrentMediaTime()])
    }
}

// MARK: search

enum SearchScene {
    static func make(_ variant: String) -> UIViewController {
        switch variant {
        case "nav":
            let nav = UINavigationController(rootViewController: SearchListScene(bottom: false))
            return nav
        case "toolbar":
            let nav = UINavigationController(rootViewController: SearchListScene(bottom: true))
            nav.isToolbarHidden = false
            return nav
        default:
            let tabs = SearchTabsScene()
            return tabs
        }
    }
}

final class SearchTabsScene: UITabBarController {
    var list: SearchListScene?
    private var scripted = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !scripted else { return }
        scripted = true
        for item in (ProcessInfo.processInfo.environment["PROBE_SCRIPT"] ?? "").split(separator: ";") {
            let parts = item.split(separator: "@")
            guard parts.count == 2, let at = Double(parts[1]) else { continue }
            let action = String(parts[0])
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                Recorder.shared.log(["k": "evt", "e": "script", "a": action, "t": CACurrentMediaTime()])
                guard let self else { return }
                switch action {
                case "tab:search": self.selectedTab = self.tabs.last
                case "tab:home": self.selectedTab = self.tabs.first
                default:
                    if action.hasPrefix("tree") { W2Sampler.shared.tree("tree-\(action).txt") } else { self.list?.run(action) }
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let home = UITab(title: "Home", image: UIImage(systemName: "house"), identifier: "home") { _ in
            let vc = UIViewController(); vc.view.backgroundColor = .systemBackground; return vc
        }
        let library = UITab(title: "Library", image: UIImage(systemName: "books.vertical"), identifier: "library") { _ in
            let vc = UIViewController(); vc.view.backgroundColor = .systemBackground; return vc
        }
        let search = UISearchTab { [weak self] _ in
            let list = SearchListScene(bottom: false)
            self?.list = list
            return UINavigationController(rootViewController: list)
        }
        tabs = [home, library, search]
        if ProcessInfo.processInfo.environment["PROBE_MINIMIZE"] == "1" { tabBarMinimizeBehavior = .onScrollDown }
    }
}

final class SearchListScene: W2ScriptedScene, UITableViewDataSource, UISearchResultsUpdating, UISearchControllerDelegate {
    let bottom: Bool
    let search = UISearchController(searchResultsController: nil)
    init(bottom: Bool) { self.bottom = bottom; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        search.searchResultsUpdater = self
        search.delegate = self
        search.searchBar.accessibilityIdentifier = "w2_searchbar"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        if bottom {
            navigationItem.preferredSearchBarPlacement = .integrated
            toolbarItems = [navigationItem.searchBarPlacementBarButtonItem]
        }
        let table = UITableView(frame: view.bounds, style: .plain)
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        view.addSubview(table)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 40 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        var c = cell.defaultContentConfiguration(); c.text = "Item \(indexPath.row)"; cell.contentConfiguration = c
        return cell
    }

    func updateSearchResults(for searchController: UISearchController) {}
    func willPresentSearchController(_ searchController: UISearchController) { Recorder.shared.log(["k": "evt", "e": "willPresentSearch", "t": CACurrentMediaTime()]) }
    func didPresentSearchController(_ searchController: UISearchController) { Recorder.shared.log(["k": "evt", "e": "didPresentSearch", "t": CACurrentMediaTime()]) }
    func willDismissSearchController(_ searchController: UISearchController) { Recorder.shared.log(["k": "evt", "e": "willDismissSearch", "t": CACurrentMediaTime()]) }
    func didDismissSearchController(_ searchController: UISearchController) { Recorder.shared.log(["k": "evt", "e": "didDismissSearch", "t": CACurrentMediaTime()]) }

    override func run(_ action: String) {
        super.run(action)
        switch action {
        case "focus": search.isActive = true; search.searchBar.searchTextField.becomeFirstResponder()
        case "cancel": search.isActive = false
        case "type": search.searchBar.text = "Item 1"
        default: break
        }
    }
}

// MARK: alerts

final class AlertScene: W2ScriptedScene {
    let source = UIButton(configuration: .glass())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        var c = UIButton.Configuration.glass()
        c.title = "Show"
        source.configuration = c
        source.accessibilityIdentifier = "w2_source"
        source.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(source)
        NSLayoutConstraint.activate([
            source.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            source.centerYAnchor.constraint(equalTo: view.topAnchor, constant: CGFloat(Double(env["PROBE_BTN_Y"] ?? "") ?? 600)),
            source.widthAnchor.constraint(equalToConstant: 120), source.heightAnchor.constraint(equalToConstant: 48),
        ])
        source.addTarget(self, action: #selector(showAlert), for: .touchUpInside)
    }

    @objc func showAlert() {
        let sheet = env["PROBE_ALERT"] == "sheet"
        let alert = UIAlertController(title: "Title", message: "A message for the alert.", preferredStyle: sheet ? .actionSheet : .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in Recorder.shared.log(["k": "evt", "e": "action", "t": CACurrentMediaTime()]) })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in Recorder.shared.log(["k": "evt", "e": "action", "t": CACurrentMediaTime()]) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in Recorder.shared.log(["k": "evt", "e": "action", "t": CACurrentMediaTime()]) })
        if sheet { alert.popoverPresentationController?.sourceView = source }
        Recorder.shared.log(["k": "evt", "e": "present", "t": CACurrentMediaTime()])
        present(alert, animated: true)
    }

    override func run(_ action: String) {
        super.run(action)
        if action == "show" { showAlert() }
        if action == "dismiss" { dismiss(animated: true) }
    }
}
