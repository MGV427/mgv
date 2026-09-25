# Simulate any location in your Xcode project

Drop-in files that let your iOS app (SwiftUI, iOS 17+) pretend it's anywhere on Earth.

## 1. In-app simulator (works in the Simulator **and** on a real iPhone)

1. Drag `LocationService.swift`, `LocationPickerView.swift` and `ContentView.swift`
   into your Xcode project (tick **Copy items if needed** and your app target).
   `ContentView.swift` replaces the template one, so delete the old one first,
   or keep yours and just add a button that opens `LocationPickerView()`.
2. Add the location permission text: select the target → **Info** tab → **+** →
   `Privacy - Location When In Use Usage Description` → e.g. *"Shows where you are."*
3. Run. Tap **Simulate Location**, then search for a place, type `lat, lon`,
   tap the map, or pick a preset city → **Simulate Here**. **Use Real** switches back.

Everywhere in your app, read the location from:

```swift
LocationService.shared.currentLocation   // CLLocation? — simulated when simulating, real otherwise
```

instead of using `CLLocationManager` directly, so the simulated spot is used everywhere.
The chosen spot is saved and survives relaunches.

## 2. Simulator-wide (any app, no code)

```bash
./simulate-location.sh 40.7580 -73.9855
./simulate-location.sh "Colosseum, Rome"
./simulate-location.sh clear
```

Uses `xcrun simctl location` (Xcode 14+). Place names are looked up with OpenStreetMap.
You can also use **Features → Location → Custom Location…** in the Simulator menu.

## 3. Xcode GPX file (Simulator or a device connected to Xcode)

Add `CustomLocation.gpx` to the project, edit its `lat`/`lon`, then while running use
**Debug → Simulate Location → CustomLocation**, or make it the default in
**Product → Scheme → Edit Scheme → Run → Options → Default Location**.
