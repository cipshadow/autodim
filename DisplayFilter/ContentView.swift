import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Namespace private var animation
    @LocalState private var showPhases = false

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
                Text("Display filter").font(.headline)
                Spacer()
                IconButton(icon: "arrow.counterclockwise", action: appState.resumeSchedule)
                    .help("Resume schedule")
                IconButton(icon: "xmark.circle", action: {
                    NSApplication.shared.terminate(nil)
                })
            }
            .padding(.horizontal, 8)

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

            FilterCard { scheduleView }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "moon.stars.fill").foregroundColor(.secondary)
                Text(phaseLine).font(.subheadline)
                Spacer()
            }
            if let until = appState.overrideUntil {
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

    private var phaseLine: String {
        guard appState.config.enabled else { return "Schedule off" }
        return appState.effective.isFading ? "\(appState.effective.phaseName), fading in" : appState.effective.phaseName
    }

    private var scheduleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Daily schedule", isOn: $appState.config.enabled)
                .font(.subheadline)
            DisclosureGroup("Phases", isExpanded: $showPhases) {
                VStack(spacing: 10) {
                    ForEach($appState.config.phases) { $phase in
                        PhaseRow(phase: $phase)
                    }
                    Stepper("Fade: \(appState.config.fadeMinutes) min", value: $appState.config.fadeMinutes, in: 0...60, step: 5)
                        .font(.caption)
                    Button("Restore defaults") { appState.config = .default }
                        .font(.caption)
                }
                .padding(.top, 6)
            }
            .font(.subheadline)
            Toggle("Launch at login", isOn: Binding(get: { appState.launchAtLogin }, set: { appState.setLaunchAtLogin($0) }))
                .font(.subheadline)
            if let error = appState.launchError {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }
}

struct PhaseRow: View {
    @Binding var phase: SchedulePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(phase.name).font(.caption).fontWeight(.semibold)
                Spacer()
                Stepper(value: $phase.startMinute, in: 0...1425, step: 15) {
                    Text(Schedule.timeString(minute: phase.startMinute)).font(.caption).monospacedDigit()
                }
            }
            HStack(spacing: 6) {
                Text("Bright").font(.caption2).foregroundColor(.secondary).frame(width: 40, alignment: .leading)
                Slider(value: $phase.brightness, in: ColorAdjuster.minimumBrightness...1)
                Text("\(Int(phase.brightness * 100))%").font(.caption2).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("Warmth").font(.caption2).foregroundColor(.secondary).frame(width: 40, alignment: .leading)
                Slider(value: $phase.kelvin, in: 1500...6500, step: 100)
                Text(verbatim: phase.kelvin >= ScheduleConfig.neutralKelvin ? "none" : "\(Int(phase.kelvin))K")
                    .font(.caption2).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
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
    case none, orange, red, green, blue
    
    var color: Color {
        switch self {
        case .none: return Color(NSColor.lightGray)
        case .orange: return .orange
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "arrow.counterclockwise.circle.fill"
        case .orange: return "sun.max.fill"
        case .red: return "eyeglasses"
        case .green: return "leaf.fill"
        case .blue: return "drop.fill"
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
