import UIKit
import QuartzCore

/// Probe scenes for control STATES that no motion capture covers (disabled look, the
/// indicators on the device). Scene names start with "x4"; they run X3Sampler (a `V` row per
/// view under an accessibilityIdentifier starting "x3_", PROBE_X3DEPTH levels, plus `anim`
/// rows) so an enable / disable transition is logged frame by frame.
///
/// - x4dis: every control twice, ENABLED in the left column (x 101), DISABLED in the right
///   column (x 301), same rows; the date pickers and the search field get full-width rows
///   (enabled above, disabled below). Identifiers x3_en_<name> / x3_dis_<name>.
/// - x4disbars: navigation bar + toolbar with enabled and disabled items (text, icon,
///   prominent), identifiers on the items' custom accessibility ids.
/// - x4distab: a 4-tab UITabBarController whose third item is disabled.
/// - x4disalert: an alert with disabled actions; PROBE_ALERTV=row (Cancel + a disabled
///   preferred OK, text field) or col (Enabled / Disabled / Cancel).
/// - x4ind: progress views (default + bar) and activity indicators (medium + large).
///
/// PROBE_SCRIPT actions: toggle (flips isEnabled of every disabled twin), dump[:tag]
/// (deep view + layer dump to Documents/dump-<tag>.txt), show (alert), progress:<v>,
/// progressn:<v> (not animated), start, stop, hide:<0|1> (hidesWhenStopped).
/// PROBE_DARK=1/0 forces the appearance (App.swift sets it on the window).
enum StatesScenes {
    static func make(_ name: String) -> UIViewController? {
        guard name.hasPrefix("x4") else { return nil }
        let vc: UIViewController
        switch name {
        case "x4dis": vc = DisabledControlsScene()
        case "x4disbars": vc = UINavigationController(rootViewController: DisabledBarsScene())
        case "x4distab": vc = DisabledTabScene()
        case "x4disalert": vc = DisabledAlertScene()
        case "x4ind": vc = IndicatorsScene()
        default: return nil
        }
        X3Sampler.shared.start(pattern: ProcessInfo.processInfo.environment["PROBE_X3TRACK"] ?? "^NONE$")
        return vc
    }

