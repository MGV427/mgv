# Simulate any location in your Xcode project

Drop-in files that let your iOS app (SwiftUI, iOS 17+) pretend it's anywhere on Earth,
and move around there live.

## 1. In-app simulator (works in the Simulator **and** on a real iPhone)

1. Drag `LocationService.swift`, `LocationPickerView.swift`, `SimulationControls.swift`
   and `ContentView.swift` into your Xcode project (tick **Copy items if needed** and
   your app target). `ContentView.swift` replaces the template one, so delete the old
   one first, or keep yours and add `SimulationControls()` and a button that opens
   `LocationPickerView()`.
2. Add the location permission text: select the target → **Info** tab → **+** →
   `Privacy - Location When In Use Usage Description` → e.g. *"Shows where you are."*
3. Run it:
   - **Tap the map** to teleport there.
   - **Drag the joystick** to move around. Pick a speed: walk, run, cycle, drive or fly.
     An arrow shows which way you're heading.
   - **🔍 button** → search for any place, type `lat, lon`, or pick a preset city.
   - **Route mode** (in the 🔍 screen): tap to drop numbered stops, choose a speed and
     *Loop back to start*, then **Follow Route**. The location travels along it live.
   - **Use Real** switches back to your actual GPS.

Everywhere in your app, read the location from:

```swift
LocationService.shared.currentLocation   // CLLocation?, including course and speed while moving
```

instead of using `CLLocationManager` directly, so the simulated spot is used everywhere.
You can also drive it from code:

```swift
let location = LocationService.shared
location.simulate(latitude: 41.8902, longitude: 12.4922, name: "Colosseum")
location.speed = .cycle
location.setJoystick(east: 0, north: 1)        // head north; (0, 0) stops
location.followRoute([a, b, c], loop: true)    // travel along waypoints
location.stopSimulating()
```

The chosen spot is saved and survives relaunches.

## 2. Simulator-wide (any app, no code)

```bash
./simulate-location.sh                     # interactive: walk with WASD / arrow keys
./simulate-location.sh 40.7580 -73.9855
./simulate-location.sh "Colosseum, Rome"
./simulate-location.sh clear
```

In interactive mode: **W A S D** or arrow keys move you, **+ / −** change the step size,
**g** goes to a place, **c** clears and **q** quits.
This uses `xcrun simctl location` (Xcode 14+). Place names are looked up with OpenStreetMap.

## 3. Xcode GPX file (Simulator or a device connected to Xcode)

Add `CustomLocation.gpx` to the project, edit its `lat`/`lon`, then while running use
**Debug → Simulate Location → CustomLocation**, or make it the default in
**Product → Scheme → Edit Scheme → Run → Options → Default Location**.
