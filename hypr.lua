-- timex — calendar/weather plugin (equisdots plugin standard).
--
-- The loader evaluates this file with the SDK injected as `...`; the popup is
-- a plugin panel (manifest provides.panels.calendar) opened through the
-- shell's panel manager (qs_manager, a core session script).
local mod = ...

local home = os.getenv("HOME") or ""
mod.bind("SUPER + S",
         mod.exec("bash " .. home .. "/.config/hypr/scripts/qs_manager.sh toggle calendar"),
         { label = "Timex: calendar/weather popup" })

mod.log("timex loaded")
