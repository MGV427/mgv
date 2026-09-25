import SwiftUI
import MapKit

/// Pick any location on Earth to simulate:
/// - search for an address, city or place
/// - type coordinates like `48.8584, 2.2945`
/// - tap anywhere on the map
/// - choose a preset city
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss

    private let service = LocationService.shared

    @State private var search = PlaceSearch()
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: CLLocationCoordinate2D?
    @State private var selectedName: String?
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if searchFocused && !search.query.isEmpty {
                    searchResults
                } else {
                    map
                    controls
                }
            }
            .navigationTitle("Simulate Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if service.isSimulating {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Use Real") {
                            service.stopSimulating()
                            dismiss()
                        }
                    }
                }
            }
            .onAppear(perform: loadInitialSelection)
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search a place or enter lat, lon", text: $search.query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(submitSearch)
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    private var searchResults: some View {
        List {
            if let coordinate = Self.parseCoordinate(search.query) {
                Button {
                    select(coordinate, name: nil)
                } label: {
                    Label(
                        String(format: "Go to %.5f, %.5f", coordinate.latitude, coordinate.longitude),
                        systemImage: "location.north.circle"
                    )
                }
            }
            ForEach(search.completions, id: \.self) { completion in
                Button {
                    Task { await choose(completion) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(completion.title).foregroundStyle(.primary)
                        if !completion.subtitle.isEmpty {
                            Text(completion.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let selected {
                    Marker(selectedName ?? "Simulated", systemImage: "location.fill", coordinate: selected)
                        .tint(.purple)
                }
                UserAnnotation()
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    select(coordinate, name: nil, moveCamera: false)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Self.presets, id: \.name) { preset in
                        Button(preset.name) {
                            select(preset.coordinate, name: preset.name)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                TextField("Latitude", text: $latitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                TextField("Longitude", text: $longitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                Button("Go") {
                    if let coordinate = Self.parseCoordinate("\(latitudeText),\(longitudeText)") {
                        select(coordinate, name: nil)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Button {
                guard let selected else { return }
                service.simulate(selected, name: selectedName ?? Self.format(selected))
                dismiss()
            } label: {
                Label("Simulate Here", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(selected == nil)
            .padding(.horizontal)

            Text("Tap the map, search, or enter coordinates.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical)
        .background(.bar)
    }

    // MARK: - Actions

    private func loadInitialSelection() {
        if let coordinate = service.simulatedCoordinate {
            select(coordinate, name: service.simulatedName)
        } else if let real = service.realLocation?.coordinate {
            position = .region(MKCoordinateRegion(center: real, latitudinalMeters: 5_000, longitudinalMeters: 5_000))
        }
    }

    private func select(_ coordinate: CLLocationCoordinate2D, name: String?, moveCamera: Bool = true) {
        selected = coordinate
        selectedName = name
        latitudeText = String(format: "%.6f", coordinate.latitude)
        longitudeText = String(format: "%.6f", coordinate.longitude)
        searchFocused = false
        if moveCamera {
            withAnimation {
                position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 5_000, longitudinalMeters: 5_000))
            }
        }
    }

    private func submitSearch() {
        if let coordinate = Self.parseCoordinate(search.query) {
            select(coordinate, name: nil)
        } else if let first = search.completions.first {
            Task { await choose(first) }
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) async {
        guard let item = await search.resolve(completion) else { return }
        select(item.coordinate, name: item.name)
    }

    // MARK: - Helpers

    /// Accepts "48.8584, 2.2945", "48.8584 2.2945" or "48.8584;2.2945".
    static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " })
            .compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    static func format(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    struct Preset {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    static let presets: [Preset] = [
        Preset(name: "New York", coordinate: .init(latitude: 40.7580, longitude: -73.9855)),
        Preset(name: "San Francisco", coordinate: .init(latitude: 37.7749, longitude: -122.4194)),
        Preset(name: "London", coordinate: .init(latitude: 51.5074, longitude: -0.1278)),
        Preset(name: "Paris", coordinate: .init(latitude: 48.8584, longitude: 2.2945)),
        Preset(name: "Rome", coordinate: .init(latitude: 41.8902, longitude: 12.4922)),
        Preset(name: "Milan", coordinate: .init(latitude: 45.4642, longitude: 9.1900)),
        Preset(name: "Tokyo", coordinate: .init(latitude: 35.6595, longitude: 139.7005)),
        Preset(name: "Sydney", coordinate: .init(latitude: -33.8568, longitude: 151.2153)),
        Preset(name: "Rio", coordinate: .init(latitude: -22.9519, longitude: -43.2105)),
        Preset(name: "Cape Town", coordinate: .init(latitude: -33.9249, longitude: 18.4241)),
    ]
}

// MARK: - Search

/// Live place search backed by MapKit's autocomplete.
@MainActor
@Observable
final class PlaceSearch: NSObject {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var completions: [MKLocalSearchCompletion] = []

    struct Result {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Turns an autocomplete suggestion into a real coordinate.
    func resolve(_ completion: MKLocalSearchCompletion) async -> Result? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        return Result(name: item.name ?? completion.title, coordinate: coordinate)
    }
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {
    // MapKit calls the completer delegate on the main thread.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            completions = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            completions = []
        }
    }
}

#Preview {
    LocationPickerView()
}
