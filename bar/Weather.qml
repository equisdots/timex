// Weather — Timex's bar module (equisdots plugin standard).
//
// Declared in the manifest as provides.bar.modules.weather; the bar loads it
// from the plugin UI tree with the standard module contract (bar, colors,
// slotIndex, ...). Self-contained: it polls the plugin engine
// (--current-icon/temp/hex, throttled refresh + cache) and opens the
// calendar/weather panel on click.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.ui.bar

ModulePill {
    id: mod
    moduleId: "weather"

    // timex engine resolver (managed shell tree, user plugin, classic wrapper).
    readonly property string timexCmd: "T=; for c in \"$TIMEX_CLI\" \"$HOME/.config/hypr/scripts/quickshell/ui/plugins/timex/core/timex.sh\" \"$HOME/.config/hypr/plugins-user/timex/core/timex.sh\" \"$HOME/.local/bin/timex\"; do [ -n \"$c\" ] && [ -f \"$c\" ] && { T=\"$c\"; break; }; done; [ -n \"$T\" ] && exec bash \"$T\""

    property string weatherIcon: "\uf0590"
    property string weatherTemp: "--°"
    property string weatherHex: ""

    accentRole: "yellow"
    accentActive: true
    // The engine reports the condition color as hex; the island fill follows
    // it (falling back to the yellow accent before the first poll completes).
    property color weatherColor: {
        let h = String(mod.weatherHex);
        if (/^#[0-9a-fA-F]{6}$/.test(h)) return h;
        return "transparent";
    }
    accentColor: weatherColor
    readonly property bool hasData: mod.weatherTemp !== "--°" && mod.weatherTemp !== ""

    Timer {
        interval: 150000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { weatherPoller.running = false; weatherPoller.running = true; }
    }

    Process {
        id: weatherPoller
        command: ["bash", "-c", `
            echo "$(${mod.timexCmd} --current-icon)"
            echo "$(${mod.timexCmd} --current-temp)"
            echo "$(${mod.timexCmd} --current-hex)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 3) {
                    if (lines[0] !== "") mod.weatherIcon = lines[0];
                    if (lines[1] !== "") mod.weatherTemp = lines[1];
                    if (lines[2] !== "") mod.weatherHex = lines[2];
                }
            }
        }
    }

    onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle calendar"])

    // --- horizontal: glyph + temperature -------------------------------------
    Row {
        visible: mod.horizontal
        spacing: bar.s(8)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: mod.glyph(mod.weatherIcon)
            font.family: bar.fontFamily
            font.pixelSize: bar.s(18)
            color: mod.contentColor
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: mod.weatherTemp
            visible: mod.hasData
            font.family: bar.fontFamily
            font.pixelSize: bar.s(13)
            font.weight: Font.Black
            color: mod.contentColor
        }
    }

    // --- compact: glyph over temperature -------------------------------------
    Column {
        visible: mod.compact
        spacing: -2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: mod.glyph(mod.weatherIcon)
            font.family: bar.fontFamily
            font.pixelSize: bar.s(20)
            color: mod.contentColor
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: mod.hasData ? mod.weatherTemp : "--"
            font.family: bar.fontFamily
            font.pixelSize: bar.s(9)
            font.weight: Font.Black
            color: mod.contentColor
        }
    }
}
