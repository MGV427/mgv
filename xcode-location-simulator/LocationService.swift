import Foundation
import CoreLocation
import Observation

/// Single source of truth for "where am I?" in the app.
///
/// Reads the real device location from Core Location, but can be switched to a
/// simulated coordinate anywhere on Earth. The rest of the app should read
/// `LocationService.shared.currentLocation` instead of talking to
/// `CLLocationManager` directly, so a simulated location takes effect everywhere.
///
/// The simulated location is saved, so it survives app relaunches.
@MainActor
@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    /// Latest fix from the GPS / Xcode's own location simulation.
    private(set) var realLocation: CLLocation?
    /// Coordinate used while `isSimulating` is on.
    private(set) var simulatedCoordinate: CLLocationCoordinate2D?
    /// Human-readable label for the simulated spot ("Eiffel Tower", "Dropped pin", ...).
    private(set) var simulatedName: String?
    private(set) var isSimulating = false
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastError: String?

    /// The location the app should use: the simulated one when simulating, the real one otherwise.
    var currentLocation: CLLocation? {
        if isSimulating, let coordinate = simulatedCoordinate {
            return CLLocation(
                coordinate: coordinate,
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: .now
            )
        }
        return realLocation
    }

    /// Label for `currentLocation`, handy for UI.
    var currentLocationName: String {
        if isSimulating { return simulatedName ?? "Simulated location" }
        return realLocation == nil ? "Unknown" : "Real location"
    }

    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let latitude = "LocationService.simulatedLatitude"
        static let longitude = "LocationService.simulatedLongitude"
        static let name = "LocationService.simulatedName"
        static let isSimulating = "LocationService.isSimulating"
    }

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
        restore()
    }

    // MARK: - Real location

    /// Asks for permission (if needed) and starts receiving real location updates.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            lastError = "Location access is off. You can still simulate a location."
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: - Simulation

    /// Pretend the device is at `coordinate`.
    func simulate(_ coordinate: CLLocationCoordinate2D, name: String? = nil) {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            lastError = "That coordinate isn't valid."
            return
        }
        simulatedCoordinate = coordinate
        simulatedName = name
        isSimulating = true
        lastError = nil
        persist()
    }

    /// Pretend the device is at the given latitude / longitude.
    func simulate(latitude: Double, longitude: Double, name: String? = nil) {
        simulate(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), name: name)
    }

    /// Go back to the real location (the last simulated spot is kept for next time).
    func stopSimulating() {
        isSimulating = false
        persist()
    }

    /// Turn simulation back on at the last simulated spot, if there is one.
    func resumeSimulating() {
        guard simulatedCoordinate != nil else { return }
        isSimulating = true
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(isSimulating, forKey: Key.isSimulating)
        defaults.set(simulatedName, forKey: Key.name)
        if let coordinate = simulatedCoordinate {
            defaults.set(coordinate.latitude, forKey: Key.latitude)
            defaults.set(coordinate.longitude, forKey: Key.longitude)
        } else {
            defaults.removeObject(forKey: Key.latitude)
            defaults.removeObject(forKey: Key.longitude)
        }
    }

    private func restore() {
        if defaults.object(forKey: Key.latitude) != nil,
           defaults.object(forKey: Key.longitude) != nil {
            simulatedCoordinate = CLLocationCoordinate2D(
                latitude: defaults.double(forKey: Key.latitude),
                longitude: defaults.double(forKey: Key.longitude)
            )
        }
        simulatedName = defaults.string(forKey: Key.name)
        isSimulating = defaults.bool(forKey: Key.isSimulating) && simulatedCoordinate != nil
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    // Core Location calls back on the thread the manager was created on (main).
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated {
            realLocation = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            lastError = message
        }
    }
}
