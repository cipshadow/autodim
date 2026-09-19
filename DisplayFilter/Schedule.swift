import Foundation

struct SchedulePhase: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var startMinute: Int
    var brightness: Double
    var kelvin: Double
}

struct ScheduleConfig: Codable, Equatable {
    static let neutralKelvin = 6500.0
    static let minutesPerDay = 1440

    var enabled = true
    var fadeMinutes = 10
    var phases: [SchedulePhase]

    static let `default` = ScheduleConfig(phases: [
        SchedulePhase(name: "Day", startMinute: 7 * 60, brightness: 1.0, kelvin: neutralKelvin),
        SchedulePhase(name: "Evening", startMinute: 20 * 60, brightness: 0.75, kelvin: 2700),
        SchedulePhase(name: "Late evening", startMinute: 22 * 60, brightness: 0.50, kelvin: 2200),
        SchedulePhase(name: "Wind-down", startMinute: 23 * 60, brightness: 0.25, kelvin: 1700),
    ])
}

struct ScheduleTarget: Equatable {
    var brightness: Double
    var kelvin: Double
    var phaseName: String
    var isFading: Bool
}

enum Schedule {
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0) + Double(c.second ?? 0) / 60
    }

    static func target(at date: Date, config: ScheduleConfig, calendar: Calendar = .current) -> ScheduleTarget {
        let phases = config.phases.sorted { $0.startMinute < $1.startMinute }
        guard !phases.isEmpty else {
            return ScheduleTarget(brightness: 1, kelvin: ScheduleConfig.neutralKelvin, phaseName: "", isFading: false)
        }
        let now = minuteOfDay(date, calendar: calendar)
        var currentIndex = phases.count - 1
        for (i, p) in phases.enumerated() where Double(p.startMinute) <= now {
            currentIndex = i
        }
        let current = phases[currentIndex]
        let previous = phases[(currentIndex + phases.count - 1) % phases.count]
        let day = Double(ScheduleConfig.minutesPerDay)
        let elapsed = (now - Double(current.startMinute) + day).truncatingRemainder(dividingBy: day)
        let next = phases[(currentIndex + 1) % phases.count]
        let gap = max(1, Double((next.startMinute - current.startMinute + ScheduleConfig.minutesPerDay) % ScheduleConfig.minutesPerDay))
        let fade = min(Double(config.fadeMinutes), gap)

        if phases.count > 1, fade > 0, elapsed < fade {
            let t = elapsed / fade
            return ScheduleTarget(
                brightness: previous.brightness + (current.brightness - previous.brightness) * t,
                kelvin: previous.kelvin + (current.kelvin - previous.kelvin) * t,
                phaseName: current.name,
                isFading: true
            )
        }
        return ScheduleTarget(brightness: current.brightness, kelvin: current.kelvin, phaseName: current.name, isFading: false)
    }

    static func nextBoundary(after date: Date, config: ScheduleConfig, calendar: Calendar = .current) -> Date? {
        var best: Date?
        for p in config.phases {
            var comps = DateComponents()
            comps.hour = p.startMinute / 60
            comps.minute = p.startMinute % 60
            comps.second = 0
            guard let d = calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) else { continue }
            if best == nil || d < best! { best = d }
        }
        return best
    }

    static func timeString(minute: Int) -> String {
        String(format: "%02d:%02d", (minute / 60) % 24, minute % 60)
    }
}
