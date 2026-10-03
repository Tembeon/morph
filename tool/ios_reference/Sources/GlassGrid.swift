import UIKit

/// The glass displacement probe: UIGlassEffect shapes and a floating tab bar over the
/// measurement grid (2 pt black lines every 16 pt on white, every fifth line red, anchored
/// at the window's top left), at the rects morph's glass_grid_test uses, plus a segmented control at (51, 680, 300 wide). Light appearance.
/// Scene name: glassGrid.
enum GlassGridLayout {
    static let pitch: CGFloat = 16
    static let line: CGFloat = 2
    static let shapes: [(String, CGRect, CGFloat?)] = [
        ("capsule", CGRect(x: 40, y: 120, width: 120, height: 44), nil),
        ("circle", CGRect(x: 220, y: 120, width: 44, height: 44), nil),
        ("bar", CGRect(x: 21, y: 220, width: 360, height: 64), nil),
        ("panel", CGRect(x: 76, y: 330, width: 250, height: 220), 34),
    ]

    static func pattern() -> UIColor {
        let tile = pitch * 5
        let r = UIGraphicsImageRenderer(size: CGSize(width: tile, height: tile))
        let img = r.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: tile, height: tile))
            for i in 0..<5 {
                (i == 0 ? UIColor.red : UIColor.black).setFill()
                ctx.fill(CGRect(x: CGFloat(i) * pitch, y: 0, width: line, height: tile))
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * pitch, width: tile, height: line))
            }
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: line, height: tile))
            ctx.fill(CGRect(x: 0, y: 0, width: tile, height: line))
        }
        return UIColor(patternImage: img)
    }
}

final class GlassGridPage: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = GlassGridLayout.pattern()
        for (name, rect, radius) in GlassGridLayout.shapes {
            let g = UIGlassEffect(style: .regular)
            g.isInteractive = false
            let v = UIVisualEffectView(effect: g)
            v.frame = rect
            v.accessibilityIdentifier = "grid-\(name)"
            if let radius { v.cornerConfiguration = .corners(radius: .fixed(radius)) } else { v.cornerConfiguration = .capsule() }
            view.addSubview(v)
        }
        var config = UIButton.Configuration.glass()
        config.title = "Glass"
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = "gridGlassButton"
        button.sizeToFit()
        button.frame.origin = CGPoint(x: 40, y: 600)
        view.addSubview(button)
        let seg = UISegmentedControl(items: ["Photos", "Albums", "Search"])
        seg.selectedSegmentIndex = 0
        seg.accessibilityIdentifier = "gridSegmented"
        seg.frame = CGRect(x: 51, y: 680, width: 300, height: 36)
        view.addSubview(seg)
    }
}

final class GlassGridScene: UITabBarController {
    init() {
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .light
        let symbols = ["house", "books.vertical", "dot.radiowaves.left.and.right"]
        let titles = ["Home", "Library", "Radio"]
        viewControllers = (0..<3).map { index in
            let vc = GlassGridPage()
            vc.tabBarItem = UITabBarItem(title: titles[index], image: UIImage(systemName: symbols[index]), tag: index)
            return vc
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}
