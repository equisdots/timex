#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# timex · api/provider — wttr.in (no API key).
#
# Input (env):  TIMEX_CITY, TIMEX_UNIT (metric|imperial)
# Output:       normalized weather JSON on stdout (see core/timex.sh)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../icons.sh"

export LC_ALL=C

CITY="${TIMEX_CITY:-}"
UNIT="${TIMEX_UNIT:-metric}"

[ -n "$CITY" ] || { echo "timex(wttr): no city configured" >&2; exit 3; }

if [ "$UNIT" = "imperial" ]; then
    TEMP_KEY="tempF"; FEELS_KEY="FeelsLikeF"; WIND_KEY="windspeedMiles"; CUR_TEMP_KEY="temp_F"
else
    TEMP_KEY="tempC"; FEELS_KEY="FeelsLikeC"; WIND_KEY="windspeedKmph"; CUR_TEMP_KEY="temp_C"
fi

raw="$(curl -fsS -m 15 "https://wttr.in/$(jq -rn --arg c "$CITY" '$c|@uri')?format=j1")" \
    || { echo "timex(wttr): request failed" >&2; exit 4; }

printf '%s' "$raw" | jq -e '.weather | length > 0' >/dev/null 2>&1 \
    || { echo "timex(wttr): city not found or bad response: $CITY" >&2; exit 4; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/items.jsonl"

idx=0
while IFS= read -r d; do
    [ -n "$d" ] || continue
    day="$(printf '%s' "$raw" | jq -c ".weather[$idx]")"

    max="$(printf '%s' "$day" | jq -r ".maxtemp${TEMP_KEY#temp}")"
    min="$(printf '%s' "$day" | jq -r ".mintemp${TEMP_KEY#temp}")"
    feels="$(printf '%s' "$day" | jq -r "[.hourly[].${FEELS_KEY}] | max")"
    wind="$(printf '%s' "$day" | jq -r "[.hourly[].${WIND_KEY}] | max | round")"
    hum="$(printf '%s' "$day" | jq -r '[.hourly[].humidity] | add / length | round')"
    pop="$(printf '%s' "$day" | jq -r '[.hourly[].chanceofrain] | max')"

    mid_desc="$(printf '%s' "$day" | jq -r '.hourly[4].weatherDesc[0].value // .hourly[0].weatherDesc[0].value')"
    icon="$(timex_text_icon "$mid_desc" | cut -d'|' -f1)"
    desc="$(timex_text_icon "$mid_desc" | cut -d'|' -f2)"
    hex="$(timex_text_hex "$mid_desc")"

    : > "$TMP/hourly.jsonl"
    while IFS= read -r h; do
        [ -n "$h" ] || continue
        hraw="$(printf '%s' "$h" | jq -r '.time')"
        htime="$(printf '%02d:%02d' $((10#${hraw} / 100)) $((10#${hraw} % 100)))"
        htemp="$(printf '%s' "$h" | jq -r ".${TEMP_KEY}")"
        hdesc="$(printf '%s' "$h" | jq -r '.weatherDesc[0].value')"
        jq -cn --arg time "$htime" --arg temp "$htemp" \
            --arg icon "$(timex_text_icon "$hdesc" | cut -d'|' -f1)" --arg hex "$(timex_text_hex "$hdesc")" \
            '{time:$time, temp:$temp, icon:$icon, hex:$hex}' >> "$TMP/hourly.jsonl"
    done < <(printf '%s' "$day" | jq -c '.hourly[]')
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
done < <(printf '%s' "$raw" | jq -r '.weather[].date')

cur_desc="$(printf '%s' "$raw" | jq -r '.current_condition[0].weatherDesc[0].value')"
jq -n \
    --arg t "$(printf '%s' "$raw" | jq -r ".current_condition[0].${CUR_TEMP_KEY}")" \
    --arg i "$(timex_text_icon "$cur_desc" | cut -d'|' -f1)" \
    --arg h "$(timex_text_hex "$cur_desc")" \
    --slurpfile f "$TMP/items.jsonl" \
    '{current_temp:$t, current_icon:$i, current_hex:$h, forecast:$f}'
