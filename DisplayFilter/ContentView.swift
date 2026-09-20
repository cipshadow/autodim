import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Namespace private var animation
    @LocalState private var tab = 0
    @LocalState private var selectedPhase = "Evening"

    private var brightness: Binding<Double> {
        Binding(get: { appState.effective.brightness }, set: { appState.setBrightness($0) })
    }

    private var intensity: Binding<Double> {
        Binding(get: { appState.colorOverride?.intensity ?? 0 }, set: { appState.setIntensity($0) })
    }

    private var selectedColor: FilterColor? { appState.colorOverride?.color }
    private var showIntensitySlider: Bool { selectedColor != nil && selectedColor != FilterColor.none }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("AutoDim").font(.headline)
                Spacer()
                IconButton(icon: "arrow.counterclockwise", action: appState.resumeSchedule)
                    .help("Resume schedule")
                IconButton(icon: "xmark.circle", action: {
                    NSApplication.shared.terminate(nil)
                })
            }
            .padding(.horizontal, 8)

            Picker("View", selection: $tab) {
                Text("Now").tag(0)
                Text("Schedule").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 { nowTab } else { scheduleTab }
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: Now tab

    private var nowTab: some View {
        VStack(spacing: 8) {
            FilterCard { statusView }

            FilterCard {
                ModernFilterSlider(value: brightness, label: "Brightness", icon: "sun.max.fill", range: ColorAdjuster.minimumBrightness...1)
            }

            FilterCard {
                VStack(spacing: 8) {
                    HStack {
                        Text("Color Filter")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(FilterColor.allCases, id: \.self) { color in
                                ColorDot(color: color, isSelected: selectedColor == color, namespace: animation)
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if selectedColor == color && color != .none {
                                                appState.setColor(.none)
                                            } else {
                                                appState.setColor(color)
                                            }
                                        }
                                    }
                            }
                        }
                    }
                    if showIntensitySlider {
                        ModernFilterSlider(value: intensity, label: "Intensity", icon: "slider.horizontal.3", range: 0...1)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .scale.combined(with: .opacity)))
                            .matchedGeometryEffect(id: "intensitySlider", in: animation)
                    }
                }
            }
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: appState.isPaused ? "pause.circle" : "moon.stars.fill")
                    .foregroundColor(appState.isPaused ? .orange : .secondary)
                Text(titleLine).font(.subheadline).fontWeight(.semibold)
                Spacer()
                if appState.isPaused {
                    Button("Resume") { appState.resumeSchedule() }
                        .buttonStyle(.borderedProminent)
                } else if appState.config.enabled {
                    pauseMenu
                }
            }
            if appState.isPaused {
                Text("Normal brightness and color until then.")
                    .font(.caption).foregroundColor(.secondary)
            } else if let until = appState.overrideUntil {
                HStack {
                    Text("Manual until \(appState.timeText(until))")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Resume") { appState.resumeSchedule() }
                        .buttonStyle(.link).font(.caption)
                }
            } else if appState.hasOverride {
                Text("Manual, schedule is off").font(.caption).foregroundColor(.secondary)
            } else if let next = appState.nextChange {
                Text("Next change at \(appState.timeText(next))")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleLine: String {
        guard appState.config.enabled else { return "Schedule off" }
        if let until = appState.pausedUntil { return "Paused until \(appState.timeText(until))" }
        return appState.effective.isFading ? "\(appState.effective.phaseName), fading in" : appState.effective.phaseName
    }

    private var pauseMenu: some View {
        Menu {
            if let next = appState.nextChange {
                Button("Until next phase (\(appState.timeText(next)))") { appState.pauseUntilNextPhase() }
            }
            Button("For 1 hour") { appState.pause(forHours: 1) }
            if let day = appState.nextDayStart {
                Button(Calendar.current.isDateInToday(day) ? "Until \(appState.timeText(day))" : "Until tomorrow (\(appState.timeText(day)))") {
                    appState.pauseUntilTomorrow()
                }
            }
        } label: {
            Label("Pause", systemImage: "pause.circle")
        }
        .fixedSize()
    }

    // MARK: Schedule tab

    private var scheduleTab: some View {
        FilterCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Daily schedule").font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Toggle("Daily schedule", isOn: $appState.config.enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                PhaseStrip(phases: appState.config.phases, selected: selectedPhase, current: appState.currentPhase) {
                    selectedPhase = $0
                }
                if let i = appState.config.phases.firstIndex(where: { $0.name == selectedPhase }) ?? appState.config.phases.indices.first {
                    PhaseEditor(phase: $appState.config.phases[i], isCurrent: appState.config.phases[i].name == appState.currentPhase)
                }
                Divider()
                HStack {
                    Text("Fade: \(appState.config.fadeMinutes) min").font(.caption).foregroundColor(.secondary)
                    Stepper("Fade", value: $appState.config.fadeMinutes, in: 0...60, step: 5).labelsHidden()
                    Spacer()
                    Button("Restore defaults") { appState.config = .default }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }
}

