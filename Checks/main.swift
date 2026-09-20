import Foundation

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
let base = cal.date(from: DateComponents(year: 2026, month: 9, day: 19))!
func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date { cal.date(byAdding: DateComponents(hour: h, minute: m, second: s), to: base)! }

let cfg = ScheduleConfig.default
var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(label) \(detail)")
}
func near(_ a: Double, _ b: Double, _ eps: Double = 0.005) -> Bool { abs(a - b) < eps }

func t(_ h: Int, _ m: Int) -> ScheduleTarget { Schedule.target(at: at(h, m), config: cfg, calendar: cal) }

var r = t(6, 59)
check("06:59 holds wind-down", near(r.brightness, 0.25) && near(r.kelvin, 1700) && r.phaseName == "Wind-down", "\(r)")
r = t(7, 0)
check("07:00 fade starts from wind-down", near(r.brightness, 0.25) && r.isFading, "\(r)")
r = t(7, 5)
check("07:05 halfway to day", near(r.brightness, 0.625) && r.isFading, "\(r)")
r = t(7, 10)
check("07:10 day, identity", near(r.brightness, 1.0) && near(r.kelvin, 6500) && !r.isFading, "\(r)")
r = t(12, 0)
check("12:00 day", near(r.brightness, 1.0) && r.phaseName == "Day", "\(r)")
r = t(19, 59)
check("19:59 still day", near(r.brightness, 1.0) && r.phaseName == "Day", "\(r)")
r = t(20, 0)
check("20:00 fade starts", near(r.brightness, 1.0) && r.isFading, "\(r)")
r = t(20, 5)
check("20:05 halfway to 75%", near(r.brightness, 0.875) && near(r.kelvin, 4600), "\(r)")
r = t(20, 10)
check("20:10 evening", near(r.brightness, 0.75) && near(r.kelvin, 2700) && !r.isFading, "\(r)")
r = t(21, 59)
check("21:59 evening", near(r.brightness, 0.75), "\(r)")
r = t(22, 5)
check("22:05 halfway to 50%", near(r.brightness, 0.625) && near(r.kelvin, 2450), "\(r)")
r = t(22, 30)
check("22:30 late evening", near(r.brightness, 0.50) && near(r.kelvin, 2200), "\(r)")
r = t(23, 5)
check("23:05 halfway to 25%", near(r.brightness, 0.375) && near(r.kelvin, 1950), "\(r)")
r = t(23, 30)
check("23:30 wind-down", near(r.brightness, 0.25) && near(r.kelvin, 1700), "\(r)")
r = t(2, 0)
check("02:00 wraps midnight, wind-down", near(r.brightness, 0.25) && r.phaseName == "Wind-down", "\(r)")

let n1 = Schedule.nextBoundary(after: at(21, 0), config: cfg, calendar: cal)
check("next boundary after 21:00 is 22:00", n1 == at(22, 0), "\(String(describing: n1))")
let n2 = Schedule.nextBoundary(after: at(23, 30), config: cfg, calendar: cal)
check("next boundary after 23:30 is 07:00 next day", n2 == cal.date(byAdding: .day, value: 1, to: at(7, 0)), "\(String(describing: n2))")
let n3 = Schedule.nextBoundary(after: at(22, 0), config: cfg, calendar: cal)
check("next boundary after 22:00 sharp is 23:00", n3 == at(23, 0), "\(String(describing: n3))")

let d1 = Schedule.nextDayStart(after: at(21, 0), config: cfg, calendar: cal)
check("next day start after 21:00 is 07:00 next day", d1 == cal.date(byAdding: .day, value: 1, to: at(7, 0)), "\(String(describing: d1))")
let d2 = Schedule.nextDayStart(after: at(6, 0), config: cfg, calendar: cal)
check("next day start after 06:00 is 07:00 same day", d2 == at(7, 0), "\(String(describing: d2))")

for k in [6500.0, 4600, 2700, 2200, 1700] {
    let m = ColorTemperature.multipliers(kelvin: k)
    print(String(format: "INFO %.0fK -> R %.3f G %.3f B %.3f", k, m.r, m.g, m.b))
}
let warm = ColorTemperature.multipliers(kelvin: 2700)
check("6500K is identity", ColorTemperature.multipliers(kelvin: 6500) == .identity)
check("2700K keeps red, cuts blue more than green", warm.r == 1 && warm.b < warm.g && warm.g < 1)

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
