#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# timex · api — condition mappings shared by the providers.
#
# Pure lookups: each function prints "glyph|desc" (or a hex) for its input.
# Providers translate their own code system (OWM icon codes, WMO codes,
# wttr.in free text) through these helpers so the cache contract stays stable.
# ═══════════════════════════════════════════════════════════════════════════

# ── OpenWeather icon code (01d … 50n) ──────────────────────────────────────
timex_owm_icon() {
    case "$1" in
        "50d"|"50n") echo "󰖑|Mist" ;;
        "01d") echo "|Sunny" ;;
        "01n") echo "|Clear" ;;
        "02d"|"02n"|"03d"|"03n"|"04d"|"04n") echo "|Cloudy" ;;
        "09d"|"09n"|"10d"|"10n") echo "󰖗|Rainy" ;;
        "11d"|"11n") echo "|Storm" ;;
        "13d"|"13n") echo "|Snow" ;;
        *) echo "|Unknown" ;;
    esac
}

timex_owm_hex() {
    case "$1" in
        "50d"|"50n") echo "#84afdb" ;;
        "01d") echo "#f9e2af" ;;
        "01n") echo "#cba6f7" ;;
        "02d"|"02n"|"03d"|"03n"|"04d"|"04n") echo "#bac2de" ;;
        "09d"|"09n"|"10d"|"10n") echo "#74c7ec" ;;
        "11d"|"11n") echo "#f9e2af" ;;
        "13d"|"13n") echo "#cdd6f4" ;;
        *) echo "#cdd6f4" ;;
    esac
}

# ── WMO weather code (Open-Meteo) ──────────────────────────────────────────
timex_wmo_icon() {
    case "$1" in
        0) echo "|Clear" ;;
        1|2) echo "|Partly cloudy" ;;
        3) echo "|Overcast" ;;
        45|48) echo "󰖑|Fog" ;;
        51|53|55|56|57) echo "󰖗|Drizzle" ;;
        61|63|65|66|67) echo "󰖗|Rain" ;;
        71|73|75|77) echo "|Snow" ;;
        80|81|82) echo "󰖗|Showers" ;;
        85|86) echo "|Snow showers" ;;
        95|96|99) echo "|Thunderstorm" ;;
        *) echo "|Unknown" ;;
    esac
}

timex_wmo_hex() {
    case "$1" in
        0|1|2) echo "#f9e2af" ;;
        3) echo "#bac2de" ;;
        45|48) echo "#84afdb" ;;
        51|53|55|56|57|61|63|65|66|67|80|81|82) echo "#74c7ec" ;;
        71|73|75|77|85|86) echo "#cdd6f4" ;;
        95|96|99) echo "#f9e2af" ;;
        *) echo "#cdd6f4" ;;
    esac
}

# ── wttr.in free-text condition (weatherDesc) ──────────────────────────────
timex_text_icon() {
    local t
    t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$t" in
        *thunder*|*storm*) echo "|Storm" ;;
        *snow*|*sleet*|*ice*|*blizzard*) echo "|Snow" ;;
        *rain*|*drizzle*|*shower*) echo "󰖗|Rain" ;;
        *mist*|*fog*|*haze*) echo "󰖑|Mist" ;;
        *sun*|*clear*) echo "|Clear" ;;
        *cloud*|*overcast*) echo "|Cloudy" ;;
        *) echo "|Unknown" ;;
    esac
}

timex_text_hex() {
    local t
    t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$t" in
        *thunder*|*storm*) echo "#f9e2af" ;;
        *snow*|*sleet*|*ice*|*blizzard*) echo "#cdd6f4" ;;
        *rain*|*drizzle*|*shower*) echo "#74c7ec" ;;
        *mist*|*fog*|*haze*) echo "#84afdb" ;;
        *sun*|*clear*) echo "#f9e2af" ;;
        *) echo "#bac2de" ;;
    esac
}
