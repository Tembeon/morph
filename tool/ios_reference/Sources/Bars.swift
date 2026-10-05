import UIKit
import ObjectiveC

/// Navigation bar / toolbar probes (iOS 26/27 bars, scroll edge effect, bar button groups).
///
/// Scene `nav`: a UINavigationController with large titles over a long colorful list, a
/// grouped trailing pair (add + more) and a text leading item, a toolbar with item set A.
/// Options:
/// - PROBE_EDGE=soft|hard|automatic (default automatic) - the scroll view's top/bottom edge
///   effect style;
/// - PROBE_AUTO=scroll|toolbar|push|pushpop|none|all (default none) - a self-driven script on
///   timers (no touches): ramps contentOffset, swaps toolbar items with setToolbarItems(_:
///   animated:), pushes / pops a detail screen with different items;
/// - PROBE_DARK=1 forces dark appearance, PROBE_DARK=0 light;
/// - PROBE_LARGE=0 disables large titles;
/// - PROBE_ROWS=<n> rows (default 80).
/// While the scene runs, `BarsRecorder` logs per display-link tick:
/// - `so` rows (scroll offset, adjusted inset, the top/bottom edge effect styles),
/// - `B` rows for every view under the navigation bar, the toolbar and every scroll pocket /
///   edge effect view, when its presentation geometry changed (window bbox, alpha, transform,
///   corner radius, text, filters with their scalar inputs),
/// - `G` rows for gradient / mask layers under the pockets (colors, locations, start/end).
/// Tree dumps (tree-nav-<tag>.txt) with full layer subtrees are written at script moments.
enum BarsEnv {
    static let env = ProcessInfo.processInfo.environment
    static var edge: String { env["PROBE_EDGE"] ?? "automatic" }
    static var auto: String { env["PROBE_AUTO"] ?? "none" }
    static var rows: Int { Int(env["PROBE_ROWS"] ?? "") ?? 80 }
    static var large: Bool { env["PROBE_LARGE"] != "0" }

    static var edgeStyle: UIScrollEdgeEffect.Style {
        switch edge {
        case "soft": return .soft
        case "hard": return .hard
        default: return .automatic
        }
    }
}

final class BarsNavController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        if let d = BarsEnv.env["PROBE_DARK"] { overrideUserInterfaceStyle = d == "1" ? .dark : .light }
        navigationBar.prefersLargeTitles = BarsEnv.large
        isToolbarHidden = false
    }
}

final class BarsListScene: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let table = UITableView(frame: .zero, style: .plain)
    static let palette: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemIndigo, .systemPurple, .systemPink, .black, .white]

    lazy var itemsA: [UIBarButtonItem] = [
        BarsListScene.tagged(UIBarButtonItem(title: "Filter", style: .plain, target: nil, action: nil), "tbFilter"),
        .flexibleSpace(),
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: nil, action: nil), "tbCompose"),
    ]
    lazy var itemsB: [UIBarButtonItem] = [
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: nil, action: nil), "tbTrash"),
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "folder"), style: .plain, target: nil, action: nil), "tbFolder"),
        .flexibleSpace(),
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "arrowshape.turn.up.left"), style: .plain, target: nil, action: nil), "tbReply"),
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: nil, action: nil), "tbCompose"),
    ]
    lazy var itemsC: [UIBarButtonItem] = [
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: nil, action: nil), "tbTrash"),
        .fixedSpace(),
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "folder"), style: .plain, target: nil, action: nil), "tbFolder"),
        .flexibleSpace(),
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: nil, action: nil), "tbCompose"),
    ]

    static func tagged(_ item: UIBarButtonItem, _ id: String) -> UIBarButtonItem {
        item.accessibilityIdentifier = id
        item.accessibilityLabel = id
        return item
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Inbox"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = BarsEnv.large ? .always : .never
        navigationItem.leftBarButtonItem = BarsListScene.tagged(UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil), "navEdit")
        navigationItem.rightBarButtonItems = [
            BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil), "navMore"),
            BarsListScene.tagged(UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil), "navAdd"),
        ]
        navigationItem.backButtonTitle = "Inbox"
        table.dataSource = self
        table.delegate = self
        table.accessibilityIdentifier = "barsTable"
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.topEdgeEffect.style = BarsEnv.edgeStyle
        table.bottomEdgeEffect.style = BarsEnv.edgeStyle
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        toolbarItems = itemsA
        BarsRecorder.shared.scroll = table
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        BarsRecorder.shared.scroll = table
        BarsScript.shared.startOnce(list: self)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { BarsEnv.rows }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = "Row \(indexPath.row)"
        config.secondaryText = "Liquid glass reference line \(indexPath.row)"
        cell.contentConfiguration = config
        cell.backgroundColor = BarsListScene.palette[indexPath.row % BarsListScene.palette.count].withAlphaComponent(0.85)
        cell.accessibilityIdentifier = "row\(indexPath.row)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        pushDetail()
    }

    func pushDetail() {
        Recorder.shared.log(["k": "evt", "e": "push", "t": CACurrentMediaTime()])
        navigationController?.pushViewController(BarsDetailScene(), animated: true)
    }
}

