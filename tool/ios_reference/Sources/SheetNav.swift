import UIKit
import QuartzCore

/// Probe scenes for the zoom transition, the back button menu and the bar glass container
/// (scene names start with "sn").
///
/// - snzoom: flat grey page, a chromatic source (PROBE_SRC=capsule|card|glass, default capsule:
///   140 x 48 magenta at PROBE_SRC_Y, default 300) presenting a page sheet with
///   preferredTransition .zoom; the sheet content is solid green (video geometry: chromatic
///   pixels over the achromatic, possibly dimmed, page). PROBE_DETENTS like w2sheet.
/// - snpush: the same source inside a UINavigationController, pushing a green page with
///   preferredTransition .zoom.
/// - snback: a navigation stack four deep (Mailboxes > Inbox > Thread > Message) for the back
///   button long-press menu; the tree is dumped 0.8 s after a context menu first appears.
/// - snbars: the bars probe scene (BarsListScene, PROBE_AUTO scripts) with the SDF layer
///   sampler on every frame (smoothness of the bar glass containers).
/// Every scene runs W2Sampler with its own class pattern; PROBE_SCRIPT actions: present,
/// dismiss, large, medium, push, pop, tree.
enum SheetNavScenes {
    static func make(_ name: String) -> UIViewController? {
        guard name.hasPrefix("sn") else { return nil }
        let env = ProcessInfo.processInfo.environment
        let pattern: String
        let vc: UIViewController
        switch name {
        case "snzoom":
            pattern = "UITransitionView|DropShadow|Dimming|Grabber|_UIPortal|Zoom|_UIReparenting|_UIPresentation"
            vc = ZoomHostScene()
        case "snpush":
            pattern = "UITransitionView|_UIPortal|Zoom|_UIReparenting|UILayoutContainerView|_UIParallax|NavigationTransition|DropShadow"
            let nav = UINavigationController(rootViewController: ZoomPushRoot())
            vc = nav
        case "snback":
            pattern = "ContextMenu|Menu|Morph|Platter|BackButton|_UIReparenting|Dimming|_UIButtonBar|Portal|TransformView"
            vc = BackStackScene.make()
        case "snbars":
            pattern = "^NONE$"
            BarsRecorder.shared.start()
            SDFFrameSampler.shared.start()
            let list = BarsListScene()
            vc = BarsNavController(rootViewController: list)
            if let seq = env["PROBE_SPLIT"] {
                var t = 2.0
                for name in seq.split(separator: ",") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        let items: [UIBarButtonItem]
                        switch name {
                        case "A": items = list.itemsA
                        case "B": items = list.itemsB
                        default: items = list.itemsC
                        }
                        Recorder.shared.log(["k": "evt", "e": "setToolbarItems", "set": String(name), "t": CACurrentMediaTime()])
                        list.setToolbarItems(items, animated: true)
                    }
                    t += 1.6
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { Recorder.shared.flush() }
            }
        default:
            pattern = "^NONE$"
            vc = UIViewController()
        }
        W2Sampler.shared.start(pattern: env["PROBE_W2TRACK"] ?? pattern)
        if name == "snback" { ContextMenuWatcher.shared.start() }
        return vc
    }

    static let grey = UIColor(white: 0.5, alpha: 1)
    static let magenta = UIColor(red: 1, green: 0, blue: 1, alpha: 1)
    static let green = UIColor(red: 0, green: 0.78, blue: 0, alpha: 1)

    static func source(_ kind: String) -> UIView {
        switch kind {
        case "glass":
            var config = UIButton.Configuration.glass()
            config.title = "Source"
            let b = UIButton(configuration: config)
            b.frame = CGRect(x: 0, y: 0, width: 140, height: 48)
            return b
        case "card":
            let v = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 100))
            v.backgroundColor = magenta
            v.layer.cornerRadius = 16
            v.layer.cornerCurve = .continuous
            return v
        default:
            let v = UIView(frame: CGRect(x: 0, y: 0, width: 140, height: 48))
            v.backgroundColor = magenta
            v.layer.cornerRadius = 24
            return v
        }
    }
}

final class ZoomSheetContent: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SheetNavScenes.green
        view.accessibilityIdentifier = "snSheet"
        let l = UILabel()
        l.text = "Zoomed sheet"
        l.font = .preferredFont(forTextStyle: .title2)
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
        ])
    }
}

