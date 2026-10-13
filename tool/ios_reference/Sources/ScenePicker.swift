import UIKit

/// The native scenes listed for a hand launch, so UIKit's own controls can be
/// tried next to the gallery. A two-finger long press anywhere returns here.
final class ScenePickerController: UITableViewController {
    private let scenes: [(String, String)] = [
        ("Controls: switch, slider, stepper, glass buttons", "controls"),
        ("Segmented control", "segmented"),
        ("Tab bar (4 tabs)", "tabbar4"),
        ("Tab bar (5 tabs)", "tabbar5"),
        ("Menu button", "menu"),
        ("Menus (UIMenu API)", "x5menu"),
        ("Context menu", "w2ctx"),
        ("Navigation: large title, bar buttons, toolbar", "nav"),
        ("Navigation with segmented", "navseg"),
        ("Sheet", "w2sheet"),
        ("Sheet zoom", "snzoom"),
        ("Zoom push", "snpush"),
        ("Alert", "x3alert"),
        ("Alert (scripted)", "w2alert"),
        ("Search", "x3search"),
        ("Search (scripted)", "w2search"),
        ("Date picker", "x3date"),
        ("Page control", "w2page"),
        ("Progress", "w2progress"),
        ("Lists", "list"),
        ("Glass merge", "merge"),
        ("Disabled states", "x4dis"),
        ("Typography", "fonts"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIKit reference"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { scenes.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "A two-finger long press returns to this list."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = scenes[indexPath.row].0
        content.secondaryText = scenes[indexPath.row].1
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let window = view.window else { return }
        let scene = Scenes.make(scenes[indexPath.row].1)
        let back = UILongPressGestureRecognizer(target: ScenePickerController.self, action: #selector(ScenePickerController.back(_:)))
        back.numberOfTouchesRequired = 2
        back.minimumPressDuration = 0.6
        back.cancelsTouchesInView = false
        window.addGestureRecognizer(back)
        ScenePickerController.backRecognizer = back
        window.rootViewController = scene
    }

    private static var backRecognizer: UIGestureRecognizer?

    @objc private static func back(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let window = recognizer.view as? UIWindow else { return }
        window.removeGestureRecognizer(recognizer)
        backRecognizer = nil
        window.rootViewController = UINavigationController(rootViewController: ScenePickerController())
    }
}
