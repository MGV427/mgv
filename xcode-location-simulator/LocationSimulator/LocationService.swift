import Foundation
import CoreLocation
import Observation

/// Single source of truth for "where am I?" in the app.
///
/// Reads the real device location from Core Location, but can be switched to a
/// simulated coordinate anywhere on Earth. The simulated position can then be
/// moved live with a joystick or sent along a route at walking, cycling,
/// driving or flying speed.
///
/// The rest of the app should read `LocationService.shared.currentLocation`
/// instead of talking to `CLLocationManager` directly, so a simulated location
/// takes effect everywhere. The simulated spot is saved across relaunches.
@MainActor
@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    /// How fast the simulated position moves with the joystick or along a route.
    enum Speed: Double, CaseIterable, Identifiable {
        case walk = 1.4
        case run = 3.5
        case cycle = 6
        case drive = 15
        case fly = 250

        var id: Double { rawValue }

        var label: String {
            switch self {
            case .walk: "Walk"
            case .run: "Run"
            case .cycle: "Cycle"
            case .drive: "Drive"
            case .fly: "Fly"
            }
        }

        var systemImage: String {
            switch self {
            case .walk: "figure.walk"
            case .run: "figure.run"
            case .cycle: "bicycle"
            case .drive: "car.fill"
            case .fly: "airplane"
            }
        }
    }

    /// Latest fix from the GPS / Xcode's own location simulation.
    private(set) var realLocation: CLLocation?
    /// Coordinate used while `isSimulating` is on.
    private(set) var simulatedCoordinate: CLLocationCoordinate2D?
    /// Human-readable label for the simulated spot ("Eiffel Tower", "Dropped pin", ...).
    private(set) var simulatedName: String?
    private(set) var isSimulating = false
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastError: String?

    /// Movement speed for the joystick and routes. Can be changed while moving.
    var speed: Speed = .walk
    /// Direction of travel in degrees (0 = north), or -1 when standing still.
    private(set) var course: CLLocationDirection = -1
    /// Current simulated speed in m/s (0 when standing still).
    private(set) var movingSpeed: CLLocationSpeed = 0
    /// Waypoints of the route being followed, if any.
    private(set) var route: [CLLocationCoordinate2D] = []
    private(set) var isFollowingRoute = false

    var isMoving: Bool { movingSpeed > 0 }

    /// The location the app should use: the simulated one when simulating, the real one otherwise.
    var currentLocation: CLLocation? {
        if isSimulating, let coordinate = simulatedCoordinate {
            return CLLocation(
                coordinate: coordinate,
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: course,
                speed: isMoving ? movingSpeed : -1,
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
    private var joystick = (east: 0.0, north: 0.0)
    private var joystickTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?

    /// How often the simulated position is advanced while moving.
    private static let tick: Duration = .milliseconds(100)

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

    /// Teleport the simulated position to `coordinate` (stops any route).
    func simulate(_ coordinate: CLLocationCoordinate2D, name: String? = nil) {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            lastError = "That coordinate isn't valid."
            return
        }
        stopRoute()
        simulatedCoordinate = coordinate
        simulatedName = name
        isSimulating = true
        lastError = nil
        persist()
    }

    /// Teleport the simulated position to the given latitude / longitude.
    func simulate(latitude: Double, longitude: Double, name: String? = nil) {
        simulate(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), name: name)
    }

    /// Go back to the real location (the last simulated spot is kept for next time).
    func stopSimulating() {
        stopRoute()
        setJoystick(east: 0, north: 0)
        isSimulating = false
        persist()
    }

    /// Turn simulation back on at the last simulated spot, if there is one.
    func resumeSimulating() {
        guard simulatedCoordinate != nil else { return }
        isSimulating = true
        persist()
    }

    // MARK: - Joystick

    /// Drive the simulated position like a joystick.
    /// `east` and `north` are -1...1; (0, 0) stops. Starts simulating from the
    /// current position if simulation is off.
    func setJoystick(east: Double, north: Double) {
        let magnitude = hypot(east, north)
        let scale = magnitude > 1 ? 1 / magnitude : 1
        joystick = (east * scale, north * scale)

        if magnitude == 0 {
            joystickTask?.cancel()
            joystickTask = nil
            if !isFollowingRoute { settle() }
            return
        }
        guard joystickTask == nil else { return }

        stopRoute()
        if !isSimulating {
            guard let start = currentLocation?.coordinate else {
                lastError = "Pick a starting location first."
                return
            }
            simulate(start, name: simulatedName)
        }

        joystickTask = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard let self, !Task.isCancelled else { return }
                let now = ContinuousClock.now
                let seconds = (now - last) / .seconds(1)
                last = now
                self.stepJoystick(seconds: seconds)
            }
        }
    }

    private func stepJoystick(seconds: Double) {
        let magnitude = hypot(joystick.east, joystick.north)
        guard magnitude > 0, let here = simulatedCoordinate else { return }
        let distance = speed.rawValue * magnitude * seconds
        simulatedCoordinate = Self.offset(
            here,
            northMeters: distance * joystick.north / magnitude,
            eastMeters: distance * joystick.east / magnitude
        )
        course = Self.normalizedDegrees(atan2(joystick.east, joystick.north) * 180 / .pi)
        movingSpeed = speed.rawValue * magnitude
    }

    // MARK: - Routes

    /// Travel along `points` at the current `speed`, starting at the first one.
    /// With `loop`, returns to the start and repeats until stopped.
    func followRoute(_ points: [CLLocationCoordinate2D], loop: Bool = false) {
        let points = points.filter(CLLocationCoordinate2DIsValid)
        guard let first = points.first else { return }
        setJoystick(east: 0, north: 0)
        simulate(first, name: points.count > 1 ? "Following route" : simulatedName)
        guard points.count > 1 else { return }

        route = points
        isFollowingRoute = true
        routeTask = Task { [weak self] in
            var target = 1
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard let self, !Task.isCancelled else { return }
                let now = ContinuousClock.now
                let seconds = (now - last) / .seconds(1)
                last = now

                var remaining = self.speed.rawValue * seconds
                // Bounded so a route of identical points can't spin forever.
                for _ in 0...points.count where remaining > 0 {
                    guard let here = self.simulatedCoordinate else { return }
                    let goal = points[target]
                    let gap = Self.distance(here, goal)
                    if gap > remaining {
                        let fraction = remaining / gap
                        self.simulatedCoordinate = CLLocationCoordinate2D(
                            latitude: here.latitude + (goal.latitude - here.latitude) * fraction,
                            longitude: here.longitude + (goal.longitude - here.longitude) * fraction
                        )
                        self.course = Self.bearing(from: here, to: goal)
                        remaining = 0
                    } else {
                        self.simulatedCoordinate = goal
                        remaining -= gap
                        target += 1
                        if target == points.count {
                            guard loop else {
                                self.finishRoute()
                                return
                            }
                            target = 0
                        }
                    }
                }
                self.movingSpeed = self.speed.rawValue
            }
        }
    }

    /// Stop following the route and stay where we are.
    func stopRoute() {
        guard routeTask != nil || isFollowingRoute else { return }
        routeTask?.cancel()
        routeTask = nil
        isFollowingRoute = false
        route = []
        settle()
    }

    private func finishRoute() {
        routeTask = nil
        isFollowingRoute = false
        route = []
        simulatedName = "Route finished"
        settle()
    }

    /// Came to a stop: clear motion and save the position.
    private func settle() {
        movingSpeed = 0
        course = -1
        persist()
    }

    // MARK: - Geometry

    static func offset(_ coordinate: CLLocationCoordinate2D, northMeters: Double, eastMeters: Double) -> CLLocationCoordinate2D {
        let metersPerDegree = 111_320.0
        let latitude = min(max(coordinate.latitude + northMeters / metersPerDegree, -89.9), 89.9)
        let cosine = max(cos(latitude * .pi / 180), 0.01)
        var longitude = coordinate.longitude + eastMeters / (metersPerDegree * cosine)
        longitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return normalizedDegrees(atan2(y, x) * 180 / .pi)
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
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