final class BarsDetailScene: UIViewController {
    let scroll = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Detail"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        let share = BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil), "navShare")
        let heart = BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "heart"), style: .plain, target: nil, action: nil), "navHeart")
        let done = BarsListScene.tagged(UIBarButtonItem(title: "Done", style: .prominent, target: nil, action: nil), "navDone")
        navigationItem.rightBarButtonItems = [done, .fixedSpace(), heart, share]
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.accessibilityIdentifier = "detailScroll"
        scroll.topEdgeEffect.style = BarsEnv.edgeStyle
        scroll.bottomEdgeEffect.style = BarsEnv.edgeStyle
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        for i in 0..<40 {
            let v = UIView()
            v.backgroundColor = BarsListScene.palette[(i * 3) % BarsListScene.palette.count]
            v.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(v)
        }
        toolbarItems = [
            BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "chevron.up"), style: .plain, target: nil, action: nil), "tbUp"),
            BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "chevron.down"), style: .plain, target: nil, action: nil), "tbDown"),
            .flexibleSpace(),
            BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: "arrowshape.turn.up.left"), style: .plain, target: nil, action: nil), "tbReply"),
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        BarsRecorder.shared.scroll = scroll
    }
}

/// The timer-driven script of PROBE_AUTO.
final class BarsScript {
    static let shared = BarsScript()
    private var started = false
    private weak var list: BarsListScene?
    private var ramp: CADisplayLink?
    private var rampFrom: CGFloat = 0
    private var rampTo: CGFloat = 0
    private var rampStart: CFTimeInterval = 0
    private var rampDur: CFTimeInterval = 1

