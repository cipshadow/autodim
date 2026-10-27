// Run with AutoDim active during a stable, non-neutral scheduled phase:
// swift Checks/GammaRecovery.swift
// This briefly resets the built-in display's tint to exercise live recovery.
import Cocoa

struct GammaTable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    init(display: CGDirectDisplayID) {
        let capacity = CGDisplayGammaTableCapacity(display)
        precondition(capacity > 1, "Display has no gamma table")
        red = .init(repeating: 0, count: Int(capacity))
        green = red
        blue = red
        var count: UInt32 = 0
        let result = CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count)
        precondition(result == .success && count > 1, "Cannot read display gamma")
        red = Array(red.prefix(Int(count)))
        green = Array(green.prefix(Int(count)))
        blue = Array(blue.prefix(Int(count)))
    }

    func matches(_ other: GammaTable) -> Bool {
        guard red.count == other.red.count else { return false }
        return zip(red + green + blue, other.red + other.green + other.blue)
            .allSatisfy { abs($0 - $1) < 0.01 }
    }
}

let displays = NSScreen.screens.compactMap {
    $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
}
guard let builtIn = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
    fatalError("This check requires a built-in display")
}
let expected = Dictionary(uniqueKeysWithValues: displays.map { ($0, GammaTable(display: $0)) })
let count = CGDisplayGammaTableCapacity(builtIn)
let neutral = (0..<Int(count)).map { CGGammaValue($0) / CGGammaValue(count - 1) }
precondition(CGSetDisplayTransferByTable(builtIn, count, neutral, neutral, neutral) == .success)
precondition(!GammaTable(display: builtIn).matches(expected[builtIn]!),
             "Use a stable, non-neutral phase so the reset is observable")
print("Reset observed; waiting up to 40 seconds for AutoDim to restore every display")
let deadline = Date().addingTimeInterval(40)
while Date() < deadline {
    Thread.sleep(forTimeInterval: 1)
    if displays.allSatisfy({ GammaTable(display: $0).matches(expected[$0]!) }) {
        print("PASS unchanged scheduled tint recovers after an external gamma reset")
        exit(0)
    }
}
fputs("FAIL scheduled tint stayed out of sync after the refresh interval\n", stderr)
exit(1)
