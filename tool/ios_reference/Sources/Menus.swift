import UIKit
import SwiftUI

/// Probe scenes for the MENU API (scene names start with "x5menu"; the Recorder runs in
/// menu mode for them: morph-container `L` rows, `frame` rows of every view matching
/// PROBE_TRACK, window rows, tree dumps with PROBE_DUMPS=1). One glass button (48 x 48,
/// ellipsis, identifier "x5btn") at x center, y 150 (PROBE_BY overrides), so menus open
/// downward; `showsMenuAsPrimaryAction`.
///
/// PROBE_MENU picks the menu:
/// - sub: Copy, Share, More > (Sub one, Sub two, Deeper > (Deep one, Deep two)), Delete;
/// - rich1: an inline titled single-selection section "Sort by" (Name on, Date, Size;
///   keepsMenuPresented), an untitled inline group (Show hidden toggle on, Mixed state),
///   a row with a subtitle, a disabled row, a hidden row (not shown), a destructive row;
/// - rich2: a palette (displayAsPalette, single selection, 5 color dots), a small
///   element group (4 actions), a medium group (3 actions), an inline submenu, a plain row;
/// - tall: 30 rows (scrolling);
/// - resize: "Add row" / "Remove row" (keepsMenuPresented, updateVisibleMenu) over 3 rows;
/// - deferred: Copy + an uncached UIDeferredMenuElement answered after PROBE_DEFER s (1.0);
/// - swiftui: a SwiftUI Menu (Section, Divider, Picker inline + palette, ControlGroup,
///   Toggle, Slider, Stepper, Label with subtitle, destructive role, a counter button with
///   menuActionDismissBehavior(.disabled), nested Menu).
/// Actions log `evt` rows (e action, title).
enum MenuScenes {
    static func make(_ name: String) -> UIViewController? {
        guard name.hasPrefix("x5menu") else { return nil }
        let env = ProcessInfo.processInfo.environment
        X3Sampler.shared.start(pattern: env["PROBE_X3TRACK"] ?? "^NONE$")
        if env["PROBE_MENU"] == "swiftui" {
            let host = UIHostingController(rootView: SwiftUIMenuProbe())
            return host
        }
        return MenuAPIScene()
    }

    static func log(_ title: String) {
        Recorder.shared.log(["k": "evt", "e": "action", "title": title, "t": CACurrentMediaTime()])
    }
}

final class MenuAPIScene: StatesScene {
    let button = UIButton(configuration: .glass())
    var extraRows = 0

    func act(_ title: String, image: String? = nil, attributes: UIMenuElement.Attributes = [], state: UIMenuElement.State = .off, subtitle: String? = nil, keeps: Bool = false) -> UIAction {
        var attrs = attributes
        if keeps { attrs.insert(.keepsMenuPresented) }
        let a = UIAction(title: title, image: image.map { UIImage(systemName: $0)! }, attributes: attrs, state: state) { [weak self] action in
            MenuScenes.log(action.title)
            self?.handle(action)
        }
        a.subtitle = subtitle
        return a
    }

    func handle(_ action: UIAction) {
        switch action.title {
        case "Add row":
            extraRows += 1
            button.contextMenuInteraction?.updateVisibleMenu { [weak self] _ in self?.makeMenu() ?? UIMenu(children: []) }
        case "Remove row":
            extraRows = max(0, extraRows - 1)
            button.contextMenuInteraction?.updateVisibleMenu { [weak self] _ in self?.makeMenu() ?? UIMenu(children: []) }
        case "Show hidden":
            action.state = action.state == .on ? .off : .on
        default:
            break
        }
    }

