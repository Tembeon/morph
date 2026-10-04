import UIKit
import CryptoKit

struct LabScenario: Decodable {
    struct Canvas: Decodable { let width: Double; let height: Double; let scale: Double }
    struct Background: Decodable { let kind: String; let color: String?; let cell: Double?; let period: Double? }
    struct Item: Decodable { let title: String; let children: [Item]?; let destructive: Bool? }
    struct Widget: Decodable {
        let id: String
        let kind: String
        let rect: [Double]
        let title: String?
        let value: Double?
        let enabled: Bool?
        let labels: [String]?
        let items: [Item]?
    }
    struct Selector: Decodable {
        let `class`: String?
        let identifier: String?
        let label: String?
        let within: String?
        let index: Int?
        let all: Bool?
        let source: String?
        let layerClass: String?
        let scalars: [String: String]?
    }
    struct Track: Decodable { let id: String; let native: Selector; let properties: [String]? }
    let id: String
    let canvas: Canvas
    let appearance: String
    let background: Background
    let widgets: [Widget]
    let tracks: [Track]
    let marker: [Double]?

    static func environment() -> LabScenario? {
        guard let raw = ProcessInfo.processInfo.environment["PROBE_LAB_JSON"],
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LabScenario.self, from: data)
    }
}

func labRect(_ parts: [Double]) -> CGRect {
    CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}

func labColor(_ value: String) -> UIColor {
    let number = UInt32(value.dropFirst(), radix: 16) ?? 0xF2F2F7
    return UIColor(red: CGFloat((number >> 16) & 255) / 255,
                   green: CGFloat((number >> 8) & 255) / 255,
                   blue: CGFloat(number & 255) / 255, alpha: 1)
}

