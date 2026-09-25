import SwiftUI

/// On-screen joystick. Drag the knob to move; let go to stop.
/// Reports `east` / `north` in -1...1 (up on screen = north).
struct JoystickView: View {
    var onChange: (_ east: Double, _ north: Double) -> Void

    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 1))
            ForEach(0..<4, id: \.self) { index in
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .offset(y: -radius + 10)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            Circle()
                .fill(.purple.gradient)
                .frame(width: 48, height: 48)
                .shadow(radius: 3)
                .offset(knob)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var vector = CGSize(width: value.location.x - radius, height: value.location.y - radius)
                    let length = hypot(vector.width, vector.height)
                    if length > radius {
                        vector.width *= radius / length
                        vector.height *= radius / length
                    }
                    knob = vector
                    onChange(Double(vector.width / radius), Double(-vector.height / radius))
                }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.25)) { knob = .zero }
                    onChange(0, 0)
                }
        )
        .accessibilityLabel("Movement joystick")
    }
}

/// Speed picker shared by the main screen and the route builder.
struct SpeedPicker: View {
    @Bindable var service = LocationService.shared

    var body: some View {
        Picker("Speed", selection: $service.speed) {
            ForEach(LocationService.Speed.allCases) { speed in
                Label(speed.label, systemImage: speed.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(speed)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Joystick, speed and live readout, shown over the map while simulating.
struct SimulationControls: View {
    private let service = LocationService.shared

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            JoystickView { east, north in
                service.setJoystick(east: east, north: north)
            }

            VStack(alignment: .leading, spacing: 8) {
                SpeedPicker()

                HStack(spacing: 6) {
                    Image(systemName: service.speed.systemImage)
                    Text(service.speed.label)
                    Text(Self.speedText(service.isMoving ? service.movingSpeed : service.speed.rawValue))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                if service.isMoving, service.course >= 0 {
                    Label(Self.compass(service.course), systemImage: "location.north.line.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if service.isFollowingRoute {
                    Button {
                        service.stopRoute()
                    } label: {
                        Label("Stop Route", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Text("Drag to move · Tap map to teleport")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    static func speedText(_ metersPerSecond: Double) -> String {
        Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .converted(to: .kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func compass(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees / 45).rounded()) % names.count
        return "Heading \(names[index]) (\(Int(degrees))°)"
    }
}

#Preview {
    SimulationControls().padding()
}