    func dot(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 20, height: 20)).fill()
        }.withRenderingMode(.alwaysOriginal)
    }

    func makeMenu() -> UIMenu {
        switch env["PROBE_MENU"] ?? "sub" {
        case "rich1":
            let sort = UIMenu(title: "Sort by", options: [.displayInline, .singleSelection], children: [
                act("Name", image: "textformat", state: .on, keeps: true),
                act("Date", image: "calendar", keeps: true),
                act("Size", image: "arrow.up.arrow.down", keeps: true),
            ])
            let group = UIMenu(title: "", options: .displayInline, children: [
                act("Show hidden", image: "eye", state: .on, keeps: true),
                act("Mixed state", image: "circle.lefthalf.filled", state: .mixed),
            ])
            return UIMenu(children: [
                sort, group,
                act("With subtitle", image: "text.alignleft", subtitle: "A second line of detail"),
                act("Disabled row", image: "nosign", attributes: .disabled),
                act("Hidden row", attributes: .hidden),
                act("Delete", image: "trash", attributes: .destructive),
            ])
        case "rich2":
            let colors: [(String, UIColor)] = [("Red", .systemRed), ("Orange", .systemOrange), ("Green", .systemGreen), ("Blue", .systemBlue), ("Purple", .systemPurple)]
            let palette = UIMenu(title: "Color", options: [.displayInline, .displayAsPalette, .singleSelection], children: colors.enumerated().map { i, c in
                let a = UIAction(title: c.0, image: dot(c.1), attributes: .keepsMenuPresented, state: i == 3 ? .on : .off) { a in MenuScenes.log(a.title) }
                return a
            })
            let small = UIMenu(title: "", options: .displayInline, children: [
                act("Cut", image: "scissors"), act("Copy", image: "doc.on.doc"), act("Paste", image: "doc.on.clipboard"), act("Share", image: "square.and.arrow.up"),
            ])
            small.preferredElementSize = .small
            let medium = UIMenu(title: "", options: .displayInline, children: [
                act("Bold", image: "bold"), act("Italic", image: "italic"), act("Underline", image: "underline"),
            ])
            medium.preferredElementSize = .medium
            let inlineSub = UIMenu(title: "Inline submenu", options: .displayInline, children: [act("Inline one"), act("Inline two")])
            return UIMenu(children: [palette, small, medium, inlineSub, act("Plain row", image: "star")])
        case "tall":
            return UIMenu(children: (1...30).map { act("Row \($0)", image: "circle") })
        case "resize":
            var kids: [UIMenuElement] = [act("Add row", image: "plus", keeps: true), act("Remove row", image: "minus", keeps: true), act("Fixed row", image: "star")]
            kids += (0..<extraRows).map { act("Extra \($0 + 1)", image: "circle") }
            return UIMenu(children: kids)
        case "deferred":
            let delay = Double(env["PROBE_DEFER"] ?? "") ?? 1.0
            let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    completion([self?.act("Loaded one", image: "1.circle"), self?.act("Loaded two", image: "2.circle"), self?.act("Loaded three", image: "3.circle")].compactMap { $0 })
                }
            }
            return UIMenu(children: [act("Copy", image: "doc.on.doc"), deferred])
        default:
            let deeper = UIMenu(title: "Deeper", image: UIImage(systemName: "ellipsis.circle"), children: [act("Deep one"), act("Deep two")])
            let more = UIMenu(title: "More", image: UIImage(systemName: "folder"), children: [act("Sub one", image: "1.circle"), act("Sub two", image: "2.circle"), deeper])
            return UIMenu(children: [act("Copy", image: "doc.on.doc"), act("Share", image: "square.and.arrow.up"), more, act("Delete", image: "trash", attributes: .destructive)])
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ExtrasScenes.spinner(view.window)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        var c = UIButton.Configuration.glass()
        c.image = UIImage(systemName: "ellipsis")
        button.configuration = c
        button.menu = makeMenu()
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "x5btn"
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        let y = CGFloat(Double(env["PROBE_BY"] ?? "") ?? 150)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.topAnchor, constant: y),
            button.widthAnchor.constraint(equalToConstant: 48), button.heightAnchor.constraint(equalToConstant: 48),
        ])
    }
}

struct SwiftUIMenuProbe: View {
    @State private var sort = "Name"
    @State private var color = "Blue"
    @State private var hidden = true
    @State private var volume = 0.4
    @State private var count = 0
    @State private var steps = 2

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            Menu {
                Button { count += 1; MenuScenes.log("Count") } label: {
                    Label("Count \(count)", systemImage: "plus")
                }
                .menuActionDismissBehavior(.disabled)
                Button { MenuScenes.log("Subtitle") } label: {
                    Text("With subtitle")
                    Text("A second line of detail")
                }
                Section("Sort by") {
                    Picker("Sort", selection: $sort) {
                        Label("Name", systemImage: "textformat").tag("Name")
                        Label("Date", systemImage: "calendar").tag("Date")
                    }
                    .pickerStyle(.inline)
                }
                Picker("Color", selection: $color) {
                    ForEach(["Red", "Green", "Blue"], id: \.self) { c in
                        Image(systemName: "circle.fill").tint(c == "Red" ? .red : c == "Green" ? .green : .blue).tag(c)
                    }
                }
                .pickerStyle(.palette)
                ControlGroup {
                    Button("Cut", systemImage: "scissors") { MenuScenes.log("Cut") }
                    Button("Copy", systemImage: "doc.on.doc") { MenuScenes.log("Copy") }
                    Button("Paste", systemImage: "doc.on.clipboard") { MenuScenes.log("Paste") }
                }
                Divider()
                Toggle(isOn: $hidden) { Label("Show hidden", systemImage: "eye") }
                Slider(value: $volume) { Text("Volume") }
                Stepper("Steps \(steps)", value: $steps)
                Menu("More") {
                    Button("Sub one") { MenuScenes.log("Sub one") }
                    Button("Sub two") { MenuScenes.log("Sub two") }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { MenuScenes.log("Delete") }
            } label: {
                Image(systemName: "ellipsis").frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("x5btn")
            .padding(.top, 126)
        }
        .onAppear {
            X3Script.schedule { action in
                if action.hasPrefix("dump") { StatesScenes.deepDump(action.contains(":") ? String(action.split(separator: ":")[1]) : "x") }
            }
        }
    }
}