final class LabBackground: UIView {
    let spec: LabScenario.Background
    init(_ spec: LabScenario.Background) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isOpaque = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(labColor(spec.color ?? "#F2F2F7").cgColor)
        context.fill(bounds)
        if spec.kind == "grid" {
            let cell = CGFloat(spec.cell ?? 12)
            let colors: [UIColor] = [.red, .green, .blue, .white]
            for row in 0..<Int(ceil(bounds.height / cell)) {
                for column in 0..<Int(ceil(bounds.width / cell)) {
                    context.setFillColor(colors[(row * 3 + column) % 4].cgColor)
                    context.fill(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
        }
        if spec.kind == "ramp" {
            let period = CGFloat(spec.period ?? 120)
            for column in 0..<Int(ceil(bounds.width)) {
                let value = CGFloat(column).truncatingRemainder(dividingBy: period) / period
                context.setFillColor(UIColor(white: value, alpha: 1).cgColor)
                context.fill(CGRect(x: CGFloat(column), y: 0, width: 1, height: bounds.height))
            }
        }
    }
}

final class LabScene: UIViewController {
    let spec: LabScenario
    private var controls: [String: UIControl] = [:]
    init(_ spec: LabScenario) { self.spec = spec; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let background = LabBackground(spec.background)
        background.frame = view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(background)
        for widget in spec.widgets {
            let control: UIControl
            switch widget.kind {
            case "button":
                var config = UIButton.Configuration.glass()
                config.title = widget.title ?? "Glass"
                control = UIButton(configuration: config)
                control.addTarget(self, action: #selector(activate(_:)), for: .touchUpInside)
            case "menu":
                var config = UIButton.Configuration.glass()
                config.image = UIImage(systemName: "ellipsis")
                let button = UIButton(configuration: config)
                button.menu = UIMenu(children: (widget.items ?? []).map { menuItem($0, owner: widget.id) })
                button.showsMenuAsPrimaryAction = true
                control = button
            case "slider":
                let slider = UISlider()
                slider.value = Float(widget.value ?? 0.3)
                control = slider
            case "switch":
                let toggle = UISwitch()
                toggle.isOn = (widget.value ?? 0) > 0
                control = toggle
            case "segmented":
                let segmented = UISegmentedControl(items: widget.labels ?? [])
                segmented.selectedSegmentIndex = Int(widget.value ?? 0)
                control = segmented
            default:
                Recorder.shared.log(["k": "lab_error", "e": "unknown widget", "id": widget.id, "t": CACurrentMediaTime()])
                continue
            }
            control.frame = labRect(widget.rect)
            control.accessibilityIdentifier = widget.id
            control.isEnabled = widget.enabled ?? true
            control.addTarget(self, action: #selector(changed(_:)), for: .valueChanged)
            controls[widget.id] = control
            view.addSubview(control)
        }
    }

    private func menuItem(_ item: LabScenario.Item, owner: String) -> UIMenuElement {
        if let children = item.children {
            return UIMenu(title: item.title, children: children.map { menuItem($0, owner: owner) })
        }
        return UIAction(title: item.title, attributes: item.destructive == true ? .destructive : []) { _ in
            Recorder.shared.log(["k": "lab_event", "id": owner, "e": "selected", "value": item.title, "t": CACurrentMediaTime()])
        }
    }

    @objc private func activate(_ sender: UIControl) {
        Recorder.shared.log(["k": "lab_event", "id": sender.accessibilityIdentifier ?? "", "e": "activate", "t": CACurrentMediaTime()])
    }

    @objc private func changed(_ sender: UIControl) {
        var value: Double = 0
        if let slider = sender as? UISlider { value = Double(slider.value) }
        if let toggle = sender as? UISwitch { value = toggle.isOn ? 1 : 0 }
        if let segmented = sender as? UISegmentedControl { value = Double(segmented.selectedSegmentIndex) }
        Recorder.shared.log(["k": "lab_event", "id": sender.accessibilityIdentifier ?? "", "e": "changed", "value": value, "t": CACurrentMediaTime()])
    }
}

final class LabMarker: UIView {
    var sequence = 0 { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let bits = (0..<16).map { (sequence >> $0) & 1 }
        let parity = bits.reduce(0, ^)
        let values = [0, 1] + bits + [parity, 1 - parity]
        for (index, value) in values.enumerated() {
            context.setFillColor((value == 1 ? UIColor.white : UIColor.black).cgColor)
            context.fill(CGRect(x: CGFloat(index) * bounds.width / 20, y: 0, width: bounds.width / 20, height: bounds.height))
        }
    }
}

final class LabCapture: NSObject {
    static let shared = LabCapture()
    private var link: CADisplayLink?
    private var spec: LabScenario?
    private var marker: LabMarker?
    private var sequence = 0

    func start(window: UIWindow) {
        guard let spec = LabScenario.environment() else { return }
        self.spec = spec
        let marker = LabMarker(frame: labRect(spec.marker ?? [8, 56, 100, 10]))
        marker.isUserInteractionEnabled = false
        marker.isOpaque = true
        window.addSubview(marker)
        self.marker = marker
        Recorder.shared.log(["k": "lab_start", "t": CACurrentMediaTime(), "side": "native", "id": spec.id,
                             "w": window.bounds.width, "h": window.bounds.height, "scale": window.screen.scale,
                             "rm": UIAccessibility.isReduceMotionEnabled, "rt": UIAccessibility.isReduceTransparencyEnabled,
                             "os": UIDevice.current.systemVersion, "maxfps": window.screen.maximumFramesPerSecond,
                             "sha256": SHA256.hash(data: Data((ProcessInfo.processInfo.environment["PROBE_LAB_JSON"] ?? "").utf8)).map { String(format: "%02x", $0) }.joined()])
        if abs(window.bounds.width - spec.canvas.width) > 0.1 || abs(window.bounds.height - spec.canvas.height) > 0.1 {
            Recorder.shared.log(["k": "lab_error", "e": "canvas mismatch", "t": CACurrentMediaTime()])
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func views() -> [UIView] {
        var output: [UIView] = []
        func walk(_ view: UIView) { output.append(view); for child in view.subviews { walk(child) } }
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene { for window in windowScene.windows { walk(window) } }
        }
        return output
    }

    private func matches(_ view: UIView, _ selector: LabScenario.Selector) -> Bool {
        if let pattern = selector.class, NSStringFromClass(type(of: view)).range(of: pattern, options: .regularExpression) == nil { return false }
        if let identifier = selector.identifier, view.accessibilityIdentifier != identifier { return false }
        if let label = selector.label, view.accessibilityLabel != label && (view as? UILabel)?.text != label { return false }
        if let owner = selector.within {
            var ancestor: UIView? = view
            var found = false
            while let current = ancestor {
                if current.accessibilityIdentifier == owner { found = true; break }
                ancestor = current.superview
            }
            if !found { return false }
        }
        return true
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let spec else { return }
        let began = CACurrentMediaTime()
        sequence += 1
        marker?.sequence = sequence & 65535
        Recorder.shared.log(["k": "lab_marker", "sequence": sequence & 65535, "t": link.targetTimestamp, "sample_t": link.timestamp])
        let all = views()
        for track in spec.tracks {
            let found = all.filter { matches($0, track.native) }
            let selected = track.native.all == true ? Array(found.enumerated()) : found.enumerated().filter { $0.offset == (track.native.index ?? 0) }
            if selected.isEmpty { Recorder.shared.log(["k": "lab_missing", "id": track.id, "t": link.timestamp]) }
            for (index, view) in selected {
                if track.native.source == "layer" { continue }
                guard let window = view.window else { continue }
                let layer = view.layer.presentation() ?? view.layer
                let root = window.layer.presentation() ?? window.layer
                let rect = layer.convert(layer.bounds, to: root)
                var clips: [[CGFloat]] = []
                var ancestor = view.superview
                var hidden = view.isHidden
                var opacity = Double(layer.opacity)
                while let current = ancestor {
                    let parent = current.layer.presentation() ?? current.layer
                    hidden = hidden || current.isHidden
                    opacity *= Double(parent.opacity)
                    if current.clipsToBounds || parent.masksToBounds {
                        let clip = parent.convert(parent.bounds, to: root)
                        clips.append([clip.minX, clip.minY, clip.width, clip.height])
                    }
                    ancestor = current.superview
                }
                var values: [String: Any] = ["left": rect.minX, "top": rect.minY, "width": rect.width, "height": rect.height,
                                             "opacity": hidden ? 0 : opacity, "scaleX": layer.transform.m11, "scaleY": layer.transform.m22,
                                             "radius": layer.cornerRadius]
                if let scroll = view as? UIScrollView { values["scrollX"] = scroll.contentOffset.x; values["scrollY"] = scroll.contentOffset.y }
                if track.native.source == "flex" {
                    guard let flex = Probe.object(view, "flexInteraction") ?? Probe.object(view, "_flexInteraction") else {
                        Recorder.shared.log(["k": "lab_missing", "id": track.id, "t": link.timestamp, "e": "no flex interaction"])
                        continue
                    }
                    values = [:]
                    for key in ["scaleX", "scaleY", "driftX", "driftY", "translationY"] {
                        if let channel = Probe.object(flex, key), let value = Probe.scalar(channel, "presentationValue") ?? Probe.scalar(channel, "value") { values[key] = value }
                    }
                    if let translation = Probe.point(flex, "translation") { values["translationX"] = translation.x; values["translationY"] = translation.y }
                }
                for (key, path) in track.native.scalars ?? [:] {
                    var target: AnyObject = view
                    let components = path.split(separator: ".").map(String.init)
                    var reachable = true
                    for component in components.dropLast() {
                        if let next = Probe.object(target, component) { target = next } else { reachable = false; break }
                    }
                    if reachable, let getter = components.last, let value = Probe.scalar(target, getter) { values[key] = value }
                }
                if let properties = track.properties { values = values.filter { properties.contains($0.key) } }
                Recorder.shared.log(["k": "lab_sample", "t": link.timestamp, "id": track.native.all == true ? "\(track.id)/\(index)" : track.id,
                                     "identity": "\(ObjectIdentifier(view))", "values": values, "clips": clips])
            }
            if track.native.source == "layer" {
                var visited = Set<ObjectIdentifier>()
                var layerIndex = 0
                func walk(_ model: CALayer, root: CALayer) {
                    guard visited.insert(ObjectIdentifier(model)).inserted else { return }
                    let name = NSStringFromClass(type(of: model))
                    if name.range(of: track.native.layerClass ?? ".", options: .regularExpression) != nil {
                        let current = layerIndex
                        layerIndex += 1
                        if track.native.all == true || current == (track.native.index ?? 0) {
                            let layer = model.presentation() ?? model
                            let box = layer.convert(layer.bounds, to: root)
                            var values: [String: Any] = ["left": box.minX, "top": box.minY, "width": box.width, "height": box.height,
                                                        "opacity": layer.opacity, "scaleX": layer.transform.m11, "scaleY": layer.transform.m22, "radius": layer.cornerRadius]
                            for (key, getter) in track.native.scalars ?? [:] { if let value = Probe.scalar(layer, getter) { values[key] = value } }
                            if let properties = track.properties { values = values.filter { properties.contains($0.key) } }
                            var clips: [[CGFloat]] = []
                            var parent = model.superlayer
                            while let current = parent {
                                let presentation = current.presentation() ?? current
                                if presentation.masksToBounds {
                                    let clip = presentation.convert(presentation.bounds, to: root)
                                    clips.append([clip.minX, clip.minY, clip.width, clip.height])
                                }
                                parent = current.superlayer
                            }
                            Recorder.shared.log(["k": "lab_sample", "t": link.timestamp,
                                                 "id": track.native.all == true ? "\(track.id)/\(current)" : track.id,
                                                 "identity": "\(ObjectIdentifier(model))", "values": values, "clips": clips])
                        }
                    }
                    for child in model.sublayers ?? [] { walk(child, root: root) }
                }
                for view in found {
                    if let window = view.window { walk(view.layer, root: window.layer.presentation() ?? window.layer) }
                }
                if layerIndex == 0 { Recorder.shared.log(["k": "lab_missing", "id": track.id, "t": link.timestamp]) }
            }
        }
        Recorder.shared.log(["k": "lab_tick", "t": link.timestamp, "cost_ms": (CACurrentMediaTime() - began) * 1000])
    }
}
