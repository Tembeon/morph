import UIKit

final class MenuKeyboardScene: UIViewController {
    private let field = UITextField()
    private let button = UIButton(configuration: .glass())
    private let countLabel = UILabel()
    private let sourceToken = UUID().uuidString
    private var presentations = 0
    private var selections = 0
    private var events: [[String: Any]] = []
    private var observations: [NSObjectProtocol] = []
    private let tall = ProcessInfo.processInfo.environment["PROBE_KEYBOARD_ROWS"] == "10"
    private let mode = ProcessInfo.processInfo.environment["PROBE_KEYBOARD"] ?? "none"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        field.placeholder = "Keyboard probe"
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.accessibilityIdentifier = "keyboardEditor"
        field.addTarget(self, action: #selector(editorChanged), for: .editingChanged)
        countLabel.text = "0"
        countLabel.accessibilityIdentifier = "keyboardSelectionCount"
        button.setTitle("Menu", for: .normal)
        button.accessibilityIdentifier = "nativeKeyboardMenu"
        let titles = ["Native first", "Native second", "Native third"] + (tall ? (4...10).map { "Native row \($0)" } : [])
        button.menu = UIMenu(children: titles.map { title in
            UIAction(title: title) { [weak self] _ in
                guard let self else { return }
                selections += 1
                countLabel.text = String(selections)
                record("selected", extra: ["title": title])
            }
        })
        button.showsMenuAsPrimaryAction = true
        button.addTarget(self, action: #selector(menuTriggered), for: .menuActionTriggered)
        for child in [field, button, countLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            field.heightAnchor.constraint(equalToConstant: 40),
            countLabel.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 430),
            button.widthAnchor.constraint(equalToConstant: 80),
            button.heightAnchor.constraint(equalToConstant: 48),
        ])
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
                     UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                self?.record(notification.name.rawValue, extra: ["keyboardEnd": Self.rect(frame)])
            })
        }
        record("loaded")
    }

    deinit {
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
    }

    @objc private func menuTriggered() {
        presentations += 1
        record("menuTriggered")
        guard presentations == 1, mode != "none" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            record("keyboardCommandBegin")
            let accepted = mode == "show" ? field.becomeFirstResponder() : field.resignFirstResponder()
            record("keyboardCommand", extra: ["accepted": accepted])
        }
    }

    @objc private func editorChanged() {
        record("editorChanged", extra: ["text": field.text ?? ""])
    }

    private static func rect(_ value: CGRect) -> [Double] {
        [value.origin.x, value.origin.y, value.width, value.height].map(Double.init)
    }

    private func record(_ kind: String, extra: [String: Any] = [:]) {
        var event: [String: Any] = ["kind": kind, "time": CACurrentMediaTime(), "mode": mode,
                                    "fieldFocused": field.isFirstResponder, "button": Self.rect(button.frame), "rowCount": tall ? 10 : 3,
                                    "sourceToken": sourceToken, "presentation": presentations, "selectionCount": selections,
                                    "systemVersion": UIDevice.current.systemVersion,
                                    "viewBounds": Self.rect(view.bounds),
                                    "safeArea": [view.safeAreaInsets.left, view.safeAreaInsets.top, view.safeAreaInsets.right, view.safeAreaInsets.bottom].map(Double.init),
                                    "displayScale": traitCollection.displayScale,
                                    "contentSizeCategory": traitCollection.preferredContentSizeCategory.rawValue,
                                    "reduceMotion": UIAccessibility.isReduceMotionEnabled]
        event.merge(extra) { _, new in new }
        events.append(event)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("menu-keyboard-\(mode).json")
        do {
            try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        } catch {
            NSLog("Keyboard probe write failed: %@", String(describing: error))
        }
    }
}
