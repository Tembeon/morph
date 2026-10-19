import UIKit
import QuartzCore

/// Adaptive bar brightness scene "abright" (spec/adaptive-brightness-capture.md): bars over
/// content of a known luma, to see whether bar glass and glyphs switch between a light and a
/// dark look, at which luma, and how fast.
///
/// PROBE_AB_BARS: all (tab bar + navigation bar + toolbar, default), tab, toolbar,
///   search (tab bar with a search tab), searchbar (toolbar with a bottom search field).
/// PROBE_AB_HOST: scroll (default, the content is a scroll view's, so the bars get the scroll
///   pocket) or static (a plain view, no scroll view: only the glass itself can adapt).
/// PROBE_AB_CONTENT: solid (default), stripes:<pt>[:<a>,<b>] (two greys alternating, default
///   black / white), ladder:<pt>[:<steps>] (greys 0 ... 1 from the top in 1/steps), split
///   (white and black parts moved by left / edge / edgeb).
/// PROBE_AB_METER: 1 (default) hidden luma meters over the content under each bar, logged as
///   `lm` rows; visible: the same, shown; 0: none.
/// PROBE_SCRIPT = "action@seconds;..." relative to the start: a tap anywhere on the content, or
///   PROBE_AB_AUTOSTART seconds after the scene appears. Actions: grey:<g>, rgb:<r>,<g>,<b>,
///   left:<f> (white left of f of the width), edge:<y> (white above window y, black below; a
///   negative y counts from the window's bottom), edgeb:<y> (black above, white below), offset:<y>, scroll:<pt/s>,<seconds>, top, crops, tree.
/// Rows: abstart (environment, UIKit defaults read, band layout), go, step (applied action),
///   off (content offset), abs (per bar: its style and its glyphs' and labels' style and colour,
///   only when changed), lm (meter luma), abcrops (window boxes for the film / screenshots).
/// PROBE_DARK must stay unset: a fixed window style stops UIKit's luma tracking.
enum AdaptiveBrightnessScenes {
    static func make(_ name: String) -> UIViewController? {
        guard name == "abright" else { return nil }
        let env = ProcessInfo.processInfo.environment
        X3Sampler.shared.start(pattern: env["PROBE_X3TRACK"] ?? "^UITabBar$|_UITabBar|_UITab|FloatingTabBar|^UINavigationBar$|_UINavigationBar|^UIToolbar$|_UIToolbar|_UIButtonBar|Search|UILabel|UIImageView")
        let bars = env["PROBE_AB_BARS"] ?? "all"
        let content = ABController(bars: bars)
        let nav = UINavigationController(rootViewController: content)
        nav.isToolbarHidden = !["all", "toolbar", "searchbar"].contains(bars)
        if bars == "toolbar" || bars == "searchbar" { return nav }
        let tabs = UITabBarController()
        let plain: (String) -> UIViewController = { title in
            let vc = UIViewController()
            vc.title = title
            vc.view.backgroundColor = .systemBackground
            return vc
        }
        let home = UITab(title: "Home", image: UIImage(systemName: "house"), identifier: "home") { _ in nav }
        let star = UITab(title: "Star", image: UIImage(systemName: "star"), identifier: "star") { _ in plain("Star") }
        if bars == "search" {
            tabs.tabs = [home, star, UISearchTab { _ in UINavigationController(rootViewController: plain("Search")) }]
        } else {
            let gear = UITab(title: "Settings", image: UIImage(systemName: "gear"), identifier: "gear") { _ in plain("Settings") }
            tabs.tabs = [home, star, gear]
        }
        return tabs
    }
}

/// A content view of solid colour, stripes, a grey ladder or a white / black split.
final class ABContent: UIView {
    enum Mode { case solid, stripes, ladder, split }

    let mode: Mode
    let spec: String
    private let solid = UIView()
    private let white = UIView()
    private let black = UIView()
    private var bandViews: [UIView] = []
    private(set) var bands: [(y0: CGFloat, y1: CGFloat, rgb: [Double])] = []

