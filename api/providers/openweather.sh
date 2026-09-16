#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# timex · api/provider — OpenWeatherMap (API key required).
#
# Input (env):  TIMEX_CITY, TIMEX_UNIT (metric|imperial), TIMEX_KEY (API key)
# Output:       normalized weather JSON on stdout (see core/timex.sh)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../icons.sh"

export LC_ALL=C

CITY="${TIMEX_CITY:-}"
UNIT="${TIMEX_UNIT:-metric}"
KEY="${TIMEX_KEY:-}"

[ -n "$CITY" ] || { echo "timex(openweather): no city configured" >&2; exit 3; }
[ -n "$KEY" ] || { echo "timex(openweather): no API key configured" >&2; exit 3; }

if [ "$UNIT" = "imperial" ]; then UNITS="imperial"; WIND_UNIT="mph"; else UNITS="metric"; WIND_UNIT="kmh"; fi

# ── 1) Geocoding (city name -> lat/lon) ────────────────────────────────────
geo="$(curl -fsS -m 10 --get 'http://api.openweathermap.org/geo/1.0/direct' \
    --data-urlencode "q=$CITY" --data 'limit=1' --data-urlencode "appid=$KEY")" \
    || { echo "timex(openweather): geocoding request failed" >&2; exit 4; }
LAT="$(printf '%s' "$geo" | jq -r '.[0].lat // empty')"
LON="$(printf '%s' "$geo" | jq -r '.[0].lon // empty')"
[ -n "$LAT" ] || { echo "timex(openweather): city not found: $CITY" >&2; exit 4; }

# ── 2) Forecast + current ──────────────────────────────────────────────────
raw="$(curl -fsS -m 10 --get 'http://api.openweathermap.org/data/2.5/forecast' \
    --data-urlencode "lat=$LAT" --data-urlencode "lon=$LON" \
    --data-urlencode "appid=$KEY" --data-urlencode "units=$UNITS")" \
    || { echo "timex(openweather): forecast request failed" >&2; exit 4; }
cur="$(curl -fsS -m 10 --get 'http://api.openweathermap.org/data/2.5/weather' \
    --data-urlencode "lat=$LAT" --data-urlencode "lon=$LON" \
    --data-urlencode "appid=$KEY" --data-urlencode "units=$UNITS")" \
    || { echo "timex(openweather): current request failed" >&2; exit 4; }

printf '%s' "$raw" | jq -e '.cod == "200"' >/dev/null 2>&1 \
    || { echo "timex(openweather): API error" >&2; exit 4; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/items.jsonl"

idx=0
while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ "$idx" -lt 5 ] || break
    day="$(printf '%s' "$raw" | jq -c --arg d "$d" '[.list[] | select(.dt_txt | startswith($d))]')"

    max="$(printf '%s' "$day" | jq -r '[.[].main.temp_max] | max')"
    min="$(printf '%s' "$day" | jq -r '[.[].main.temp_min] | min')"
    feels="$(printf '%s' "$day" | jq -r '[.[].main.feels_like] | max')"
    wind="$(printf '%s' "$day" | jq -r '[.[].wind.speed] | max | round')"
    hum="$(printf '%s' "$day" | jq -r '[.[].main.humidity] | add / length | round')"
    pop="$(printf '%s' "$day" | jq -r '[.[].pop] | max * 100 | round')"
    code="$(printf '%s' "$day" | jq -r '[.[] | select(.dt_txt | contains("12:00"))][0].weather[0].icon
        // .[length / 2 | floor].weather[0].icon')"
    icon="$(timex_owm_icon "$code" | cut -d'|' -f1)"
    desc="$(timex_owm_icon "$code" | cut -d'|' -f2)"
    hex="$(timex_owm_hex "$code")"

    : > "$TMP/hourly.jsonl"
    while IFS= read -r h; do
        [ -n "$h" ] || continue
        htime="$(printf '%s' "$h" | jq -r '.dt_txt | .[11:16]')"
        htemp="$(printf '%s' "$h" | jq -r '.main.temp | tostring')"
        hcode="$(printf '%s' "$h" | jq -r '.weather[0].icon')"
        jq -cn --arg time "$htime" --arg temp "$htemp" \
            --arg icon "$(timex_owm_icon "$hcode" | cut -d'|' -f1)" --arg hex "$(timex_owm_hex "$hcode")" \
            '{time:$time, temp:$temp, icon:$icon, hex:$hex}' >> "$TMP/hourly.jsonl"
    done < <(printf '%s' "$day" | jq -c '.[]')
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
done < <(printf '%s' "$raw" | jq -r '[.list[].dt_txt | .[0:10]] | unique[]')

cur_code="$(printf '%s' "$cur" | jq -r '.weather[0].icon')"
jq -n \
    --arg t "$(printf '%.1f' "$(printf '%s' "$cur" | jq -r '.main.temp')")" \
    --arg i "$(timex_owm_icon "$cur_code" | cut -d'|' -f1)" \
    --arg h "$(timex_owm_hex "$cur_code")" \
    --slurpfile f "$TMP/items.jsonl" \
    '{current_temp:$t, current_icon:$i, current_hex:$h, forecast:$f}'
