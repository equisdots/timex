#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# timex — time & weather engine (equisdots)
#
# One provider, chosen explicitly: NO fallbacks. Providers live in
# api/providers/ (open-meteo · wttr · openweather) and print a normalized
# weather JSON document on stdout; this script owns caching, the CLI modes the
# shell consumes and the key storage.
#
# Usage:
#   timex.sh                       # refresh the cache now
#   timex.sh --getdata             # same as above (explicit)
#   timex.sh --invalidate          # drop the cache (provider/city changed)
#   timex.sh --json                # throttled refresh + cache JSON
#   timex.sh --current-icon|--current-temp|--current-hex
#   timex.sh --icon|--temp|--hex   # forecast[0] variants
#   timex.sh providers list        # name|label|needs_key|hint
#   timex.sh geocode <query>       # label|country|lat|lon  (top 5)
#   timex.sh test                  # ok|<desc> | fail|<error>
#   timex.sh snapshot              # icon|temp|max|min|desc|updated_epoch
#   timex.sh keys set OPENWEATHER_KEY <value>
#   timex.sh keys remove OPENWEATHER_KEY
#   timex.sh keys list             # NAME|label|where|0-1
#   timex.sh status                # provider|city|unit|configured|key_set|last_update|last_error
#
# Config: settings.json -> "timex": { provider, city, unit }
# Keys:   <state>/keys.conf (chmod 600) — only for keyed providers
# Cache:  ~/.cache/quickshell/timex/weather.json (contract kept from weather)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
API="$ROOT/api"

export LC_ALL=C

SETTINGS="${TIMEX_SETTINGS:-$HOME/.config/hypr/settings.json}"
CACHE_DIR="${QS_CACHE_TIMEX:-${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/timex}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/timex"
JSON="$CACHE_DIR/weather.json"
KEYS_FILE="$STATE_DIR/keys.conf"
CACHE_TTL=900

CATALOG=(
    "open-meteo|Open-Meteo|0|free · city name or lat,lon"
    "wttr|wttr.in|0|free · city name"
    "openweather|OpenWeatherMap|1|free tier · city + API key"
)

mkdir -p "$CACHE_DIR" "$STATE_DIR"

cfg() { jq -r ".timex.$1 // empty" "$SETTINGS" 2>/dev/null; }

key_value() {
    local k="$1" v=""
    [ -f "$KEYS_FILE" ] && v="$(grep "^${k}=" "$KEYS_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)"
    [ -n "$v" ] || v="${!k:-}"
    printf '%s' "$v"
}

needs_key() {
    local entry
    for entry in "${CATALOG[@]}"; do
        [ "${entry%%|*}" = "$1" ] || continue
        printf '%s' "$(printf '%s' "$entry" | cut -d'|' -f3)"
        return
    done
    printf '?'
}

PROVIDER="$(cfg provider)"
CITY="$(cfg city)"
UNIT="$(cfg unit)"
UNIT="${UNIT:-metric}"
case "$UNIT" in
    imperial) UNIT_SYM="°F" ;;
    standard) UNIT_SYM="K" ;;
    *) UNIT_SYM="°C" ;;
esac

# ── cache writers ──────────────────────────────────────────────────────────
write_dummy() {
    local desc="$1"
    jq -n --arg desc "$desc" '
      [range(0; 5) as $i
       | (now + $i * 86400) as $t
       | {id: ($i | tostring),
          day: ($t | strftime("%a")), day_full: ($t | strftime("%A")), date: ($t | strftime("%d %b")),
          max: "0.0", min: "0.0", feels_like: "0.0", wind: "0", humidity: "0", pop: "0",
          icon: "", hex: "#cdd6f4", desc: $desc,
          hourly: [{time: "00:00", temp: "0.0", icon: "", hex: "#cdd6f4"}]}]
      | {current_temp: "0.0", current_icon: "", current_hex: "#cdd6f4", forecast: .}
    ' > "$JSON.tmp" && mv "$JSON.tmp" "$JSON"
}

