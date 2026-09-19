import Foundation

enum ColorTemperature {
    struct RGB: Equatable {
        var r: Double
        var g: Double
        var b: Double
        static let identity = RGB(r: 1, g: 1, b: 1)
    }

    // Tanner Helland's blackbody approximation, normalised so 6500K is the identity.
    private static func raw(_ kelvin: Double) -> RGB {
        let t = min(max(kelvin, 1000), 40000) / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func clamp(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return RGB(r: clamp(r), g: clamp(g), b: clamp(b))
    }

    static func multipliers(kelvin: Double) -> RGB {
        if kelvin >= ScheduleConfig.neutralKelvin { return .identity }
        let w = raw(ScheduleConfig.neutralKelvin)
        let c = raw(kelvin)
        return RGB(r: min(c.r / w.r, 1), g: min(c.g / w.g, 1), b: min(c.b / w.b, 1))
    }
}