    func startOnce(list: BarsListScene) {
        guard !started else { return }
        started = true
        self.list = list
        let auto = BarsEnv.auto
        if auto == "none" { return }
        var t = 1.5
        func at(_ dt: Double, _ f: @escaping () -> Void) {
            t += dt
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f)
        }
        at(0) { BarsRecorder.shared.dump("rest") }
        if auto == "scroll" || auto == "all" {
            let top = -list.table.adjustedContentInset.top
            at(0.5) { self.scrollRamp(from: top, to: top + 240, duration: 4.8) }
            at(1.2) { BarsRecorder.shared.dump("scroll-mid") }
            at(4.3) { BarsRecorder.shared.dump("scroll-end") }
            at(0.8) { self.scrollRamp(from: top + 240, to: top, duration: 4.8) }
            at(5.6) { BarsRecorder.shared.dump("scroll-back") }
            at(0.5) { self.scrollRamp(from: top, to: top + 600, duration: 1.0) }
            at(2.0) { BarsRecorder.shared.dump("scroll-deep") }
            at(0.5) { self.scrollRamp(from: top + 600, to: top, duration: 1.0) }
            at(2.0) {}
        }
        if auto == "scrollquick" {
            let top = -list.table.adjustedContentInset.top
            at(0.3) { self.scrollRamp(from: top, to: top + 240, duration: 2.4) }
            at(3.0) { self.scrollRamp(from: top + 240, to: top, duration: 2.4) }
            at(3.0) {}
        }
        if auto == "toolbar" || auto == "all" {
            for (name, items) in [("B", list.itemsB), ("A", list.itemsA), ("C", list.itemsC), ("A", list.itemsA)] {
                at(1.6) {
                    Recorder.shared.log(["k": "evt", "e": "setToolbarItems", "set": name, "t": CACurrentMediaTime()])
                    list.setToolbarItems(items, animated: true)
                }
                at(0.12) { BarsRecorder.shared.dump("toolbar-\(name)-mid") }
            }
            at(1.6) {}
        }
        if auto == "push" || auto == "pushpop" || auto == "all" {
            at(1.6) { list.pushDetail() }
            at(0.2) { BarsRecorder.shared.dump("push-mid") }
            at(1.6) { BarsRecorder.shared.dump("push-end") }
            at(0.4) {
                Recorder.shared.log(["k": "evt", "e": "pop", "t": CACurrentMediaTime()])
                list.navigationController?.popViewController(animated: true)
            }
            at(0.2) { BarsRecorder.shared.dump("pop-mid") }
            at(1.6) {}
            if auto == "pushpop" || auto == "all" {
                let top = -list.table.adjustedContentInset.top
                at(0.2) { list.table.setContentOffset(CGPoint(x: 0, y: top + 300), animated: false) }
                at(1.0) { list.pushDetail() }
                at(1.8) {
                    Recorder.shared.log(["k": "evt", "e": "pop", "t": CACurrentMediaTime()])
                    list.navigationController?.popViewController(animated: true)
                }
                at(1.8) {}
            }
        }
        at(0.5) { Recorder.shared.log(["k": "evt", "e": "scriptEnd", "t": CACurrentMediaTime()]); Recorder.shared.flush() }
    }

    private func scrollRamp(from: CGFloat, to: CGFloat, duration: Double) {
        rampFrom = from
        rampTo = to
        rampDur = duration
        rampStart = CACurrentMediaTime()
        Recorder.shared.log(["k": "evt", "e": "ramp", "from": Double(from), "to": Double(to), "dur": duration, "t": rampStart])
        ramp?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(stepRamp(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        ramp = link
    }

    @objc private func stepRamp(_ link: CADisplayLink) {
        guard let table = list?.table else { return }
        let f = min(1, (link.targetTimestamp - rampStart) / rampDur)
        table.contentOffset = CGPoint(x: 0, y: rampFrom + (rampTo - rampFrom) * CGFloat(f))
        if f >= 1 { link.invalidate(); ramp = nil }
    }
}

/// Samples the bars every display-link tick (see the file comment).
final class BarsRecorder: NSObject {
    static let shared = BarsRecorder()
    weak var scroll: UIScrollView?
    private var link: CADisplayLink?
    private var sigs: [ObjectIdentifier: String] = [:]
    private var lastSo = ""
    private var ids: [ObjectIdentifier: Int] = [:]
    static let interesting = "Pocket|EdgeEffect|ScrollEdge|Backdrop|Blur|NavigationBar|Toolbar|BarButton|_UIBar|Glass|Platter|TitleView|LargeTitle|ButtonBar|BackButton|Portal"

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func lid(_ o: AnyObject) -> Int {
        let k = ObjectIdentifier(o)
        if let v = ids[k] { return v }
        let n = ids.count + 1
        ids[k] = n
        return n
    }

    private func r2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }
    private func r4(_ v: CGFloat) -> Double { (Double(v) * 10000).rounded() / 10000 }

    private func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    }

    /// The scalar inputs of a CAFilter, read through its own inputKeys list.
    static func filterInputs(_ f: NSObject) -> [String: Any] {
        var out: [String: Any] = [:]
        if let name = Probe.object(f, "name") as? String { out["name"] = name }
        if let type = Probe.object(f, "type") as? String { out["type"] = type }
        if let keys = Probe.object(f, "inputKeys") as? [String] {
            for key in keys {
                let v = f.value(forKey: key)
                if let n = v as? NSNumber { out[key] = (n.doubleValue * 10000).rounded() / 10000 }
                else if let v, CFGetTypeID(v as CFTypeRef) == CGImage.typeID {
                    let img = v as! CGImage
                    out[key] = ["img": [img.width, img.height], "alpha": BarsRecorder.alphaProfile(img)]
                } else if let v { out[key] = String(String(describing: v).prefix(100)) }
            }
        }
        return out
    }

    /// The alpha of a mask image down its middle column, 33 samples top to bottom, and across
    /// its middle row.
    static func alphaProfile(_ img: CGImage) -> [String: [Double]] {
        let w = img.width, h = img.height
        guard w > 0, h > 0 else { return [:] }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [:] }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var col: [Double] = []
        var row: [Double] = []
        let n = 33
        for i in 0..<n {
            let y = min(h - 1, Int(Double(i) / Double(n - 1) * Double(h - 1)))
            col.append(Double(data[(y * w + w / 2) * 4 + 3]) / 255)
            let x = min(w - 1, Int(Double(i) / Double(n - 1) * Double(w - 1)))
            row.append(Double(data[((h / 2) * w + x) * 4 + 3]) / 255)
        }
        return ["col": col, "row": row]
    }

    private func roots() -> [UIView] {
        var out: [UIView] = []
        func find(_ v: UIView) {
            let n = NSStringFromClass(type(of: v))
            if v is UINavigationBar || v is UIToolbar || n.contains("Pocket") || n.contains("EdgeEffect") || n.contains("ScrollEdge") || n.contains("FloatingBarContainer") || n == "_UINavigationBarLargeTitleView" {
                out.append(v)
                return
            }
            v.subviews.forEach(find)
        }
        windows().forEach(find)
        return out
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if let s = scroll {
            let so = "\(r2(s.contentOffset.y))|\(r2(s.adjustedContentInset.top))|\(s.isTracking)|\(s.isDecelerating)"
            if so != lastSo {
                lastSo = so
                Recorder.shared.log(["k": "so", "t": now, "oy": r2(s.contentOffset.y), "it": r2(s.adjustedContentInset.top), "ib": r2(s.adjustedContentInset.bottom),
                                     "tr": s.isTracking, "dec": s.isDecelerating, "ch": r2(s.contentSize.height), "fh": r2(s.bounds.height)])
            }
        }
        for root in roots() {
            guard let wp = root.window?.layer.presentation() else { continue }
            walk(root, path: NSStringFromClass(type(of: root)), wp: wp, now: now, depth: 0)
        }
    }

    private func walk(_ v: UIView, path: String, wp: CALayer, now: CFTimeInterval, depth: Int) {
        guard depth < 14 else { return }
        logLayer(v.layer, view: v, path: path, wp: wp, now: now)
        if v.isHidden { return }
        for (i, s) in v.subviews.enumerated() { walk(s, path: path + "/" + String(i), wp: wp, now: now, depth: depth + 1) }
        for (i, l) in (v.layer.sublayers ?? []).enumerated() where !(l.delegate is UIView) {
            walkLayer(l, path: path + "/L" + String(i), wp: wp, now: now, depth: depth + 1)
        }
    }

    private func walkLayer(_ l: CALayer, path: String, wp: CALayer, now: CFTimeInterval, depth: Int) {
        guard depth < 18 else { return }
        logLayer(l, view: nil, path: path, wp: wp, now: now)
        for (i, s) in (l.sublayers ?? []).enumerated() where !(s.delegate is UIView) {
            walkLayer(s, path: path + "/L" + String(i), wp: wp, now: now, depth: depth + 1)
        }
    }

    private func logLayer(_ l: CALayer, view: UIView?, path: String, wp: CALayer, now: CFTimeInterval) {
        guard let p = l.presentation() else { return }
        let box = p.convert(p.bounds, to: wp)
        let tf = p.transform
        var row: [String: Any] = [
            "cls": NSStringFromClass(type(of: l)), "path": path,
            "x": r2(box.midX), "y": r2(box.midY), "w": r2(box.width), "h": r2(box.height),
            "bw": r2(p.bounds.width), "bh": r2(p.bounds.height), "a": r4(CGFloat(p.opacity)),
            "sx": r4(tf.m11), "sy": r4(tf.m22), "tx": r2(tf.m41), "ty": r2(tf.m42), "cr": r2(p.cornerRadius),
        ]
        if let view {
            row["view"] = NSStringFromClass(type(of: view))
            if view.alpha != 1 { row["va"] = r4(view.alpha) }
            if let id = view.accessibilityIdentifier, !id.isEmpty { row["aid"] = id }
            if let lbl = view as? UILabel {
                row["text"] = lbl.text ?? ""
                row["font"] = r2(lbl.font.pointSize)
                if let c = lbl.textColor { row["fg"] = rgba(c.cgColor) }
            }
            if view.isHidden { row["hid"] = true }
        }
        if p.isHidden { row["lhid"] = true }
        if let bg = rgba(p.backgroundColor) { row["bg"] = bg }
        if p.mask != nil { row["mask"] = NSStringFromClass(type(of: p.mask!)) }
        if let fl = l.filters as? [NSObject], !fl.isEmpty { row["flt"] = fl.map { BarsRecorder.filterValues($0, layer: p) } }
        logAnimations(l, path: path, now: now)
        if let cf = l.compositingFilter { row["cf"] = String(describing: cf).prefix(60).description }
        if let g = p as? CAGradientLayer {
            row["gcolors"] = (g.colors ?? []).map { rgba(($0 as! CGColor)) ?? [] }
            row["glocs"] = (g.locations ?? []).map { $0.doubleValue }
            row["gse"] = [r4(g.startPoint.x), r4(g.startPoint.y), r4(g.endPoint.x), r4(g.endPoint.y)]
            row["gtype"] = g.type.rawValue
        }
        if let m = p.mask, let g = m as? CAGradientLayer {
            row["mcolors"] = (g.colors ?? []).map { rgba(($0 as! CGColor)) ?? [] }
            row["mlocs"] = (g.locations ?? []).map { $0.doubleValue }
            row["mse"] = [r4(g.startPoint.x), r4(g.startPoint.y), r4(g.endPoint.x), r4(g.endPoint.y)]
            let mb = m.convert(m.bounds, to: wp)
            row["mbox"] = [r2(mb.minX), r2(mb.minY), r2(mb.width), r2(mb.height)]
        }
        let sig = BarsRecorder.signature(row)
        let oid = ObjectIdentifier(l)
        if sigs[oid] == sig { return }
        sigs[oid] = sig
        row["k"] = "B"
        row["t"] = now
        row["lid"] = lid(l)
        Recorder.shared.log(row)
    }

    static func signature(_ v: Any) -> String {
        switch v {
        case let m as [String: Any]: return "{" + m.keys.sorted().map { "\($0):" + signature(m[$0]!) }.joined(separator: ",") + "}"
        case let a as [Any]: return "[" + a.map { signature($0) }.joined(separator: ",") + "]"
        default: return "\(v)"
        }
    }

    /// The inputs of a filter read through the layer's public `filters.<name>.<key>` key paths,
    /// for the keys the known filter types take.
    static func filterValues(_ f: NSObject, layer: CALayer) -> [String: Any] {
        var out: [String: Any] = [:]
        let name = (Probe.object(f, "name") as? String) ?? "?"
        let type = (Probe.object(f, "type") as? String) ?? "?"
        out["name"] = name
        out["type"] = type
        var keys: [String] = []
        switch type {
        case "gaussianBlur": keys = ["inputRadius", "inputNormalizeEdges", "inputHardEdges"]
        case "variableBlur": keys = ["inputRadius", "inputMaskImage", "inputNormalizeEdges", "inputSourceSublayerName"]
        case "colorMatrix": keys = ["inputColorMatrix"]
        case "colorSaturate": keys = ["inputAmount"]
        case "colorBrightness": keys = ["inputAmount"]
        default: keys = []
        }
        for key in keys {
            guard let v = layer.value(forKeyPath: "filters.\(name).\(key)") else { continue }
            if let n = v as? NSNumber { out[key] = (n.doubleValue * 10000).rounded() / 10000 }
            else if CFGetTypeID(v as CFTypeRef) == CGImage.typeID {
                let img = v as! CGImage
                out[key] = ["img": [img.width, img.height], "alpha": BarsRecorder.alphaProfile(img)]
            } else if let val = v as? NSValue, key == "inputColorMatrix" {
                var raw = [Float](repeating: 0, count: 20)
                raw.withUnsafeMutableBytes { buf in val.getValue(buf.baseAddress!, size: MemoryLayout<Float>.size * 20) }
                out[key] = raw.map { (Double($0) * 10000).rounded() / 10000 }
            } else { out[key] = String(String(describing: v).prefix(100)) }
        }
        return out
    }

    private var seenAnims = Set<ObjectIdentifier>()

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
        return String(describing: v).prefix(160).description
    }

    private func logAnimations(_ layer: CALayer, path: String, now: CFTimeInterval) {
        for key in layer.animationKeys() ?? [] {
            guard let anim = layer.animation(forKey: key) else { continue }
            let oid = ObjectIdentifier(anim)
            if seenAnims.contains(oid) { continue }
            seenAnims.insert(oid)
            var row: [String: Any] = ["k": "anim", "t": now, "path": path, "layer": NSStringFromClass(type(of: layer)), "lid": lid(layer), "key": key,
                                      "cls": NSStringFromClass(type(of: anim)), "begin": anim.beginTime, "dur": anim.duration, "speed": anim.speed,
                                      "now": CACurrentMediaTime()]
            if let d = layer.delegate as? UIView { row["view"] = NSStringFromClass(type(of: d)) }
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
                if let vs = a.values, vs.count <= 200 { row["vals"] = vs.map { describeValue($0) } }
            }
            if let g = anim as? CAAnimationGroup { row["sub"] = g.animations?.map { "\(($0 as? CAPropertyAnimation)?.keyPath ?? "?")" } ?? [] }
            Recorder.shared.log(row)
        }
    }

    private func rgba(_ c: CGColor?) -> [Double]? {
        guard let c, let conv = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let comps = conv.components else { return nil }
        return comps.map { (Double($0) * 1000).rounded() / 1000 }
    }

    /// A full view + layer tree dump of the key window.
    func dump(_ tag: String) {
        var out = ""
        func lw(_ l: CALayer, _ d: Int, _ indent: String) {
            guard d < 12 else { return }
            var info = "\(NSStringFromClass(type(of: l))) name=\(l.name ?? "-") frame=\(l.frame) op=\(l.opacity) cr=\(l.cornerRadius) hid=\(l.isHidden)"
            if let fl = l.filters as? [NSObject], !fl.isEmpty { info += " filters=\(fl.map { BarsRecorder.filterValues($0, layer: l) })" }
            if let cf = l.compositingFilter { info += " cf=\(cf)" }
            if let m = l.mask { info += " mask=\(NSStringFromClass(type(of: m))) \(m.frame)" }
            if let g = l as? CAGradientLayer { info += " grad colors=\(g.colors?.count ?? 0) locs=\(g.locations ?? [])" }
            out += indent + "[L] " + info + "\n"
            if let m = l.mask { lw(m, d + 1, indent + "  (mask) ") }
            for s in l.sublayers ?? [] where !(s.delegate is UIView) { lw(s, d + 1, indent + "  ") }
        }
        func walk(_ v: UIView, _ depth: Int) {
            let f = v.convert(v.bounds, to: nil)
            let ind = String(repeating: "  ", count: depth)
            var extra = " a=\(v.alpha) L=\(NSStringFromClass(type(of: v.layer))) cr=\(v.layer.cornerRadius)"
            if v.isHidden { extra += " HIDDEN" }
            if let lbl = v as? UILabel { extra += " text=\(lbl.text ?? "") font=\(lbl.font.pointSize)" }
            if let id = v.accessibilityIdentifier { extra += " #\(id)" }
            out += ind + "\(NSStringFromClass(type(of: v))) \(f)\(extra)\n"
            let n = NSStringFromClass(type(of: v))
            if BarsRecorder.interesting.split(separator: "|").contains(where: { n.contains($0) }) || v is UINavigationBar || v is UIToolbar {
                lw(v.layer, 0, ind + "    ")
            }
            for s in v.subviews { walk(s, depth + 1) }
        }
        for w in windows() { walk(w, 0) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? out.write(to: docs.appendingPathComponent("tree-nav-\(tag).txt"), atomically: true, encoding: .utf8)
        Recorder.shared.log(["k": "evt", "e": "dump", "tag": tag, "t": CACurrentMediaTime()])
    }
}