    /// Every view (and every layer that is not a view's) of every window: geometry, alpha,
    /// colors, tint, filters with their inputs, compositing filter, contentsMultiplyColor.
    static func deepDump(_ tag: String) {
        var out = ""
        func rgba(_ c: CGColor?) -> String {
            guard let c, let s = CGColorSpace(name: CGColorSpace.sRGB),
                  let conv = c.converted(to: s, intent: .defaultIntent, options: nil), let comps = conv.components else { return "-" }
            return "[" + comps.map { String(format: "%.4f", Double($0)) }.joined(separator: ",") + "]"
        }
        func r(_ f: CGRect) -> String { String(format: "%.2f,%.2f %.2fx%.2f", f.minX, f.minY, f.width, f.height) }
        func layerInfo(_ l: CALayer) -> String {
            var info = "\(NSStringFromClass(type(of: l))) name=\(l.name ?? "-") op=\(l.opacity) cr=\(l.cornerRadius)"
            if l.isHidden { info += " HID" }
            if let bg = l.backgroundColor { info += " bg=\(rgba(bg))" }
            if let fl = l.filters as? [NSObject], !fl.isEmpty { info += " filters=\(fl.map { BarsRecorder.filterValues($0, layer: l) })" }
            if let cf = l.compositingFilter { info += " cf=\(cf)" }
            if let c = l.value(forKey: "contentsMultiplyColor") as AnyObject?, CFGetTypeID(c) == CGColor.typeID, rgba((c as! CGColor)) != "[1.0000,1.0000,1.0000,1.0000]" { info += " cmul=\(rgba((c as! CGColor)))" }
            if let ct = l.contents { info += CFGetTypeID(ct as CFTypeRef) == CGImage.typeID ? " img=\((ct as! CGImage).width)x\((ct as! CGImage).height)" : " contents" }
            if l.borderWidth > 0 { info += " border=\(l.borderWidth) bc=\(rgba(l.borderColor))" }
            if l.shadowOpacity > 0 { info += " shadow=\(l.shadowOpacity)/\(l.shadowRadius)" }
            if let t = l as? CATextLayer { info += " text=\(String(describing: t.string).prefix(30))" }
            if let s = l as? CAShapeLayer { info += " fill=\(rgba(s.fillColor)) stroke=\(rgba(s.strokeColor))" }
            if l.mask != nil { info += " MASK" }
            return info
        }
        func lw(_ l: CALayer, _ wl: CALayer, _ d: Int, _ indent: String) {
            guard d < 14 else { return }
            out += indent + "[L] " + r(l.convert(l.bounds, to: wl)) + " " + layerInfo(l) + "\n"
            if let m = l.mask { lw(m, wl, d + 1, indent + "  (mask) ") }
            for s in l.sublayers ?? [] where !(s.delegate is UIView) { lw(s, wl, d + 1, indent + "  ") }
        }
        func walk(_ v: UIView, _ wl: CALayer, _ depth: Int) {
            guard depth < 60 else { return }
            let ind = String(repeating: "  ", count: depth)
            var extra = " a=\(v.alpha)"
            if v.isHidden { extra += " HIDDEN" }
            if let id = v.accessibilityIdentifier, !id.isEmpty { extra += " #\(id)" }
            if let c = v as? UIControl { extra += " enabled=\(c.isEnabled) hl=\(c.isHighlighted) sel=\(c.isSelected)" }
            let tint: UIColor? = v.tintColor
            extra += " tint=\(rgba(tint?.resolvedColor(with: v.traitCollection).cgColor)) tam=\(v.tintAdjustmentMode.rawValue)"
            if let bg = v.backgroundColor { extra += " bg=\(rgba(bg.resolvedColor(with: v.traitCollection).cgColor))" }
            if let lbl = v as? UILabel {
                let tc: UIColor? = lbl.textColor
                let font: UIFont? = lbl.font
                extra += " text=\(lbl.text ?? "") tc=\(rgba(tc?.resolvedColor(with: lbl.traitCollection).cgColor)) enabledLbl=\(lbl.isEnabled) fs=\(font?.pointSize ?? 0)"
            }
            if let iv = v as? UIImageView, let img = iv.image {
                extra += " image=\(img.isSymbolImage ? "symbol" : "bitmap") rm=\(img.renderingMode.rawValue)"
            }
            if let e = v as? UIVisualEffectView { extra += " effect=\(String(describing: e.effect).prefix(160))" }
            if let b = v as? UIButton, let cfg = b.configuration {
                extra += " cfg.fg=\(rgba(cfg.baseForegroundColor?.resolvedColor(with: b.traitCollection).cgColor)) cfg.bg=\(rgba(cfg.baseBackgroundColor?.resolvedColor(with: b.traitCollection).cgColor))"
            }
            if let tf = v as? UITextField { extra += " field=\(tf.text ?? "") ph=\(tf.placeholder ?? "") tfEnabled=\(tf.isEnabled)" }
            out += ind + "\(NSStringFromClass(type(of: v))) \(r(v.convert(v.bounds, to: nil)))\(extra)\n"
            out += ind + "    [L] " + layerInfo(v.layer) + "\n"
            if let m = v.layer.mask { lw(m, wl, 1, ind + "    (mask) ") }
            for s in v.layer.sublayers ?? [] where !(s.delegate is UIView) { lw(s, wl, 1, ind + "      ") }
            for s in v.subviews { walk(s, wl, depth + 1) }
        }
        let wins = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        for w in wins { walk(w, w.layer, 0) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? out.write(to: docs.appendingPathComponent("dump-\(ProcessInfo.processInfo.environment["PROBE_REC"] ?? "x")-\(tag).txt"), atomically: true, encoding: .utf8)
        Recorder.shared.log(["k": "evt", "e": "dump", "tag": tag, "t": CACurrentMediaTime()])
        Recorder.shared.flush()
    }
}

/// Runs PROBE_SCRIPT through X3Script and handles the shared actions.
class StatesScene: UIViewController {
    let env = ProcessInfo.processInfo.environment
    private var scripted = false
    var togglables: [() -> Void] = []

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !scripted else { return }
        scripted = true
        X3Script.schedule { [weak self] action in self?.run(action) }
    }

    func run(_ action: String) {
        if action.hasPrefix("dump") {
            StatesScenes.deepDump(action.contains(":") ? String(action.split(separator: ":")[1]) : "x")
        }
        if action == "toggle" { togglables.forEach { $0() } }
    }
}

