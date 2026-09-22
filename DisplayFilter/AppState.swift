import SwiftUI

struct ColorOverride: Equatable {
    var color: FilterColor
    var intensity: Double
}

struct EffectiveState: Equatable {
    var brightness: Double
    var rgb: ColorTemperature.RGB
    var phaseName: String
    var isFading: Bool
}

final class AppState: ObservableObject {
    static let shared = AppState()
    private static let configKey = "scheduleConfig.v1"

    @Published var config: ScheduleConfig {
        didSet {
            save()
            if !config.enabled {
                overrideUntil = nil
                pausedUntil = nil
            } else if hasOverride {
                overrideUntil = Schedule.nextBoundary(after: now, config: config)
            }
            refresh()
        }
    }
    @Published private(set) var brightnessOverride: Double?
    @Published private(set) var colorOverride: ColorOverride?
    @Published private(set) var overrideUntil: Date?
    @Published private(set) var effective = EffectiveState(brightness: 1, rgb: .identity, phaseName: "", isFading: false)
    @Published private(set) var nextChange: Date?
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var currentPhase = ""

    private var timeOffset: TimeInterval = 0
    private var timer: Timer?

    var now: Date { Date().addingTimeInterval(timeOffset) }
    var hasOverride: Bool { brightnessOverride != nil || colorOverride != nil }
    var isPaused: Bool { pausedUntil != nil }
    var nextDayStart: Date? { Schedule.nextDayStart(after: now, config: config) }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(ScheduleConfig.self, from: data) {
            config = saved
        } else {
            config = .default
        }

        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--simulate-time"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2,
               let sim = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) {
                timeOffset = sim.timeIntervalSince(Date())
            }
        }
        #endif

        registerObservers()
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 5
    }

    func refresh(force: Bool = false) {
        let now = self.now
        if let until = overrideUntil, now >= until {
            brightnessOverride = nil
            colorOverride = nil
            overrideUntil = nil
        }

        if let until = pausedUntil, now >= until { pausedUntil = nil }

        let scheduled = Schedule.target(at: now, config: config)
        let target: ScheduleTarget
        if !config.enabled {
            target = ScheduleTarget(brightness: 1, kelvin: ScheduleConfig.neutralKelvin, phaseName: "Schedule off", isFading: false)
        } else if isPaused {
            target = ScheduleTarget(brightness: 1, kelvin: ScheduleConfig.neutralKelvin, phaseName: "Paused", isFading: false)
        } else {
            target = scheduled
        }
        let phase = config.enabled ? scheduled.phaseName : ""
        if phase != currentPhase { currentPhase = phase }

        let brightness = brightnessOverride ?? target.brightness
        let rgb: ColorTemperature.RGB
        if let c = colorOverride {
            rgb = ColorAdjuster.multipliers(for: c.color, intensity: c.intensity)
        } else {
            rgb = ColorTemperature.multipliers(kelvin: target.kelvin)
        }

        let state = EffectiveState(brightness: brightness, rgb: rgb, phaseName: target.phaseName, isFading: target.isFading)
        if state != effective { effective = state }
        let next = config.enabled ? Schedule.nextBoundary(after: now, config: config) : nil
        if next != nextChange { nextChange = next }

        ColorAdjuster.shared.apply(brightness: brightness, rgb: rgb, force: force)
    }

    func setBrightness(_ value: Double) {
        brightnessOverride = max(ColorAdjuster.minimumBrightness, min(1, value))
        beginOverride()
    }

    func setColor(_ color: FilterColor) {
        let intensity = color == .none ? 0 : (colorOverride?.intensity ?? 0.5)
        colorOverride = ColorOverride(color: color, intensity: intensity)
        beginOverride()
    }

    func setIntensity(_ value: Double) {
        guard let current = colorOverride else { return }
        colorOverride = ColorOverride(color: current.color, intensity: max(0, min(1, value)))
        beginOverride()
    }

    func resumeSchedule() {
        brightnessOverride = nil
        colorOverride = nil
        overrideUntil = nil
        pausedUntil = nil
        refresh()
    }

    func pauseIndefinitely() {
        pausedUntil = .distantFuture
        refresh()
    }

    func pause(forHours hours: Double) {
        pausedUntil = now.addingTimeInterval(hours * 3600)
        refresh()
    }

    func pauseUntilMorning() {
        pausedUntil = nextDayStart ?? now.addingTimeInterval(24 * 3600)
        refresh()
    }

    func timeText(_ date: Date) -> String {
        Schedule.timeString(minute: Int(Schedule.minuteOfDay(date)))
    }

    private func beginOverride() {
        overrideUntil = config.enabled ? Schedule.nextBoundary(after: now, config: config) : nil
        refresh()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }

    private func registerObservers() {
        let reapply: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self?.refresh(force: true) }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reapply)
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: reapply)
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: reapply)

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reapply)
        center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: reapply)
        center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: reapply)
        center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: reapply)
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            ColorAdjuster.shared.restoreAll()
        }
    }
}
