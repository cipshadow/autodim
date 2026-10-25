import AppKit
import CoreGraphics
import Foundation
import IOKit

struct BrightnessDisplay: Equatable {
    let id: UInt32
    let key: String
    let name: String
}

protocol HardwareBrightnessBackend: AnyObject {
    func connectedDisplays() -> [BrightnessDisplay]
    func readBrightness(for display: BrightnessDisplay) -> Double?
    func writeBrightness(_ value: Double, for display: BrightnessDisplay) -> Bool
    func invalidateDisplays()
}

extension HardwareBrightnessBackend { func invalidateDisplays() {} }

protocol BrightnessRestorationStoring: AnyObject {
    func savedValues() -> [String: Double]
    func save(_ values: [String: Double])
}

final class UserDefaultsBrightnessRestorationStore: BrightnessRestorationStoring {
    private let key = "hardwareBrightness.restore.v1"
    func savedValues() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
    func save(_ values: [String: Double]) { UserDefaults.standard.set(values, forKey: key) }
}

final class HardwareBrightnessController {
    private struct State { var original: Double; var lastApplied: Double }
    private let backend: HardwareBrightnessBackend
    private let store: BrightnessRestorationStoring?
    private var states: [String: State] = [:]
    private(set) var hardwareControlledIDs: Set<UInt32> = []
    private(set) var softwareFallbackIDs: Set<UInt32> = []
    private(set) var displays: [BrightnessDisplay] = []

    init(backend: HardwareBrightnessBackend, store: BrightnessRestorationStoring? = nil) {
        self.backend = backend
        self.store = store
    }

    @discardableResult
    func apply(multiplier: Double) -> Set<UInt32> {
        let clamped = max(0, min(1, multiplier))
        displays = backend.connectedDisplays()
        hardwareControlledIDs.removeAll()
        softwareFallbackIDs.removeAll()

        if clamped >= 0.999 {
            restoreAll()
            return []
        }

        for display in displays {
            guard let current = backend.readBrightness(for: display) else {
                softwareFallbackIDs.insert(display.id)
                continue
            }
            var state = states[display.key] ?? State(original: current, lastApplied: current)
            if abs(current - state.lastApplied) > 0.015 {
                state.original = min(1, max(0, current / clamped))
            }
            let target = state.original * clamped
            if abs(current - target) <= 0.005 {
                state.lastApplied = target
                states[display.key] = state
                hardwareControlledIDs.insert(display.id)
                continue
            }
            guard backend.writeBrightness(target, for: display) else {
                softwareFallbackIDs.insert(display.id)
                continue
            }
            state.lastApplied = target
            states[display.key] = state
            hardwareControlledIDs.insert(display.id)
        }
        persistRestoration()
        return hardwareControlledIDs
    }

    func recoverPendingRestoration() {
        guard let store else { return }
        let saved = store.savedValues()
        guard !saved.isEmpty else { return }
        let connected = backend.connectedDisplays()
        var remaining = saved
        for display in connected {
            guard let value = saved[display.key], backend.readBrightness(for: display) != nil,
                  backend.writeBrightness(value, for: display) else { continue }
            remaining.removeValue(forKey: display.key)
        }
        store.save(remaining)
    }

    func invalidateDisplays() {
        backend.invalidateDisplays()
        displays = []
    }

    func restoreAll() {
        displays = backend.connectedDisplays()
        for display in displays {
            guard let state = states[display.key], backend.writeBrightness(state.original, for: display) else { continue }
            states.removeValue(forKey: display.key)
        }
        hardwareControlledIDs.removeAll()
        softwareFallbackIDs.removeAll()
        persistRestoration()
    }

    private func persistRestoration() {
        guard let store else { return }
        let values = Dictionary(uniqueKeysWithValues: states.map { ($0.key, $0.value.original) })
        if values != store.savedValues() { store.save(values) }
    }
}

