import UIKit

/// Scene names:
/// - segmented (default): seg2/seg3/seg4/seg5/segContent/segContent4/segNarrow rows;
/// - tabbar<N>: floating tab bar with N (2..5) tabs;
/// - sw, swOn, st, st5, sl<W>, slT<N>, slV<pct>, gb<W>x<H>, gbp<W>x<H>: one centered control
///   (see Controls.swift);
/// - menu: glass button menu, shaped by PROBE_POS (center/tl/tr/bl/br/bottom/left),
///   PROBE_ITEMS, PROBE_WIDE=1, PROBE_CTX=1, PROBE_SUBMENU=1; nav bar button menu too;
/// - controls: the old mixed controls page;
/// - glassGrid: glass shapes and a tab bar over the measurement grid (GlassGrid.swift).
enum Scenes {
    static func isSingleControl(_ name: String) -> Bool {
        ["sw", "swOn", "st", "st5"].contains(name) || name.hasPrefix("sl") || name.hasPrefix("gb")
    }

    static func make(_ name: String) -> UIViewController {
        if let w2 = Widgets2Scenes.make(name) { return w2 }
        if let x3 = ExtrasScenes.make(name) { return x3 }
        if name.hasPrefix("tabbar") {
            let count = Int(name.dropFirst("tabbar".count)) ?? 4
            return TabBarScene(count: count)
        }
        if isSingleControl(name) {
            return SingleControlScene(name: name)
        }
        switch name {
        case "merge":
            return MergeScene()
        case "glassGrid":
            return GlassGridScene()
        case "mergeDyn":
            return MergeDynScene()
        case "mergeID":
            return MergeIDScene()
        case "menu":
            return UINavigationController(rootViewController: MenuScene())
        case "nav":
            BarsRecorder.shared.start()
            return BarsNavController(rootViewController: BarsListScene())
        case "controls":
            return ControlsScene()
        default:
            return SegmentedScene()
        }
    }
}

final class SegmentedScene: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 22
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
        ])
        let rows: [(String, [String], Bool)] = [
            ("seg2", ["Day", "Night"], false),
            ("seg3", ["A", "B", "C"], false),
            ("seg4", ["1", "2", "3", "4"], false),
            ("seg5", ["1", "2", "3", "4", "5"], false),
            ("segContent", ["All", "Unread messages", "VIP"], true),
            ("segContent4", ["A", "Wide segment here", "B", "Mid size"], true),
        ]
        for (id, items, byContent) in rows {
            let control = UISegmentedControl(items: items)
            control.apportionsSegmentWidthsByContent = byContent
            control.selectedSegmentIndex = 0
            control.accessibilityIdentifier = id
            stack.addArrangedSubview(control)
        }
        let narrow = UISegmentedControl(items: ["X", "Y", "Z"])
        narrow.selectedSegmentIndex = 0
        narrow.accessibilityIdentifier = "segNarrow"
        let holder = UIView()
        holder.addSubview(narrow)
        narrow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            narrow.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            narrow.topAnchor.constraint(equalTo: holder.topAnchor),
            narrow.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            narrow.widthAnchor.constraint(equalToConstant: 150),
        ])
        stack.addArrangedSubview(holder)
    }
}