fetch_now() {
    local prov_file err tmp
    if [ -z "$PROVIDER" ]; then write_dummy "Select a provider"; return 1; fi
    prov_file="$API/providers/$PROVIDER.sh"
    if [ ! -f "$prov_file" ]; then write_dummy "Unknown provider: $PROVIDER"; return 1; fi
    if [ "$(needs_key "$PROVIDER")" = "1" ] && [ -z "$(key_value OPENWEATHER_KEY)" ]; then
        write_dummy "Set the API key"; return 1
    fi
    if [ -z "$CITY" ]; then write_dummy "Set a city"; return 1; fi

    tmp="$CACHE_DIR/weather.json.tmp.$$"
    if TIMEX_CITY="$CITY" TIMEX_UNIT="$UNIT" TIMEX_STATE_DIR="$STATE_DIR" \
       TIMEX_KEY="$(key_value OPENWEATHER_KEY)" bash "$prov_file" > "$tmp" 2>"$CACHE_DIR/last_error.log"; then
        if jq -e '.forecast and (.forecast | length > 0)' "$tmp" >/dev/null 2>&1; then
            mv "$tmp" "$JSON"
            : > "$CACHE_DIR/last_error.log"
            return 0
        fi
        err="Provider returned bad data"
    else
        err="$(tail -n1 "$CACHE_DIR/last_error.log" 2>/dev/null)"
        err="${err:-Provider failed}"
    fi
    rm -f "$tmp"
    # Keep the last good cache; only write the error state when there is none.
    [ -f "$JSON" ] || write_dummy "$err"
    return 1
}

ensure_cache() {
    [ -f "$JSON" ] || { fetch_now; return; }
    local diff
    diff=$(( $(date +%s) - $(stat -c %Y "$JSON") ))
    if [ "$diff" -gt "$CACHE_TTL" ]; then
        touch "$JSON" # avoid a refresh stampede while the background fetch runs
        ( fetch_now >/dev/null 2>&1 & )
    fi
}