@_silgen_name("autodim_builtin_get") private func builtInGet(_ display: UInt32, _ value: UnsafeMutablePointer<Float>) -> Bool
@_silgen_name("autodim_builtin_set") private func builtInSet(_ display: UInt32, _ value: Float) -> Bool
@_silgen_name("autodim_ddc_available") private func ddcAvailable() -> Bool
@_silgen_name("autodim_ddc_create") private func ddcCreate(_ service: io_service_t) -> UnsafeMutableRawPointer?
@_silgen_name("autodim_ddc_release") private func ddcRelease(_ service: UnsafeMutableRawPointer?)
@_silgen_name("autodim_ddc_write") private func ddcWrite(_ service: UnsafeMutableRawPointer, _ bytes: UnsafeMutableRawPointer, _ count: UInt32) -> kern_return_t
@_silgen_name("autodim_ddc_read") private func ddcRead(_ service: UnsafeMutableRawPointer, _ bytes: UnsafeMutableRawPointer, _ count: UInt32) -> kern_return_t

final class MacHardwareBrightnessBackend: HardwareBrightnessBackend {
    private enum DDC {
        static let displayAddress: UInt8 = 0x6E
        static let hostAddress: UInt8 = 0x51
        static let brightnessVCP: UInt8 = 0x10
        static let getVCP: UInt8 = 0x01
        static let setVCP: UInt8 = 0x03
        static let getReply: UInt8 = 0x02
        static let readWait: TimeInterval = 0.05
    }
    private enum Transport { case builtIn, ddc(UnsafeMutableRawPointer) }
    private var transports: [UInt32: Transport] = [:]
    private var ddcMaximums: [UInt32: UInt16] = [:]
    private var cached: [BrightnessDisplay]?

    deinit { releaseDDCServices() }

    func connectedDisplays() -> [BrightnessDisplay] {
        if let cached { return cached }
        var result: [BrightnessDisplay] = []
        for screen in NSScreen.screens {
            guard let id = displayID(for: screen) else { continue }
            var brightness: Float = 0
            if CGDisplayIsBuiltin(id) != 0, builtInGet(id, &brightness) {
                let display = BrightnessDisplay(id: id, key: "builtin", name: screen.localizedName)
                transports[id] = .builtIn
                result.append(display)
            }
        }
        result += discoverDDCDisplays()
        cached = result
        return result
    }

    func invalidateDisplays() {
        cached = nil
        releaseDDCServices()
    }

    func readBrightness(for display: BrightnessDisplay) -> Double? {
        guard let transport = transports[display.id] else { return nil }
        switch transport {
        case .builtIn:
            var value: Float = 0
            return builtInGet(display.id, &value) ? Double(value) : nil
        case .ddc(let service):
            guard let reading = readDDC(service), reading.maximum > 0 else { return nil }
            ddcMaximums[display.id] = reading.maximum
            return Double(reading.current) / Double(reading.maximum)
        }
    }

    func writeBrightness(_ value: Double, for display: BrightnessDisplay) -> Bool {
        guard let transport = transports[display.id] else { return false }
        switch transport {
        case .builtIn:
            return builtInSet(display.id, Float(max(0, min(1, value))))
        case .ddc(let service):
            guard let maximum = ddcMaximums[display.id] else { return false }
            let raw = UInt16((value * Double(maximum)).rounded())
            guard writeDDC(raw, service: service) else { return false }
            Thread.sleep(forTimeInterval: 0.05)
            guard let confirmed = readDDC(service) else { return false }
            return abs(Int(confirmed.current) - Int(raw)) <= 1
        }
    }

    private func discoverDDCDisplays() -> [BrightnessDisplay] {
        guard ddcAvailable() else { return [] }
        let external = allOnlineDisplayInfo().filter { CGDisplayIsBuiltin($0.id) == 0 }
        guard !external.isEmpty else { return [] }
        var result: [BrightnessDisplay] = []
        for entry in registryEntries() {
            defer { IOObjectRelease(entry) }
            let className = registryClass(entry)
            guard className == "DCPAVServiceProxy", registryProperty(entry, "Location") as? String == "External",
                  let identity = parentDisplayIdentity(entry),
                  let match = external.first(where: { $0.vendor == identity.vendor && $0.product == identity.product && $0.serial == identity.serial }),
                  let service = ddcCreate(entry) else {
                continue
            }
            transports[match.id] = .ddc(service)
            let stableIdentity = "\(identity.vendor)-\(identity.product)-\(identity.serial)"
            let key = identity.serial == 0 ? "\(stableIdentity)-volatile-\(match.id)" : stableIdentity
            result.append(BrightnessDisplay(id: match.id, key: key, name: match.name))
        }
        return result
    }

