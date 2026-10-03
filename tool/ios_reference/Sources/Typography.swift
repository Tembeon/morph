import UIKit
import CoreText

/// The typography dump (scene "fonts"): what UIKit's controls actually draw their labels
/// with. Writes Documents/fonts.jsonl and NSLogs every row prefixed "FONTS ".
///
/// Rows:
/// - `k: "sys"`: the system font per size and weight - PostScript name, the variation axes
///   CoreText instantiated (opsz/wght), the width of sample strings as UIKit lays them out,
///   the same with tracking forced to 0, and the automatic tracking derived from a run of
///   "n" (per glyph, pt);
/// - `k: "label"`: every UILabel / text field on screen at a stage (segmented, tab bar,
///   glass and bar buttons, nav titles, toolbar, search, date picker, alert, menu): text,
///   font name, size, weight trait, opsz, the kern attribute if any, the label's frame
///   width and the laid-out text width.
enum TypographyScenes {
    static func make(_ name: String) -> UIViewController? {
        guard name == "fonts" else { return nil }
        return TypographyRoot()
    }
}

final class TypographyDump {
    static let shared = TypographyDump()
    private var lines: [String] = []

    func emit(_ row: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return }
        lines.append(s)
        NSLog("FONTS %@", s)
        flush()
    }

    func flush() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("fonts.jsonl"), atomically: true, encoding: .utf8)
    }
}

private func r3(_ v: CGFloat) -> Double { (Double(v) * 1000).rounded() / 1000 }

private func axes(_ font: UIFont) -> [String: Double] {
    var out: [String: Double] = [:]
    let ct = font as CTFont
    guard let variation = CTFontCopyVariation(ct) as? [NSNumber: NSNumber],
          let axesInfo = CTFontCopyVariationAxes(ct) as? [[CFString: Any]] else { return out }
    for axis in axesInfo {
        guard let id = axis[kCTFontVariationAxisIdentifierKey] as? NSNumber else { continue }
        let tag = id.uint32Value
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((tag >> $0) & 0xFF))) }
        out[String(chars)] = variation[id]?.doubleValue ?? (axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue
    }
    return out
}

