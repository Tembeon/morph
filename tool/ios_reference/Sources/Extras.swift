import UIKit
import QuartzCore

/// Probe scenes for the third widget pass: alerts and action sheets, the search field and
/// the compact date picker. Scene names start with "x3"; they run X3Sampler, which logs a
/// `V` row per matched view per tick (only when the row changed) like W2Sampler, plus the
/// label font, size and color (`font`, `fs`, `fw`, `tc`, `text`) so layouts and colors
/// can be read from the same file. PROBE_X3TRACK overrides the class pattern; views under
/// an accessibilityIdentifier starting "x3_" are sampled to PROBE_X3DEPTH levels.
/// PROBE_DARK=1 forces the dark appearance on the window. PROBE_SCRIPT = "action@s;..."
/// as in Widgets2 (show, dismiss, focus, type, clear, cancel, resign, open, close,
/// tab:search, tab:home, tree...).
enum ExtrasScenes {
    static func make(_ name: String) -> UIViewController? {
        guard name.hasPrefix("x3") else { return nil }
        let env = ProcessInfo.processInfo.environment
        let pattern: String
        let vc: UIViewController
        switch name {
        case "x3alert":
            pattern = "Alert|_UIInterfaceAction|Dimming|Platter|TransitionView|_UIPopover|Popover|DropShadow|UILabel|Glass|_UISheet|Sheet"
            vc = X3AlertScene()
        case "x3search":
            pattern = "Search|^UITabBar$|_UITabBar|_UITab|Platter|LiquidLens|_UIBarBackground|_UIButtonBar|UINavigationBar|UIToolbar|_UIToolbar|Cancel|Close|Glass|Keyboard|InputSetHost|UIInputSetContainerView|_UIRemoteKeyboard|UILabel|UIImageView"
            vc = X3SearchScene.make(env["PROBE_SEARCH"] ?? "toolbar")
        case "x3date":
            pattern = "DatePicker|Compact|_UIPopover|Popover|Calendar|Dimming|TransitionView|Platter|Glass|UILabel|_UIDatePicker|Wheel|Picker"
            vc = X3DateScene()
        default:
            pattern = "^NONE$"
            vc = UIViewController()
        }
        X3Sampler.shared.start(pattern: env["PROBE_X3TRACK"] ?? pattern)
        return vc
    }

    /// Keeps a spinner turning at the top trailing corner of the window
    /// (PROBE_SPINNER=1): a screen recorder that drops the first frames of
    /// motion after a still screen then films every frame of a transition.
    static func spinner(_ window: UIWindow?) {
        guard ProcessInfo.processInfo.environment["PROBE_SPINNER"] == "1", let window,
              !window.subviews.contains(where: { $0.accessibilityIdentifier == "x3spinner" }) else { return }
        let s = UIActivityIndicatorView(style: .medium)
        s.accessibilityIdentifier = "x3spinner"
        s.center = CGPoint(x: window.bounds.width - 30, y: 64)
        s.startAnimating()
        window.addSubview(s)
    }
}