/// Scene `navseg`: which glass capsule of a navigation bar becomes which on a push or a pop
/// when the pages' leading and trailing groups differ. Five pages over colored stripes:
/// - 0 "Root": large title, no leading item, trailing [plus];
/// - 1 "Alpha": inline title, back button, trailing [share];
/// - 2 no title: a "Cancel" leading item instead of the back button, trailing [heart share]
///   (one group);
/// - 3 "Gamma": back button, no trailing item;
/// - 4 "Delta": large title, back button, trailing [Done (prominent)] and [heart] (two groups).
/// PROBE_SEQ (default "push,push,push,push,pop,pop,pop,pop") runs from 1.5 s, PROBE_GAP
/// seconds apart (default 1.6); `push` pushes the next page, `pop` pops one, `root` pops to the
/// root, `tbA` / `tbB` / `tbC` set the root's toolbar (NavSegPages.toolbar). Every transition logs an `evt` row (e push / pop / root, from / to page). BarsRecorder
/// logs every layer under the bar (cls CASDFElementLayer = one glass capsule; lid = the layer's
/// identity, so a capsule that becomes another keeps its lid). PROBE_LARGE=0 drops the large
/// titles; PROBE_SEQ=none leaves the scene for touches: a tap on a page pushes the next one
/// (BarsUITests.testNavSeg: taps, edge swipes, back button taps).
enum NavSegPages {
    static func item(_ name: String, _ id: String) -> UIBarButtonItem {
        BarsListScene.tagged(UIBarButtonItem(image: UIImage(systemName: name), style: .plain, target: nil, action: nil), id)
    }

