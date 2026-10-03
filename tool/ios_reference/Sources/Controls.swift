import UIKit

/// One control per scene, centered, so a gesture per launch is easy to aim.
/// Scene names: sw, swOn, sl<W>, slT<N> (ticks), slV<pct> (value), st, gb<W>x<H>, gbp<W>x<H> (prominent).
final class SingleControlScene: UIViewController {
    let name: String
    init(name: String) { self.name = name; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let control = makeControl()
        control.accessibilityIdentifier = "c_" + name
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)
        var cs = [
            control.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            control.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 400),
        ]
        if let w = width { cs.append(control.widthAnchor.constraint(equalToConstant: w)) }
        if let h = height { cs.append(control.heightAnchor.constraint(equalToConstant: h)) }
        NSLayoutConstraint.activate(cs)
        if let s = control as? UISwitch { s.addTarget(self, action: #selector(changed(_:)), for: .valueChanged) }
        if let s = control as? UISlider { s.addTarget(self, action: #selector(changed(_:)), for: .valueChanged) }
        if let s = control as? UIStepper { s.addTarget(self, action: #selector(changed(_:)), for: .valueChanged) }
        if let b = control as? UIButton {
            b.addTarget(self, action: #selector(evt(_:)), for: .touchDown)
            b.addTarget(self, action: #selector(evtUp(_:)), for: .touchUpInside)
        }
    }

    var width: CGFloat?
    var height: CGFloat?

    private func num(_ s: Substring) -> Int? { Int(s) }

    func makeControl() -> UIView {
        if name == "sw" || name == "swOn" {
            let s = UISwitch()
            s.isOn = name == "swOn"
            return s
        }
        if name.hasPrefix("slT") {
            let n = Int(name.dropFirst(3)) ?? 5
            let s = UISlider()
            s.trackConfiguration = UISlider.TrackConfiguration(numberOfTicks: n)
            s.value = 0.0
            width = 300
            return s
        }
        if name.hasPrefix("slV") {
            let s = UISlider()
            s.value = Float(Int(name.dropFirst(3)) ?? 30) / 100
            width = 300
            return s
        }
        if name.hasPrefix("sl") {
            let s = UISlider()
            s.value = Float(ProcessInfo.processInfo.environment["PROBE_SLIDER_VALUE"] ?? "") ?? 0.3
            width = CGFloat(Int(name.dropFirst(2)) ?? 300)
            return s
        }
        if name == "st" || name == "st5" {
            let s = UIStepper()
            if name == "st5" { s.value = 5 }
            return s
        }
        if name.hasPrefix("gb") {
            let prominent = name.hasPrefix("gbp")
            let dims = name.dropFirst(prominent ? 3 : 2).split(separator: "x")
            width = CGFloat(Int(dims.first ?? "120") ?? 120)
            height = CGFloat(Int(dims.count > 1 ? dims[1] : "44") ?? 44)
            var config: UIButton.Configuration = prominent ? .prominentGlass() : .glass()
            if (width ?? 0) < 70 { config.image = UIImage(systemName: "star.fill") } else { config.title = "Glass" }
            return UIButton(configuration: config)
        }
        return UISwitch()
    }

    @objc func changed(_ sender: UIControl) {
        var v: Double = 0
        if let s = sender as? UISwitch { v = s.isOn ? 1 : 0 }
        if let s = sender as? UISlider { v = Double(s.value) }
        if let s = sender as? UIStepper { v = s.value }
        Recorder.shared.log(["k": "evt", "e": "valueChanged", "t": CACurrentMediaTime(), "v": v])
    }
    @objc func evt(_ sender: UIControl) { Recorder.shared.log(["k": "evt", "e": "touchDown", "t": CACurrentMediaTime()]) }
    @objc func evtUp(_ sender: UIControl) { Recorder.shared.log(["k": "evt", "e": "touchUpInside", "t": CACurrentMediaTime()]) }
}