    init(spec: String) {
        self.spec = spec
        let parts = spec.split(separator: ":").map(String.init)
        switch parts.first {
        case "stripes": mode = .stripes
        case "ladder": mode = .ladder
        case "split": mode = .split
        default: mode = .solid
        }
        super.init(frame: .zero)
        solid.backgroundColor = ABContent.grey(0)
        white.backgroundColor = ABContent.grey(1)
        black.backgroundColor = ABContent.grey(0)
        switch mode {
        case .solid: addSubview(solid)
        case .split:
            addSubview(white)
            addSubview(black)
        case .stripes, .ladder: break
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    static func grey(_ g: Double) -> UIColor { UIColor(red: g, green: g, blue: g, alpha: 1) }

    /// Lays the content out in its own coordinates from `top` (negative: above the scroll
    /// content's origin) to `top + height`; bands start at 0.
    func layout(width: CGFloat, top: CGFloat, screen: CGFloat) -> CGFloat {
        let parts = spec.split(separator: ":").map(String.init)
        var height = 4 * screen
        bands = []
        switch mode {
        case .solid:
            solid.frame = CGRect(x: 0, y: 0, width: width, height: height)
        case .split:
            setSplit(left: 1, edge: nil, whiteAbove: true, width: width, height: height)
        case .stripes:
            let pt = CGFloat(Double(parts.count > 1 ? parts[1] : "") ?? 300)
            let greys = (parts.count > 2 ? parts[2] : "0,1").split(separator: ",").compactMap { Double($0) }
            let a = greys.first ?? 0, b = greys.count > 1 ? greys[1] : 1
            let count = Int((10 * screen / pt).rounded(.up)) + 1
            var y = top
            for i in 0..<count {
                let g = i % 2 == 0 ? a : b
                bands.append((y, y + pt, [g, g, g]))
                y += pt
            }
            height = y - top
        case .ladder:
            let pt = CGFloat(Double(parts.count > 1 ? parts[1] : "") ?? 300)
            let steps = Int(parts.count > 2 ? parts[2] : "") ?? 32
            bands.append((top, 0, [0, 0, 0]))
            var y: CGFloat = 0
            for k in 0...steps {
                let g = Double(k) / Double(steps)
                bands.append((y, y + pt, [g, g, g]))
                y += pt
            }
            bands.append((y, y + screen, [1, 1, 1]))
            height = y + screen - top
        }
        if mode == .stripes || mode == .ladder {
            bandViews.forEach { $0.removeFromSuperview() }
            bandViews = bands.map { band in
                let v = UIView(frame: CGRect(x: 0, y: band.y0 - top, width: width, height: band.y1 - band.y0))
                v.backgroundColor = UIColor(red: band.rgb[0], green: band.rgb[1], blue: band.rgb[2], alpha: 1)
                addSubview(v)
                return v
            }
        }
        if mode == .solid || mode == .split {
            bands = [(top, top + height, [-1, -1, -1])]
        }
        return height
    }

    func setColor(_ rgb: [Double]) {
        solid.backgroundColor = UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }

    /// White on the leading `left` of the width; or, with an `edge` in local coordinates, white
    /// above it (`whiteAbove`) or below it.
    func setSplit(left: CGFloat, edge: CGFloat?, whiteAbove: Bool, width: CGFloat? = nil, height: CGFloat? = nil) {
        let w = width ?? bounds.width, h = height ?? bounds.height
        if let edge {
            let e = min(max(edge, 0), h)
            let upper = CGRect(x: 0, y: 0, width: w, height: e)
            let lower = CGRect(x: 0, y: e, width: w, height: h - e)
            white.frame = whiteAbove ? upper : lower
            black.frame = whiteAbove ? lower : upper
        } else {
            let x = w * min(max(left, 0), 1)
            white.frame = CGRect(x: 0, y: 0, width: x, height: h)
            black.frame = CGRect(x: x, y: 0, width: w - x, height: h)
        }
    }
}

/// A hidden backdrop layer with luma tracking over the content under a bar: the render
/// server's own average luma of that content, logged as `lm` rows.
final class ABLumaMeter: UIView {
    let name: String
    private(set) var available = false

    override class var layerClass: AnyClass { (NSClassFromString("CABackdropLayer") as? CALayer.Type) ?? CALayer.self }

    init(name: String, visible: Bool) {
        self.name = name
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        available = set("setTracksLuma:", true)
        _ = set("setTracksLumaWhileHidden:", true)
        isHidden = !visible
    }

    required init?(coder: NSCoder) { fatalError() }

    private func set(_ name: String, _ value: Bool) -> Bool {
        let sel = NSSelectorFromString(name)
        guard let cls = object_getClass(layer), let m = class_getInstanceMethod(cls, sel) else { return false }
        unsafeBitCast(method_getImplementation(m), to: (@convention(c) (AnyObject, Selector, Bool) -> Void).self)(layer, sel, value)
        return true
    }

    @objc(backdropLayer:didChangeLuma:)
    func backdropLayer(_ layer: CALayer, didChangeLuma luma: CGFloat) {
        Recorder.shared.log(["k": "lm", "t": CACurrentMediaTime(), "m": name, "l": (Double(luma) * 100000).rounded() / 100000])
    }
}

final class ABController: UIViewController {
    let bars: String
    private let env = ProcessInfo.processInfo.environment
    private let host: String
    private let content: ABContent
    private var scroll: UIScrollView?
    private var meters: [ABLumaMeter] = []
    private var link: CADisplayLink?
    private var started = false
    private var appeared = false
    private var t0: CFTimeInterval = 0
    private var lastOffset: CGFloat = .nan
    private var scrollVelocity: CGFloat = 0
    private var scrollUntil: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var barSignature: [String: String] = [:]
    private var barItems: [String: [UIView]] = [:]
    private var lastItemScan: CFTimeInterval = 0
    private var contentHeight: CGFloat = 0
    private var contentTop: CGFloat = 0

    init(bars: String) {
        self.bars = bars
        host = ProcessInfo.processInfo.environment["PROBE_AB_HOST"] ?? "scroll"
        content = ABContent(spec: ProcessInfo.processInfo.environment["PROBE_AB_CONTENT"] ?? "solid")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bands"
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil)
        if bars == "searchbar" {
            let search = UISearchController(searchResultsController: nil)
            navigationItem.searchController = search
            navigationItem.hidesSearchBarWhenScrolling = false
            navigationItem.preferredSearchBarPlacement = .integrated
            toolbarItems = [UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: nil, action: nil), .flexibleSpace(),
                            navigationItem.searchBarPlacementBarButtonItem]
        } else {
            toolbarItems = [UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: nil, action: nil), .flexibleSpace(),
                            UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: nil, action: nil)]
        }
        if host == "static" {
            view.addSubview(content)
        } else {
            let s = UIScrollView(frame: view.bounds)
            s.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            s.alwaysBounceVertical = true
            s.showsVerticalScrollIndicator = false
            s.addSubview(content)
            view.addSubview(s)
            scroll = s
        }
        let meterMode = env["PROBE_AB_METER"] ?? "1"
        if meterMode != "0" {
            for name in ["tab", "toolbar", "nav", "bottomBand", "topBand"] {
                let m = ABLumaMeter(name: name, visible: meterMode == "visible")
                view.addSubview(m)
                meters.append(m)
            }
        }
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .systemRed
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let h = view.bounds.height, w = view.bounds.width
        if contentHeight == 0 || content.bounds.width != w {
            contentTop = host == "static" ? 0 : -h
            contentHeight = content.layout(width: w, top: contentTop, screen: h)
            if host == "static" {
                content.frame = CGRect(x: 0, y: 0, width: w, height: contentHeight)
            } else {
                content.frame = CGRect(x: 0, y: contentTop, width: w, height: contentHeight)
                scroll?.contentSize = CGSize(width: w, height: contentHeight + contentTop)
            }
        }
        for m in meters { m.frame = meterFrame(m.name) }
    }

    private func barViews() -> [(String, UIView)] {
        var out: [(String, UIView)] = []
        if let tb = tabBarController?.tabBar, !tb.isHidden { out.append(("tab", tb)) }
        if let nc = navigationController {
            if !nc.isToolbarHidden { out.append(("toolbar", nc.toolbar)) }
            out.append(("nav", nc.navigationBar))
        }
        return out
    }

    private func meterFrame(_ name: String) -> CGRect {
        let h = view.bounds.height, w = view.bounds.width
        let navBottom = navigationController.map { $0.navigationBar.convert($0.navigationBar.bounds, to: view).maxY } ?? 100
        switch name {
        case "bottomBand": return CGRect(x: 0, y: h - 160, width: w, height: 160)
        case "topBand": return CGRect(x: 0, y: 0, width: w, height: navBottom + 40)
        default:
            guard let bar = barViews().first(where: { $0.0 == name })?.1 else { return .zero }
            return bar.convert(bar.bounds, to: view)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !appeared else { return }
        appeared = true
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        logStart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.logCrops() }
        if let auto = Double(env["PROBE_AB_AUTOSTART"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + auto) { [weak self] in self?.start("auto") }
        }
    }

    @objc private func tapped() { start("tap") }

    private func start(_ how: String) {
        guard !started else { return }
        started = true
        t0 = CACurrentMediaTime()
        Recorder.shared.log(["k": "go", "t": t0, "how": how])
        logCrops()
        var index = 0
        for item in (env["PROBE_SCRIPT"] ?? "").split(separator: ";") {
            let parts = item.split(separator: "@")
            guard parts.count == 2, let at = Double(parts[1]) else { continue }
            let action = String(parts[0])
            let i = index
            index += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in self?.apply(action, index: i, at: at) }
        }
    }

    private func apply(_ action: String, index: Int, at: Double) {
        let now = CACurrentMediaTime()
        Recorder.shared.log(["k": "step", "t": now, "rel": now - t0, "plan": at, "i": index, "a": action])
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        let args = (parts.count > 1 ? parts[1] : "").split(separator: ",").compactMap { Double($0) }
        switch parts[0] {
        case "grey": if let g = args.first { content.setColor([g, g, g]) }
        case "rgb": if args.count == 3 { content.setColor(args) }
        case "left": if let f = args.first { content.setSplit(left: CGFloat(f), edge: nil, whiteAbove: true) }
        case "edge", "edgeb":
            if var y = args.first {
                if y < 0 { y += Double(view.window?.bounds.height ?? 0) }
                content.setSplit(left: 1, edge: localY(CGFloat(y)), whiteAbove: parts[0] == "edge")
            }
        case "offset": if let y = args.first { scroll?.setContentOffset(CGPoint(x: 0, y: y), animated: false) }
        case "top": if let s = scroll { s.setContentOffset(CGPoint(x: 0, y: -s.adjustedContentInset.top), animated: false) }
        case "scroll":
            if args.count == 2 {
                scrollVelocity = CGFloat(args[0])
                scrollUntil = now + args[1]
            }
        case "crops": logCrops()
        case "tree": X3Sampler.shared.tree("tree-\(env["PROBE_REC"] ?? "abright")-\(index).txt")
        default: break
        }
    }

    /// Window y to the content view's own coordinates.
    private func localY(_ y: CGFloat) -> CGFloat {
        guard let s = scroll else { return y }
        let windowTop = s.convert(CGPoint.zero, to: nil).y
        return y - windowTop + s.contentOffset.y - contentTop
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if let s = scroll {
            if scrollUntil > now, lastTick > 0 {
                let maxY = max(s.contentSize.height - s.bounds.height + s.adjustedContentInset.bottom, 0)
                let y = min(max(s.contentOffset.y + scrollVelocity * CGFloat(now - lastTick), -s.adjustedContentInset.top), maxY)
                s.contentOffset = CGPoint(x: 0, y: y)
            }
            if s.contentOffset.y != lastOffset {
                lastOffset = s.contentOffset.y
                Recorder.shared.log(["k": "off", "t": now, "y": (Double(lastOffset) * 100).rounded() / 100])
            }
        }
        lastTick = now
        if now - lastItemScan > 0.5 {
            lastItemScan = now
            for (name, bar) in barViews() { barItems[name] = items(in: bar) }
        }
        for (name, bar) in barViews() {
            var row: [String: Any] = ["k": "abs", "bar": name, "uis": bar.traitCollection.userInterfaceStyle.rawValue]
            row["items"] = (barItems[name] ?? []).map { item -> [Any] in
                var color: [Double] = []
                if let iv = item as? UIImageView { color = X3Sampler.rgba(iv.tintColor.resolvedColor(with: iv.traitCollection).cgColor) ?? [] }
                if let lbl = item as? UILabel { color = X3Sampler.rgba(lbl.textColor.resolvedColor(with: lbl.traitCollection).cgColor) ?? [] }
                return [item is UILabel ? "l" : "g", item.traitCollection.userInterfaceStyle.rawValue, color]
            }
            let sig = "\(row)"
            if barSignature[name] != sig {
                barSignature[name] = sig
                row["t"] = now
                Recorder.shared.log(row)
            }
        }
    }

    /// The bar's visible glyphs and labels, in reading order.
    private func items(in bar: UIView) -> [UIView] {
        var out: [UIView] = []
        func walk(_ v: UIView, _ alpha: CGFloat) {
            let a = alpha * v.alpha * (v.isHidden ? 0 : 1)
            guard a > 0.01 else { return }
            if let iv = v as? UIImageView, iv.image != nil, iv.bounds.width > 4 { out.append(iv) }
            if let lbl = v as? UILabel, !(lbl.text ?? "").isEmpty { out.append(lbl) }
            for s in v.subviews { walk(s, a) }
        }
        walk(bar, 1)
        return out.sorted { a, b in
            let fa = a.convert(a.bounds, to: nil), fb = b.convert(b.bounds, to: nil)
            return abs(fa.midY - fb.midY) > 8 ? fa.midY < fb.midY : fa.midX < fb.midX
        }
    }

    private func box(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height].map { (Double($0) * 100).rounded() / 100 } }

    private func logCrops() {
        guard let window = view.window else { return }
        let w = window.bounds.width, h = window.bounds.height
        var barsOut: [String: Any] = [:]
        for (name, bar) in barViews() {
            let views = items(in: bar)
            let glyphs = views.filter { $0 is UIImageView }.map { $0.convert($0.bounds, to: nil) }
            let labels = views.filter { $0 is UILabel }.map { $0.convert($0.bounds, to: nil) }
            var patches: [CGRect] = []
            if name == "tab", glyphs.count >= 3 {
                patches.append(CGRect(x: (glyphs[1].maxX + glyphs[2].minX) / 2 - 2, y: glyphs[1].midY - 2, width: 4, height: 4))
            }
            for g in glyphs { patches.append(CGRect(x: g.midX - 1.5, y: g.minY - 6.5, width: 3, height: 3)) }
            barsOut[name] = ["frame": box(bar.convert(bar.bounds, to: nil)), "glyphs": glyphs.map(box), "labels": labels.map(box), "patches": patches.map(box)]
        }
        Recorder.shared.log(["k": "abcrops", "t": CACurrentMediaTime(), "w": w, "h": h, "scale": window.screen.scale, "bars": barsOut,
                             "content": box(CGRect(x: 16, y: h * 0.5 - 5, width: 10, height: 10)),
                             "status": box(CGRect(x: 24, y: 16, width: 60, height: 18)),
                             "home": box(CGRect(x: w / 2 - 50, y: h - 10, width: 100, height: 6)),
                             "meters": meters.map { [$0.name, box($0.convert($0.bounds, to: nil))] as [Any] }])
    }

    private func defaultsRow() -> [String: Any] {
        var out: [String: Any] = [:]
        let suite = UserDefaults(suiteName: "com.apple.UIKit")
        for key in ["CalistogaAllowLumaTracking", "MPLumaChangeDuration"] {
            out["uikit." + key] = suite?.object(forKey: key).map { "\($0)" } ?? "nil"
            out["standard." + key] = UserDefaults.standard.object(forKey: key).map { "\($0)" } ?? "nil"
        }
        return out
    }

    private func logStart() {
        guard let window = view.window else { return }
        var row: [String: Any] = [
            "k": "abstart", "t": CACurrentMediaTime(), "bars": bars, "host": host, "content": content.spec,
            "os": UIDevice.current.systemVersion, "sys": window.traitCollection.userInterfaceStyle.rawValue,
            "override": window.overrideUserInterfaceStyle.rawValue, "probeDark": env["PROBE_DARK"] ?? "",
            "args": Array(ProcessInfo.processInfo.arguments.dropFirst()), "defaults": defaultsRow(),
            "w": window.bounds.width, "h": window.bounds.height, "scale": window.screen.scale,
            "meters": meters.map { [$0.name, $0.available] as [Any] },
            "bands": content.bands.map { [Double($0.y0), Double($0.y1)] + $0.rgb },
        ]
        if let s = scroll {
            row["scrollTop"] = Double(s.convert(CGPoint.zero, to: nil).y)
            row["inset"] = [Double(s.adjustedContentInset.top), Double(s.adjustedContentInset.bottom)]
            row["offset"] = Double(s.contentOffset.y)
        }
        Recorder.shared.log(row)
    }
}