    static func configure(_ vc: UIViewController, page: Int) {
        let n = vc.navigationItem
        switch page {
        case 0:
            vc.title = "Root"
            n.largeTitleDisplayMode = BarsEnv.large ? .always : .never
            n.rightBarButtonItems = [item("plus", "segPlus")]
            vc.toolbarItems = toolbar("A")
        case 1:
            vc.title = "Alpha"
            n.largeTitleDisplayMode = .never
            n.rightBarButtonItems = [item("square.and.arrow.up", "segShare")]
        case 2:
            vc.title = nil
            n.largeTitleDisplayMode = .never
            n.leftBarButtonItem = BarsListScene.tagged(UIBarButtonItem(title: "Cancel", primaryAction: UIAction { [weak vc] _ in
                Recorder.shared.log(["k": "evt", "e": "pop", "from": 2, "to": 1, "cancel": true, "t": CACurrentMediaTime()])
                vc?.navigationController?.popViewController(animated: true)
            }), "segCancel")
            n.rightBarButtonItems = [item("heart", "segHeart"), item("square.and.arrow.up", "segShare2")]
        case 3:
            vc.title = "Gamma"
            n.largeTitleDisplayMode = .never
        default:
            vc.title = "Delta"
            n.largeTitleDisplayMode = BarsEnv.large ? .always : .never
            let done = BarsListScene.tagged(UIBarButtonItem(title: "Done", style: .prominent, target: nil, action: nil), "segDone")
            n.rightBarButtonItems = [done, .fixedSpace(), item("heart", "segHeart4")]
        }
    }
}