    private func releaseDDCServices() {
        for transport in transports.values {
            if case .ddc(let service) = transport { ddcRelease(service) }
        }
        transports.removeAll()
        ddcMaximums.removeAll()
    }

    private struct DisplayInfo { let id: UInt32; let name: String; let vendor: UInt32; let product: UInt32; let serial: UInt32 }
    private func allOnlineDisplayInfo() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let names = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in displayID(for: screen).map { ($0, screen.localizedName) } })
        return ids.map { DisplayInfo(id: $0, name: names[$0] ?? "Display \($0)", vendor: CGDisplayVendorNumber($0), product: CGDisplayModelNumber($0), serial: CGDisplaySerialNumber($0)) }
    }

    private func registryEntries() -> [io_registry_entry_t] {
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var entries: [io_registry_entry_t] = []
        while true { let entry = IOIteratorNext(iterator); if entry == 0 { break }; entries.append(entry) }
        return entries
    }
    private func registryClass(_ entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(entry, &name) == KERN_SUCCESS else { return "" }
        return String(cString: name)
    }
    private func registryProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    private func displayIdentity(_ entry: io_registry_entry_t) -> (vendor: UInt32, product: UInt32, serial: UInt32)? {
        guard let attributes = registryProperty(entry, "DisplayAttributes") as? [String: Any],
              let product = attributes["ProductAttributes"] as? [String: Any],
              let vendor = product["LegacyManufacturerID"] as? UInt32,
              let productID = product["ProductID"] as? UInt32 else { return nil }
        return (vendor, productID, product["SerialNumber"] as? UInt32 ?? 0)
    }
    private func parentDisplayIdentity(_ entry: io_registry_entry_t) -> (vendor: UInt32, product: UInt32, serial: UInt32)? {
        if let identity = displayIdentity(entry) { return identity }
        var iterator = io_iterator_t()
        guard IORegistryEntryGetParentIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while true {
            let parent = IOIteratorNext(iterator)
            if parent == 0 { break }
            defer { IOObjectRelease(parent) }
            if let identity = displayIdentity(parent) { return identity }
        }
        return nil
    }

    private func readDDC(_ service: UnsafeMutableRawPointer) -> (current: UInt16, maximum: UInt16)? {
        var request: [UInt8] = [0x82, DDC.getVCP, DDC.brightnessVCP]
        request.append(request.reduce(DDC.displayAddress ^ DDC.hostAddress, ^))
        let sent = request.withUnsafeMutableBytes { ddcWrite(service, $0.baseAddress!, UInt32($0.count)) }
        guard sent == kIOReturnSuccess else { return nil }
        Thread.sleep(forTimeInterval: DDC.readWait)
        var reply = [UInt8](repeating: 0, count: 16)
        let received = reply.withUnsafeMutableBytes { ddcRead(service, $0.baseAddress!, UInt32($0.count)) }
        guard received == kIOReturnSuccess, reply[2] == DDC.getReply, reply[3] == 0, reply[4] == DDC.brightnessVCP else { return nil }
        return (UInt16(reply[8]) << 8 | UInt16(reply[9]), UInt16(reply[6]) << 8 | UInt16(reply[7]))
    }
    private func writeDDC(_ value: UInt16, service: UnsafeMutableRawPointer) -> Bool {
        var packet: [UInt8] = [0x84, DDC.setVCP, DDC.brightnessVCP, UInt8(value >> 8), UInt8(value)]
        packet.append(packet.reduce(DDC.displayAddress ^ DDC.hostAddress, ^))
        return packet.withUnsafeMutableBytes { ddcWrite(service, $0.baseAddress!, UInt32($0.count)) == kIOReturnSuccess }
    }
}