final class ZoomHostScene: W2ScriptedScene, UISheetPresentationControllerDelegate {
    var src = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SheetNavScenes.grey
        src = SheetNavScenes.source(env["PROBE_SRC"] ?? "capsule")
        src.accessibilityIdentifier = "w2_src"
        let y = CGFloat(Double(env["PROBE_SRC_Y"] ?? "") ?? 300)
        src.center = CGPoint(x: 201, y: y)
        view.addSubview(src)
        src.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        if let b = src as? UIButton { b.addTarget(self, action: #selector(tapped), for: .touchUpInside) }
    }

    @objc func tapped() { run("present") }

    func doPresent() {
        let content = ZoomSheetContent()
        content.modalPresentationStyle = env["PROBE_STYLE"] == "full" ? .fullScreen : .pageSheet
        content.preferredTransition = .zoom { [weak self] _ in self?.src }
        if let sheet = content.sheetPresentationController {
            let detents = env["PROBE_DETENTS"] ?? "ml"
            var list: [UISheetPresentationController.Detent] = []
            if detents.contains("m") { list.append(.medium()) }
            if detents.contains("l") { list.append(.large()) }
            sheet.detents = list
            sheet.prefersGrabberVisible = env["PROBE_GRABBER"] != "0"
            sheet.delegate = self
            if let start = env["PROBE_START"] { sheet.selectedDetentIdentifier = start == "l" ? .large : .medium }
        }
        Recorder.shared.log(["k": "evt", "e": "present", "t": CACurrentMediaTime(),
                             "src": [src.frame.minX, src.frame.minY, src.frame.width, src.frame.height]])
        present(content, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Recorder.shared.log(["k": "evt", "e": "dismissed", "t": CACurrentMediaTime()])
    }

    override func run(_ action: String) {
        super.run(action)
        let sheet = presentedViewController?.sheetPresentationController
        switch action {
        case "present": doPresent()
        case "dismiss":
            Recorder.shared.log(["k": "evt", "e": "dismiss", "t": CACurrentMediaTime()])
            dismiss(animated: true)
        case "large": sheet?.animateChanges { sheet?.selectedDetentIdentifier = .large }
        case "medium": sheet?.animateChanges { sheet?.selectedDetentIdentifier = .medium }
        case "frames":
            if let pv = presentedViewController?.view, let w = view.window {
                let f = pv.convert(pv.bounds, to: w)
                Recorder.shared.log(["k": "evt", "e": "frames", "t": CACurrentMediaTime(), "sheet": [f.minX, f.minY, f.width, f.height]])
            }
        default: break
        }
    }
}

final class ZoomPushRoot: W2ScriptedScene {
    var src = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Grid"
        view.backgroundColor = SheetNavScenes.grey
        src = SheetNavScenes.source(env["PROBE_SRC"] ?? "card")
        src.accessibilityIdentifier = "w2_src"
        let y = CGFloat(Double(env["PROBE_SRC_Y"] ?? "") ?? 300)
        src.center = CGPoint(x: 201, y: y)
        view.addSubview(src)
        src.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @objc func tapped() { run("push") }

    override func run(_ action: String) {
        super.run(action)
        switch action {
        case "push":
            let detail = ZoomSheetContent()
            detail.title = "Detail"
            detail.preferredTransition = .zoom { [weak self] _ in self?.src }
            Recorder.shared.log(["k": "evt", "e": "push", "t": CACurrentMediaTime(),
                                 "src": [src.frame.minX, src.frame.minY, src.frame.width, src.frame.height]])
            navigationController?.pushViewController(detail, animated: true)
        case "pop":
            Recorder.shared.log(["k": "evt", "e": "pop", "t": CACurrentMediaTime()])
            navigationController?.popViewController(animated: true)
        default: break
        }
    }
}

final class BackStackPage: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        let l = UILabel()
        l.text = title
        l.font = .preferredFont(forTextStyle: .largeTitle)
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

enum BackStackScene {
    static func make() -> UIViewController {
        let env = ProcessInfo.processInfo.environment
        let titles = (env["PROBE_STACK"] ?? "Mailboxes,Inbox,Thread,Message").split(separator: ",").map(String.init)
        let pages: [UIViewController] = titles.map { t in
            let p = BackStackPage()
            p.title = t
            return p
        }
        let nav = UINavigationController()
        if let d = env["PROBE_DARK"] { nav.overrideUserInterfaceStyle = d == "1" ? .dark : .light }
        nav.setViewControllers(pages, animated: false)
        nav.delegate = BackStackDelegate.shared
        return nav
    }
}

final class BackStackDelegate: NSObject, UINavigationControllerDelegate {
    static let shared = BackStackDelegate()

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        Recorder.shared.log(["k": "evt", "e": "willShow", "title": viewController.title ?? "", "animated": animated,
                             "depth": navigationController.viewControllers.count, "t": CACurrentMediaTime()])
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        Recorder.shared.log(["k": "evt", "e": "didShow", "title": viewController.title ?? "",
                             "depth": navigationController.viewControllers.count, "t": CACurrentMediaTime()])
    }
}

/// Dumps the view tree once, 0.8 s after a context menu container first appears, and logs the
/// appearance and disappearance moments.
final class ContextMenuWatcher: NSObject {
    static let shared = ContextMenuWatcher()
    private var link: CADisplayLink?
    private var shown = false
    private var dumps = 0

    func start() {
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        var found = false
        func walk(_ v: UIView) {
            if found { return }
            if NSStringFromClass(type(of: v)).contains("ContextMenuContainer") { found = true; return }
            v.subviews.forEach(walk)
        }
        for scene in UIApplication.shared.connectedScenes {
            for w in (scene as? UIWindowScene)?.windows ?? [] { walk(w) }
        }
        if found != shown {
            shown = found
            Recorder.shared.log(["k": "evt", "e": found ? "menuShown" : "menuGone", "t": l.timestamp])
            if found && dumps < 2 {
                dumps += 1
                let n = dumps
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { W2Sampler.shared.tree("tree-back-menu-\(n).txt") }
            }
        }
    }
}