final class X3Sampler: NSObject {
    static let shared = X3Sampler()
    private var pattern: NSRegularExpression?
    private var link: CADisplayLink?
    private var sig: [ObjectIdentifier: String] = [:]
    private var ids: [ObjectIdentifier: Int] = [:]
    private var seenAnims = Set<ObjectIdentifier>()
    private let rootDepth = Int(ProcessInfo.processInfo.environment["PROBE_X3DEPTH"] ?? "8") ?? 8

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
        guard depth < 70 else { return }
        let name = NSStringFromClass(type(of: v))
        let pres = v.layer.presentation() ?? v.layer
        let ea = alpha * Double(pres.opacity) * (v.isHidden ? 0 : 1)
        var r = rooted
        if r < 0, let id = v.accessibilityIdentifier, id.hasPrefix("x3_") { r = 0 }
        let inRoot = r >= 0 && r <= rootDepth
        let match = inRoot || pattern?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        if match { sample(v, pres, wp, now, name, ea) }
        for s in v.subviews { walk(s, wp, now, depth + 1, rooted: r >= 0 ? r + 1 : -1, alpha: ea) }
    }

    static func rgba(_ c: CGColor?) -> [Double]? {
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
        if let bg = X3Sampler.rgba(p.backgroundColor), bg.count == 4, bg[3] > 0 { row["bg"] = bg }
        if p.shadowOpacity > 0 { row["sh"] = [r4(CGFloat(p.shadowOpacity)), r2(p.shadowRadius), r2(p.shadowOffset.height)] }
        if v.isHidden { row["hid"] = true }
        if let par = v.superview { row["par"] = NSStringFromClass(type(of: par)) }
        if let aid = v.accessibilityIdentifier, !aid.isEmpty { row["aid"] = aid }
        if let fl = p.filters as? [NSObject], !fl.isEmpty {
            row["flt"] = fl.map { (Probe.object($0, "name") as? String) ?? "?" }
        }
        if let lbl = v as? UILabel {
            row["text"] = String((lbl.text ?? "").prefix(40))
            row["fs"] = r2(lbl.font.pointSize)
            row["fw"] = r2(CGFloat((lbl.font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? Double ?? 0))
            if let c = X3Sampler.rgba(lbl.textColor.resolvedColor(with: lbl.traitCollection).cgColor) { row["tc"] = c }
        }
        if let iv = v as? UIImageView, let tint = X3Sampler.rgba(iv.tintColor.resolvedColor(with: iv.traitCollection).cgColor) { row["tint"] = tint }
        if let tf = v as? UITextField {
            row["text"] = String((tf.text ?? "").prefix(40))
            row["fs"] = r2(tf.font?.pointSize ?? 0)
            row["focus"] = tf.isFirstResponder
        }
        let s = row.description
        if sig[oid] != s {
            sig[oid] = s
            row["k"] = "V"
            row["t"] = now
            Recorder.shared.log(row)
        }
        anims(v.layer, cls, id, now)
    }

    private func value(_ v: Any?) -> Any {
        guard let v else { return NSNull() }
        if let n = v as? NSNumber { return n.doubleValue }
        if let val = v as? NSValue {
            let type = String(cString: val.objCType)
            if type.hasPrefix("{CATransform3D") {
                var t = CATransform3DIdentity
                val.getValue(&t, size: MemoryLayout<CATransform3D>.size)
                return [t.m11, t.m12, t.m21, t.m22, t.m41, t.m42].map { Double($0) }
            }
            return String(describing: val).prefix(160).description
        }
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
                                          "key": key, "cls": NSStringFromClass(type(of: a)), "begin": a.beginTime, "dur": a.duration, "speed": a.speed]
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
            var extra = " a=\(v.alpha) cr=\(v.layer.cornerRadius)"
            if v.isHidden { extra += " HIDDEN" }
            if let bg = v.backgroundColor, let c = X3Sampler.rgba(bg.resolvedColor(with: v.traitCollection).cgColor) { extra += " bg=\(c)" }
            if let lbl = v as? UILabel {
                let w = (lbl.font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? Double ?? 0
                extra += " text=\(lbl.text ?? "") font=\(lbl.font.fontName) fs=\(lbl.font.pointSize) fw=\(w) tc=\(X3Sampler.rgba(lbl.textColor.resolvedColor(with: lbl.traitCollection).cgColor) ?? [])"
            }
            if let iv = v as? UIImageView { extra += " tint=\(X3Sampler.rgba(iv.tintColor.resolvedColor(with: iv.traitCollection).cgColor) ?? [])" }
            if let tf = v as? UITextField { extra += " field=\(tf.text ?? "") placeholder=\(tf.placeholder ?? "") fs=\(tf.font?.pointSize ?? 0)" }
            if let fl = v.layer.filters, !fl.isEmpty { extra += " filters=\(fl.count)" }
            out += String(repeating: "  ", count: depth) + "\(NSStringFromClass(type(of: v))) \(r2(f.minX)),\(r2(f.minY)) \(r2(f.width))x\(r2(f.height))\(v.accessibilityIdentifier.map { " #\($0)" } ?? "")\(extra)\n"
            for s in v.subviews { walk(s, depth + 1) }
        }
        for w in windows() { walk(w, 0) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? out.write(to: docs.appendingPathComponent(name), atomically: true, encoding: .utf8)
        Recorder.shared.flush()
    }
}

/// Runs PROBE_SCRIPT actions ("name@seconds;...") relative to the first appearance.
class X3ScriptedScene: UIViewController {
    let env = ProcessInfo.processInfo.environment
    var scripted = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if env["PROBE_DARK"] == "1" { view.window?.overrideUserInterfaceStyle = .dark }
        ExtrasScenes.spinner(view.window)
        guard !scripted else { return }
        scripted = true
        X3Script.schedule { [weak self] action in self?.run(action) }
    }

    func run(_ action: String) {
        if action.hasPrefix("tree") { X3Sampler.shared.tree("tree-\(action).txt") }
    }
}

