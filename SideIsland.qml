import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import IslandBackend
import "."
import "qml/shared"
import "qml/side"

PanelWindow {
    id: root

    readonly property var userConfig: UserConfig
    property bool sidebarEnabled: false

    readonly property real pillWidth: 38
    readonly property real panelWidth: 320
    readonly property real edgeGap: 12
    readonly property real pillMaxHeight: 560

    property bool controlCenterOpen: false

    color: StyleTokens.transparent
    anchors { top: true; bottom: true; left: true }
    exclusiveZone: root.sidebarEnabled ? (pillWidth + edgeGap) : -1
    aboveWindows: true
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.controlCenterOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    implicitWidth: panelWidth + edgeGap * 2

    Behavior on exclusiveZone {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
    visible: sidebarEnabled

    mask: Region {
        x: Math.floor(sidePill.x)
        y: Math.floor(sidePill.y)
        width: root.sidebarEnabled ? Math.ceil(sidePill.width) : 0
        height: root.sidebarEnabled ? Math.ceil(sidePill.height) : 0
    }

    IslandClock {
        id: timeObj
    }

    // ── Sync with the "Sidebar" toggle in ControlCenterLayer ───────────
    Process {
        id: sidebarSettingsQuery
        property string _buf: ""
        command: ["bash", "-c",
            "cat \"$HOME/.cache/quickshell/appearance-settings.json\" 2>/dev/null"]
        stdout: SplitParser { onRead: sidebarSettingsQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                const raw = sidebarSettingsQuery._buf.trim()
                sidebarSettingsQuery._buf = ""
                if (raw.length > 0) {
                    try {
                        const parsed = JSON.parse(raw)
                        if (typeof parsed.sidebarEnabled === "boolean")
                            root.sidebarEnabled = parsed.sidebarEnabled
                    } catch (e) {
                        // keep last known value on parse failure
                    }
                }
            }
        }
    }

    Timer {
        interval: 400
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!sidebarSettingsQuery.running) sidebarSettingsQuery.running = true
    }

    // ── The pill IS the panel — no separate flyout item. It grows in
    // place from a narrow pill into the full control center. ──────────
    Rectangle {
        id: sidePill
        anchors.left: parent.left
        anchors.leftMargin: root.edgeGap
        anchors.verticalCenter: parent.verticalCenter
        width: root.controlCenterOpen ? root.panelWidth : root.pillWidth
        height: Math.min(parent.height - root.edgeGap * 2, root.pillMaxHeight)
        radius: 22
        color: Qt.rgba(0, 0, 0, 0.20)
        opacity: root.sidebarEnabled ? 1 : 0
        clip: true

        Behavior on width {
            NumberAnimation { duration: 340; easing.type: Easing.OutExpo }
        }
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // ── Control center content — fills the pill above the gear
        // button, fades in as the pill widens ──────────────────────
        SideControlCenterPanel {
            id: panelContent
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: gearSection.top
            showCondition: root.controlCenterOpen
            iconFontFamily: root.userConfig.iconFontFamily
            textFontFamily: root.userConfig.textFontFamily
            heroFontFamily: root.userConfig.heroFontFamily
            currentTime: timeObj.currentTime
            currentDateLabel: timeObj.currentDateLabel
            batteryCapacity: 0
            isCharging: false
            pinned: root.sidebarEnabled
            onPinToggleRequested: root.sidebarEnabled = !root.sidebarEnabled
        }

        // ── Fixed bottom section: gear icon ─────────────────────────
        Item {
            id: gearSection
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            height: 38

            Rectangle {
                id: gearBtn
                anchors.left: parent.left
                anchors.leftMargin: (root.pillWidth - width) / 2
                width: 28; height: 28; radius: 14
                color: gearMouse.containsMouse || root.controlCenterOpen
                       ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "\uf013"
                    font.family: root.userConfig.iconFontFamily
                    font.pixelSize: 13
                    color: root.controlCenterOpen ? StyleTokens.white : StyleTokens.textPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.controlCenterOpen = !root.controlCenterOpen
            }
        }
    }
}
