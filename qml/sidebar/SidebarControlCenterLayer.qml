import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Io
import IslandBackend
import "../shared"

// ── Sidebar Control Center popup — centered, replica of ControlCenterLayer ───
// Opened by the cog icon below the notification bell in the sidebar pill.

PanelWindow {
    id: root

    // ── Theming ───────────────────────────────────────────────────────
    property bool  useWalColor:         false
    property color walColor:            "#000000"
    property real  capsuleOpacityValue: 0.20
    property bool  gamemodeActive:      false

    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: ""

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 0.97)
        : Qt.rgba(0.07, 0.07, 0.09, 0.96)

    readonly property color moduleColor:  Qt.rgba(1,1,1, gamemodeActive ? 0.03 : 0.05)
    readonly property color moduleHover:  Qt.rgba(1,1,1, gamemodeActive ? 0.06 : 0.09)
    readonly property color trackColor:   StyleTokens.track
    readonly property color textPrimary:  IslandMotion.textPrimary
    readonly property color textSecondary: IslandMotion.textSecondary

    // ── Open/close ────────────────────────────────────────────────────
    property bool popupOpen: false
    function open()  { popupOpen = true  }
    function close() { popupOpen = false }
    function toggle(){ popupOpen = !popupOpen }

    // ── Signals ───────────────────────────────────────────────────────
    signal dndToggleRequested()
    signal gamemodeToggleRequested()
    signal sidebarToggleRequested()
    signal appearanceOpacityRequested(real value)
    signal appearanceWalColorToggleRequested(bool enabled)
    signal appearanceWalColorIndexRequested(int index)
    property bool dndActive:      false
    property bool sidebarEnabled: true
    property bool appearanceMenuOpen: false
    property bool capsuleUseWalColor: false
    property var  capsuleWalColors:   []
    property int  capsuleWalColorIndex: 0
    readonly property color capsuleWalColor: (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
        ? capsuleWalColors[capsuleWalColorIndex] : "#000000"

    // ── System state ──────────────────────────────────────────────────
    property string currentTime:       "00:00"
    property string currentDateLabel:  ""
    property int    batteryCapacity:   0
    property bool   isCharging:        false
    property real   volumeLevel:       -1
    property real   brightnessLevel:   -1

    property real  localVolume:      0.5
    property real  localBrightness:  0.5
    property real  displayedVolume:  0.5
    property real  displayedBrightness: 0.5
    property real  pendingVolume:    0.5
    property real  pendingBrightness: 0.5
    property real  lastAppliedVolume: -1
    property real  lastAppliedBrightness: -1
    property bool  brightnessSetterRunning: false
    property bool  volumeSetterRunning: false
    property bool  sliderIntroPending: false
    property int   sliderIntroDelay: 400

    property bool  hyprsunsetActive: false
    property bool  wifiPanelOpen:    false
    property bool  bluetoothPanelOpen: false

    readonly property var wifiController:      WifiController
    readonly property var bluetoothPairingAgent: BluetoothPairingAgent
    readonly property bool bluetoothAvailable: !!bluetoothAdapter
    readonly property var  bluetoothAdapter:   Bluetooth.defaultAdapter
    readonly property bool bluetoothEnabled:   bluetoothAdapter ? bluetoothAdapter.enabled : false
    readonly property bool bluetoothBusy:      bluetoothAdapter
        ? (bluetoothAdapter.state === BluetoothAdapterState.Enabling || bluetoothAdapter.state === BluetoothAdapterState.Disabling)
        : false
    readonly property bool wifiSupported:  wifiController ? wifiController.supported  : false
    readonly property bool wifiAvailable:  wifiController ? wifiController.available  : false
    readonly property bool wifiEnabled:    wifiController ? wifiController.enabled    : false
    readonly property bool wifiBusy:       wifiController ? wifiController.busy       : false
    readonly property string wifiCurrentSsid: wifiController ? wifiController.currentSsid : ""
    readonly property string wifiStatusText:  wifiController ? wifiController.statusText  : "Unavailable"

    readonly property string wifiGlyph:        ""
    readonly property string bluetoothGlyph:   ""
    readonly property string brightnessGlyph:  "\u{F00DF}"
    readonly property string volumeGlyph:      "\u{F057E}"

    // ── Helpers ───────────────────────────────────────────────────────
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    function trimString(v) { return (v === undefined || v === null) ? "" : String(v).trim() }

    function bluetoothDeviceName(device) {
        if (!device) return "Unknown"
        const n = trimString(device.deviceName) || trimString(device.name) || trimString(device.address)
        return n || "Unknown"
    }
    function buildBluetoothStatusText() {
        if (!bluetoothAvailable) return "Unavailable"
        if (!bluetoothEnabled) return "Off"
        const devs = bluetoothAdapter ? bluetoothAdapter.devices.values : []
        const names = devs.filter(d => d && d.connected).map(d => bluetoothDeviceName(d))
        if (names.length === 1) return names[0]
        if (names.length > 1) return names[0] + " +" + (names.length - 1)
        if (bluetoothAdapter && bluetoothAdapter.discovering) return "Scanning"
        return bluetoothBusy ? "Working..." : "On"
    }
    function toggleWifiEnabled() {
        if (wifiController) wifiController.setEnabled(!wifiEnabled)
    }
    function toggleBluetoothEnabled() {
        if (!bluetoothAdapter) return
        if (bluetoothAdapter.discovering) bluetoothAdapter.discovering = false
        bluetoothAdapter.enabled = !bluetoothAdapter.enabled
    }

    function syncBrightnessFromLevel(level) {
        if (level < 0) return
        localBrightness = clamp01(level)
        if (popupOpen && !sliderIntroPending) displayedBrightness = localBrightness
        pendingBrightness = localBrightness; lastAppliedBrightness = localBrightness
    }
    function syncVolumeFromLevel(level) {
        if (level < 0) return
        localVolume = clamp01(level)
        if (popupOpen && !sliderIntroPending) displayedVolume = localVolume
        pendingVolume = localVolume; lastAppliedVolume = localVolume
    }
    function queueBrightness(value) {
        localBrightness = clamp01(value)
        if (popupOpen && !sliderIntroPending) displayedBrightness = localBrightness
        pendingBrightness = localBrightness; brightnessApplyTimer.restart()
    }
    function queueVolume(value) {
        localVolume = clamp01(value)
        if (popupOpen && !sliderIntroPending) displayedVolume = localVolume
        pendingVolume = localVolume; volumeApplyTimer.restart()
    }
    function flushBrightness(force) {
        const v = clamp01(pendingBrightness)
        if (!force && Math.abs(v - lastAppliedBrightness) < 0.01) return
        if (brightnessSetterRunning) { brightnessApplyTimer.restart(); return }
        lastAppliedBrightness = v; brightnessSetterRunning = true; SystemServices.setBrightness(v)
    }
    function flushVolume(force) {
        const v = clamp01(pendingVolume)
        if (!force && Math.abs(v - lastAppliedVolume) < 0.01) return
        if (volumeSetterRunning) { volumeApplyTimer.restart(); return }
        lastAppliedVolume = v; volumeSetterRunning = true; SystemServices.setVolume(v)
    }

    // ── Window setup ──────────────────────────────────────────────────
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: popupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: popupOpen

    mask: Region {
        Region {
            x: Math.floor(card.x); y: Math.floor(card.y)
            width:  root.popupOpen ? Math.ceil(card.width)  : 0
            height: root.popupOpen ? Math.ceil(card.height) : 0
        }
    }

    MouseArea { anchors.fill: parent; enabled: root.popupOpen; onClicked: root.close(); z: -1 }
    Keys.onEscapePressed: root.close()

    // ── Timers ────────────────────────────────────────────────────────
    Timer { id: brightnessApplyTimer; interval: 55; repeat: false; onTriggered: root.flushBrightness(false) }
    Timer { id: volumeApplyTimer;     interval: 55; repeat: false; onTriggered: root.flushVolume(false) }
    Timer {
        id: sliderIntroTimer; interval: root.sliderIntroDelay; repeat: false
        onTriggered: {
            root.sliderIntroPending = false
            root.displayedBrightness = root.localBrightness
            root.displayedVolume = root.localVolume
        }
    }

    // ── Hyprsunset ────────────────────────────────────────────────────
    Process {
        id: hyprsunsetExec
        command: ["bash", "-c", "pgrep -x hyprsunset > /dev/null && pkill -x hyprsunset || hyprsunset --temperature 4500 &"]
    }
    Process {
        id: hyprsunsetChecker
        command: ["bash", "-c", "pgrep -x hyprsunset > /dev/null && echo 1 || echo 0"]
        stdout: SplitParser { onRead: (data) => { root.hyprsunsetActive = (data.trim() === "1") } }
    }
    Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!hyprsunsetChecker.running) hyprsunsetChecker.running = true
    }

    // ── SystemServices connections ────────────────────────────────────
    Connections {
        target: SystemServices
        function onBrightnessSnapshotReady(value, errorString) {
            if (errorString === "") root.syncBrightnessFromLevel(value)
        }
        function onBrightnessSetFinished(value, success, errorString) {
            root.brightnessSetterRunning = false
            if (success) root.syncBrightnessFromLevel(value)
        }
        function onVolumeSnapshotReady(value, muted, errorString) {
            if (errorString === "") root.syncVolumeFromLevel(value)
        }
        function onVolumeSetFinished(value, success, errorString) {
            root.volumeSetterRunning = false
            if (success) root.syncVolumeFromLevel(value)
        }
    }

    onBrightnessLevelChanged: syncBrightnessFromLevel(brightnessLevel)
    onVolumeLevelChanged: syncVolumeFromLevel(volumeLevel)

    onPopupOpenChanged: {
        if (popupOpen) {
            syncBrightnessFromLevel(brightnessLevel)
            syncVolumeFromLevel(volumeLevel)
            sliderIntroPending = true
            displayedBrightness = localBrightness
            displayedVolume = localVolume
            sliderIntroTimer.restart()
            hyprsunsetChecker.running = true
            SystemServices.requestBrightness()
            SystemServices.requestVolume()
        } else {
            sliderIntroTimer.stop()
            sliderIntroPending = false
            displayedBrightness = localBrightness
            displayedVolume = localVolume
        }
    }

    Component.onCompleted: {
        syncBrightnessFromLevel(brightnessLevel)
        syncVolumeFromLevel(volumeLevel)
        SystemServices.requestBrightness()
        SystemServices.requestVolume()
    }

    Behavior on displayedBrightness {
        enabled: root.popupOpen && !root.sliderIntroPending && !brightnessSliderCard.pressed
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }
    Behavior on displayedVolume {
        enabled: root.popupOpen && !root.sliderIntroPending && !volumeSliderCard.pressed
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    // ── Card ──────────────────────────────────────────────────────────
    Item {
        id: card
        width: 440
        anchors.centerIn: parent
        height: contentCol.implicitHeight + 24

        opacity: root.popupOpen ? 1 : 0
        scale:   root.popupOpen ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }

        Rectangle {
            anchors.fill: parent; radius: 28
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            clip: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Column {
            id: contentCol
            anchors.top: parent.top; anchors.topMargin: 12
            anchors.left: parent.left; anchors.leftMargin: 12
            anchors.right: parent.right; anchors.rightMargin: 12
            spacing: 12

            // ── Header row: time + battery ────────────────────────────
            Item {
                width: parent.width; height: 28

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.currentTime
                    color: IslandMotion.textPrimary
                    font.pixelSize: 19; font.family: root.heroFontFamily
                    font.weight: Font.Bold; font.letterSpacing: -0.45
                }

                Row {
                    anchors.right: parent.right; anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        renderType: Text.NativeRendering
                        text: "\uf0e7"; color: "white"
                        font.pixelSize: 13; font.family: root.iconFontFamily
                        visible: root.isCharging
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        renderType: Text.NativeRendering
                        text: root.batteryCapacity + "%"; color: "white"
                        font.pixelSize: 13; font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // Hyprsunset button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.hyprsunsetActive ? Qt.rgba(0.9,0.66,0.29,0.25)
                             : (sunMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.08))
                        border.color: root.hyprsunsetActive ? "#e5a84b"
                                    : (sunMouse.containsMouse ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.2))
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text {
                            renderType: Text.NativeRendering; anchors.centerIn: parent
                            text: "\uf186"; font.family: root.iconFontFamily; font.pixelSize: 13
                            color: root.hyprsunsetActive ? "#e5a84b" : IslandMotion.textPrimary
                        }
                        MouseArea {
                            id: sunMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                root.hyprsunsetActive = !root.hyprsunsetActive
                                hyprsunsetExec.running = true
                            }
                        }
                    }
                    // Appearance button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.appearanceMenuOpen || appearBtnMouse.containsMouse
                             ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                        border.color: root.appearanceMenuOpen
                                    ? Qt.rgba(1,1,1,0.4)
                                    : (appearBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.2))
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text {
                            renderType: Text.NativeRendering; anchors.centerIn: parent
                            text: "\uf1fc"; font.family: root.iconFontFamily; font.pixelSize: 13
                            color: root.appearanceMenuOpen ? "white" : IslandMotion.textPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            id: appearBtnMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.appearanceMenuOpen = !root.appearanceMenuOpen
                        }
                    }
                }
            }

            // ── Wi-Fi + Bluetooth cards ───────────────────────────────
            Row {
                width: parent.width; height: 80; spacing: 12

                Rectangle {
                    width: (parent.width - 12) / 2; height: parent.height; radius: 20
                    color: wifiHover.containsMouse ? root.moduleHover : root.moduleColor
                    border.width: 1; border.color: Qt.rgba(1,1,1,0.16)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea { id: wifiHover; anchors.fill: parent; hoverEnabled: true }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.top: parent.top; anchors.topMargin: 12
                        text: root.wifiGlyph; font.family: root.iconFontFamily; font.pixelSize: 18
                        color: root.wifiEnabled ? StyleTokens.accent : IslandMotion.textFaint
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.top: parent.top; anchors.topMargin: 12
                        width: 34; height: 20; radius: 10
                        color: root.wifiEnabled ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 2
                            x: root.wifiEnabled ? 16 : 2; color: "white"
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.wifiSupported && root.wifiAvailable && !root.wifiBusy
                            onClicked: root.toggleWifiEnabled()
                        }
                    }
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                        spacing: 2
                        Text {
                            renderType: Text.NativeRendering; text: "Wi-Fi"
                            color: IslandMotion.textPrimary; font.pixelSize: 13
                            font.family: root.textFontFamily; font.weight: Font.DemiBold
                        }
                        Text {
                            renderType: Text.NativeRendering; text: root.wifiStatusText
                            color: IslandMotion.textFaint; font.pixelSize: 10
                            font.family: root.textFontFamily
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 12) / 2; height: parent.height; radius: 20
                    color: btHover.containsMouse ? root.moduleHover : root.moduleColor
                    border.width: 1; border.color: Qt.rgba(1,1,1,0.16)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea { id: btHover; anchors.fill: parent; hoverEnabled: true }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.top: parent.top; anchors.topMargin: 12
                        text: root.bluetoothGlyph; font.family: root.iconFontFamily; font.pixelSize: 18
                        color: root.bluetoothEnabled ? StyleTokens.accent : IslandMotion.textFaint
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.top: parent.top; anchors.topMargin: 12
                        width: 34; height: 20; radius: 10
                        color: root.bluetoothEnabled ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 2
                            x: root.bluetoothEnabled ? 16 : 2; color: "white"
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.bluetoothAvailable && !root.bluetoothBusy
                            onClicked: root.toggleBluetoothEnabled()
                        }
                    }
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                        spacing: 2
                        Text {
                            renderType: Text.NativeRendering; text: "Bluetooth"
                            color: IslandMotion.textPrimary; font.pixelSize: 13
                            font.family: root.textFontFamily; font.weight: Font.DemiBold
                        }
                        Text {
                            renderType: Text.NativeRendering; text: root.buildBluetoothStatusText()
                            color: IslandMotion.textFaint; font.pixelSize: 10
                            font.family: root.textFontFamily
                        }
                    }
                }
            }

            // ── Game Mode card ────────────────────────────────────────
            Rectangle {
                width: parent.width; height: 56; radius: 20
                color: gamemodeHover.containsMouse ? root.moduleHover : root.moduleColor
                border.width: 1; border.color: Qt.rgba(1,1,1,0.16)
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea { id: gamemodeHover; anchors.fill: parent; hoverEnabled: true }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf11b"; font.family: root.iconFontFamily; font.pixelSize: 18
                    color: root.gamemodeActive ? "#60a5fa" : IslandMotion.textFaint
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Game Mode"
                    color: IslandMotion.textPrimary; font.pixelSize: 13
                    font.family: root.textFontFamily; font.weight: Font.DemiBold
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 9
                    text: root.gamemodeActive ? "Sidebar blacked out" : "Normal mode"
                    color: IslandMotion.textFaint; font.pixelSize: 10
                    font.family: root.textFontFamily
                }

                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 20; radius: 10
                    color: root.gamemodeActive ? StyleTokens.success : StyleTokens.switchOff
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2
                        x: root.gamemodeActive ? 16 : 2; color: "white"
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.gamemodeToggleRequested()
                    }
                }
            }

            // ── Sidebar toggle card ───────────────────────────────────
            Rectangle {
                width: parent.width; height: 56; radius: 20
                color: sidebarHover.containsMouse ? root.moduleHover : root.moduleColor
                border.width: 1; border.color: Qt.rgba(1,1,1,0.16)
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea { id: sidebarHover; anchors.fill: parent; hoverEnabled: true }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf0c9"; font.family: root.iconFontFamily; font.pixelSize: 18
                    color: root.sidebarEnabled ? StyleTokens.accent : IslandMotion.textFaint
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.top: parent.top; anchors.topMargin: 10
                    text: "Sidebar"
                    color: IslandMotion.textPrimary; font.pixelSize: 13
                    font.family: root.textFontFamily; font.weight: Font.DemiBold
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 9
                    text: "Tap to hide sidebar"
                    color: IslandMotion.textFaint; font.pixelSize: 10
                    font.family: root.textFontFamily
                }

                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 20; radius: 10
                    color: root.sidebarEnabled ? StyleTokens.success : StyleTokens.switchOff
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2
                        x: root.sidebarEnabled ? 16 : 2; color: "white"
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.close()
                            root.sidebarToggleRequested()
                        }
                    }
                }
            }

            // ── Brightness slider ─────────────────────────────────────
            SidebarSliderCard {
                id: brightnessSliderCard
                visible: !root.appearanceMenuOpen
                opacity: root.appearanceMenuOpen ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                width: parent.width; height: 76
                title: "Display"; iconText: root.brightnessGlyph
                iconFontFamily: root.iconFontFamily; textFontFamily: root.textFontFamily
                value: root.displayedBrightness
                moduleColor: root.moduleColor; moduleHover: root.moduleHover
                trackColor: root.trackColor
                textPrimary: root.textPrimary; textSecondary: root.textSecondary
                onInteractionStarted: {
                    if (root.sliderIntroPending) {
                        sliderIntroTimer.stop(); root.sliderIntroPending = false
                        root.displayedBrightness = root.localBrightness
                        root.displayedVolume = root.localVolume
                    }
                }
                onValueMoved: function(v) { root.queueBrightness(v) }
                onCommitRequested: { brightnessApplyTimer.stop(); root.flushBrightness(true) }
                onCancelRequested: SystemServices.requestBrightness()
            }

            // ── Volume slider ─────────────────────────────────────────
            SidebarSliderCard {
                id: volumeSliderCard
                visible: !root.appearanceMenuOpen
                opacity: root.appearanceMenuOpen ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                width: parent.width; height: 76
                title: "Sound"; iconText: root.volumeGlyph
                iconFontFamily: root.iconFontFamily; textFontFamily: root.textFontFamily
                value: root.displayedVolume
                moduleColor: root.moduleColor; moduleHover: root.moduleHover
                trackColor: root.trackColor
                textPrimary: root.textPrimary; textSecondary: root.textSecondary
                onInteractionStarted: {
                    if (root.sliderIntroPending) {
                        sliderIntroTimer.stop(); root.sliderIntroPending = false
                        root.displayedBrightness = root.localBrightness
                        root.displayedVolume = root.localVolume
                    }
                }
                onValueMoved: function(v) { root.queueVolume(v) }
                onCommitRequested: { volumeApplyTimer.stop(); root.flushVolume(true) }
                onCancelRequested: SystemServices.requestVolume()
            }

            // ── Appearance drawer ─────────────────────────────────────
            Item {
                id: appearanceMenuDrawer
                width: parent.width
                height: root.appearanceMenuOpen ? appearanceMenuContent.implicitHeight + 12 : 0
                clip: true
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Rectangle {
                    id: appearanceMenuContent
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: appearanceColumn.implicitHeight + 28
                    radius: 20
                    color: Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.16)

                    Column {
                        id: appearanceColumn
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 14
                        spacing: 10

                        // Header row: label + Pywal switch
                        Item {
                            width: parent.width
                            height: 24

                            Text {
                                renderType: Text.NativeRendering
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Appearance"
                                color: root.textPrimary
                                font.pixelSize: 13
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Pywal"
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                    font.family: root.textFontFamily
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34; height: 20; radius: 10
                                    color: root.capsuleUseWalColor ? StyleTokens.success : StyleTokens.switchOff
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Rectangle {
                                        width: 16; height: 16; radius: 8; y: 2
                                        x: root.capsuleUseWalColor ? 16 : 2; color: "white"
                                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.appearanceWalColorToggleRequested(!root.capsuleUseWalColor)
                                    }
                                }
                            }
                        }

                        // Preview pill
                        Rectangle {
                            width: parent.width; height: 40; radius: 14
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.15)
                            color: root.capsuleUseWalColor
                                 ? Qt.rgba(root.capsuleWalColor.r, root.capsuleWalColor.g, root.capsuleWalColor.b, root.capsuleOpacityValue)
                                 : Qt.rgba(0, 0, 0, root.capsuleOpacityValue)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: "Preview"
                                color: "white"; opacity: 0.55
                                font.pixelSize: 10; font.family: root.textFontFamily
                                font.weight: Font.Medium
                            }
                        }

                        // Pywal color swatches (only when pywal enabled)
                        Item {
                            width: parent.width
                            height: root.capsuleUseWalColor && root.capsuleWalColors.length > 0 ? 40 : 0
                            clip: true
                            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            ListView {
                                anchors.fill: parent
                                anchors.bottomMargin: 8
                                orientation: ListView.Horizontal
                                spacing: 6
                                clip: true
                                interactive: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.capsuleWalColors.length
                                readonly property real contentNaturalWidth: count > 0
                                    ? (count * 26 + Math.max(0, count - 1) * spacing) : 0
                                leftMargin:  Math.max(0, (width - contentNaturalWidth) / 2)
                                rightMargin: Math.max(0, (width - contentNaturalWidth) / 2)

                                ScrollBar.horizontal: ScrollBar {
                                    policy: ScrollBar.AsNeeded; height: 4
                                    contentItem: Rectangle { implicitHeight: 4; radius: 2; color: Qt.rgba(1,1,1,0.25) }
                                    background: Item {}
                                }

                                delegate: Rectangle {
                                    id: swatchDelegate
                                    required property int index
                                    readonly property bool isActive: root.capsuleWalColorIndex === index
                                    width: 26; height: 26; radius: 13
                                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                    color: root.capsuleWalColors[index] || "#000000"
                                    border.width: isActive ? 2 : 1
                                    border.color: isActive ? "white" : Qt.rgba(1,1,1,0.25)
                                    scale: isActive ? 1.12 : (swatchMouse.containsMouse ? 1.06 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    Text {
                                        renderType: Text.NativeRendering; anchors.centerIn: parent
                                        text: swatchDelegate.index; color: "white"
                                        font.pixelSize: 8; font.weight: Font.Bold
                                        font.family: root.textFontFamily
                                        style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.65)
                                    }

                                    MouseArea {
                                        id: swatchMouse; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.appearanceWalColorIndexRequested(swatchDelegate.index)
                                    }
                                }
                            }
                        }

                        // Opacity presets
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Repeater {
                                model: [0.20, 0.40, 0.60, 0.80, 1.0]
                                delegate: Rectangle {
                                    required property real modelData
                                    readonly property bool isActive: Math.abs(root.capsuleOpacityValue - modelData) < 0.01
                                    width: presetLbl.implicitWidth + 16; height: 26; radius: 13
                                    color: isActive ? Qt.rgba(1,1,1,0.20)
                                         : (presetMouse2.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06))
                                    border.color: isActive ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.12)
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        renderType: Text.NativeRendering
                                        id: presetLbl; anchors.centerIn: parent
                                        text: Math.round(parent.modelData * 100) + "%"
                                        color: "white"
                                        opacity: parent.isActive ? 0.95 : 0.55
                                        font.pixelSize: 10; font.family: root.textFontFamily
                                        font.weight: parent.isActive ? Font.DemiBold : Font.Medium
                                    }

                                    MouseArea {
                                        id: presetMouse2; anchors.fill: parent; hoverEnabled: true
                                        onClicked: root.appearanceOpacityRequested(parent.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Focus / Sidebar settings drawer ──────────────────────
            Item {
                id: focusSettingsDrawer
                width: parent.width
                height: root.appearanceMenuOpen ? focusSettingsContent.implicitHeight + 12 : 0
                clip: true
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Rectangle {
                    id: focusSettingsContent
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: focusSettingsColumn.implicitHeight + 28
                    radius: 20
                    color: Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.16)

                    Column {
                        id: focusSettingsColumn
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 14
                        spacing: 10

                        Item {
                            width: parent.width; height: 24

                            Text {
                                renderType: Text.NativeRendering
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: "Focus Settings"
                                color: root.textPrimary; font.pixelSize: 13
                                font.family: root.textFontFamily; font.weight: Font.DemiBold
                            }
                        }

                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            text: "Hides the island and moves widgets to the background layer. Visible on empty workspaces, hidden when windows are open."
                            color: root.textSecondary; font.pixelSize: 10
                            font.family: root.textFontFamily
                            wrapMode: Text.WordWrap; opacity: 0.7
                        }

                        // Sidebar toggle inside focus drawer
                        Item {
                            width: parent.width; height: 24

                            Text {
                                renderType: Text.NativeRendering
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: "Sidebar"
                                color: root.textPrimary; font.pixelSize: 13
                                font.family: root.textFontFamily; font.weight: Font.DemiBold
                            }

                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Show Sidebar"
                                    color: root.textSecondary; font.pixelSize: 10
                                    font.family: root.textFontFamily; font.weight: Font.Medium
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34; height: 20; radius: 10
                                    color: root.sidebarEnabled ? StyleTokens.success : StyleTokens.switchOff
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Rectangle {
                                        width: 16; height: 16; radius: 8; y: 2
                                        x: root.sidebarEnabled ? 16 : 2; color: "white"
                                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.close()
                                            root.sidebarToggleRequested()
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            text: "Shows a slim pill on the left edge of the screen with workspaces, media, notifications, and clock."
                            color: root.textSecondary; font.pixelSize: 10
                            font.family: root.textFontFamily
                            wrapMode: Text.WordWrap; opacity: 0.7
                        }
                    }
                }
            }

            Item { width: 1; height: 0 }
        }
    }
}
