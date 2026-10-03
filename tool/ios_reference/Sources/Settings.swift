import UIKit
import ObjectiveC

enum SettingsDump {
    static func run(pattern: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return "bad regex" }
        var out = ""
        var count: UInt32 = 0
        guard let list = objc_copyClassList(&count) else { return "no classes" }
        let raw = UnsafeRawPointer(list)
        var matches: [AnyClass] = []
        for i in 0..<Int(count) {
            let ptr = raw.load(fromByteOffset: i * MemoryLayout<OpaquePointer>.size, as: OpaquePointer.self)
            let cls = unsafeBitCast(ptr, to: AnyClass.self)
            let name = String(cString: class_getName(cls))
            guard re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil else { continue }
            var sup: AnyClass? = class_getSuperclass(cls)
            var isPT = false
            while let s = sup { if String(cString: class_getName(s)) == "PTSettings" { isPT = true; break }; sup = class_getSuperclass(s) }
            if isPT { matches.append(cls) }
        }
        free(UnsafeMutableRawPointer(mutating: raw))
        for cls in matches {
            out += "== \(String(cString: class_getName(cls)))\n"
            out += dump(cls: cls, indent: "  ", depth: 0)
        }
        return out
    }

    static func dump(cls: AnyClass, indent: String, depth: Int) -> String {
        guard depth < 3 else { return "" }
        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("init")
        guard let meta = object_getClass(cls), let am = class_getClassMethod(cls, allocSel) else { return "" }
        _ = meta
        let alloc = unsafeBitCast(method_getImplementation(am), to: (@convention(c) (AnyClass, Selector) -> AnyObject).self)
        let obj0 = alloc(cls, allocSel)
        guard let im = class_getInstanceMethod(cls, initSel) else { return "" }
        let initF = unsafeBitCast(method_getImplementation(im), to: (@convention(c) (AnyObject, Selector) -> AnyObject).self)
        let obj = initF(obj0, initSel)
        let sdv = NSSelectorFromString("setDefaultValues")
        if let m = class_getInstanceMethod(cls, sdv) {
            unsafeBitCast(method_getImplementation(m), to: (@convention(c) (AnyObject, Selector) -> Void).self)(obj, sdv)
        }
        return dump(obj: obj, indent: indent, depth: depth)
    }

    static func dump(obj: AnyObject, indent: String, depth: Int) -> String {
        var out = ""
        var c: AnyClass? = object_getClass(obj)
        var seen = Set<String>()
        while let cur = c, String(cString: class_getName(cur)) != "PTSettings", String(cString: class_getName(cur)) != "NSObject" {
            var n: UInt32 = 0
            if let props = class_copyPropertyList(cur, &n) {
                for i in 0..<Int(n) {
                    let name = String(cString: property_getName(props[i]))
                    if seen.contains(name) { continue }
                    seen.insert(name)
                    if let v = Probe.scalar(obj, name) { out += "\(indent)\(name) = \(v)\n"; continue }
                    if let o = Probe.object(obj, name) {
                        if let s = o as? String { out += "\(indent)\(name) = \"\(s)\"\n"; continue }
                        if let num = o as? NSNumber { out += "\(indent)\(name) = \(num)\n"; continue }
                        let cn = object_getClass(o).map { String(cString: class_getName($0)) } ?? "?"
                        out += "\(indent)\(name): \(cn)\n"
                        out += dump(obj: o, indent: indent + "  ", depth: depth + 1)
                    }
                }
                free(props)
            }
            c = class_getSuperclass(cur)
        }
        return out
    }
}
