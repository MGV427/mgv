# Location Sim: an iPhone app that can pretend to be anywhere

A ready-made Xcode project. Open it, press ▶, and you get an app that can pretend it's anywhere
on Earth and move around there live.

## How to run it (Mac + Xcode)

1. Install **Xcode** from the Mac App Store (free).
2. Download this folder: on GitHub click **Code → Download ZIP**, then double-click the ZIP.
3. Open the `xcode-location-simulator` folder and double-click **`LocationSimulator.xcodeproj`**.
4. At the top of Xcode, pick an iPhone Simulator (for example "iPhone 16") and press **▶**.

That's it. The app opens in the Simulator.

**On your own iPhone:** plug it in and choose it at the top instead of a Simulator.
Then click **LocationSimulator** in the left list → **Signing & Capabilities** → choose your
Apple ID under **Team**. The first time, your iPhone may ask you to trust the developer in
**Settings → General → VPN & Device Management**.

## What you can do in the app

- **Tap the map** to teleport there.
- **Drag the purple joystick** to walk around. Pick a speed: walk, run, cycle, drive or fly.
- **🔍 button**: search any place, type coordinates like `41.8902, 12.4922`, or pick a city.
- **Route** (inside 🔍): tap to drop stops, then **Follow Route** and watch it travel.
- **Use Real** goes back to your actual GPS.

The simulated location is inside this app only. It doesn't change your iPhone's GPS for other apps.

## Extra: change the Simulator's location for *every* app

With the Simulator open, run this in Terminal from this folder:

```bash
./simulate-location.sh                     # interactive: walk with WASD / arrow keys
./simulate-location.sh "Colosseum, Rome"   # jump to a place
./simulate-location.sh 40.7580 -73.9855    # jump to coordinates
./simulate-location.sh clear
```

Or use `CustomLocation.gpx` with Xcode's **Debug → Simulate Location** menu. Drag it into
the project first and edit the coordinates inside.

## What's inside

| File | What it does |
|------|--------------|
| `LocationSimulator.xcodeproj` | The Xcode project; double-click to open |
| `LocationSimulator/LocationSimulatorApp.swift` | App start |
| `LocationSimulator/ContentView.swift` | Main map screen |
| `LocationSimulator/SimulationControls.swift` | Joystick and speed picker |
| `LocationSimulator/LocationPickerView.swift` | Search, coordinates, presets, route builder |
| `LocationSimulator/LocationService.swift` | Real vs. simulated location, movement and routes |
| `LocationSimulator/Assets.xcassets` | App icon and colours |
