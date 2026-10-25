import Foundation

func runHardwareBrightnessChecks() {
    // GitHub's hosted macOS VMs expose no physical display backlight or DDC
    // transport. Keep the real-hardware smoke test for developer Macs, while
    // exercising the controller's logic with the deterministic backend below.
    if ProcessInfo.processInfo.environment["CI"] == nil {
        let systemBackend = MacHardwareBrightnessBackend()
        let systemDisplays = systemBackend.connectedDisplays()
        check("discovers the built-in hardware brightness control", !systemDisplays.isEmpty)
        if let builtIn = systemDisplays.first {
            check("reads built-in hardware brightness", systemBackend.readBrightness(for: builtIn) != nil)
        }
    } else {
        print("INFO hardware discovery skipped on a hosted CI runner")
    }

    let builtIn = BrightnessDisplay(id: 1, key: "builtin", name: "MacBook")
    let external = BrightnessDisplay(id: 2, key: "external", name: "Desk")
    let backend = FakeBrightnessBackend(values: [1: 0.8, 2: 0.6], displays: [builtIn, external])
    let controller = HardwareBrightnessController(backend: backend)

    check("hardware dims all controllable displays", controller.apply(multiplier: 0.5) == [1, 2])
    check("built-in uses its original level", near(backend.values[1]!, 0.4))
    check("external uses its original level", near(backend.values[2]!, 0.3))

    backend.values[1] = 0.2
    controller.apply(multiplier: 0.5)
    check("manual brightness change becomes the new baseline", near(backend.values[1]!, 0.2))

    backend.failWrites.insert(2)
    controller.apply(multiplier: 0.25)
    check("failed hardware write drops to software fallback", controller.softwareFallbackIDs.contains(2))

    controller.restoreAll()
    check("restore returns updated built-in baseline", near(backend.values[1]!, 0.4))
    check("failed display is not marked restored", !controller.hardwareControlledIDs.contains(2))

    let saved = MemoryRestorationStore()
    let recoveryBackend = FakeBrightnessBackend(values: [1: 0.9], displays: [builtIn])
    let beforeCrash = HardwareBrightnessController(backend: recoveryBackend, store: saved)
    beforeCrash.apply(multiplier: 0.5)
    check("stores original brightness before a crash", near(saved.values["builtin"]!, 0.9))
    let afterCrash = HardwareBrightnessController(backend: recoveryBackend, store: saved)
    afterCrash.recoverPendingRestoration()
    check("startup recovery restores saved brightness", near(recoveryBackend.values[1]!, 0.9))
    check("startup recovery clears restored values", saved.values.isEmpty)

    let disconnected = BrightnessDisplay(id: 3, key: "gone", name: "Travel")
    let disconnectBackend = FakeBrightnessBackend(values: [3: 0.7], displays: [disconnected])
    let disconnectStore = MemoryRestorationStore()
    let disconnectController = HardwareBrightnessController(backend: disconnectBackend, store: disconnectStore)
    disconnectController.apply(multiplier: 0.5)
    disconnectBackend.displays = []
    disconnectController.restoreAll()
    check("disconnected display restoration remains pending", near(disconnectStore.values["gone"]!, 0.7))
}

private final class FakeBrightnessBackend: HardwareBrightnessBackend {
    var values: [UInt32: Double]
    var displays: [BrightnessDisplay]
    var failWrites: Set<UInt32> = []

    init(values: [UInt32: Double], displays: [BrightnessDisplay]) {
        self.values = values
        self.displays = displays
    }

    func connectedDisplays() -> [BrightnessDisplay] { displays }
    func readBrightness(for display: BrightnessDisplay) -> Double? { values[display.id] }
    func writeBrightness(_ value: Double, for display: BrightnessDisplay) -> Bool {
        guard !failWrites.contains(display.id) else { return false }
        values[display.id] = value
        return true
    }
}

private final class MemoryRestorationStore: BrightnessRestorationStoring {
    var values: [String: Double] = [:]
    func savedValues() -> [String: Double] { values }
    func save(_ values: [String: Double]) { self.values = values }
}
