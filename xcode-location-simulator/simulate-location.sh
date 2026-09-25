#!/usr/bin/env bash
# Set the iOS Simulator's location to anywhere, for every app running in it.
#
#   ./simulate-location.sh                       # interactive: walk around with WASD / arrow keys
#   ./simulate-location.sh 48.8584 2.2945        # latitude longitude
#   ./simulate-location.sh "48.8584, 2.2945"
#   ./simulate-location.sh "Colosseum, Rome"     # any place name or address
#   ./simulate-location.sh clear                 # back to no simulated location
#
# Needs Xcode 14+ and a booted Simulator.
set -euo pipefail

LAST_FILE="${TMPDIR:-/tmp}/simulate-location-last"

# Resolve "lat lon", "lat, lon" or a place name into $lat, $lon and $label.
resolve() {
  local input="$1"
  local number='-?[0-9]+(\.[0-9]+)?'
  if [[ "$input" =~ ^[[:space:]]*($number)[[:space:],\;]+($number)[[:space:]]*$ ]]; then
    lat="${BASH_REMATCH[1]}"
    lon="${BASH_REMATCH[3]}"
    label="$lat, $lon"
    return 0
  fi
  # Look the place up with OpenStreetMap's free geocoder.
  local json
  json=$(curl -fsS -G "https://nominatim.openstreetmap.org/search" \
    --data-urlencode "q=$input" -d format=json -d limit=1 \
    -H "User-Agent: xcode-location-simulator/1.0") || return 1
  lat=$(printf '%s' "$json" | plutil -extract 0.lat raw -o - - 2>/dev/null || true)
  lon=$(printf '%s' "$json" | plutil -extract 0.lon raw -o - - 2>/dev/null || true)
  label=$(printf '%s' "$json" | plutil -extract 0.display_name raw -o - - 2>/dev/null || echo "$input")
  [ -n "$lat" ] && [ -n "$lon" ]
}

set_location() {
  xcrun simctl location booted set "$lat,$lon"
  echo "$lat $lon" > "$LAST_FILE"
}

# Move $lat/$lon by the given meters north and east.
offset() {
  read -r lat lon < <(awk -v lat="$lat" -v lon="$lon" -v n="$1" -v e="$2" 'BEGIN {
    pi = atan2(0, -1)
    lat2 = lat + n / 111320
    if (lat2 > 89.9) lat2 = 89.9
    if (lat2 < -89.9) lat2 = -89.9
    lon2 = lon + e / (111320 * cos(lat2 * pi / 180))
    while (lon2 > 180) lon2 -= 360
    while (lon2 < -180) lon2 += 360
    printf "%.6f %.6f\n", lat2, lon2
  }')
}

interactive() {
  local step=50 key="" rest="" query=""
  if [ -f "$LAST_FILE" ]; then
    read -r lat lon < "$LAST_FILE"
  else
    lat=""
  fi
  while [ -z "${lat:-}" ]; do
    read -rp "Start where? (place or lat, lon): " query
    resolve "$query" || { echo "Couldn't find \"$query\"."; lat=""; }
  done
  set_location

  cat <<EOF

  Interactive location control
  ----------------------------
  W A S D / arrow keys   move north / west / south / east
  + / -                  bigger / smaller steps
  g                      go to a place or coordinates
  c                      clear simulated location
  q                      quit

EOF

  while true; do
    printf '\r\033[K  %s, %s   step %sm   ' "$lat" "$lon" "$step"
    IFS= read -rsn1 key || break
    if [ "$key" = $'\033' ]; then
      rest=""
      read -rsn2 -t 1 rest || true
      case "$rest" in
        '[A') key=w ;; '[B') key=s ;; '[C') key=d ;; '[D') key=a ;;
      esac
    fi
    case "$key" in
      w|W) offset "$step" 0; set_location ;;
      s|S) offset "-$step" 0; set_location ;;
      d|D) offset 0 "$step"; set_location ;;
      a|A) offset 0 "-$step"; set_location ;;
      +|=) if [ "$step" -lt 100000 ]; then step=$((step * 2)); fi ;;
      -|_) if [ "$step" -gt 1 ]; then step=$((step / 2)); fi ;;
      g|G)
        printf '\r\033[K'
        read -rp "  Go to: " query
        if resolve "$query"; then set_location; echo "  → $label"; else echo "  Couldn't find \"$query\"."; fi
        ;;
      c|C) xcrun simctl location booted clear; printf '\r\033[K  Cleared.\n' ;;
      q|Q) printf '\n'; break ;;
    esac
  done
}

if [ $# -eq 0 ]; then
  interactive
  exit 0
fi

case "$1" in
  -h|--help)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  clear)
    xcrun simctl location booted clear
    echo "Simulated location cleared."
    exit 0
    ;;
esac

if ! resolve "$*"; then
  echo "Couldn't find \"$*\"." >&2
  exit 1
fi
set_location
echo "Simulator is now at $label ($lat, $lon)"