final class TabBarScene: UITabBarController {
    init(count: Int) {
        super.init(nibName: nil, bundle: nil)
        let symbols = ["house", "books.vertical", "dot.radiowaves.left.and.right", "person", "gearshape"]
        let titles = ["Home", "Library", "Radio", "Profile", "Settings"]
        viewControllers = (0..<max(2, min(5, count))).map { index in
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = titles[index]
            label.font = .preferredFont(forTextStyle: .largeTitle)
            label.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
            ])
            vc.tabBarItem = UITabBarItem(title: titles[index], image: UIImage(systemName: symbols[index]), tag: index)
            return vc
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class MenuScene: UIViewController {
    let env = ProcessInfo.processInfo.environment

    func makeMenu() -> UIMenu {
        let count = Int(env["PROBE_ITEMS"] ?? "3") ?? 3
        let titles = ["Copy", "Share", "Delete", "Rename", "Duplicate", "Move", "Favorite", "Pin", "Archive", "Print", "Export", "Info"]
        let symbols = ["doc.on.doc", "square.and.arrow.up", "trash", "pencil", "plus.square.on.square", "folder", "heart", "pin", "archivebox", "printer", "arrow.up.doc", "info.circle"]
        var actions: [UIMenuElement] = (0..<max(1, min(12, count))).map { i in
            UIAction(title: titles[i], image: UIImage(systemName: symbols[i]), attributes: titles[i] == "Delete" ? .destructive : []) { _ in
                Recorder.shared.log(["k": "action", "t": CACurrentMediaTime(), "title": titles[i]])
            }
        }
        if env["PROBE_SUBMENU"] == "1" {
            let sub = UIMenu(title: "More", image: UIImage(systemName: "ellipsis.circle"), children: [
                UIAction(title: "Sub one") { _ in }, UIAction(title: "Sub two") { _ in }, UIAction(title: "Sub three") { _ in },
            ])
            actions.insert(sub, at: min(1, actions.count))
        }
        return UIMenu(children: actions)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Menu"
        let menu = makeMenu()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: menu)
        let pos = env["PROBE_POS"] ?? "center"
        var config = UIButton.Configuration.glass()
        let wide = env["PROBE_WIDE"] == "1"
        if wide { config.title = "Sort by name" } else { config.image = UIImage(systemName: "ellipsis") }
        let inline = UIButton(configuration: config)
        inline.menu = menu
        inline.showsMenuAsPrimaryAction = true
        inline.accessibilityIdentifier = "inlineMenu"
        inline.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inline)
        let g = view.safeAreaLayoutGuide
        var cs: [NSLayoutConstraint] = [inline.heightAnchor.constraint(equalToConstant: 48)]
        if !wide { cs.append(inline.widthAnchor.constraint(equalToConstant: 48)) }
        switch pos {
        case "tl": cs += [inline.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 20), inline.topAnchor.constraint(equalTo: g.topAnchor, constant: 80)]
        case "tr": cs += [inline.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -20), inline.topAnchor.constraint(equalTo: g.topAnchor, constant: 80)]
        case "bl": cs += [inline.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 20), inline.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -20)]
        case "br": cs += [inline.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -20), inline.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -20)]
        case "bottom": cs += [inline.centerXAnchor.constraint(equalTo: g.centerXAnchor), inline.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -20)]
        case "left": cs += [inline.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 20), inline.centerYAnchor.constraint(equalTo: g.centerYAnchor)]
        default: cs += [inline.centerXAnchor.constraint(equalTo: view.centerXAnchor), inline.centerYAnchor.constraint(equalTo: view.centerYAnchor)]
        }
        NSLayoutConstraint.activate(cs)
        if env["PROBE_CTX"] == "1" {
            let card = UIView()
            card.backgroundColor = .systemBlue
            card.layer.cornerRadius = 16
            card.accessibilityIdentifier = "ctxCard"
            card.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(card)
            NSLayoutConstraint.activate([
                card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                card.topAnchor.constraint(equalTo: g.topAnchor, constant: 60),
                card.widthAnchor.constraint(equalToConstant: 120), card.heightAnchor.constraint(equalToConstant: 80),
            ])
            card.addInteraction(UIContextMenuInteraction(delegate: self))
        }
    }
}

extension MenuScene: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in self.makeMenu() }
    }
}

final class ControlsScene: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
        ])
        let toggle = UISwitch()
        toggle.accessibilityIdentifier = "switch"
        let toggleRow = UIStackView(arrangedSubviews: [UILabel(), toggle])
        stack.addArrangedSubview(toggleRow)
        let slider = UISlider()
        slider.value = 0.3
        slider.accessibilityIdentifier = "slider"
        stack.addArrangedSubview(slider)
        let stepper = UIStepper()
        stepper.accessibilityIdentifier = "stepper"
        stack.addArrangedSubview(stepper)
        var config = UIButton.Configuration.glass()
        config.title = "Glass button"
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = "glassButton"
        stack.addArrangedSubview(button)
    }
}