extension NavSegPages {
    /// Toolbar sets of the root page: A = [flex, compose], B = [trash, flex, compose],
    /// C = [trash, flex] (a side empties or fills while the other keeps its group).
    static func toolbar(_ set: String) -> [UIBarButtonItem] {
        let trash = item("trash", "segTbTrash")
        let compose = item("square.and.pencil", "segTbCompose")
        switch set {
        case "B": return [trash, .flexibleSpace(), compose]
        case "C": return [trash, .flexibleSpace()]
        default: return [.flexibleSpace(), compose]
        }
    }
}

final class NavSegPage: UIViewController {
    let page: Int
    let scroll = UIScrollView()

    init(page: Int) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
        NavSegPages.configure(self, page: page)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.accessibilityIdentifier = "segScroll\(page)"
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        scroll.addGestureRecognizer(tap)
        for i in 0..<30 {
            let v = UIView()
            v.backgroundColor = BarsListScene.palette[(i + page * 2) % BarsListScene.palette.count].withAlphaComponent(0.85)
            v.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(v)
        }
    }

    @objc private func tapped() {
        guard page < 4 else { return }
        Recorder.shared.log(["k": "evt", "e": "push", "from": page, "to": page + 1, "tap": true, "t": CACurrentMediaTime()])
        navigationController?.pushViewController(NavSegPage(page: page + 1), animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        BarsRecorder.shared.scroll = scroll
        if page == 0 { NavSegScript.shared.startOnce(nav: navigationController) }
    }
}

