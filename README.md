# OffTheCouch 🛋️➡️🚶

A website that scans the area around you and surfaces **real nearby places and activities that get you off the couch** — volunteering, pickup sports, parks, gyms, open-mic nights, markets, libraries, and more. Each result is matched to your **age and interests**, with a short "what to expect" so you know why it's worth leaving the house.

## How it works

1. **Scan** — asks your browser for your location, then queries the free
   [OpenStreetMap **Overpass API**](https://wiki.openstreetmap.org/wiki/Overpass_API)
   for real places within a radius you choose (a slider from *walkable* to
   *worth the drive*). No API key required.
2. **Match** — a built-in recommendation engine scores every place against your
   age, interests, and mood, ranks them, and keeps a varied top set.
3. **Insight** — every result gets a "what to expect" nudge written to get you
   to actually go.
4. **(Optional) Claude** — paste your own Anthropic API key and your top picks
   get richer insights written by Claude (`claude-opus-4-8`), called directly
   from the browser. Everything works fully without a key.

## Running it

It's a static site — no build step.

- **Locally:** serve the folder (geolocation needs `https://` or `localhost`):
  ```bash
  python3 -m http.server 8000
  # open http://localhost:8000
  ```
- **GitHub Pages:** enable Pages for this branch and open the published URL.

## Privacy

- Your location is used only to build the area scan and never leaves your
  browser except as coordinates sent to the OpenStreetMap Overpass API.
- If you provide an Anthropic API key, it stays in your browser and is sent
  only to Anthropic's API. Nothing is stored server-side (there is no server).

## Notes & limits

- Place data comes from OpenStreetMap contributors; coverage and opening hours
  vary by area. Always double-check details before heading out.
- Events like "open-mic night" are surfaced via the venues that host them
  (music venues, community centres, markets) rather than a live events feed.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Page structure and the profile form |
| `styles.css` | Styling (dark, responsive) |
| `app.js` | Scan, scoring/recommendation engine, insights, Claude option |
