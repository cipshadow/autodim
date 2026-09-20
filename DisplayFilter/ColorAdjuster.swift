import SwiftUI
import Cocoa

class ColorAdjuster {
    static let shared = ColorAdjuster()
    static let minimumBrightness: Double = 0.05

    private struct Baseline {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        var count: UInt32
    }

    private var baselines: [CGDirectDisplayID: Baseline] = [:]
    private var lastApplied: [CGDirectDisplayID: String] = [:]

    private init() {
        CGDisplayRestoreColorSyncSettings()
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func baseline(for displayID: CGDirectDisplayID) -> Baseline {
        if let existing = baselines[displayID] { return existing }
        var red = [CGGammaValue](repeating: 0, count: 256)
        var green = [CGGammaValue](repeating: 0, count: 256)
        var blue = [CGGammaValue](repeating: 0, count: 256)
        var count: UInt32 = 0
        CGGetDisplayTransferByTable(displayID, 256, &red, &green, &blue, &count)
        let b = Baseline(red: red, green: green, blue: blue, count: count)
        baselines[displayID] = b
        return b
    }

    // Multiplier of a manual color filter; values above 1 boost a channel and are clamped after brightness.
    static func multipliers(for filterColor: FilterColor, intensity: Double) -> ColorTemperature.RGB {
        let i = max(0, min(1, intensity))
        switch filterColor {
        case .none: return .identity
        case .orange: return .init(r: 1 + i * 0.5, g: 1 - i * 0.3, b: 1 - i * 0.8)
        case .red: return .init(r: 1 + i * 0.3, g: 1 - i * 0.8, b: 1 - i * 0.8)
        }
    }

    func apply(brightness: Double, rgb: ColorTemperature.RGB, force: Bool = false) {
        let b = max(Self.minimumBrightness, min(1, brightness))
        for screen in NSScreen.screens {
            guard let displayID = Self.displayID(for: screen) else { continue }
            let key = String(format: "%.4f/%.4f/%.4f/%.4f", b, rgb.r, rgb.g, rgb.b)
            if !force && lastApplied[displayID] == key { continue }
            let base = baseline(for: displayID)
            func scaled(_ table: [CGGammaValue], _ m: Double) -> [CGGammaValue] {
                let factor = CGGammaValue(b * m)
                return table.map { min($0 * factor, 1.0) }
            }
            let red = scaled(base.red, rgb.r)
            let green = scaled(base.green, rgb.g)
            let blue = scaled(base.blue, rgb.b)
            let err = CGSetDisplayTransferByTable(displayID, base.count, red, green, blue)
            lastApplied[displayID] = key
            #if DEBUG
            var rr = [CGGammaValue](repeating: 0, count: 256), gg = rr, bb = rr
            var n: UInt32 = 0
            CGGetDisplayTransferByTable(displayID, 256, &rr, &gg, &bb, &n)
            fputs(String(format: "applied display %u err %d brightness %.3f rgb %.3f/%.3f/%.3f readback-top %.3f/%.3f/%.3f\n",
                         displayID, err.rawValue, b, rgb.r, rgb.g, rgb.b, rr[Int(n) - 1], gg[Int(n) - 1], bb[Int(n) - 1]), stderr)
            #endif
        }
    }

    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
        lastApplied.removeAll()
        baselines.removeAll()
    }
}
