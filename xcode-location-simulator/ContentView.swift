import SwiftUI
import MapKit

/// Example screen: shows where the app thinks you are and lets you
/// simulate any location. Replace the template ContentView.swift with this,
/// or copy the pieces you need into your own view.
struct ContentView: View {
    private let location = LocationService.shared
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Map(position: .constant(cameraPosition)) {
                    if let coordinate = location.currentLocation?.coordinate {
                        Marker(location.currentLocationName, systemImage: "location.fill", coordinate: coordinate)
                            .tint(location.isSimulating ? .purple : .blue)
                    }
                }
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 4) {
                    Label(
                        location.isSimulating ? "Simulating" : "Real location",
                        systemImage: location.isSimulating ? "location.circle.fill" : "location.circle"
                    )
                    .font(.headline)
                    .foregroundStyle(location.isSimulating ? .purple : .blue)

                    Text(location.currentLocationName)
                    if let coordinate = location.currentLocation?.coordinate {
                        Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let error = location.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                HStack {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Simulate Location", systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    if location.isSimulating {
                        Button("Use Real") { location.stopSimulating() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .navigationTitle("Location")
            .sheet(isPresented: $showingPicker) {
                LocationPickerView()
            }
            .onAppear { location.start() }
        }
    }

    private var cameraPosition: MapCameraPosition {
        guard let coordinate = location.currentLocation?.coordinate else { return .automatic }
        return .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 3_000, longitudinalMeters: 3_000))
    }
}

#Preview {
    ContentView()
}