final class DisabledControlsScene: StatesScene {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        var y: CGFloat = 90
        func pair(_ name: String, height: CGFloat, width: CGFloat? = nil, _ make: () -> UIView) {
            for (col, x) in [("en", 101.0), ("dis", 301.0)] {
                let v = make()
                v.accessibilityIdentifier = "x3_\(col)_\(name)"
                v.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(v)
                var cs = [v.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: x),
                          v.centerYAnchor.constraint(equalTo: view.topAnchor, constant: y + height / 2)]
                if let width { cs.append(v.widthAnchor.constraint(equalToConstant: width)) }
                if !(v is UISwitch) && !(v is UIStepper) && !(v is UIPageControl) { cs.append(v.heightAnchor.constraint(equalToConstant: height)) }
                NSLayoutConstraint.activate(cs)
                if col == "dis", let c = v as? UIControl {
                    c.isEnabled = false
                    togglables.append { c.isEnabled.toggle() }
                }
            }
            y += height + 18
        }
        func full(_ name: String, height: CGFloat, _ make: () -> UIView) {
            for col in ["en", "dis"] {
                let v = make()
                v.accessibilityIdentifier = "x3_\(col)_\(name)"
                v.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(v)
                NSLayoutConstraint.activate([
                    v.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                    v.centerYAnchor.constraint(equalTo: view.topAnchor, constant: y + height / 2),
                    v.heightAnchor.constraint(equalToConstant: height),
                ] + (v is UIDatePicker ? [] : [v.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)]))
                if col == "dis", let c = v as? UIControl {
                    c.isEnabled = false
                    togglables.append { c.isEnabled.toggle() }
                }
                y += height + 10
            }
            y += 8
        }
        pair("seg", height: 32, width: 170) {
            let s = UISegmentedControl(items: ["Day", "Night", "All"])
            s.selectedSegmentIndex = 0
            return s
        }
        pair("swOff", height: 28) { UISwitch() }
        pair("swOn", height: 28) { let s = UISwitch(); s.isOn = true; return s }
        pair("slider", height: 28, width: 170) { let s = UISlider(); s.value = 0.3; return s }
        pair("sliderT", height: 28, width: 170) {
            let s = UISlider()
            s.trackConfiguration = UISlider.TrackConfiguration(numberOfTicks: 5)
            s.value = 0.5
            return s
        }
        pair("stepper", height: 32) { let s = UIStepper(); s.value = 5; return s }
        pair("glass", height: 44, width: 120) { var c = UIButton.Configuration.glass(); c.title = "Glass"; return UIButton(configuration: c) }
        pair("prominent", height: 44, width: 120) { var c = UIButton.Configuration.prominentGlass(); c.title = "Glass"; return UIButton(configuration: c) }
        pair("glassIcon", height: 44, width: 44) { var c = UIButton.Configuration.glass(); c.image = UIImage(systemName: "star.fill"); return UIButton(configuration: c) }
        pair("menu", height: 48, width: 48) {
            var c = UIButton.Configuration.glass()
            c.image = UIImage(systemName: "ellipsis")
            let b = UIButton(configuration: c)
            b.menu = UIMenu(children: [UIAction(title: "Copy") { _ in }, UIAction(title: "Share") { _ in }])
            b.showsMenuAsPrimaryAction = true
            return b
        }
        pair("page", height: 26) { let p = UIPageControl(); p.numberOfPages = 5; p.currentPage = 1; return p }
        full("search", height: 36) { let s = UISearchTextField(); s.placeholder = "Search"; return s }
        full("date", height: 36) {
            let d = UIDatePicker()
            d.preferredDatePickerStyle = .compact
            d.datePickerMode = .dateAndTime
            d.date = Date(timeIntervalSince1970: 1_790_000_000)
            return d
        }
    }
}

