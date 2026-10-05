import UIKit
import QuartzCore

/// Which time a presentation layer read in a display-link callback shows:
/// a box moves 300 pt on a 1 s linear animation, every display-link tick
/// logs the link's timestamp, targetTimestamp, the callback time and the
/// box's presentation x, and every animation logs its committed beginTime.
/// Launch with PROBE_SCENE=clockprobe; the rows (`probe: clock`) land in
/// the recorder's Documents/rec-clockprobe.jsonl.
enum ClockProbeScene {
    static func make(_ name: String) -> UIViewController? {
        name == "clockprobe" ? ClockProbeController() : nil
    }
}

final class ClockProbeController: UIViewController {
    private let box = UIView(frame: CGRect(x: 20, y: 300, width: 40, height: 40))
    private var link: CADisplayLink?
    private var rightward = true
    private var rounds = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        box.backgroundColor = .systemBlue
        view.addSubview(box)
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.go() }
    }

    private func write(_ row: [String: Any]) {
        var tagged = row
        tagged["probe"] = "clock"
        Recorder.shared.log(tagged)
    }

    private func go() {
        rounds += 1
        let called = CACurrentMediaTime()
        let target: CGFloat = rightward ? 320 : 20
        UIView.animate(withDuration: 1.0, delay: 0, options: [.curveLinear]) {
            self.box.frame.origin.x = target
        }
        rightward.toggle()
        write(["k": "call", "t": called, "round": rounds, "to": target])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let a = self.box.layer.animation(forKey: "position") {
                self.write(["k": "begin", "t": CACurrentMediaTime(), "begin": a.beginTime, "round": self.rounds])
            }
        }
        if rounds < 6 { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.go() } }
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        let x = box.layer.presentation()?.frame.origin.x ?? -1
        write(["k": "tick", "ts": l.timestamp, "tt": l.targetTimestamp, "now": now, "x": x])
    }
}