private func weightTrait(_ font: UIFont) -> Double {
    (font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? Double ?? 0
}

private func lineWidth(_ text: String, _ font: UIFont, tracking: CGFloat? = nil) -> Double {
    var attrs: [NSAttributedString.Key: Any] = [.font: font]
    if let tracking { attrs[.tracking] = tracking }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    return Double(CTLineGetTypographicBounds(line, nil, nil, nil))
}

let typographySamples = ["Unread messages", "All", "VIP", "Day", "Night", "Glass button", "Home", "Library",
                         "Cancel", "OK", "Search", "Copy", "Settings", "Large Title", "September 2026", "nnnnnnnnnn"]

func dumpSystemFonts() {
    let weights: [(String, UIFont.Weight)] = [("regular", .regular), ("medium", .medium), ("semibold", .semibold), ("bold", .bold)]
    let sizes: [CGFloat] = (6...40).map { CGFloat($0) } + [44, 48, 56, 64, 72, 80, 88, 96]
    let weighed: Set<CGFloat> = [10, 13, 15, 17, 20, 22, 28, 34]
    for size in sizes {
        for (wname, w) in weights where wname == "regular" || weighed.contains(size) {
            let font = UIFont.systemFont(ofSize: size, weight: w)
            let n1 = lineWidth("n", font)
            let n21 = lineWidth(String(repeating: "n", count: 21), font)
            let z1 = lineWidth("n", font, tracking: 0)
            let z21 = lineWidth(String(repeating: "n", count: 21), font, tracking: 0)
            var widths: [String: Double] = [:]
            var flat: [String: Double] = [:]
            for s in typographySamples {
                widths[s] = r3(lineWidth(s, font))
                flat[s] = r3(lineWidth(s, font, tracking: 0))
            }
            TypographyDump.shared.emit([
                "k": "sys", "size": Double(size), "weight": wname, "wt": r3(weightTrait(font)),
                "name": font.fontName, "family": font.familyName, "axes": axes(font),
                "trackPerGlyph": r3((n21 - n1) / 20 - (z21 - z1) / 20),
                "advN": r3((z21 - z1) / 20),
                "w": widths, "w0": flat,
                "asc": r3(font.ascender), "desc": r3(font.descender), "lineH": r3(font.lineHeight), "leading": r3(font.leading),
            ])
        }
    }
    let styles: [UIFont.TextStyle] = [.largeTitle, .title1, .title2, .title3, .headline, .body, .callout, .subheadline, .footnote, .caption1, .caption2]
    for st in styles {
        let font = UIFont.preferredFont(forTextStyle: st)
        TypographyDump.shared.emit(["k": "style", "style": st.rawValue, "name": font.fontName, "size": Double(font.pointSize), "wt": r3(weightTrait(font)), "axes": axes(font), "lineH": r3(font.lineHeight)])
    }
}

func dumpLabels(stage: String, windows: [UIWindow]) {
    func visit(_ v: UIView, path: String) {
        if v.isHidden || v.alpha < 0.01 { return }
        let cls = String(describing: type(of: v))
        var text: String?
        var font: UIFont?
        var attributed: NSAttributedString?
        if let l = v as? UILabel { text = l.text; font = l.font; attributed = l.attributedText }
        if let tf = v as? UITextField {
            text = (tf.text?.isEmpty ?? true) ? tf.placeholder : tf.text
            font = tf.font
            attributed = (tf.text?.isEmpty ?? true) ? tf.attributedPlaceholder : tf.attributedText
        }
        if let text, !text.isEmpty, let font {
            var kern: Double?
            var tracking: Double?
            var aFont: UIFont?
            if let a = attributed, a.length > 0 {
                kern = (a.attribute(.kern, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue
                tracking = (a.attribute(.tracking, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue
                aFont = a.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            }
            let used = aFont ?? font
            let frame = v.convert(v.bounds, to: nil)
            var row: [String: Any] = [
                "k": "label", "stage": stage, "cls": cls, "path": path, "text": text,
                "name": used.fontName, "size": Double(used.pointSize), "wt": r3(weightTrait(used)), "axes": axes(used),
                "frameW": r3(frame.width), "frameX": r3(frame.minX), "frameY": r3(frame.minY), "frameH": r3(frame.height),
                "textW": r3(attributed.map { CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString($0), nil, nil, nil)) } ?? 0),
                "plainW": r3(lineWidth(text, used)),
            ]
            if let kern { row["kern"] = kern }
            if let tracking { row["tracking"] = tracking }
            TypographyDump.shared.emit(row)
        }
        for s in v.subviews { visit(s, path: path + "/" + String(describing: type(of: s))) }
    }
    for w in windows { visit(w, path: String(describing: type(of: w))) }
}

final class TypographyRoot: UITabBarController {
    let content = TypographyContent()

    override func viewDidLoad() {
        super.viewDidLoad()
        let nav = UINavigationController(rootViewController: content)
        nav.navigationBar.prefersLargeTitles = true
        nav.isToolbarHidden = false
        nav.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0)
        let titles = ["Library", "Radio", "Profile"]
        let symbols = ["books.vertical", "dot.radiowaves.left.and.right", "person"]
        var vcs: [UIViewController] = [nav]
        for i in 0..<titles.count {
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            vc.tabBarItem = UITabBarItem(title: titles[i], image: UIImage(systemName: symbols[i]), tag: i + 1)
            vcs.append(vc)
        }
        viewControllers = vcs
    }

    private var started = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if started { return }
        started = true
        dumpSystemFonts()
        run()
    }

    private func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    }

    private func after(_ s: Double, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: body)
    }

    private func run() {
        after(1.0) {
            dumpLabels(stage: "main", windows: self.windows())
            self.content.navigationItem.largeTitleDisplayMode = .never
            self.content.navigationController?.navigationBar.prefersLargeTitles = false
        }
        after(2.0) {
            dumpLabels(stage: "inline", windows: self.windows())
            let alert = UIAlertController(title: "Delete message?", message: "This cannot be undone.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive))
            self.present(alert, animated: true)
        }
        after(3.5) {
            dumpLabels(stage: "alert", windows: self.windows())
            let sheet = UIAlertController(title: "Sort by", message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Name", style: .default))
            sheet.addAction(UIAlertAction(title: "Date", style: .default))
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            self.dismiss(animated: false) { self.present(sheet, animated: true) }
        }
        after(5.0) {
            dumpLabels(stage: "actionSheet", windows: self.windows())
            self.dismiss(animated: false)
        }
        after(5.8) {
            if let interaction = self.content.menuButton.contextMenuInteraction {
                let sel = NSSelectorFromString("_presentMenuAtLocation:")
                if interaction.responds(to: sel) {
                    typealias Present = @convention(c) (AnyObject, Selector, CGPoint) -> Void
                    let imp = interaction.method(for: sel)
                    unsafeBitCast(imp, to: Present.self)(interaction, sel, CGPoint(x: 20, y: 20))
                } else {
                    NSLog("FONTS no _presentMenuAtLocation:")
                }
            }
        }
        after(7.3) {
            dumpLabels(stage: "menu", windows: self.windows())
            self.content.dismiss(animated: false)
            self.dismiss(animated: false)
        }
        after(8.0) {
            self.content.search.isActive = true
            self.content.search.searchBar.searchTextField.becomeFirstResponder()
        }
        after(9.5) {
            dumpLabels(stage: "searchActive", windows: self.windows())
            NSLog("FONTS done")
        }
    }
}

final class TypographyContent: UIViewController {
    let menuButton: UIButton = {
        var config = UIButton.Configuration.glass()
        config.title = "Sort by name"
        let b = UIButton(configuration: config)
        b.menu = UIMenu(children: ["Copy", "Share", "Delete", "Rename"].map { UIAction(title: $0) { _ in } })
        b.showsMenuAsPrimaryAction = true
        return b
    }()
    let search = UISearchController(searchResultsController: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .prominent, target: nil, action: nil)
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        toolbarItems = [UIBarButtonItem(title: "Select", style: .plain, target: nil, action: nil), .flexibleSpace(),
                        UIBarButtonItem(title: "Share", style: .prominent, target: nil, action: nil)]
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
        let seg = UISegmentedControl(items: ["All", "Unread messages", "VIP"])
        seg.apportionsSegmentWidthsByContent = true
        seg.selectedSegmentIndex = 0
        stack.addArrangedSubview(seg)
        let seg2 = UISegmentedControl(items: ["Day", "Night"])
        seg2.selectedSegmentIndex = 1
        stack.addArrangedSubview(seg2)
        var glass = UIButton.Configuration.glass()
        glass.title = "Glass button"
        stack.addArrangedSubview(UIButton(configuration: glass))
        var prominent = UIButton.Configuration.prominentGlass()
        prominent.title = "Continue"
        stack.addArrangedSubview(UIButton(configuration: prominent))
        stack.addArrangedSubview(menuButton)
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 14)) ?? Date()
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.widthAnchor.constraint(equalToConstant: 340).isActive = true
        holder.heightAnchor.constraint(equalToConstant: 380).isActive = true
        picker.frame = CGRect(x: 0, y: 0, width: 340, height: 380)
        holder.addSubview(picker)
        stack.addArrangedSubview(holder)
        let compact = UIDatePicker()
        compact.datePickerMode = .dateAndTime
        compact.preferredDatePickerStyle = .compact
        stack.addArrangedSubview(compact)
    }
}
