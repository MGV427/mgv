#!/usr/bin/env bash
# Set the iOS Simulator's location to anywhere, for every app running in it.
#
#   ./simulate-location.sh 48.8584 2.2945        # latitude longitude
#   ./simulate-location.sh "48.8584, 2.2945"
#   ./simulate-location.sh "Colosseum, Rome"     # any place name or address
#   ./simulate-location.sh clear                 # back to no simulated location
#
# Needs Xcode 14+ and a booted Simulator.
set -euo pipefail

if [ $# -eq 0 ]; then
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

if [ "$1" = "clear" ]; then
  xcrun simctl location booted clear
  echo "Simulated location cleared."
  exit 0
fi

input="$*"
number='-?[0-9]+(\.[0-9]+)?'

if [[ "$input" =~ ^[[:space:]]*($number)[[:space:],\;]+($number)[[:space:]]*$ ]]; then
  lat="${BASH_REMATCH[1]}"
  lon="${BASH_REMATCH[3]}"
  label="$lat, $lon"
else
  # Look the place up with OpenStreetMap's free geocoder.
  json=$(curl -fsS -G "https://nominatim.openstreetmap.org/search" \
    --data-urlencode "q=$input" -d format=json -d limit=1 \
    -H "User-Agent: xcode-location-simulator/1.0")
  lat=$(printf '%s' "$json" | plutil -extract 0.lat raw -o - - 2>/dev/null || true)
  lon=$(printf '%s' "$json" | plutil -extract 0.lon raw -o - - 2>/dev/null || true)
  label=$(printf '%s' "$json" | plutil -extract 0.display_name raw -o - - 2>/dev/null || echo "$input")
  if [ -z "$lat" ] || [ -z "$lon" ]; then
    echo "Couldn't find \"$input\"." >&2
    exit 1
  fi
fi

xcrun simctl location booted set "$lat,$lon"
echo "Simulator is now at $label ($lat, $lon)"