final class DisabledBarsScene: StatesScene {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Bars"
        func item(_ id: String, title: String? = nil, symbol: String? = nil, enabled: Bool, prominent: Bool = false) -> UIBarButtonItem {
            let i = symbol.map { UIBarButtonItem(image: UIImage(systemName: $0), style: prominent ? .prominent : .plain, target: nil, action: #selector(noop)) }
                ?? UIBarButtonItem(title: title, style: prominent ? .prominent : .plain, target: nil, action: #selector(noop))
            i.target = self
            i.accessibilityIdentifier = "x3_\(enabled ? "en" : "dis")_\(id)"
            i.isEnabled = enabled
            if !enabled { togglables.append { i.isEnabled.toggle() } }
            return i
        }
        navigationItem.leftBarButtonItems = [item("navText", title: "Edit", enabled: true), item("navTextD", title: "Edit", enabled: false)]
        navigationItem.rightBarButtonItems = [item("navProm", symbol: "checkmark", enabled: false, prominent: true), item("navIcon", symbol: "plus", enabled: true), item("navIconD", symbol: "plus", enabled: false)]
        toolbarItems = [
            item("tbIcon", symbol: "square.and.arrow.up", enabled: true), item("tbIconD", symbol: "square.and.arrow.up", enabled: false),
            .flexibleSpace(),
            item("tbProm", symbol: "checkmark", enabled: true, prominent: true), item("tbPromD", symbol: "checkmark", enabled: false, prominent: true),
        ]
        let note = UILabel()
        note.text = "enabled | disabled"
        note.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(note)
        NSLayoutConstraint.activate([note.centerXAnchor.constraint(equalTo: view.centerXAnchor), note.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: false)
    }

    @objc func noop() {}
}

final class DisabledTabScene: UITabBarController {
    private var scripted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let symbols = ["house", "books.vertical", "dot.radiowaves.left.and.right", "person"]
        let titles = ["Home", "Library", "Radio", "Profile"]
        viewControllers = (0..<4).map { i in
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            vc.tabBarItem = UITabBarItem(title: titles[i], image: UIImage(systemName: symbols[i]), tag: i)
            return vc
        }
        tabBar.items?[2].isEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !scripted else { return }
        scripted = true
        X3Script.schedule { [weak self] action in
            if action.hasPrefix("dump") { StatesScenes.deepDump(action.contains(":") ? String(action.split(separator: ":")[1]) : "x") }
            if action == "toggle", let it = self?.tabBar.items?[2] { it.isEnabled.toggle() }
        }
    }
}

final class DisabledAlertScene: StatesScene {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
    }

    override func run(_ action: String) {
        super.run(action)
        guard action == "show" else { return }
        let a: UIAlertController
        if env["PROBE_ALERTV"] == "col" {
            a = UIAlertController(title: "Title", message: "A message under the title.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Enabled", style: .default))
            let d = UIAlertAction(title: "Disabled", style: .default)
            d.isEnabled = false
            a.addAction(d)
            let dd = UIAlertAction(title: "Delete", style: .destructive)
            dd.isEnabled = false
            a.addAction(dd)
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            togglables = [{ d.isEnabled.toggle(); dd.isEnabled.toggle() }]
        } else {
            a = UIAlertController(title: "Rename", message: "Enter a name.", preferredStyle: .alert)
            a.addTextField { $0.placeholder = "Name" }
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            let ok = UIAlertAction(title: "OK", style: .default)
            ok.isEnabled = false
            a.addAction(ok)
            a.preferredAction = ok
            togglables = [{ ok.isEnabled.toggle() }]
        }
        present(a, animated: true)
    }
}

final class IndicatorsScene: StatesScene {
    let pv = UIProgressView(progressViewStyle: .default)
    let bar = UIProgressView(progressViewStyle: .bar)
    let ai = UIActivityIndicatorView(style: .medium)
    let ail = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        pv.progress = Float(Double(env["PROBE_PV0"] ?? "") ?? 0.2)
        bar.progress = pv.progress
        pv.accessibilityIdentifier = "x3_pv"
        bar.accessibilityIdentifier = "x3_bar"
        ai.accessibilityIdentifier = "x3_ai"
        ail.accessibilityIdentifier = "x3_ail"
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
        if action.hasPrefix("progressn:"), let v = Float(action.dropFirst(10)) { pv.setProgress(v, animated: false); bar.setProgress(v, animated: false) }
        if action == "stop" { ai.stopAnimating(); ail.stopAnimating() }
        if action == "start" { ai.startAnimating(); ail.startAnimating() }
        if action.hasPrefix("hide:") { let h = action.hasSuffix("1"); ai.hidesWhenStopped = h; ail.hidesWhenStopped = h }
    }
}
