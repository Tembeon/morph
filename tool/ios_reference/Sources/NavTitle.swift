import UIKit

/// Scene "navtitle": where UINavigationBar puts an inline title between its
/// leading and trailing groups. A root page ("Inbox") with one pushed page
/// whose navigationItem cycles through a matrix of titles, subtitles and bar
/// button groups; for every configuration it writes one JSON line to
/// Documents/navtitle.jsonl with the bar's labels (frame in bar coordinates,
/// intrinsic width, effective alpha) and its button views, plus a PNG of the
/// window (navtitle-<n>.png). PROBE_NAVTITLE_HOLD (s, default 0.7) is the
/// time per configuration; PROBE_NAVTITLE_ONLY=<i,j,..> restricts the set.
enum NavTitleScene {
    static func make() -> UIViewController {
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        root.title = "Inbox"
        let nav = UINavigationController(rootViewController: root)
        let page = NavTitlePage()
        DispatchQueue.main.async { nav.pushViewController(page, animated: false) }
        return nav
    }
}

struct NavTitleConfig {
    var title: String
    var subtitle: String?
    var leading: String
    var trailing: String
}

final class NavTitlePage: UITableViewController {
    private var configs: [NavTitleConfig] = []
    private var index = 0
    private var lines: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        navigationItem.largeTitleDisplayMode = .never
        let titles = [
            "Hi",
            "Message 4",
            "A medium length title",
            "A considerably longer navigation title",
            "An extremely long navigation title that cannot fit anywhere at all",
        ]
        let trailing = ["none", "icon", "pair", "pairDone", "wide", "wider"]
        let leading = ["back", "none", "wide"]
        for l in leading {
            for r in trailing {
                for t in titles {
                    configs.append(NavTitleConfig(title: t, subtitle: nil, leading: l, trailing: r))
                }
                configs.append(NavTitleConfig(title: "Message 4", subtitle: "From Anna, today", leading: l, trailing: r))
                configs.append(NavTitleConfig(title: "A considerably longer navigation title", subtitle: "With a subtitle that is long as well", leading: l, trailing: r))
            }
        }
        if let only = ProcessInfo.processInfo.environment["PROBE_NAVTITLE_ONLY"] {
            let keep = Set(only.split(separator: ",").compactMap { Int($0) })
            configs = configs.enumerated().filter { keep.contains($0.offset) }.map { $0.element }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 60 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        var c = cell.defaultContentConfiguration(); c.text = "Row \(indexPath.row)"; cell.contentConfiguration = c
        return cell
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.step() }
    }

    private var hold: Double { Double(ProcessInfo.processInfo.environment["PROBE_NAVTITLE_HOLD"] ?? "") ?? 0.7 }

    private func item(_ symbol: String) -> UIBarButtonItem {
        UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: nil, action: nil)
    }

    private func text(_ title: String) -> UIBarButtonItem {
        UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)
    }

    private func apply(_ c: NavTitleConfig) {
        let n = navigationItem
        n.title = c.title
        n.subtitle = c.subtitle
        switch c.leading {
        case "none":
            n.hidesBackButton = true
            n.leftBarButtonItems = nil
        case "wide":
            n.hidesBackButton = true
            n.leftBarButtonItems = [text("Cancel"), text("Organize")]
        default:
            n.hidesBackButton = false
            n.leftBarButtonItems = nil
        }
        switch c.trailing {
        case "icon": n.rightBarButtonItems = [item("plus")]
        case "pair": n.rightBarButtonItems = [item("square.and.arrow.up"), item("heart")]
        case "pairDone":
            let done = UIBarButtonItem(title: "Done", style: .prominent, target: nil, action: nil)
            n.rightBarButtonItems = [done, item("square.and.arrow.up"), item("heart")]
        case "wide": n.rightBarButtonItems = [text("Share"), text("Select")]
        case "wider": n.rightBarButtonItems = [text("Organize"), text("Share"), text("Select All")]
        default: n.rightBarButtonItems = nil
        }
    }

    private func step() {
        guard index < configs.count else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? (lines.joined(separator: "\n") + "\n").write(to: docs.appendingPathComponent("navtitle.jsonl"), atomically: true, encoding: .utf8)
            try? "done\n".write(to: docs.appendingPathComponent("navtitle.done"), atomically: true, encoding: .utf8)
            return
        }
        let c = configs[index]
        UIView.performWithoutAnimation { apply(c) }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            self.dump(c)
            self.index += 1
            self.step()
        }
    }

    private func r2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }

    private func dump(_ c: NavTitleConfig) {
        guard let bar = navigationController?.navigationBar, let window = view.window else { return }
        var labels: [[String: Any]] = []
        var buttons: [[String: Any]] = []
        func walk(_ v: UIView, _ alpha: CGFloat) {
            let a = alpha * v.alpha * (v.isHidden ? 0 : 1)
            let f = v.convert(v.bounds, to: bar)
            let cls = NSStringFromClass(type(of: v))
            if let l = v as? UILabel, let t = l.text, !t.isEmpty {
                labels.append(["text": t, "x": r2(f.minX), "y": r2(f.minY), "w": r2(f.width), "h": r2(f.height),
                               "iw": r2(l.intrinsicContentSize.width), "a": r2(a), "fs": r2(l.font.pointSize),
                               "lines": l.numberOfLines, "par": NSStringFromClass(type(of: l.superview ?? l))])
            } else if cls.contains("ButtonBarButton") || cls.contains("TitleControl") || cls.contains("HostedView") || cls.contains("TitleView") {
                buttons.append(["cls": cls, "x": r2(f.minX), "y": r2(f.minY), "w": r2(f.width), "h": r2(f.height), "a": r2(a)])
            }
            for s in v.subviews { walk(s, a) }
        }
        walk(bar, 1)
        let row: [String: Any] = ["i": index, "title": c.title, "subtitle": c.subtitle ?? "", "leading": c.leading,
                                  "trailing": c.trailing, "barW": r2(bar.bounds.width), "labels": labels, "views": buttons]
        if let data = try? JSONSerialization.data(withJSONObject: row), let s = String(data: data, encoding: .utf8) { lines.append(s) }
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: window.bounds.width, height: 130))
        let png = renderer.pngData { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? png.write(to: docs.appendingPathComponent("navtitle-\(index).png"))
    }
}