enum X3Script {
    static func schedule(_ handler: @escaping (String) -> Void) {
        let script = ProcessInfo.processInfo.environment["PROBE_SCRIPT"] ?? ""
        for item in script.split(separator: ";") {
            let parts = item.split(separator: "@")
            guard parts.count == 2, let at = Double(parts[1]) else { continue }
            let action = String(parts[0])
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                Recorder.shared.log(["k": "evt", "e": "script", "a": action, "t": CACurrentMediaTime()])
                handler(action)
            }
        }
    }
}

// MARK: alerts

final class X3AlertScene: X3ScriptedScene {
    let source = UIButton(configuration: .glass())
    weak var alert: UIAlertController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        var c = UIButton.Configuration.glass()
        c.title = "Show"
        source.configuration = c
        source.accessibilityIdentifier = "x3src"
        source.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(source)
        let x = CGFloat(Double(env["PROBE_BTN_X"] ?? "") ?? 0)
        NSLayoutConstraint.activate([
            x == 0 ? source.centerXAnchor.constraint(equalTo: view.centerXAnchor) : source.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: x),
            source.centerYAnchor.constraint(equalTo: view.topAnchor, constant: CGFloat(Double(env["PROBE_BTN_Y"] ?? "") ?? 600)),
            source.widthAnchor.constraint(equalToConstant: 120), source.heightAnchor.constraint(equalToConstant: 48),
        ])
        source.addTarget(self, action: #selector(showAlert), for: .touchUpInside)
    }

    @objc func showAlert() {
        let kind = env["PROBE_ALERT"] ?? "alert"
        let sheet = kind != "alert"
        let message = env["PROBE_LONG"] == "1"
            ? "A much longer message for the alert that wraps over several lines so the header grows and the layout of the platter can be read from it."
            : "A message for the alert."
        let title: String? = env["PROBE_NOTITLE"] == "1" ? nil : "Title"
        let alert = UIAlertController(title: title, message: env["PROBE_NOMSG"] == "1" ? nil : message, preferredStyle: sheet ? .actionSheet : .alert)
        let count = Int(env["PROBE_ACTIONS"] ?? "3") ?? 3
        let specs: [(String, UIAlertAction.Style)] = [("OK", .default), ("Delete", .destructive), ("Cancel", .cancel), ("Another", .default), ("Fifth", .default)]
        let order = env["PROBE_ORDER"] ?? ""
        let chosen: [(String, UIAlertAction.Style)] = order.isEmpty ? Array(specs.prefix(count)) : order.split(separator: ",").map { s in specs.first { $0.0 == String(s) } ?? ("?", .default) }
        for (t, s) in chosen {
            let action = UIAlertAction(title: t, style: s) { _ in Recorder.shared.log(["k": "evt", "e": "action", "title": t, "t": CACurrentMediaTime()]) }
            alert.addAction(action)
        }
        if env["PROBE_PREFERRED"] == "1", let first = alert.actions.first { alert.preferredAction = first }
        if env["PROBE_TF"] == "1" { alert.addTextField { $0.placeholder = "Name" } }
        if kind == "sheet" { alert.popoverPresentationController?.sourceView = source }
        if kind == "sheetbar" { alert.popoverPresentationController?.sourceItem = source }
        self.alert = alert
        Recorder.shared.log(["k": "evt", "e": "present", "t": CACurrentMediaTime()])
        present(alert, animated: true) { Recorder.shared.log(["k": "evt", "e": "presented", "t": CACurrentMediaTime()]) }
    }

    override func run(_ action: String) {
        super.run(action)
        switch action {
        case "show": showAlert()
        case "dismiss":
            Recorder.shared.log(["k": "evt", "e": "dismiss", "t": CACurrentMediaTime()])
            dismiss(animated: true) { Recorder.shared.log(["k": "evt", "e": "dismissed", "t": CACurrentMediaTime()]) }
        case "settings":
            let text = SettingsDump.run(pattern: env["PROBE_SETTINGS_RE"] ?? "Alert|Popover|DatePicker|Calendar|Search|Keyboard|Dimming|ActionSheet|Interface")
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? text.write(to: docs.appendingPathComponent("settings-x3.txt"), atomically: true, encoding: .utf8)
        default: break
        }
    }
}

// MARK: search

enum X3SearchScene {
    static func make(_ variant: String) -> UIViewController {
        switch variant {
        case "nav":
            return UINavigationController(rootViewController: X3SearchList(bottom: false, top: true))
        case "tab", "tabauto":
            return X3SearchTabs(auto: variant == "tabauto")
        default:
            let nav = UINavigationController(rootViewController: X3SearchList(bottom: true, top: false))
            nav.isToolbarHidden = false
            return nav
        }
    }
}

