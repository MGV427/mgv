import SwiftUI
import MapKit

/// Example screen: a live map of where the app thinks you are.
/// - Tap anywhere on the map to teleport there.
/// - Drag the joystick to walk / cycle / drive / fly around.
/// - Open the picker to search places or build a route to follow.
/// Replace the template ContentView.swift with this, or copy the pieces you need.
struct ContentView: View {
    private let location = LocationService.shared

    @State private var showingPicker = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var cameraDistance: Double = 3_000
    @State private var followsLocation = true

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if location.isFollowingRoute {
                        MapPolyline(coordinates: location.route)
                            .stroke(.purple.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 6]))
                    }
                    if let coordinate = location.currentLocation?.coordinate {
                        Annotation(location.currentLocationName, coordinate: coordinate) {
                            PositionDot(
                                isSimulated: location.isSimulating,
                                course: location.isMoving ? location.course : nil
                            )
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { point in
                    guard let coordinate = proxy.convert(point, from: .local) else { return }
                    location.simulate(coordinate, name: "Dropped pin")
                    followsLocation = true
                }
                .onMapCameraChange { context in
                    cameraDistance = context.camera.distance
                }
                .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in
                    followsLocation = false
                })
            }
            .onChange(of: coordinateKey) { recenter(animated: false) }
            .safeAreaInset(edge: .top) { statusBanner }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        followsLocation = true
                        recenter(animated: true)
                    } label: {
                        Image(systemName: followsLocation ? "location.fill" : "location")
                    }
                    .accessibilityLabel("Follow location")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Search or Route", systemImage: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                LocationPickerView()
            }
            .onAppear {
                location.start()
                recenter(animated: false)
            }
        }
    }

    // MARK: - Pieces

    private var statusBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(location.isSimulating ? Color.purple : Color.blue)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(location.isSimulating ? "Simulating · \(location.currentLocationName)" : "Real location")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let coordinate = location.currentLocation?.coordinate {
                    Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else if let error = location.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text("Tap the map to simulate a location").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if location.isSimulating {
                Button("Use Real") { location.stopSimulating() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
    }

    private var bottomPanel: some View {
        SimulationControls()
            .padding(.horizontal)
            .padding(.bottom, 8)
    }

    // MARK: - Camera

    /// Changes whenever the shown position moves.
    private var coordinateKey: [Double] {
        guard let coordinate = location.currentLocation?.coordinate else { return [] }
        return [coordinate.latitude, coordinate.longitude]
    }

    private func recenter(animated: Bool) {
        guard followsLocation, let coordinate = location.currentLocation?.coordinate else { return }
        let target = MapCameraPosition.camera(MapCamera(centerCoordinate: coordinate, distance: cameraDistance))
        if animated {
            withAnimation { camera = target }
        } else {
            camera = target
        }
    }
}

/// Blue dot for the real location, purple for a simulated one,
/// with an arrow showing the direction of travel while moving.
struct PositionDot: View {
    var isSimulated: Bool
    var course: Double?

    var body: some View {
        let color: Color = isSimulated ? .purple : .blue
        ZStack {
            Circle().fill(color.opacity(0.2)).frame(width: 44, height: 44)
            if let course {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(course))
            } else {
                Circle().fill(.white).frame(width: 20, height: 20)
                Circle().fill(color).frame(width: 14, height: 14)
            }
        }
        .animation(.easeOut(duration: 0.15), value: course)
    }
}

#Preview {
    ContentView()
}
