// ═══════════════════════════════════════════════════════════════════════════
// timex · ui — Weather settings tab (timex subsystem).
//
// Provider-driven weather: pick a provider and fill only what it needs
// (a city, or a city + API key). No fallbacks: the engine runs exactly the
// selected provider (core/timex.sh, deployed as ~/.local/bin/timex).
//
// Live settings: settings.json -> "timex": { provider, city, unit }; secrets
// go through `timex keys set` (state file, chmod 600). The city field offers
// Open-Meteo geocoding suggestions; the data card shows the engine snapshot,
// its age and any error reported by the last fetch.
//
// Shared-tab contract: `property var host` (colors, s(), highlightedBox,
// clearHighlight()), same as the rest of ui/settings/tabs/*.qml.
// ═══════════════════════════════════════════════════════════════════════════

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../core"

Item {
    id: root

    // ════ Forwarding al host ════
    property var host: null
    readonly property color base: host ? host.base : "#363537"
    readonly property color blue: host ? host.blue : "#5ad4e6"
    readonly property color green: host ? host.green : "#7bd88f"
    readonly property color overlay0: host ? host.overlay0 : "#f7f1ff"
    readonly property color peach: host ? host.peach : "#fd9353"
    readonly property color red: host ? host.red : "#fc618d"
    readonly property color subtext0: host ? host.subtext0 : "#f7f1ff"
    readonly property color subtext1: host ? host.subtext1 : "#f7f1ff"
    readonly property color surface0: host ? host.surface0 : "#363537"
    readonly property color surface1: host ? host.surface1 : "#363537"
    readonly property color surface2: host ? host.surface2 : "#363537"
    readonly property color text: host ? host.text : "#f7f1ff"
    readonly property color yellow: host ? host.yellow : "#fce566"
    function s(val) { return host ? host.s(val) : val; }
    property int highlightedBox: host ? host.highlightedBox : -1
    onHighlightedBoxChanged: {
        if (host && host.highlightedBox !== highlightedBox) {
            host.highlightedBox = highlightedBox;
            highlightedBox = Qt.binding(function() { return host ? host.highlightedBox : -1; });
        }
    }
    function clearHighlight() { if (host) host.clearHighlight(); }

    // ════ timex engine (CLI) ════
    readonly property string cliPath: Quickshell.env("TIMEX_CLI")
        ? Quickshell.env("TIMEX_CLI")
        : (Quickshell.env("HOME") + "/.local/bin/timex")

    // ════ Config (settings.json -> timex) ════
    property string provider: "open-meteo"
    property string city: ""
    property string unit: "metric"

    // ════ timex layout (applied by the calendar popup) ════
    property bool uiForecastEnabled: true
    property string uiPosition: "below"
    property real uiSize: 1.0
    property int uiGap: 16
    property int uiHours: 8
    property bool uiShowTime: true
    property bool uiShowIcon: true
    property bool uiShowTemp: true
    property string uiOrder: "time,icon,temp"
    property real uiClockScale: 1.0
    property bool uiClockShowSeconds: true
    property bool uiClockShowDate: true
    property bool uiCalendarEnabled: true
    property real uiCalendarSize: 1.0
    property string uiWeekStart: "monday"
    property bool uiPanelEnabled: true
    property real uiPanelSize: 1.0
    property bool uiPanelWind: true
    property bool uiPanelHumidity: true
    property bool uiPanelPop: true
    property bool uiPanelFeels: true

    // ════ UI state ════
    property var providerRows: []
    property var suggestions: []
    property bool suggestionsOpen: false
    property bool keySet: false
    property string keyWhere: ""
    property bool keyVisible: false
    property string keyTest: ""
    property string engineError: ""
    property real lastUpdate: 0
    property int nowTick: 0
    property bool flashOn: false
    property string flashText: ""

    // ════ Snapshot (cache) ════
    property string snapIcon: ""
    property string snapTemp: ""
    property string snapMax: ""
    property string snapMin: ""
    property string snapDesc: ""

    readonly property var activeRow: {
        for (let i = 0; i < providerRows.length; i++) {
            if (providerRows[i].name === provider) return providerRows[i];
        }
        return null;
    }
    readonly property bool needsKey: activeRow ? activeRow.needsKey === "1" : false
    readonly property string providerHint: activeRow ? activeRow.hint : ""
    readonly property string updatedText: {
        root.nowTick;
        if (!root.lastUpdate) return "never";
        let secs = Math.max(0, Math.floor(Date.now() / 1000 - root.lastUpdate));
        if (secs < 60) return secs + "s ago";
        if (secs < 3600) return Math.floor(secs / 60) + "m ago";
        return Math.floor(secs / 3600) + "h ago";
    }
    readonly property bool hasSnapshot: root.snapTemp !== "" && root.snapTemp !== "0.0"

    function loadFromConfig() {
        let c = (Config.rawSettings && Config.rawSettings.timex) ? Config.rawSettings.timex : {};
        provider = c.provider || "open-meteo";
        city = c.city || "";
        unit = c.unit || "metric";
        uiForecastEnabled = c.forecastEnabled !== false;
        uiPosition = (c.forecastPosition === "above") ? "above" : "below";
        uiSize = (typeof c.forecastSize === "number") ? Math.max(0.8, Math.min(1.4, c.forecastSize)) : 1.0;
        uiGap = (typeof c.forecastGap === "number") ? Math.max(2, Math.min(40, Math.round(c.forecastGap))) : 16;
        uiHours = (typeof c.forecastHours === "number") ? Math.max(3, Math.min(8, Math.round(c.forecastHours))) : 8;
        uiShowTime = c.forecastShowTime !== false;
        uiShowIcon = c.forecastShowIcon !== false;
        uiShowTemp = c.forecastShowTemp !== false;
        uiOrder = (typeof c.forecastOrder === "string" && c.forecastOrder !== "") ? c.forecastOrder : "time,icon,temp";
        uiClockScale = (typeof c.clockScale === "number") ? Math.max(0.85, Math.min(1.25, c.clockScale)) : 1.0;
        uiClockShowSeconds = c.clockShowSeconds !== false;
        uiClockShowDate = c.clockShowDate !== false;
        uiCalendarEnabled = c.calendarEnabled !== false;
        uiCalendarSize = (typeof c.calendarSize === "number") ? Math.max(0.8, Math.min(1.2, c.calendarSize)) : 1.0;
        uiWeekStart = (c.calendarWeekStart === "sunday") ? "sunday" : "monday";
        uiPanelEnabled = c.panelEnabled !== false;
        uiPanelSize = (typeof c.panelSize === "number") ? Math.max(0.8, Math.min(1.2, c.panelSize)) : 1.0;
        uiPanelWind = c.panelShowWind !== false;
        uiPanelHumidity = c.panelShowHumidity !== false;
        uiPanelPop = c.panelShowPop !== false;
        uiPanelFeels = c.panelShowFeels !== false;
    }

    function flash(msg) {
        flashText = msg;
        flashOn = true;
        flashTimer.restart();
    }

    function persistConfig() {
        if (cityInput.text !== root.city) root.city = cityInput.text;
        Config.setSetting("timex", {
            provider: provider, city: city, unit: unit,
            forecastEnabled: uiForecastEnabled,
            forecastPosition: uiPosition,
            forecastSize: Number(uiSize.toFixed(2)),
            forecastGap: uiGap,
            forecastHours: uiHours,
            forecastShowTime: uiShowTime,
            forecastShowIcon: uiShowIcon,
            forecastShowTemp: uiShowTemp,
            forecastOrder: uiOrder,
            clockScale: Number(uiClockScale.toFixed(2)),
            clockShowSeconds: uiClockShowSeconds,
            clockShowDate: uiClockShowDate,
            calendarEnabled: uiCalendarEnabled,
            calendarSize: Number(uiCalendarSize.toFixed(2)),
            calendarWeekStart: uiWeekStart,
            panelEnabled: uiPanelEnabled,
            panelSize: Number(uiPanelSize.toFixed(2)),
            panelShowWind: uiPanelWind,
            panelShowHumidity: uiPanelHumidity,
            panelShowPop: uiPanelPop,
            panelShowFeels: uiPanelFeels
        });
        flash("Saved");
        refreshWeather();
    }

    function rotateOrder() {
        let parts = uiOrder.split(",");
        if (parts.length !== 3) parts = ["time", "icon", "temp"];
        uiOrder = parts[1] + "," + parts[2] + "," + parts[0];
        saveDebounce.restart();
    }

    function bumpSize(d) { uiSize = Math.max(0.8, Math.min(1.4, Math.round((uiSize + d) * 100) / 100)); saveDebounce.restart(); }
    function bumpGap(d) { uiGap = Math.max(2, Math.min(40, uiGap + d)); saveDebounce.restart(); }
    function bumpHours(d) { uiHours = Math.max(3, Math.min(8, uiHours + d)); saveDebounce.restart(); }
    function bumpClock(d) { uiClockScale = Math.max(0.85, Math.min(1.25, Math.round((uiClockScale + d) * 100) / 100)); saveDebounce.restart(); }
    function bumpCalendarSize(d) { uiCalendarSize = Math.max(0.8, Math.min(1.2, Math.round((uiCalendarSize + d) * 100) / 100)); saveDebounce.restart(); }
    function bumpPanelSize(d) { uiPanelSize = Math.max(0.8, Math.min(1.2, Math.round((uiPanelSize + d) * 100) / 100)); saveDebounce.restart(); }

    function refreshWeather() {
        Quickshell.execDetached(["bash", "-c",
            cliPath + " --invalidate >/dev/null 2>&1; " + cliPath + " --getdata >/dev/null 2>&1"]);
        snapshotTimer.restart();
    }

    function pickCity(label) {
        cityInput.text = label;
        root.city = label;
        suggestionsOpen = false;
        suggestions = [];
        persistConfig();
    }

    function requestGeocode(q) {
        if (q.trim().length < 2) {
            suggestions = [];
            suggestionsOpen = false;
            return;
        }
        geocodeProc.query = q.trim();
        geocodeProc.running = false;
        geocodeProc.running = true;
    }

    // ════ Acciones ════
    Timer { id: saveDebounce; interval: 500; onTriggered: root.persistConfig() }
    Timer { id: geocodeDebounce; interval: 400; onTriggered: root.requestGeocode(cityInput.text) }
    Timer { id: keysRefreshTimer; interval: 500; onTriggered: { keysProc.running = false; keysProc.running = true; } }
    Timer { id: suggestionsCloseTimer; interval: 220; onTriggered: root.suggestionsOpen = false }
    Timer { id: flashTimer; interval: 1400; onTriggered: root.flashOn = false }
    Timer {
        id: snapshotTimer
        interval: 3200
        onTriggered: {
            snapshotProc.running = false; snapshotProc.running = true;
            statusProc.running = false; statusProc.running = true;
            keysProc.running = false; keysProc.running = true;
        }
    }
    Timer { id: ageTimer; interval: 30000; running: true; repeat: true; onTriggered: root.nowTick++ }

    Process {
        id: providersProc
        command: [root.cliPath, "providers", "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = [];
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue;
                    let p = lines[i].split("|");
                    out.push({ name: p[0], label: p[1] || p[0], needsKey: p[2] || "0", hint: p[3] || "" });
                }
                root.providerRows = out;
            }
        }
    }

    Process {
        id: keysProc
        command: [root.cliPath, "keys", "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let p = lines[i].split("|");
                    if (p[0] === "OPENWEATHER_KEY") {
                        root.keySet = p[3] === "1";
                        root.keyWhere = p[2] || "";
                    }
                }
            }
        }
    }

    Process {
        id: statusProc
        command: [root.cliPath, "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim().split("|");
                root.lastUpdate = parseInt(p[5] || "0", 10) || 0;
                root.engineError = (p[6] || "").trim();
            }
        }
    }

    Process {
        id: snapshotProc
        command: [root.cliPath, "snapshot"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim().split("|");
                root.snapIcon = p[0] || "";
                root.snapTemp = p[1] || "";
                root.snapMax = p[2] || "";
                root.snapMin = p[3] || "";
                root.snapDesc = p[4] || "";
                root.lastUpdate = parseInt(p[5] || "0", 10) || root.lastUpdate;
                root.nowTick++;
            }
        }
    }

    Process {
        id: geocodeProc
        property string query: ""
        command: [root.cliPath, "geocode", query]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let out = [];
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue;
                    let p = lines[i].split("|");
                    out.push({ label: p[0] || "", country: p[1] || "", lat: p[2] || "", lon: p[3] || "" });
                }
                root.suggestions = out;
                root.suggestionsOpen = out.length > 0;
            }
        }
    }

    Process {
        id: testProc
        command: [root.cliPath, "test"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim().split("|");
                if (p[0] === "ok") root.keyTest = "Key OK · " + (p[1] || "")
                else {
                    root.keyTest = "Key failed · " + (p[1] || "unknown error")
                    snapshotTimer.restart();
                }
            }
        }
    }

    // ════ Card header (inline component) ════
    component CardHead: RowLayout {
        id: cardHead
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property bool active: false
        Layout.fillWidth: true
        spacing: root.s(14)
        Item {
            Layout.preferredWidth: root.s(22)
            Layout.alignment: Qt.AlignVCenter
            Text {
                anchors.centerIn: parent
                text: cardHead.icon
                font.family: "Hack Nerd Font"; font.pixelSize: root.s(18)
                color: cardHead.active ? root.base : root.blue
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: root.s(3)
            Text {
                text: cardHead.title
                font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                color: cardHead.active ? root.base : root.text
                Layout.fillWidth: true
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
            }
            Text {
                text: cardHead.subtitle
                font.family: "Inter"; font.pixelSize: root.s(11)
                color: cardHead.active ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7)
                Layout.fillWidth: true
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
            }
        }
    }

    // ════ Small controls for the layout card ════
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool active: false
        signal clicked()
        implicitWidth: chipLabel.implicitWidth + root.s(22)
        implicitHeight: root.s(28)
        radius: root.s(20)
        color: chip.active ? root.blue : (chipMa.containsMouse ? Qt.alpha(root.surface1, 0.7) : "transparent")
        border.color: chip.active ? root.blue : (chipMa.containsMouse ? root.blue : root.surface1)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
            color: chip.active ? root.base : root.subtext0
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component Stepper: RowLayout {
        id: stepper
        property string label: ""
        property string valueText: ""
        signal dec()
        signal inc()
        Layout.fillWidth: true
        spacing: root.s(6)
        Text {
            text: stepper.label
            font.family: "Inter"; font.pixelSize: root.s(11)
            color: root.subtext0
            Layout.fillWidth: true
        }
        Rectangle {
            Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24); radius: root.s(18)
            color: decMa.containsMouse ? Qt.alpha(root.blue, 0.2) : "transparent"
            border.color: root.blue; border.width: 1
            Text { anchors.centerIn: parent; text: "−"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(13); color: root.blue }
            MouseArea { id: decMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stepper.dec() }
        }
        Text {
            text: stepper.valueText
            font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
            color: root.text
            Layout.preferredWidth: root.s(46)
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle {
            Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24); radius: root.s(18)
            color: incMa.containsMouse ? Qt.alpha(root.blue, 0.2) : "transparent"
            border.color: root.blue; border.width: 1
            Text { anchors.centerIn: parent; text: "+"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(13); color: root.blue }
            MouseArea { id: incMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stepper.inc() }
        }
    }

    // ════ Cuerpo ════
    Flickable {
        id: weatherFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: wCol.implicitHeight + root.s(100)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        MouseArea { anchors.fill: parent; onClicked: root.clearHighlight(); z: -1 }

        ColumnLayout {
            id: wCol
            width: parent.width
            spacing: root.s(10)

            // ── Fila: Provider + Unit ────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(10)

                // Box 0: Provider
                Rectangle {
                    id: wBox0
                    Layout.fillWidth: true
                    Layout.preferredWidth: root.s(2)
                    Layout.preferredHeight: providerCol.implicitHeight + root.s(28)
                    radius: root.s(26)
                    property bool isActive: root.highlightedBox === 0
                    color: isActive ? root.blue : root.surface0
                    border.color: isActive ? root.blue : root.surface1
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                    MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 0; z: -1 }

                    ColumnLayout {
                        id: providerCol
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        anchors.margins: root.s(16)
                        spacing: root.s(10)

                        CardHead {
                            icon: "󰖐"; title: "Provider"
                            subtitle: root.providerHint !== "" ? root.providerHint : "Weather data source"
                            active: wBox0.isActive
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: root.s(8)
                            Repeater {
                                model: root.providerRows
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(34); radius: root.s(22)
                                    property bool isSelected: root.provider === modelData.name
                                    property bool parentActive: wBox0.isActive
                                    property bool pillHover: pillMa.containsMouse
                                    color: isSelected
                                        ? (parentActive ? Qt.alpha(root.base, 0.25) : root.blue)
                                        : (parentActive ? Qt.alpha(root.base, 0.1) : (pillHover ? Qt.alpha(root.surface1, 0.7) : "transparent"))
                                    border.color: isSelected
                                        ? (parentActive ? Qt.alpha(root.base, 0.6) : root.blue)
                                        : (parentActive ? Qt.alpha(root.base, 0.2) : (pillHover ? root.blue : root.surface1))
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 0
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.label
                                            font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                                            color: isSelected ? root.base : (parentActive ? Qt.alpha(root.base, 0.6) : root.subtext0)
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.needsKey === "1" ? "key" : "free"
                                            font.family: "Inter"; font.pixelSize: root.s(8)
                                            opacity: 0.75
                                            color: isSelected ? Qt.alpha(root.base, 0.8) : (parentActive ? Qt.alpha(root.base, 0.55) : root.overlay0)
                                        }
                                    }
                                    MouseArea {
                                        id: pillMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.provider = modelData.name; saveDebounce.restart(); }
                                    }
                                }
                            }
                        }
                    }
                }

                // Box 3: Unit
                Rectangle {
                    id: wBox3
                    Layout.preferredWidth: root.s(280)
                    Layout.preferredHeight: unitCol.implicitHeight + root.s(28)
                    radius: root.s(26)
                    property bool isActive: root.highlightedBox === 3
                    color: isActive ? root.blue : root.surface0
                    border.color: isActive ? root.blue : root.surface1
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                    MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 3; z: -1 }

                    ColumnLayout {
                        id: unitCol
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        anchors.margins: root.s(16)
                        spacing: root.s(10)

                        CardHead {
                            icon: "󰔄"; title: "Temperature unit"
                            subtitle: "Metric (°C) or Imperial (°F)"
                            active: wBox3.isActive
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: root.s(8)
                            Repeater {
                                model: [{ val: "metric", label: "Celsius" }, { val: "imperial", label: "Fahrenheit" }]
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(30); radius: root.s(22)
                                    property bool isSelected: root.unit === modelData.val
                                    property bool parentActive: wBox3.isActive
                                    property bool pillHover: unitMa.containsMouse
                                    color: isSelected
                                        ? (parentActive ? Qt.alpha(root.base, 0.25) : root.blue)
                                        : (parentActive ? Qt.alpha(root.base, 0.1) : (pillHover ? Qt.alpha(root.surface1, 0.7) : "transparent"))
                                    border.color: isSelected
                                        ? (parentActive ? Qt.alpha(root.base, 0.6) : root.blue)
                                        : (parentActive ? Qt.alpha(root.base, 0.2) : (pillHover ? root.blue : root.surface1))
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        anchors.centerIn: parent; text: modelData.label
                                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                                        color: isSelected ? root.base : (parentActive ? Qt.alpha(root.base, 0.6) : root.subtext0)
                                    }
                                    MouseArea {
                                        id: unitMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.unit = modelData.val; saveDebounce.restart(); }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Box 1: City (with geocoding suggestions) ─────────────
            Rectangle {
                id: wBox1
                Layout.fillWidth: true
                Layout.preferredHeight: cityCol.implicitHeight + root.s(28)
                radius: root.s(26)
                property bool isActive: root.highlightedBox === 1
                color: isActive ? root.blue : root.surface0
                border.color: isActive ? root.blue : root.surface1
                border.width: 1
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 1; z: -1 }

                ColumnLayout {
                    id: cityCol
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: root.s(16)
                    spacing: root.s(10)

                    CardHead {
                        icon: "󰍎"; title: "City"
                        subtitle: "Type a city and pick a result (Open-Meteo also accepts \"lat,lon\")"
                        active: wBox1.isActive
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: root.s(42)
                        radius: root.s(15)
                        color: wBox1.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                        border.color: cityInput.activeFocus
                            ? (wBox1.isActive ? root.base : root.blue)
                            : (wBox1.isActive ? Qt.alpha(root.base, 0.3) : root.surface2)
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                        TextInput {
                            id: cityInput
                            anchors.fill: parent; anchors.margins: root.s(10)
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Hack Nerd Font"; font.pixelSize: root.s(12)
                            color: wBox1.isActive ? root.base : root.text
                            clip: true; selectByMouse: true
                            text: root.city
                            onTextEdited: {
                                geocodeDebounce.restart();
                                suggestionsCloseTimer.stop();
                            }
                            onAccepted: root.persistConfig()
                            onActiveFocusChanged: {
                                if (!activeFocus && root.suggestionsOpen)
                                    suggestionsCloseTimer.restart();
                            }
                            Text {
                                text: "e.g. Madrid"
                                color: wBox1.isActive ? Qt.alpha(root.base, 0.5) : root.subtext0
                                visible: !parent.text && !parent.activeFocus
                                font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { ColorAnimation { duration: 220 } }
                            }
                        }
                    }

                    // Suggestions dropdown
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.suggestionsOpen && root.suggestions.length > 0
                        Layout.preferredHeight: visible ? suggCol.implicitHeight + root.s(12) : 0
                        radius: root.s(14)
                        color: wBox1.isActive ? Qt.alpha(root.base, 0.12) : root.surface1
                        border.color: wBox1.isActive ? Qt.alpha(root.base, 0.25) : root.surface2
                        border.width: 1
                        clip: true

                        ColumnLayout {
                            id: suggCol
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.margins: root.s(6)
                            spacing: 0

                            Repeater {
                                model: root.suggestions
                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(28)
                                    radius: root.s(9)
                                    color: suggMa.containsMouse
                                        ? (wBox1.isActive ? Qt.alpha(root.base, 0.2) : Qt.alpha(root.blue, 0.15))
                                        : "transparent"
                                    Text {
                                        anchors.left: parent.left; anchors.leftMargin: root.s(8)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                        color: wBox1.isActive ? root.base : root.text
                                        elide: Text.ElideRight
                                        width: parent.width - root.s(16)
                                    }
                                    MouseArea {
                                        id: suggMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.pickCity(modelData.label); }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Box 2: API key (only when the provider needs one) ────
            Rectangle {
                id: wBox2
                Layout.fillWidth: true
                visible: root.needsKey
                Layout.preferredHeight: visible ? keyCol.implicitHeight + root.s(28) : 0
                radius: root.s(26)
                property bool isActive: root.highlightedBox === 2
                color: isActive ? root.blue : root.surface0
                border.color: isActive ? root.blue : root.surface1
                border.width: 1
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 2; z: -1 }

                ColumnLayout {
                    id: keyCol
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: root.s(16)
                    spacing: root.s(10)

                    CardHead {
                        icon: "󰌆"; title: "API key"
                        subtitle: root.keySet ? "Stored (state file, 600)" + (root.keyWhere !== "" ? " · " + root.keyWhere : "")
                                              : "Not set — required by this provider"
                        active: wBox2.isActive
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: root.s(42)
                        radius: root.s(15)
                        color: wBox2.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                        border.color: keyInput.activeFocus
                            ? (wBox2.isActive ? root.base : root.blue)
                            : (wBox2.isActive ? Qt.alpha(root.base, 0.3) : root.surface2)
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: root.s(10); spacing: root.s(8)
                            TextInput {
                                id: keyInput
                                Layout.fillWidth: true; Layout.fillHeight: true
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: "Hack Nerd Font"; font.pixelSize: root.s(12)
                                color: wBox2.isActive ? root.base : root.text
                                clip: true; selectByMouse: true
                                echoMode: root.keyVisible ? TextInput.Normal : TextInput.Password
                                passwordCharacter: "•"
                                onAccepted: {
                                    if (text.trim() === "") return;
                                    Quickshell.execDetached([root.cliPath, "keys", "set", "OPENWEATHER_KEY", text.trim()]);
                                    text = "";
                                    root.keyTest = "";
                                    keysRefreshTimer.restart();
                                    root.flash("Key saved");
                                }
                                Text {
                                    text: "Paste the key and press Enter"
                                    color: wBox2.isActive ? Qt.alpha(root.base, 0.5) : root.subtext0
                                    visible: !parent.text && !parent.activeFocus
                                    font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Text {
                                text: root.keyVisible ? "󰈈" : "󰈉"
                                font.family: "Hack Nerd Font"; font.pixelSize: root.s(16)
                                color: eyeMa.containsMouse ? root.blue : (wBox2.isActive ? Qt.alpha(root.base, 0.7) : root.subtext0)
                                MouseArea {
                                    id: eyeMa
                                    anchors.fill: parent; anchors.margins: root.s(-6)
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.keyVisible = !root.keyVisible
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: root.s(8)
                        Text {
                            Layout.fillWidth: true
                            text: root.keyTest !== "" ? root.keyTest
                                                      : (root.engineError !== "" ? root.engineError : "")
                            font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                            color: root.engineError !== "" && root.keyTest === "" ? root.red : root.subtext0
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            Layout.preferredWidth: root.s(70); Layout.preferredHeight: root.s(26); radius: root.s(20)
                            color: testMa.containsMouse ? Qt.alpha(root.blue, 0.2) : "transparent"
                            border.color: root.blue; border.width: 1
                            Text {
                                anchors.centerIn: parent; text: "Test"
                                font.family: "Hack Nerd Font"; font.pixelSize: root.s(10); color: root.blue
                            }
                            MouseArea {
                                id: testMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { root.keyTest = "Testing…"; root.persistConfig(); testProc.running = false; testProc.running = true; }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(26); radius: root.s(20)
                            visible: root.keySet
                            color: rmMa.containsMouse ? Qt.alpha(root.red, 0.2) : "transparent"
                            border.color: root.red; border.width: 1
                            Text {
                                anchors.centerIn: parent; text: "Remove"
                                font.family: "Hack Nerd Font"; font.pixelSize: root.s(10); color: root.red
                            }
                            MouseArea {
                                id: rmMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached([root.cliPath, "keys", "remove", "OPENWEATHER_KEY"]);
                                    root.keyTest = "";
                                    keysRefreshTimer.restart();
                                    root.flash("Key removed");
                                }
                            }
                        }
                    }
                }
            }

            // ── Box 4: Weather data ──────────────────────────────────
            Rectangle {
                id: wBox4
                Layout.fillWidth: true
                Layout.preferredHeight: dataCol.implicitHeight + root.s(28)
                radius: root.s(26)
                property bool isActive: root.highlightedBox === 4
                color: isActive ? root.blue : root.surface0
                border.color: isActive ? root.blue : root.surface1
                border.width: 1
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 4; z: -1 }

                ColumnLayout {
                    id: dataCol
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: root.s(16)
                    spacing: root.s(10)

                    CardHead {
                        icon: "󰙦"; title: "Weather data"
                        subtitle: root.flashOn ? root.flashText
                                               : "Saved automatically · last fetch " + root.updatedText
                        active: wBox4.isActive
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: root.s(14)
                        Text {
                            text: root.hasSnapshot ? root.snapIcon : ""
                            font.family: "Hack Nerd Font"; font.pixelSize: root.s(30)
                            color: wBox4.isActive ? root.base : root.subtext0
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: root.s(2)
                            Text {
                                text: root.hasSnapshot ? root.snapTemp + "°" : "—"
                                font.family: "Hack Nerd Font"; font.weight: Font.Black; font.pixelSize: root.s(20)
                                color: wBox4.isActive ? root.base : root.text
                            }
                            Text {
                                text: root.hasSnapshot ? root.snapDesc : "no data"
                                font.family: "Inter"; font.pixelSize: root.s(11)
                                color: wBox4.isActive ? Qt.alpha(root.base, 0.8) : root.subtext0
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: root.hasSnapshot
                                text: "max " + root.snapMax + "° · min " + root.snapMin + "°"
                                font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                                color: wBox4.isActive ? Qt.alpha(root.base, 0.7) : root.overlay0
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: root.s(100); Layout.preferredHeight: root.s(30); radius: root.s(22)
                            color: wBox4.isActive ? Qt.alpha(root.base, 0.25) : (refMa.containsMouse ? Qt.alpha(root.blue, 0.2) : root.blue)
                            border.color: wBox4.isActive ? Qt.alpha(root.base, 0.6) : root.blue
                            border.width: 1
                            Text {
                                anchors.centerIn: parent; text: "Refresh"
                                font.family: "Hack Nerd Font"; font.pixelSize: root.s(10); color: root.base
                            }
                            MouseArea {
                                id: refMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { root.refreshWeather(); root.flash("Refreshing…"); }
                            }
                        }
                    }

                    Text {
                        visible: root.engineError !== ""
                        Layout.fillWidth: true
                        text: "Error: " + root.engineError
                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                        color: wBox4.isActive ? root.base : root.red
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ── Box 5: Timex layout (calendar popup row + clock) ─────
            Rectangle {
                id: wBox5
                Layout.fillWidth: true
                Layout.preferredHeight: layoutCol.implicitHeight + root.s(28)
                radius: root.s(26)
                property bool isActive: root.highlightedBox === 5
                color: isActive ? root.blue : root.surface0
                border.color: isActive ? root.blue : root.surface1
                border.width: 1
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 5; z: -1 }

                ColumnLayout {
                    id: layoutCol
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: root.s(16)
                    spacing: root.s(10)

                    CardHead {
                        icon: "󰒓"; title: "Timex layout"
                        subtitle: "Hourly forecast row and clock in the calendar popup (SUPER+S)"
                        active: wBox5.isActive
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: root.s(8)
                        Chip {
                            label: "Hourly row"; active: root.uiForecastEnabled
                            onClicked: { root.uiForecastEnabled = !root.uiForecastEnabled; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Below"; active: root.uiPosition === "below"
                            onClicked: { root.uiPosition = "below"; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Above"; active: root.uiPosition === "above"
                            onClicked: { root.uiPosition = "above"; saveDebounce.restart(); }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: root.s(8)
                        Chip {
                            label: "Time"; active: root.uiShowTime
                            onClicked: { root.uiShowTime = !root.uiShowTime; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Icon"; active: root.uiShowIcon
                            onClicked: { root.uiShowIcon = !root.uiShowIcon; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Temp"; active: root.uiShowTemp
                            onClicked: { root.uiShowTemp = !root.uiShowTemp; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Order: " + root.uiOrder.split(",").join(" · ") + "  ↻"
                            onClicked: root.rotateOrder()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: root.s(8)
                        Chip {
                            label: "Clock seconds"; active: root.uiClockShowSeconds
                            onClicked: { root.uiClockShowSeconds = !root.uiClockShowSeconds; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Clock date"; active: root.uiClockShowDate
                            onClicked: { root.uiClockShowDate = !root.uiClockShowDate; saveDebounce.restart(); }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Stepper {
                        label: "Forecast size"; valueText: root.uiSize.toFixed(2)
                        onDec: root.bumpSize(-0.1); onInc: root.bumpSize(0.1)
                    }
                    Stepper {
                        label: "Gap"; valueText: String(root.uiGap)
                        onDec: root.bumpGap(-2); onInc: root.bumpGap(2)
                    }
                    Stepper {
                        label: "Hours shown"; valueText: String(root.uiHours)
                        onDec: root.bumpHours(-1); onInc: root.bumpHours(1)
                    }
                    Stepper {
                        label: "Clock scale"; valueText: root.uiClockScale.toFixed(2)
                        onDec: root.bumpClock(-0.05); onInc: root.bumpClock(0.05)
                    }
                }
            }

            // ── Box 6: Calendar & day panel ──────────────────────────
            Rectangle {
                id: wBox6
                Layout.fillWidth: true
                Layout.preferredHeight: calCol.implicitHeight + root.s(28)
                radius: root.s(26)
                property bool isActive: root.highlightedBox === 6
                color: isActive ? root.blue : root.surface0
                border.color: isActive ? root.blue : root.surface1
                border.width: 1
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 6; z: -1 }

                ColumnLayout {
                    id: calCol
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: root.s(16)
                    spacing: root.s(10)

                    CardHead {
                        icon: "󰃭"; title: "Calendar & day panel"
                        subtitle: "Month grid and the selected-day panel inside the popup"
                        active: wBox6.isActive
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: root.s(8)
                        Chip {
                            label: "Calendar"; active: root.uiCalendarEnabled
                            onClicked: { root.uiCalendarEnabled = !root.uiCalendarEnabled; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Week starts Monday"; active: root.uiWeekStart === "monday"
                            onClicked: { root.uiWeekStart = "monday"; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Sunday"; active: root.uiWeekStart === "sunday"
                            onClicked: { root.uiWeekStart = "sunday"; saveDebounce.restart(); }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Stepper {
                        label: "Calendar size"; valueText: root.uiCalendarSize.toFixed(2)
                        onDec: root.bumpCalendarSize(-0.05); onInc: root.bumpCalendarSize(0.05)
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: root.s(8)
                        Chip {
                            label: "Day panel"; active: root.uiPanelEnabled
                            onClicked: { root.uiPanelEnabled = !root.uiPanelEnabled; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Wind"; active: root.uiPanelWind
                            onClicked: { root.uiPanelWind = !root.uiPanelWind; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Humid"; active: root.uiPanelHumidity
                            onClicked: { root.uiPanelHumidity = !root.uiPanelHumidity; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Rain"; active: root.uiPanelPop
                            onClicked: { root.uiPanelPop = !root.uiPanelPop; saveDebounce.restart(); }
                        }
                        Chip {
                            label: "Feels"; active: root.uiPanelFeels
                            onClicked: { root.uiPanelFeels = !root.uiPanelFeels; saveDebounce.restart(); }
                        }
                    }

                    Stepper {
                        label: "Day panel size"; valueText: root.uiPanelSize.toFixed(2)
                        onDec: root.bumpPanelSize(-0.05); onInc: root.bumpPanelSize(0.05)
                    }
                }
            }
        }
    }

    Component.onCompleted: root.loadFromConfig()
    Connections {
        target: Config
        function onRawSettingsChanged() { root.loadFromConfig(); }
    }
}