final class X3SearchTabs: UITabBarController {
    let auto: Bool
    var list: X3SearchList?
    private var scripted = false
    init(auto: Bool) { self.auto = auto; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if ProcessInfo.processInfo.environment["PROBE_DARK"] == "1" { view.window?.overrideUserInterfaceStyle = .dark }
        ExtrasScenes.spinner(view.window)
        guard !scripted else { return }
        scripted = true
        X3Script.schedule { [weak self] action in
            guard let self else { return }
            switch action {
            case "tab:search": self.selectedTab = self.tabs.last
            case "tab:home": self.selectedTab = self.tabs.first
            default:
                if action.hasPrefix("tree") { X3Sampler.shared.tree("tree-\(action).txt") } else { self.list?.run(action) }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let make: (String) -> UIViewController = { title in
            let vc = UIViewController(); vc.view.backgroundColor = .systemBackground
            let l = UILabel(); l.text = title; l.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(l)
            NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor), l.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)])
            return vc
        }
        let home = UITab(title: "Home", image: UIImage(systemName: "house"), identifier: "home") { _ in make("Home") }
        let library = UITab(title: "Library", image: UIImage(systemName: "books.vertical"), identifier: "library") { _ in make("Library") }
        let search = UISearchTab { [weak self] _ in
            let list = X3SearchList(bottom: false, top: false)
            list.scripted = true
            self?.list = list
            return UINavigationController(rootViewController: list)
        }
        if auto { search.automaticallyActivatesSearch = true }
        tabs = [home, library, search]
    }
}

final class X3SearchList: X3ScriptedScene, UITableViewDataSource, UISearchResultsUpdating, UISearchControllerDelegate {
    let bottom: Bool
    let top: Bool
    let search = UISearchController(searchResultsController: nil)
    init(bottom: Bool, top: Bool) { self.bottom = bottom; self.top = top; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        search.searchResultsUpdater = self
        search.delegate = self
        search.searchBar.accessibilityIdentifier = "x3_searchbar"
        if let scopes = env["PROBE_SCOPES"] { search.searchBar.scopeButtonTitles = scopes.split(separator: ",").map(String.init) }
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        if top { navigationItem.preferredSearchBarPlacement = .stacked }
        if bottom {
            navigationItem.preferredSearchBarPlacement = .integrated
            var items: [UIBarButtonItem] = []
            if env["PROBE_TBITEMS"] == "1" {
                items.append(UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"), style: .plain, target: nil, action: nil))
                items.append(.flexibleSpace())
            }
            items.append(navigationItem.searchBarPlacementBarButtonItem)
            if env["PROBE_TBITEMS"] == "1" {
                items.append(.flexibleSpace())
                items.append(UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: nil, action: nil))
            }
            toolbarItems = items
        }
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification, UIResponder.keyboardWillHideNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { n in
                let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                Recorder.shared.log(["k": "evt", "e": "keyboard", "n": n.name.rawValue, "y": f.minY, "h": f.height, "t": CACurrentMediaTime()])
            }
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

    func updateSearchResults(for searchController: UISearchController) {
        Recorder.shared.log(["k": "evt", "e": "update", "text": searchController.searchBar.text ?? "", "t": CACurrentMediaTime()])
    }
    func willPresentSearchController(_ searchController: UISearchController) { Recorder.shared.log(["k": "evt", "e": "willPresentSearch", "t": CACurrentMediaTime()]) }
    func didPresentSearchController(_ searchController: UISearchController) {
        Recorder.shared.log(["k": "evt", "e": "didPresentSearch", "t": CACurrentMediaTime()])
        X3SearchList.logTraits(searchController.searchBar.searchTextField)
    }

    /// The text input traits of the search text field (what decides the keyboard's bar).
    static func logTraits(_ f: UITextField) {
        var row: [String: Any] = ["k": "evt", "e": "traits", "t": CACurrentMediaTime(),
            "autocorrection": f.autocorrectionType.rawValue, "spellChecking": f.spellCheckingType.rawValue,
            "autocapitalization": f.autocapitalizationType.rawValue, "keyboardType": f.keyboardType.rawValue,
            "returnKey": f.returnKeyType.rawValue, "smartQuotes": f.smartQuotesType.rawValue,
            "smartDashes": f.smartDashesType.rawValue, "smartInsert": f.smartInsertDeleteType.rawValue,
            "appearance": f.keyboardAppearance.rawValue, "enablesReturn": f.enablesReturnKeyAutomatically,
            "contentType": f.textContentType?.rawValue ?? "nil"]
        if #available(iOS 17.0, *) { row["inlinePrediction"] = f.inlinePredictionType.rawValue }
        if #available(iOS 18.0, *) {
            row["writingTools"] = f.writingToolsBehavior.rawValue
            row["mathExpression"] = f.mathExpressionCompletionType.rawValue
        }
        Recorder.shared.log(row)
    }
    func willDismissSearchController(_ searchController: UISearchController) { Recorder.shared.log(["k": "evt", "e": "willDismissSearch", "t": CACurrentMediaTime()]) }
    func didDismissSearchController(_ searchController: UISearchController) { Recorder.shared.log(["k": "evt", "e": "didDismissSearch", "t": CACurrentMediaTime()]) }