struct PhaseStrip: View {
    let phases: [SchedulePhase]
    let selected: String
    let current: String
    let select: (String) -> Void

    private func swatch(_ phase: SchedulePhase) -> Color {
        let m = ColorTemperature.multipliers(kelvin: phase.kelvin)
        return Color(red: 0.92 * m.r, green: 0.92 * m.g, blue: 0.94 * m.b)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(phases.sorted { $0.startMinute < $1.startMinute }) { phase in
                Button { select(phase.name) } label: {
                    VStack(spacing: 1) {
                        Text(verbatim: Schedule.timeString(minute: phase.startMinute))
                            .font(.system(size: 12, weight: .bold)).monospacedDigit()
                        Text(verbatim: "\(Int((phase.brightness * 100).rounded()))%")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Color(white: 0.11))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 9).fill(swatch(phase)))
                    .overlay(alignment: .topTrailing) {
                        if phase.name == current {
                            Circle().fill(Color(white: 0.11)).frame(width: 6, height: 6).padding(5)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary, lineWidth: phase.name == selected ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(phase.name), starts \(Schedule.timeString(minute: phase.startMinute)), brightness \(Int((phase.brightness * 100).rounded())) percent")
            }
        }
    }
}

struct PhaseEditor: View {
    @Binding var phase: SchedulePhase
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(phase.name).font(.subheadline).fontWeight(.semibold)
                if isCurrent { Text("(now)").font(.subheadline).foregroundColor(.secondary) }
                Spacer()
                Text(verbatim: "Starts \(Schedule.timeString(minute: phase.startMinute))")
                    .font(.subheadline).monospacedDigit()
                Stepper("Start time", value: $phase.startMinute, in: 0...1425, step: 15).labelsHidden()
            }
            row("Bright", value: "\(Int((phase.brightness * 100).rounded()))%") {
                Slider(value: $phase.brightness, in: ColorAdjuster.minimumBrightness...1)
            }
            row("Warmth", value: phase.kelvin >= ScheduleConfig.neutralKelvin ? "none" : "\(Int(phase.kelvin))K") {
                Slider(value: $phase.kelvin, in: 1500...6500, step: 100)
            }
        }
    }

    private func row<S: View>(_ label: String, value: String, @ViewBuilder slider: () -> S) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 46, alignment: .leading)
            slider()
            Text(verbatim: value).font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

struct IconButton: View {
    let icon: String
    let action: () -> Void
    
    @LocalState private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(isHovered ? Color(NSColor.selectedContentBackgroundColor) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ModernFilterSlider: View {
    @Binding var value: Double
    let label: String
    let icon: String
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ModernSlider(value: $value, range: range)
                .frame(height: 36)
        }
    }
}

struct ModernSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.trackFillColor = NSColor.controlAccentColor
        slider.isContinuous = true
        return slider
    }
    
    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.doubleValue = value
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ModernSlider
        
        init(_ parent: ModernSlider) {
            self.parent = parent
        }
        
        @objc func valueChanged(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }
    }
}

struct FilterCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(10)
            .background(
                ZStack {
                    VisualEffectView(material: .menu, blendingMode: .withinWindow)
                    Color(NSColor.controlBackgroundColor).opacity(0.3)
                }
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// New components

enum FilterColor: String, CaseIterable {
    case none, orange, red
    
    var color: Color {
        switch self {
        case .none: return Color(NSColor.lightGray)
        case .orange: return .orange
        case .red: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "arrow.counterclockwise.circle.fill"
        case .orange: return "sun.max.fill"
        case .red: return "eyeglasses"
        }
    }
}

struct ColorDot: View {
    let color: FilterColor
    let isSelected: Bool
    let namespace: Namespace.ID
    
    var body: some View {
        ZStack {
            if color == .none {
                Image(systemName: color.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            } else {
                Circle()
                    .fill(color.color)
                    .frame(width: 20, height: 20)
                
                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .matchedGeometryEffect(id: "selectedBorder_\(color.rawValue)", in: namespace)
                }
            }
        }
        .overlay(
            Circle()
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                .frame(width: 22, height: 22)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// SwiftUI's @State is a macro whose plugin ships only with full Xcode; this wrapper lets build.sh compile with Command Line Tools.
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    private var storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