final class NavSegScript {
    static let shared = NavSegScript()
    private var started = false

    func startOnce(nav: UINavigationController?) {
        guard !started, let nav else { return }
        started = true
        let env = BarsEnv.env
        let seq = (env["PROBE_SEQ"] ?? "push,push,push,push,pop,pop,pop,pop").split(separator: ",").map(String.init)
        if seq == ["none"] { return }
        let gap = Double(env["PROBE_GAP"] ?? "") ?? 1.6
        var t = 1.5
        for step in seq {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                let from = (nav.topViewController as? NavSegPage)?.page ?? -1
                switch step {
                case "push":
                    let next = NavSegPage(page: min(4, from + 1))
                    Recorder.shared.log(["k": "evt", "e": "push", "from": from, "to": next.page, "t": CACurrentMediaTime()])
                    nav.pushViewController(next, animated: true)
                case "tbA", "tbB", "tbC":
                    let set = String(step.dropFirst(2))
                    Recorder.shared.log(["k": "evt", "e": "setToolbarItems", "set": set, "t": CACurrentMediaTime()])
                    nav.topViewController?.setToolbarItems(NavSegPages.toolbar(set), animated: true)
                case "root":
                    Recorder.shared.log(["k": "evt", "e": "root", "from": from, "to": 0, "t": CACurrentMediaTime()])
                    nav.popToRootViewController(animated: true)
                default:
                    Recorder.shared.log(["k": "evt", "e": "pop", "from": from, "to": max(0, from - 1), "t": CACurrentMediaTime()])
                    nav.popViewController(animated: true)
                }
            }
            t += gap
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            Recorder.shared.log(["k": "evt", "e": "scriptEnd", "t": CACurrentMediaTime()])
            Recorder.shared.flush()
        }
    }
}
