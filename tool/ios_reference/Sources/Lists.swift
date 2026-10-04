import UIKit

/// Scene `list`: an inset grouped UITableView under a large-title navigation
/// bar, with the cell configurations an app's settings and index screens use
/// (plain, subtitle, value, leading symbol, disclosure, switch), a section
/// header and footer, and one selected row. 1.5 s after launch it writes the
/// view tree (frames in window points, corner radii, resolved colors, fonts)
/// to Documents/list-tree.txt, plus the resolved grouped-cell background
/// colors for the normal, highlighted and selected states.
/// `PROBE_LISTSTYLE=plain` uses a plain table instead.
enum ListScenes {
    static func make(_ name: String) -> UIViewController? {
        guard name == "list" else { return nil }
        let nav = UINavigationController(rootViewController: ListScene())
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
}

final class ListScene: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let plain = ProcessInfo.processInfo.environment["PROBE_LISTSTYLE"] == "plain"
    private lazy var table = UITableView(frame: .zero, style: plain ? .plain : .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Widgets"
        navigationItem.largeTitleDisplayMode = .always
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        view.addSubview(table)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.table.selectRow(at: IndexPath(row: 0, section: 1), animated: false, scrollPosition: .none)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.dump() }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 4 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        [5, 2, 3, 1][section]
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        [0: "Controls", 3: "More"][section]
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "A footer explains the section above it." : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        var content: UIListContentConfiguration
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            content = .cell()
            content.text = "Segmented control"
            cell.accessoryType = .disclosureIndicator
        case (0, 1):
            content = .subtitleCell()
            content.text = "Tab bar"
            content.secondaryText = "Floating bar with 2 to 5 tabs"
            cell.accessoryType = .disclosureIndicator
        case (0, 2):
            content = .valueCell()
            content.text = "Width"
            content.secondaryText = "94"
        case (0, 3):
            content = .cell()
            content.text = "Settings"
            content.image = UIImage(systemName: "gear")
            cell.accessoryType = .disclosureIndicator
        case (0, 4):
            content = .cell()
            content.text = "Loupe"
            let toggle = UISwitch()
            toggle.isOn = true
            cell.accessoryView = toggle
        case (1, 0):
            content = .cell()
            content.text = "Selected row"
        case (1, 1):
            content = .cell()
            content.text = "Checked row"
            cell.accessoryType = .checkmark
        case (3, _):
            content = .cell()
            content.text = "After a header"
        case (2, let r):
            content = .valueCell()
            content.text = ["Lift", "Release spring", "Movement"][r]
            content.secondaryText = ["16.00 px", "0.350 s", "12.0 px"][r]
            cell.accessoryType = r == 0 ? .disclosureIndicator : .none
        default:
            content = .cell()
        }
        cell.contentConfiguration = content
        return cell
    }

    private func r2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }

    private func dump() {
        var out = "style=\(plain ? "plain" : "insetGrouped") dark=\(traitCollection.userInterfaceStyle == .dark)\n"
        let traits = traitCollection
        for (name, highlighted, selected) in [("normal", false, false), ("highlighted", true, false), ("selected", false, true)] {
            var state = UICellConfigurationState(traitCollection: traits)
            state.isHighlighted = highlighted
            state.isSelected = selected
            let grouped = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
            let plainBg = UIBackgroundConfiguration.listPlainCell().updated(for: state)
            let g = grouped.resolvedBackgroundColor(for: view.tintColor).resolvedColor(with: traits).cgColor
            let p = plainBg.resolvedBackgroundColor(for: view.tintColor).resolvedColor(with: traits).cgColor
            out += "bgconfig \(name) grouped=\(X3Sampler.rgba(g) ?? []) cr=\(grouped.cornerRadius) plain=\(X3Sampler.rgba(p) ?? [])\n"
        }
        for (name, color) in [
            ("systemGroupedBackground", UIColor.systemGroupedBackground),
            ("secondarySystemGroupedBackground", UIColor.secondarySystemGroupedBackground),
            ("separator", UIColor.separator),
            ("label", UIColor.label),
            ("secondaryLabel", UIColor.secondaryLabel),
            ("tertiaryLabel", UIColor.tertiaryLabel),
            ("systemGray4", UIColor.systemGray4),
            ("systemGray5", UIColor.systemGray5),
        ] {
            out += "color \(name)=\(X3Sampler.rgba(color.resolvedColor(with: traits).cgColor) ?? [])\n"
        }
        for (name, c) in [("cell", UIListContentConfiguration.cell()), ("subtitleCell", .subtitleCell()), ("valueCell", .valueCell()), ("header", .header()), ("footer", .footer())] {
            out += "config \(name) margins=\(c.directionalLayoutMargins) textToSecondaryH=\(c.textToSecondaryTextHorizontalPadding) textToSecondaryV=\(c.textToSecondaryTextVerticalPadding) imageToText=\(c.imageToTextPadding) imageReserved=\(c.imageProperties.reservedLayoutSize) textFont=\(c.textProperties.font.pointSize) secondaryFont=\(c.secondaryTextProperties.font.pointSize) prefersSideBySide=\(c.prefersSideBySideTextAndSecondaryText)\n"
        }
        out += "table separatorInset=\(table.separatorInset) layoutMargins=\(table.layoutMargins) directional=\(table.directionalLayoutMargins) sectionHeaderTopPadding=\(table.sectionHeaderTopPadding) rowHeight=\(table.rowHeight) estimated=\(table.estimatedRowHeight)\n"
        func walk(_ v: UIView, _ depth: Int) {
            let f = v.convert(v.bounds, to: nil)
            var extra = " a=\(v.alpha) cr=\(r2(v.layer.cornerRadius)) mc=\(v.layer.maskedCorners.rawValue) cc=\(v.layer.cornerCurve.rawValue)"
            if v.isHidden { extra += " HIDDEN" }
            if let bg = v.backgroundColor, let c = X3Sampler.rgba(bg.resolvedColor(with: v.traitCollection).cgColor) { extra += " bg=\(c)" }
            if let c = X3Sampler.rgba(v.layer.backgroundColor), v.backgroundColor == nil { extra += " lbg=\(c)" }
            if let lbl = v as? UILabel {
                let w = (lbl.font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? Double ?? 0
                extra += " text=\(lbl.text ?? "") font=\(lbl.font.fontName) fs=\(lbl.font.pointSize) fw=\(w) tc=\(X3Sampler.rgba(lbl.textColor.resolvedColor(with: lbl.traitCollection).cgColor) ?? []) lines=\(lbl.numberOfLines)"
            }
            if let iv = v as? UIImageView {
                extra += " tint=\(X3Sampler.rgba(iv.tintColor.resolvedColor(with: iv.traitCollection).cgColor) ?? [])"
                if let img = iv.image { extra += " img=\(r2(img.size.width))x\(r2(img.size.height))" }
                if let cfg = iv.preferredSymbolConfiguration { extra += " sym=\(cfg)" }
            }
            if let cell = v as? UITableViewCell {
                extra += " sepInset=\(cell.separatorInset) margins=\(cell.directionalLayoutMargins)"
            }
            out += String(repeating: "  ", count: depth) + "\(NSStringFromClass(type(of: v))) \(r2(f.minX)),\(r2(f.minY)) \(r2(f.width))x\(r2(f.height))\(extra)\n"
            for s in v.subviews { walk(s, depth + 1) }
        }
        if let w = view.window { walk(w, 0) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let suffix = (plain ? "plain-" : "") + (traitCollection.userInterfaceStyle == .dark ? "dark" : "light")
        try? out.write(to: docs.appendingPathComponent("list-tree-\(suffix).txt"), atomically: true, encoding: .utf8)
    }
}