# ── modes ──────────────────────────────────────────────────────────────────
case "${1:-}" in
    --getdata|"")
        fetch_now
        ;;
    --invalidate)
        rm -f "$JSON"
        ;;
    --json)
        ensure_cache
        cat "$JSON" 2>/dev/null
        ;;
    --current-icon)
        ensure_cache
        jq -r '.current_icon // empty' "$JSON" 2>/dev/null
        ;;
    --current-temp)
        ensure_cache
        t="$(jq -r '.current_temp // empty' "$JSON" 2>/dev/null)"
        [ -n "$t" ] && printf '%s%s\n' "$t" "$UNIT_SYM"
        ;;
    --current-hex)
        ensure_cache
        jq -r '.current_hex // empty' "$JSON" 2>/dev/null
        ;;
    --icon)
        ensure_cache
        jq -r '.forecast[0].icon // empty' "$JSON" 2>/dev/null
        ;;
    --temp)
        ensure_cache
        t="$(jq -r '.forecast[0].max // empty' "$JSON" 2>/dev/null)"
        [ -n "$t" ] && printf '%s%s\n' "$t" "$UNIT_SYM"
        ;;
    --hex)
        ensure_cache
        jq -r '.forecast[0].hex // empty' "$JSON" 2>/dev/null
        ;;
    providers)
        [ "${2:-list}" = "list" ] || { echo "usage: timex.sh providers list" >&2; exit 2; }
        printf '%s\n' "${CATALOG[@]}"
        ;;
    geocode)
        q="${2:-}"
        [ -n "$q" ] || { echo "usage: timex.sh geocode <query>" >&2; exit 2; }
        curl -fsS -m 10 --get 'https://geocoding-api.open-meteo.com/v1/search' \
            --data-urlencode "name=$q" --data 'count=5&language=en&format=json' 2>/dev/null \
        | jq -r '.results[]? | [(.name + (if .admin1 then ", " + .admin1 else "" end) + (if .country then ", " + .country else "" end)), (.country // ""), (.latitude | tostring), (.longitude | tostring)] | join("|")'
        ;;
    test)
        if fetch_now; then
            printf 'ok|%s\n' "$(jq -r '.forecast[0].desc // ""' "$JSON" 2>/dev/null)"
        else
            printf 'fail|%s\n' "$(tail -n1 "$CACHE_DIR/last_error.log" 2>/dev/null || echo 'provider failed')"
        fi
        ;;
    snapshot)
        ensure_cache
        printf '%s|%s\n' \
            "$(jq -r '[(.current_icon // ""), (.current_temp // ""), (.forecast[0].max // ""), (.forecast[0].min // ""), (.forecast[0].desc // "")] | join("|")' "$JSON" 2>/dev/null)" \
            "$(stat -c %Y "$JSON" 2>/dev/null || echo 0)"
        ;;
    keys)
        action="${2:-}"; name="${3:-}"; value="${4:-}"
        case "$action" in
            set)
                [ "$name" = "OPENWEATHER_KEY" ] || { echo "timex: unknown key: $name" >&2; exit 2; }
                [ -n "$value" ] || { echo "usage: timex.sh keys set OPENWEATHER_KEY <value>" >&2; exit 2; }
                touch "$KEYS_FILE" && chmod 600 "$KEYS_FILE"
                if grep -q '^OPENWEATHER_KEY=' "$KEYS_FILE"; then
                    sed -i "s|^OPENWEATHER_KEY=.*|OPENWEATHER_KEY=${value}|" "$KEYS_FILE"
                else
                    printf 'OPENWEATHER_KEY=%s\n' "$value" >> "$KEYS_FILE"
                fi
                echo "saved OPENWEATHER_KEY in $KEYS_FILE"
                ;;
            remove)
                [ "$name" = "OPENWEATHER_KEY" ] || { echo "timex: unknown key: $name" >&2; exit 2; }
                if [ -f "$KEYS_FILE" ]; then
                    grep -v '^OPENWEATHER_KEY=' "$KEYS_FILE" > "$KEYS_FILE.tmp" 2>/dev/null || true
                    mv "$KEYS_FILE.tmp" "$KEYS_FILE"
                fi
                echo "removed OPENWEATHER_KEY"
                ;;
            list)
                if [ -n "$(key_value OPENWEATHER_KEY)" ]; then
                    printf 'OPENWEATHER_KEY|OpenWeatherMap|openweathermap.org/api|1\n'
                else
                    printf 'OPENWEATHER_KEY|OpenWeatherMap|openweathermap.org/api|0\n'
                fi
                ;;
            *)
                printf 'keys file: %s\n' "$KEYS_FILE"
                ;;
        esac
        ;;
    status)
        configured=0
        [ -n "$PROVIDER" ] && [ -n "$CITY" ] && configured=1
        key_set=0
        [ -n "$(key_value OPENWEATHER_KEY)" ] && key_set=1
        last_update=0
        [ -f "$JSON" ] && last_update="$(stat -c %Y "$JSON")"
        last_error=""
        [ -s "$CACHE_DIR/last_error.log" ] && last_error="$(tail -n1 "$CACHE_DIR/last_error.log" | tr '|' '/')"
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$PROVIDER" "$CITY" "$UNIT" "$configured" "$key_set" "$last_update" "$last_error"
        ;;
    *)
        cat >&2 <<'EOF'
usage: timex.sh [--json|--getdata|--invalidate|--current-icon|--current-temp|
                --current-hex|--icon|--temp|--hex|providers list|geocode <q>|
                test|snapshot|keys set|keys remove|keys list|status]
EOF
        exit 2
        ;;
esac
