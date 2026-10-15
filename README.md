# timex

Time & weather engine for the [equisdots](https://github.com/equisdots) desktop
— the "tiempo" subsystem: provider-driven weather data plus the time/clock
interfaces it feeds (bar module, calendar popup, desktop faces — wired in the
shell).

Version: **0.2.0** · License: MIT

## Architecture

```
timex/
  plugin.json              equisdots plugin manifest (panel + settings page)
  hypr.lua                 SUPER+S opens the calendar panel (SDK: mod.bind)
  core/timex.sh            dispatcher: provider selection, cache, CLI, keys
  api/
    icons.sh               condition mappings (OWM codes · WMO codes · text)
    providers/             one file per provider, same normalized output
      open-meteo.sh        no key · city or "lat,lon" (geocoding included)
      wttr.sh              no key · city
      openweather.sh       API key + city (geocoding included)
  ui/
    TimexPopup.qml         calendar panel: clock, month calendar, hourly
                           forecast row and day panel (SUPER + S target);
                           shipped as provides.panels.calendar
  settings/
    TimexPage.qml          the plugin's settings page (provider/city/key +
                           layout), shown as p_timex in the Plugins group
```

**No fallbacks:** the engine runs exactly the selected provider. If the
provider is missing, unknown, or lacks its city/key, the cache gets an explicit
error state (`Select a provider`, `Set a city`, `Set the API key`,
`Unknown provider: …`) and nothing else is tried.

## CLI

```bash
timex --json                     # throttled refresh + cache JSON
timex --getdata                  # force a refresh
timex --invalidate               # drop the cache (provider/city changed)
timex --current-icon             # bar module reads
timex --current-temp             #   (unit symbol included)
timex --current-hex
timex --icon | --temp | --hex    # forecast[0] variants
timex providers list             # name|label|needs_key|hint
timex geocode <query>            # label|country|lat|lon (top 5, for the UI picker)
timex test                       # ok|<desc> | fail|<error> (runs the selected provider)
timex snapshot                   # icon|temp|max|min|desc|updated_epoch
timex keys set OPENWEATHER_KEY <value>
timex keys remove OPENWEATHER_KEY
timex keys list                  # NAME|label|where|0-1
timex status                     # provider|city|unit|configured|key_set|last_update|last_error
```

Deployment is the equisdots plugin convention (`dots plugins add timex`; it
also installs by default): the whole repo lands at
`~/.config/hypr/scripts/quickshell/ui/plugins/timex/` and the popup, the
settings page and the shell's `weather.sh` shim resolve the engine from there
across deploy layouts (managed tree, user plugin, classic `~/.local/bin`
wrapper). `TIMEX_CLI` overrides the resolver for tests.

## Configuration

- `settings.json → "timex"`: `{ provider, city, unit }` (no secrets).
- UI layout (the plugin's Timex settings page): extra keys in the
  same object, applied live by the calendar popup —
  `forecastEnabled`, `forecastPosition` (`below`/`above`), `forecastSize`,
  `forecastGap`, `forecastHours`, `forecastShowTime/Icon/Temp`,
  `forecastOrder` (CSV of `time,icon,temp`) and `clockScale`. Defaults are
  plugin-owned (popup/page).
- API keys: `~/.local/state/quickshell/timex/keys.conf` (chmod 600), written
  through `timex keys set` — never stored in `settings.json`.
- Cache: `~/.cache/quickshell/timex/weather.json` (contract kept from the old
  weather script: `current_temp/current_icon/current_hex/forecast[]` with
  `day/day_full/date/max/min/feels_like/wind/humidity/pop/icon/hex/desc/hourly`).

## Providers

| Name | Key | Input | Notes |
|---|---|---|---|
| `open-meteo` | — | city or `lat,lon` | geocoding cached in the state dir; 5 days, hourly |
| `wttr` | — | city | 3 days, hourly; good fallback-free alternative |
| `openweather` | yes | city + key | free tier; geocoding with the key, 5 days |

Adding a provider is one executable under `api/providers/` that reads
`TIMEX_CITY`, `TIMEX_UNIT`, `TIMEX_KEY`, `TIMEX_STATE_DIR` from the environment
and prints the normalized JSON document; then add its line to the catalog in
`core/timex.sh`.
