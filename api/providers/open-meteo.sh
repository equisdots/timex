#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# timex · api/provider — Open-Meteo (no API key).
#
# Input (env):  TIMEX_CITY (city name or "lat,lon"), TIMEX_UNIT (metric|imperial),
#               TIMEX_STATE_DIR (geocoding cache)
# Output:       normalized weather JSON on stdout (see core/timex.sh)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../icons.sh"

export LC_ALL=C

CITY="${TIMEX_CITY:-}"
UNIT="${TIMEX_UNIT:-metric}"
STATE_DIR="${TIMEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/timex}"
GEO_CACHE="$STATE_DIR/geocode.json"

[ -n "$CITY" ] || { echo "timex(open-meteo): no city configured" >&2; exit 3; }
mkdir -p "$STATE_DIR"

# ── 1) Location: "lat,lon" literal, or geocoded (cached per city) ──────────
if [[ "$CITY" =~ ^-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?$ ]]; then
    LAT="${CITY%%,*}"
    LON="${CITY##*,}"
elif [ -f "$GEO_CACHE" ] && [ "$(jq -r '.query // empty' "$GEO_CACHE" 2>/dev/null)" = "$CITY" ]; then
    LAT="$(jq -r '.lat' "$GEO_CACHE")"
    LON="$(jq -r '.lon' "$GEO_CACHE")"
else
    geo="$(curl -fsS -m 10 --get 'https://geocoding-api.open-meteo.com/v1/search' \
        --data-urlencode "name=$CITY" --data 'count=1&language=en&format=json')" \
        || { echo "timex(open-meteo): geocoding request failed" >&2; exit 4; }
    LAT="$(printf '%s' "$geo" | jq -r '.results[0].latitude // empty')"
    LON="$(printf '%s' "$geo" | jq -r '.results[0].longitude // empty')"
    LABEL="$(printf '%s' "$geo" | jq -r '(.results[0].name // "") + (if .results[0].country then ", " + .results[0].country else "" end)')"
    [ -n "$LAT" ] || { echo "timex(open-meteo): city not found: $CITY" >&2; exit 4; }
    jq -n --arg q "$CITY" --arg lat "$LAT" --arg lon "$LON" --arg label "$LABEL" \
        '{query:$q, lat:$lat, lon:$lon, label:$label}' > "$GEO_CACHE"
fi

# ── 2) Forecast ────────────────────────────────────────────────────────────
if [ "$UNIT" = "imperial" ]; then
    TUNIT="fahrenheit"; WUNIT="mph"
else
    TUNIT="celsius"; WUNIT="kmh"
fi

raw="$(curl -fsS -m 10 --get 'https://api.open-meteo.com/v1/forecast' \
    --data-urlencode "latitude=$LAT" --data-urlencode "longitude=$LON" \
    --data 'current=temperature_2m,weather_code' \
    --data 'hourly=temperature_2m,weather_code,relative_humidity_2m' \
    --data 'daily=weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,wind_speed_10m_max,precipitation_probability_max' \
    --data "temperature_unit=$TUNIT" --data "wind_speed_unit=$WUNIT" \
    --data 'timezone=auto' --data 'forecast_days=5')" \
    || { echo "timex(open-meteo): forecast request failed" >&2; exit 4; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/items.jsonl"

idx=0
while IFS= read -r d; do
    [ -n "$d" ] || continue
    code="$(printf '%s' "$raw" | jq -r ".daily.weather_code[$idx]")"
    max="$(printf '%s' "$raw" | jq -r ".daily.temperature_2m_max[$idx]")"
    min="$(printf '%s' "$raw" | jq -r ".daily.temperature_2m_min[$idx]")"
    feels="$(printf '%s' "$raw" | jq -r ".daily.apparent_temperature_max[$idx]")"
    wind="$(printf '%s' "$raw" | jq -r ".daily.wind_speed_10m_max[$idx] | round")"
    pop="$(printf '%s' "$raw" | jq -r ".daily.precipitation_probability_max[$idx] // 0 | round")"
    hum="$(printf '%s' "$raw" | jq -r --arg d "$d" \
        '[.hourly.time | to_entries[] | select(.value | startswith($d)) | .key] as $i
         | [.hourly.relative_humidity_2m[$i[]]] | if length > 0 then (add / length | round) else 0 end')"
    icon="$(timex_wmo_icon "$code" | cut -d'|' -f1)"
    desc="$(timex_wmo_icon "$code" | cut -d'|' -f2)"
    hex="$(timex_wmo_hex "$code")"

    : > "$TMP/hourly.jsonl"
    while IFS= read -r h; do
        [ -n "$h" ] || continue
        htime="$(printf '%s' "$h" | jq -r '.time' | cut -c12-16)"
        htemp="$(printf '%s' "$h" | jq -r '.temp | tostring')"
        hcode="$(printf '%s' "$h" | jq -r '.code')"
        jq -cn --arg time "$htime" --arg temp "$htemp" \
            --arg icon "$(timex_wmo_icon "$hcode" | cut -d'|' -f1)" --arg hex "$(timex_wmo_hex "$hcode")" \
            '{time:$time, temp:$temp, icon:$icon, hex:$hex}' >> "$TMP/hourly.jsonl"
    done < <(printf '%s' "$raw" | jq -c --arg d "$d" \
        '[range(0; (.hourly.time | length)) as $i
          | select(.hourly.time[$i] | startswith($d))
          | {time: .hourly.time[$i], temp: .hourly.temperature_2m[$i], code: .hourly.weather_code[$i]}] | .[]')
    hourly="$(jq -s '.' "$TMP/hourly.jsonl" 2>/dev/null || echo '[]')"

    jq -cn --arg id "$idx" \
        --arg day "$(date -d "$d" +%a)" --arg day_full "$(date -d "$d" +%A)" --arg date "$(date -d "$d" '+%d %b')" \
        --arg max "$(printf '%.1f' "$max")" --arg min "$(printf '%.1f' "$min")" --arg feels "$(printf '%.1f' "$feels")" \
        --arg wind "$wind" --arg hum "$hum" --arg pop "$pop" \
        --arg icon "$icon" --arg hex "$hex" --arg desc "$desc" --argjson hourly "$hourly" \
        '{id:$id, day:$day, day_full:$day_full, date:$date, max:$max, min:$min, feels_like:$feels,
          wind:$wind, humidity:$hum, pop:$pop, icon:$icon, hex:$hex, desc:$desc, hourly:$hourly}' \
        >> "$TMP/items.jsonl"
    idx=$((idx + 1))
done < <(printf '%s' "$raw" | jq -r '.daily.time[]')

# ── 3) Normalized document ─────────────────────────────────────────────────
cur_code="$(printf '%s' "$raw" | jq -r '.current.weather_code')"
jq -n \
    --arg t "$(printf '%.1f' "$(printf '%s' "$raw" | jq -r '.current.temperature_2m')")" \
    --arg i "$(timex_wmo_icon "$cur_code" | cut -d'|' -f1)" \
    --arg h "$(timex_wmo_hex "$cur_code")" \
    --slurpfile f "$TMP/items.jsonl" \
    '{current_temp:$t, current_icon:$i, current_hex:$h, forecast:$f}'
