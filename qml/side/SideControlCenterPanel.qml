import QtQuick
import Quickshell.Io
import Quickshell.Bluetooth
import IslandBackend
import QtQuick.Controls
import "../controlcenter"

Item {
    id: controlCenter

    signal connectivityPanelRequested(string kind, bool open)
    signal clearNotificationHistoryRequested()
    signal notificationEntryActivated(var entry)
    signal dndToggleRequested()
    property bool dndActive: false
    signal appearanceOpacityRequested(real value)
    signal appearanceWalColorToggleRequested(bool enabled)
    signal appearanceWalColorIndexRequested(int index)
    signal pinToggleRequested()
    property bool pinned: false
    property bool appearanceMenuOpen: false
    property real capsuleOpacity: 0.20
    property bool capsuleUseWalColor: false
    property var capsuleWalColors: []
    property int capsuleWalColorIndex: 0
    readonly property color capsuleWalColor: (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
        ? capsuleWalColors[capsuleWalColorIndex]
        : "#000000"
    readonly property real appearanceMenuTotalHeight: notificationPanelTotalHeight

    readonly property var userConfig: UserConfig

    property bool showCondition: false
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property string heroFontFamily: userConfig.heroFontFamily

    // ── Panel sizing — read these from the flyout wrapper ──────────────
    readonly property real panelWidth: 320
    readonly property real panelHeight: controlCenterColumn.implicitHeight + 24

    property string currentTime: "00:00"
    property string currentDateLabel: ""
    property int batteryCapacity: 0
    property bool isCharging: false
    property real volumeLevel: -1
    property real brightnessLevel: -1
    property int sliderIntroDelay: 200
    property int currentWorkspace: 1
    property string currentTrack: ""
    property string currentArtist: ""

    property real localVolume: 0.5
    property real localBrightness: 0.5
    property real displayedVolume: 0.5
    property real displayedBrightness: 0.5
    property real pendingVolume: 0.5
    property real pendingBrightness: 0.5
    property real lastAppliedVolume: -1
    property real lastAppliedBrightness: -1
    property bool brightnessSetterRunning: false
    property bool volumeSetterRunning: false
    property bool sliderIntroPending: false
    property bool wifiPanelOpen: false
    property bool bluetoothPanelOpen: false
    property bool powerMenuOpen: false
    property bool notificationPanelOpen: false
    property var notificationHistory: []
    property int expandedNotificationIndex: -1

    onNotificationHistoryChanged: {
        if (notificationHistory.length === 0)
            expandedNotificationIndex = -1
    }
    property bool hyprsunsetActive: false

    property string wifiLocalInfoMessage: ""
    property string wifiLocalError: ""
    property string wifiPendingPasswordSsid: ""
    property string wifiPendingPasswordValue: ""

    property string bluetoothInfoMessage: ""
    property string bluetoothError: ""
    property string bluetoothPairAndConnectPath: ""
    property string bluetoothPendingSecretValue: ""
    readonly property var wifiController: WifiController
    readonly property var bluetoothPairingAgent: BluetoothPairingAgent
    readonly property var wifiNetworks: wifiController ? wifiController.networks : null

    readonly property real sliderKnobSize: 24
    readonly property color panelColor: StyleTokens.panel
    readonly property color moduleColor: StyleTokens.module
    readonly property color moduleHover: StyleTokens.moduleHover
    readonly property color trackColor: StyleTokens.track
    readonly property color textPrimary: StyleTokens.textPrimary
    readonly property color textSecondary: StyleTokens.textSecondary
    readonly property color cardAccent: StyleTokens.accent
    readonly property string wifiGlyph: ""
    readonly property string bluetoothGlyph: ""
    readonly property string chargingIconGlyph: "\uf0e7"
    readonly property string brightnessIconGlyph: "\u{F00DF}"
    readonly property string volumeIconGlyph: "\u{F057E}"

    // No battery drawer in the sidebar prototype — extra height is a
    // fixed bottom margin only.
    readonly property real controlCenterExtraHeight: 0

    readonly property real powerMenuTotalHeight: 150
    readonly property real notificationPanelTotalHeight: controlCenterColumn.implicitHeight + 24
    readonly property bool bluetoothAvailable: !!bluetoothAdapter
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property var bluetoothDeviceValues: bluetoothAdapter ? bluetoothAdapter.devices.values : []
    readonly property bool wifiSupported: wifiController ? wifiController.supported : false
    readonly property bool wifiReadOnly: wifiController ? wifiController.readOnly : true
    readonly property bool wifiAvailable: wifiController ? wifiController.available : false
    readonly property bool wifiEnabled: wifiController ? wifiController.enabled : false
    readonly property bool wifiBusy: wifiController ? wifiController.busy : false
    readonly property string wifiCurrentSsid: wifiController ? wifiController.currentSsid : ""
    readonly property string wifiInfoMessage: wifiLocalInfoMessage.length > 0
        ? wifiLocalInfoMessage
        : (wifiController ? wifiController.infoMessage : "")
    readonly property string wifiError: wifiLocalError.length > 0
        ? wifiLocalError
        : (wifiController ? wifiController.errorMessage : "")
    readonly property string wifiUnsupportedReason: wifiController ? wifiController.unsupportedReason : ""
    readonly property string wifiAvailabilityMessage: {
        if (wifiUnsupportedReason.length > 0) return wifiUnsupportedReason;
        if (wifiSupported && !wifiAvailable) return "No Wi-Fi device is available.";
        return "";
    }
    readonly property bool bluetoothEnabled: bluetoothAdapter ? bluetoothAdapter.enabled : false
    readonly property bool bluetoothBusy: bluetoothAdapter
        ? bluetoothAdapter.state === BluetoothAdapterState.Enabling
            || bluetoothAdapter.state === BluetoothAdapterState.Disabling
        : false
    readonly property bool bluetoothPairingActive: bluetoothPairingAgent ? bluetoothPairingAgent.requestActive : false
    readonly property bool hasConnectivityPrompt: wifiPendingPasswordSsid.length > 0 || bluetoothPairingActive
    readonly property string wifiStatusText: wifiController ? wifiController.statusText : "Unavailable"
    readonly property string bluetoothStatusText: buildBluetoothStatusText()

    function trimString(value) {
        if (value === undefined || value === null) return "";
        return String(value).trim();
    }

    function isConnectivityPanelOpen(kind) {
        if (kind === "wifi") return wifiPanelOpen;
        if (kind === "bluetooth") return bluetoothPanelOpen;
        return false;
    }

    function setConnectivityPanelOpen(kind, open, emitSignal) {
        if (emitSignal === undefined) emitSignal = true;
        const nextOpen = !!open;
        let changed = false;

        if (kind === "wifi") {
            changed = wifiPanelOpen !== nextOpen;
            wifiPanelOpen = nextOpen;
            if (nextOpen && showCondition && wifiController) {
                wifiController.refreshState();
                if (wifiSupported && wifiEnabled)
                    wifiController.refreshNetworks(true);
            } else if (!nextOpen) {
                wifiPendingPasswordSsid = "";
                wifiPendingPasswordValue = "";
                wifiLocalInfoMessage = "";
                wifiLocalError = "";
            }
        } else if (kind === "bluetooth") {
            changed = bluetoothPanelOpen !== nextOpen;
            bluetoothPanelOpen = nextOpen;
            if (!nextOpen) {
                bluetoothPairAndConnectPath = "";
                bluetoothPendingSecretValue = "";
                bluetoothInfoMessage = "";
                bluetoothError = "";
            }
        } else {
            return;
        }

        if (changed && emitSignal)
            connectivityPanelRequested(kind, nextOpen);
    }

    function toggleConnectivityOverlay(kind) {
        setConnectivityPanelOpen(kind, !isConnectivityPanelOpen(kind));
    }

    function closeConnectivityPanels(emitSignals) {
        if (emitSignals === undefined) emitSignals = true;
        setConnectivityPanelOpen("wifi", false, emitSignals);
        setConnectivityPanelOpen("bluetooth", false, emitSignals);
    }

    function toggleWifiEnabled() {
        wifiPendingPasswordSsid = "";
        wifiPendingPasswordValue = "";
        if (wifiController) wifiController.setEnabled(!wifiEnabled);
    }

    function toggleBluetoothEnabled() {
        if (!bluetoothAdapter) {
            bluetoothError = "No Bluetooth adapter is available.";
            return;
        }
        bluetoothError = "";
        bluetoothInfoMessage = "";
        if (bluetoothAdapter.discovering) bluetoothAdapter.discovering = false;
        bluetoothAdapter.enabled = !bluetoothAdapter.enabled;
    }

    function buildBluetoothStatusText() {
        if (!bluetoothAvailable) return "Unavailable";
        if (!bluetoothEnabled) return "Off";
        const devices = bluetoothDeviceValues || [];
        const connectedNames = [];
        for (let index = 0; index < devices.length; index++) {
            const device = devices[index];
            if (device && device.connected) {
                const nm = trimString(device.deviceName) || trimString(device.name) || trimString(device.address) || "Unknown device";
                connectedNames.push(nm);
            }
        }
        if (connectedNames.length === 1) return connectedNames[0];
        if (connectedNames.length > 1) return connectedNames[0] + " +" + (connectedNames.length - 1);
        if (bluetoothAdapter.discovering) return "Scanning";
        return bluetoothBusy ? "Working..." : "On";
    }

    function clamp01(value) { return Math.max(0, Math.min(1, value)); }

    function applyBrightnessSnapshot(value) { if (value >= 0) syncBrightnessFromLevel(value); }
    function applyVolumeSnapshot(value) { if (value >= 0) syncVolumeFromLevel(value); }

    function flushBrightness(force) {
        const nextValue = clamp01(pendingBrightness);
        if (!force && Math.abs(nextValue - lastAppliedBrightness) < 0.01) return;
        if (brightnessSetterRunning) { brightnessApplyTimer.restart(); return; }
        lastAppliedBrightness = nextValue;
        brightnessSetterRunning = true;
        SystemServices.setBrightness(nextValue);
    }

    function queueBrightness(value) {
        localBrightness = clamp01(value);
        if (showCondition && !sliderIntroPending) displayedBrightness = localBrightness;
        pendingBrightness = localBrightness;
        brightnessApplyTimer.restart();
    }

    function flushVolume(force) {
        const nextValue = clamp01(pendingVolume);
        if (!force && Math.abs(nextValue - lastAppliedVolume) < 0.01) return;
        if (volumeSetterRunning) { volumeApplyTimer.restart(); return; }
        lastAppliedVolume = nextValue;
        volumeSetterRunning = true;
        SystemServices.setVolume(nextValue);
    }

    function queueVolume(value) {
        localVolume = clamp01(value);
        if (showCondition && !sliderIntroPending) displayedVolume = localVolume;
        pendingVolume = localVolume;
        volumeApplyTimer.restart();
    }

    function syncBrightnessFromLevel(level) {
        if (level < 0) return;
        localBrightness = clamp01(level);
        if (showCondition && !sliderIntroPending) displayedBrightness = localBrightness;
        pendingBrightness = localBrightness;
        lastAppliedBrightness = localBrightness;
    }

    function syncVolumeFromLevel(level) {
        if (level < 0) return;
        localVolume = clamp01(level);
        if (showCondition && !sliderIntroPending) displayedVolume = localVolume;
        pendingVolume = localVolume;
        lastAppliedVolume = localVolume;
    }

    function syncLevelsFromProps() {
        syncBrightnessFromLevel(brightnessLevel);
        syncVolumeFromLevel(volumeLevel);
    }

    anchors.fill: parent
    anchors.margins: 12
    opacity: showCondition ? 1 : 0
    visible: opacity > 0

    onBrightnessLevelChanged: syncBrightnessFromLevel(brightnessLevel)
    onVolumeLevelChanged: syncVolumeFromLevel(volumeLevel)
    onShowConditionChanged: {
        if (showCondition) {
            syncLevelsFromProps();
            sliderIntroPending = true;
            displayedBrightness = localBrightness;
            displayedVolume = localVolume;
            sliderIntroTimer.interval = sliderIntroDelay;
            sliderIntroTimer.restart();
            if (wifiController) wifiController.refreshState();
            hyprsunsetChecker.running = true;
            if (wifiPanelOpen && wifiSupported && wifiEnabled && wifiController)
                wifiController.refreshNetworks(true);
        } else {
            sliderIntroTimer.stop();
            sliderIntroPending = false;
            displayedBrightness = localBrightness;
            displayedVolume = localVolume;
            closeConnectivityPanels();
            powerMenuOpen = false;
            notificationPanelOpen = false;
            expandedNotificationIndex = -1;
            appearanceMenuOpen = false;
        }
    }

    Component.onCompleted: {
        syncLevelsFromProps();
        displayedBrightness = localBrightness;
        displayedVolume = localVolume;
        SystemServices.requestBrightness();
        SystemServices.requestVolume();
    }

    Behavior on opacity {
        NumberAnimation { duration: showCondition ? 240 : 100; easing.type: Easing.InOutQuad }
    }
    Behavior on displayedBrightness {
        enabled: controlCenter.showCondition && !controlCenter.sliderIntroPending && !brightnessCard.pressed
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }
    Behavior on displayedVolume {
        enabled: controlCenter.showCondition && !controlCenter.sliderIntroPending && !volumeCard.pressed
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    Connections {
        target: SystemServices
        function onBrightnessSnapshotReady(value, errorString) {
            if (errorString === "") controlCenter.applyBrightnessSnapshot(value);
        }
        function onBrightnessSetFinished(value, success, errorString) {
            controlCenter.brightnessSetterRunning = false;
            if (success) controlCenter.applyBrightnessSnapshot(value);
            if (success && Math.abs(controlCenter.pendingBrightness - controlCenter.lastAppliedBrightness) >= 0.01)
                brightnessApplyTimer.restart();
        }
        function onVolumeSnapshotReady(value, muted, errorString) {
            if (errorString === "") controlCenter.applyVolumeSnapshot(value);
        }
        function onVolumeSetFinished(value, success, errorString) {
            controlCenter.volumeSetterRunning = false;
            if (success) controlCenter.applyVolumeSnapshot(value);
            if (success && Math.abs(controlCenter.pendingVolume - controlCenter.lastAppliedVolume) >= 0.01)
                volumeApplyTimer.restart();
        }
    }

    Process {
        id: powerExec
        function run(cmd) { command = ["bash", "-c", cmd]; running = true }
    }

    Process {
        id: hyprsunsetExec
        command: ["bash", "-c", "pgrep -x hyprsunset > /dev/null && pkill -x hyprsunset || hyprsunset --temperature 4500 &"]
    }

    Process {
        id: hyprsunsetChecker
        command: ["bash", "-c", "pgrep -x hyprsunset > /dev/null && echo 1 || echo 0"]
        function run() { running = true }
        stdout: SplitParser {
            onRead: (data) => { controlCenter.hyprsunsetActive = (data.trim() === "1") }
        }
    }

    Timer {
        id: hyprsunsetTimer
        interval: 2500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: hyprsunsetChecker.run()
    }

    Timer {
        id: brightnessApplyTimer
        interval: 55
        repeat: false
        onTriggered: controlCenter.flushBrightness(false)
    }

    Timer {
        id: volumeApplyTimer
        interval: 55
        repeat: false
        onTriggered: controlCenter.flushVolume(false)
    }

    Timer {
        id: sliderIntroTimer
        interval: controlCenter.sliderIntroDelay
        repeat: false
        onTriggered: {
            controlCenter.sliderIntroPending = false;
            controlCenter.displayedBrightness = controlCenter.localBrightness;
            controlCenter.displayedVolume = controlCenter.localVolume;
        }
    }

    Connections {
        target: wifiController
        function onEnabledChanged() {
            if (!controlCenter.wifiEnabled) {
                controlCenter.wifiPendingPasswordSsid = "";
                controlCenter.wifiPendingPasswordValue = "";
            }
        }
    }

    Column {
        id: controlCenterColumn
        anchors.fill: parent
        spacing: 12

        Item {
            width: parent.width
            height: 28

            Item {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 160
                height: parent.height

                Text {
                    id: timeLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: currentTime
                    color: StyleTokens.textPrimaryBright
                    font.pixelSize: 17
                    font.family: heroFontFamily
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Text {
                    text: controlCenter.chargingIconGlyph
                    color: StyleTokens.white
                    font.pixelSize: 13
                    font.family: iconFontFamily
                    visible: isCharging
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: batteryCapacity + "%"
                    color: StyleTokens.white
                    font.pixelSize: 13
                    font.family: textFontFamily
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    id: appearanceBtn
                    width: 26; height: 26; radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: appearanceBtnMouse.containsMouse || controlCenter.appearanceMenuOpen
                           ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                    border.color: controlCenter.appearanceMenuOpen ? Qt.rgba(1,1,1,0.4)
                                  : (appearanceBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.2))
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf1fc"
                        font.family: iconFontFamily
                        font.pixelSize: 13
                        color: controlCenter.appearanceMenuOpen ? StyleTokens.white : StyleTokens.textPrimary
                    }
                    MouseArea {
                        id: appearanceBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            controlCenter.appearanceMenuOpen = !controlCenter.appearanceMenuOpen
                            if (controlCenter.appearanceMenuOpen) {
                                controlCenter.powerMenuOpen = false
                                controlCenter.notificationPanelOpen = false
                            }
                        }
                    }
                }

                Rectangle {
                    id: notificationBtn
                    width: 26; height: 26; radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: notifBtnMouse.containsMouse || controlCenter.notificationPanelOpen
                           ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                    border.color: controlCenter.notificationPanelOpen ? Qt.rgba(1,1,1,0.4)
                                  : (notifBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.2))
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf0f3"
                        font.family: iconFontFamily
                        font.pixelSize: 13
                        color: controlCenter.notificationPanelOpen ? StyleTokens.white : StyleTokens.textPrimary
                    }
                    Rectangle {
                        visible: controlCenter.notificationHistory.length > 0
                        width: 14; height: 14; radius: 7
                        color: "#ff6b6b"
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -2
                        anchors.rightMargin: -2
                        Text {
                            anchors.centerIn: parent
                            text: controlCenter.notificationHistory.length > 9 ? "9+" : controlCenter.notificationHistory.length
                            color: "white"
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            font.family: textFontFamily
                        }
                    }
                    MouseArea {
                        id: notifBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            controlCenter.notificationPanelOpen = !controlCenter.notificationPanelOpen
                            if (controlCenter.notificationPanelOpen) {
                                controlCenter.powerMenuOpen = false
                                controlCenter.appearanceMenuOpen = false
                            } else {
                                controlCenter.expandedNotificationIndex = -1
                            }
                        }
                    }
                }

                Rectangle {
                    id: powerBtn
                    width: 26; height: 26; radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: powerBtnMouse.containsMouse || controlCenter.powerMenuOpen
                           ? Qt.rgba(1, 0.3, 0.3, 0.25) : Qt.rgba(1, 1, 1, 0.08)
                    border.color: controlCenter.powerMenuOpen ? "#ff6b6b"
                                  : (powerBtnMouse.containsMouse ? "#ff9999" : Qt.rgba(1,1,1,0.2))
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf011"
                        font.family: iconFontFamily
                        font.pixelSize: 13
                        color: controlCenter.powerMenuOpen ? "#ff6b6b"
                               : (powerBtnMouse.containsMouse ? "#ff9999" : StyleTokens.textPrimary)
                    }
                    MouseArea {
                        id: powerBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            controlCenter.powerMenuOpen = !controlCenter.powerMenuOpen
                            if (controlCenter.powerMenuOpen) {
                                controlCenter.notificationPanelOpen = false
                                controlCenter.appearanceMenuOpen = false
                            }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 76
            visible: !controlCenter.powerMenuOpen && !controlCenter.notificationPanelOpen && !controlCenter.appearanceMenuOpen
            opacity: (controlCenter.powerMenuOpen || controlCenter.notificationPanelOpen || controlCenter.appearanceMenuOpen) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Row {
                id: connectivityCardsRow
                anchors.fill: parent
                spacing: 10

                Rectangle {
                    id: wifiCard
                    width: (connectivityCardsRow.width - connectivityCardsRow.spacing) / 2
                    height: connectivityCardsRow.height
                    radius: 18
                    color: (wifiCardMouse.containsMouse || wifiPanelOpen) ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: (wifiCardMouse.containsMouse || wifiPanelOpen) ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)
                    Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                    MouseArea { id: wifiCardMouse; anchors.fill: parent; hoverEnabled: true }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        text: wifiGlyph
                        color: wifiEnabled ? cardAccent : StyleTokens.textDisabled
                        font.pixelSize: 16
                        font.family: iconFontFamily
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        width: 32; height: 18; radius: 9
                        color: wifiEnabled ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                        Rectangle {
                            width: 14; height: 14; radius: 7; y: 2
                            x: wifiEnabled ? 16 : 2
                            color: StyleTokens.white
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: wifiSupported && wifiAvailable && !wifiBusy
                            onClicked: controlCenter.toggleWifiEnabled()
                        }
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.bottomMargin: 7
                        height: 28

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: "Wi-Fi"
                            color: textPrimary
                            font.pixelSize: 12
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            text: wifiStatusText
                            color: StyleTokens.textMuted
                            font.pixelSize: 9
                            font.family: textFontFamily
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: controlCenter.toggleConnectivityOverlay("wifi")
                        }
                    }
                }

                Rectangle {
                    id: bluetoothCard
                    width: (connectivityCardsRow.width - connectivityCardsRow.spacing) / 2
                    height: connectivityCardsRow.height
                    radius: 18
                    color: (bluetoothCardMouse.containsMouse || bluetoothPanelOpen) ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: (bluetoothCardMouse.containsMouse || bluetoothPanelOpen) ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)
                    Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                    MouseArea { id: bluetoothCardMouse; anchors.fill: parent; hoverEnabled: true }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        text: bluetoothGlyph
                        color: bluetoothEnabled ? cardAccent : StyleTokens.textDisabled
                        font.pixelSize: 16
                        font.family: iconFontFamily
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        width: 32; height: 18; radius: 9
                        color: bluetoothEnabled ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                        Rectangle {
                            width: 14; height: 14; radius: 7; y: 2
                            x: bluetoothEnabled ? 16 : 2
                            color: StyleTokens.white
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: bluetoothAvailable && !bluetoothBusy
                            onClicked: controlCenter.toggleBluetoothEnabled()
                        }
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.bottomMargin: 7
                        height: 28

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: "Bluetooth"
                            color: textPrimary
                            font.pixelSize: 12
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            text: bluetoothStatusText
                            color: StyleTokens.textMuted
                            font.pixelSize: 9
                            font.family: textFontFamily
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: controlCenter.toggleConnectivityOverlay("bluetooth")
                        }
                    }
                }
            }
        }

        // ── Power menu (inline) ─────────────────────────────────────────
        Item {
            id: powerMenuDrawer
            width: parent.width
            height: controlCenter.powerMenuOpen ? powerMenuContent.height + 12 : 0
            clip: true
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Rectangle {
                id: powerMenuContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: powerRow.implicitHeight + 20
                radius: 18
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Flow {
                    id: powerRow
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 10

                    Repeater {
                        model: [
                            { icon: "\uf023", label: "Lock",     cmd: "pidof hyprlock || hyprlock" },
                            { icon: "\uf186", label: "Sleep",    cmd: "systemctl suspend" },
                            { icon: "\uf011", label: "Logout",   cmd: "uwsm stop" },
                            { icon: "\uf021", label: "Reboot",   cmd: "systemctl reboot" },
                            { icon: "\uf08d", label: "Shutdown", cmd: "systemctl poweroff" }
                        ]

                        delegate: Column {
                            required property var modelData
                            spacing: 4

                            Rectangle {
                                width: 40; height: 40; radius: 13
                                color: pwrItemMouse.containsMouse ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                                border.color: pwrItemMouse.containsMouse ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)
                                border.width: 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                Behavior on color { ColorAnimation { duration: 130 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: iconFontFamily
                                    font.pixelSize: 16
                                    color: StyleTokens.textPrimary
                                }
                                MouseArea {
                                    id: pwrItemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        controlCenter.powerMenuOpen = false
                                        powerExec.run(modelData.cmd)
                                    }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: StyleTokens.textMuted
                                font.pixelSize: 8
                                font.family: textFontFamily
                            }
                        }
                    }
                }
            }
        }

        // ── Notification history (inline) ───────────────────────────────
        Item {
            id: notificationPanelDrawer
            width: parent.width
            height: controlCenter.notificationPanelOpen ? notificationPanelContent.height + 12 : 0
            clip: true
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Rectangle {
                id: notificationPanelContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: notifPanelColumn.implicitHeight + 24
                radius: 18
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Column {
                    id: notifPanelColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 12
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 22

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Notifications"
                            color: controlCenter.textPrimary
                            font.pixelSize: 12
                            font.family: controlCenter.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear All"
                            visible: controlCenter.notificationHistory.length > 0
                            color: clearAllMouse.containsMouse ? "#ff6b6b" : controlCenter.textSecondary
                            font.pixelSize: 10
                            font.family: controlCenter.textFontFamily
                            MouseArea {
                                id: clearAllMouse
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                onClicked: controlCenter.clearNotificationHistoryRequested()
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: controlCenter.notificationHistory.length === 0
                        text: "No notifications yet"
                        color: controlCenter.textSecondary
                        font.pixelSize: 10
                        font.family: controlCenter.textFontFamily
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        model: Math.min(controlCenter.notificationHistory.length, 5)
                        delegate: Rectangle {
                            required property int index
                            property var entry: controlCenter.notificationHistory[index] || {}
                            width: notifPanelColumn.width
                            height: 40
                            radius: 10
                            color: Qt.rgba(1,1,1,0.05)

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: entry.appName || ""
                                    color: controlCenter.textPrimary
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    font.family: controlCenter.textFontFamily
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: entry.summary || ""
                                    color: controlCenter.textSecondary
                                    font.pixelSize: 9
                                    font.family: controlCenter.textFontFamily
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Appearance drawer (inline) ──────────────────────────────────
        Item {
            id: appearanceMenuDrawer
            width: parent.width
            height: controlCenter.appearanceMenuOpen ? appearanceMenuContent.height + 12 : 0
            clip: true
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Rectangle {
                id: appearanceMenuContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: appearanceColumn.implicitHeight + 24
                radius: 18
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Column {
                    id: appearanceColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        text: "Appearance"
                        color: controlCenter.textPrimary
                        font.pixelSize: 12
                        font.family: controlCenter.textFontFamily
                        font.weight: Font.DemiBold
                    }

                    Row {
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Pin Sidebar"
                            color: controlCenter.textSecondary
                            font.pixelSize: 10
                            font.family: controlCenter.textFontFamily
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 18; radius: 9
                            color: controlCenter.pinned ? StyleTokens.success : StyleTokens.switchOff
                            Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }
                            Rectangle {
                                width: 14; height: 14; radius: 7; y: 2
                                x: controlCenter.pinned ? 16 : 2
                                color: StyleTokens.white
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: controlCenter.pinToggleRequested()
                            }
                        }
                    }

                    Row {
                        spacing: 6

                        Repeater {
                            model: [0.20, 0.40, 0.60, 0.80, 1.0]
                            delegate: Rectangle {
                                required property real modelData
                                readonly property bool isActive: Math.abs(controlCenter.capsuleOpacity - modelData) < 0.01
                                width: presetLabel.implicitWidth + 14
                                height: 24
                                radius: 12
                                color: isActive ? Qt.rgba(1,1,1,0.20) : (presetMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06))
                                border.color: isActive ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.12)
                                border.width: 1

                                Text {
                                    id: presetLabel
                                    anchors.centerIn: parent
                                    text: Math.round(parent.modelData * 100) + "%"
                                    color: "white"
                                    opacity: parent.isActive ? 0.95 : 0.55
                                    font.pixelSize: 9
                                    font.family: controlCenter.textFontFamily
                                }
                                MouseArea {
                                    id: presetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: controlCenter.appearanceOpacityRequested(parent.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        ControlSliderCard {
            id: brightnessCard
            visible: !controlCenter.powerMenuOpen && !controlCenter.notificationPanelOpen && !controlCenter.appearanceMenuOpen
            opacity: (controlCenter.powerMenuOpen || controlCenter.notificationPanelOpen || controlCenter.appearanceMenuOpen) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            width: parent.width
            height: 68
            title: "Display"
            iconText: controlCenter.brightnessIconGlyph
            iconFontFamily: controlCenter.iconFontFamily
            textFontFamily: controlCenter.textFontFamily
            value: controlCenter.displayedBrightness
            knobSize: controlCenter.sliderKnobSize
            moduleColor: Qt.rgba(1,1,1,0.05)
            moduleHover: Qt.rgba(1,1,1,0.09)
            trackColor: controlCenter.trackColor
            textPrimary: controlCenter.textPrimary
            textSecondary: controlCenter.textSecondary

            onInteractionStarted: {
                if (controlCenter.sliderIntroPending) {
                    sliderIntroTimer.stop();
                    controlCenter.sliderIntroPending = false;
                    controlCenter.displayedBrightness = controlCenter.localBrightness;
                    controlCenter.displayedVolume = controlCenter.localVolume;
                }
            }
            onValueMoved: function(value) { controlCenter.queueBrightness(value); }
            onCommitRequested: { brightnessApplyTimer.stop(); controlCenter.flushBrightness(true); }
            onCancelRequested: SystemServices.requestBrightness()
        }

        ControlSliderCard {
            id: volumeCard
            visible: !controlCenter.powerMenuOpen && !controlCenter.notificationPanelOpen && !controlCenter.appearanceMenuOpen
            opacity: (controlCenter.powerMenuOpen || controlCenter.notificationPanelOpen || controlCenter.appearanceMenuOpen) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            width: parent.width
            height: 68
            title: "Sound"
            iconText: controlCenter.volumeIconGlyph
            iconFontFamily: controlCenter.iconFontFamily
            textFontFamily: controlCenter.textFontFamily
            value: controlCenter.displayedVolume
            knobSize: controlCenter.sliderKnobSize
            moduleColor: Qt.rgba(1,1,1,0.05)
            moduleHover: Qt.rgba(1,1,1,0.09)
            trackColor: controlCenter.trackColor
            textPrimary: controlCenter.textPrimary
            textSecondary: controlCenter.textSecondary

            onInteractionStarted: {
                if (controlCenter.sliderIntroPending) {
                    sliderIntroTimer.stop();
                    controlCenter.sliderIntroPending = false;
                    controlCenter.displayedBrightness = controlCenter.localBrightness;
                    controlCenter.displayedVolume = controlCenter.localVolume;
                }
            }
            onValueMoved: function(value) { controlCenter.queueVolume(value); }
            onCommitRequested: { volumeApplyTimer.stop(); controlCenter.flushVolume(true); }
            onCancelRequested: SystemServices.requestVolume()
        }
    }
}