    override func run(_ action: String) {
        super.run(action)
        switch action {
        case "focus": search.isActive = true; search.searchBar.searchTextField.becomeFirstResponder()
        case "activate": search.isActive = true
        case "cancel": search.isActive = false
        case "resign": search.searchBar.searchTextField.resignFirstResponder()
        case "type": search.searchBar.text = "Item 1"; updateSearchResults(for: search)
        case "type2": search.searchBar.searchTextField.insertText("It")
        case "clear": search.searchBar.text = ""; updateSearchResults(for: search)
        default: break
        }
    }
}

// MARK: compact date picker

final class X3DateScene: X3ScriptedScene, UIPopoverPresentationControllerDelegate {
    let picker = UIDatePicker()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        picker.preferredDatePickerStyle = .compact
        switch env["PROBE_DMODE"] ?? "date" {
        case "time": picker.datePickerMode = .time
        case "both": picker.datePickerMode = .dateAndTime
        default: picker.datePickerMode = .date
        }
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 3; comps.hour = 9; comps.minute = 41
        picker.calendar = Calendar(identifier: .gregorian)
        picker.locale = Locale(identifier: env["PROBE_LOCALE"] ?? "en_US")
        picker.timeZone = TimeZone(identifier: "UTC")
        picker.date = picker.calendar.date(from: comps) ?? Date()
        picker.accessibilityIdentifier = "x3_picker"
        picker.addTarget(self, action: #selector(changed), for: .valueChanged)
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)
        let x = CGFloat(Double(env["PROBE_PX"] ?? "") ?? 0)
        NSLayoutConstraint.activate([
            x == 0 ? picker.centerXAnchor.constraint(equalTo: view.centerXAnchor) : picker.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: x),
            picker.centerYAnchor.constraint(equalTo: view.topAnchor, constant: CGFloat(Double(env["PROBE_PY"] ?? "") ?? 300)),
        ])
    }

    @objc func changed() {
        Recorder.shared.log(["k": "evt", "e": "valueChanged", "v": picker.date.timeIntervalSince1970, "t": CACurrentMediaTime()])
    }

    private func controls(_ v: UIView) -> [UIView] {
        var out: [UIView] = []
        for s in v.subviews {
            let n = NSStringFromClass(type(of: s))
            if n.contains("Compact") || s is UIControl || s.isAccessibilityElement { out.append(s) }
            out += controls(s)
        }
        return out
    }

    override func run(_ action: String) {
        super.run(action)
        switch action {
        case _ where action.hasPrefix("open"):
            let targets = controls(picker)
            Recorder.shared.log(["k": "evt", "e": "targets", "list": targets.map { NSStringFromClass(type(of: $0)) }, "t": CACurrentMediaTime()])
            let index = Int(action.dropFirst(4)) ?? 0
            guard targets.count > index else { return }
            let target = targets[index]
            Recorder.shared.log(["k": "evt", "e": "open", "cls": NSStringFromClass(type(of: target)), "t": CACurrentMediaTime()])
            if let c = target as? UIControl {
                c.sendActions(for: .touchUpInside)
                if c.allTargets.isEmpty { _ = target.accessibilityActivate() }
            } else {
                _ = target.accessibilityActivate()
            }
        case "activate":
            Recorder.shared.log(["k": "evt", "e": "open", "cls": "picker", "t": CACurrentMediaTime()])
            _ = picker.accessibilityActivate()
        case "close":
            Recorder.shared.log(["k": "evt", "e": "close", "t": CACurrentMediaTime()])
            presentedViewController?.dismiss(animated: true)
        case "next":
            picker.date = picker.date.addingTimeInterval(86400)
        default: break
        }
    }
}
