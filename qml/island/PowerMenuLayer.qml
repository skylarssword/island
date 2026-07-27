import QtQuick
import Quickshell.Io
import "../shared"

// Power menu island state: lock, logout, DND toggle, reload, power,
// and settings (opens the control panel). Rendered inside the capsule
// like every other layer (search, control_center, etc), not a popup.
Item {
    id: root

    property string iconFontFamily: "monospace"
    property string textFontFamily: "sans-serif"
    property bool dndActive: false
    property bool showCondition: true

    signal dndToggleRequested()
    signal openControlCenterRequested()
    signal closeRequested()

    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: showCondition ? IslandMotion.contentEnterDelay : 0 }
            NumberAnimation {
                duration: showCondition ? IslandMotion.contentEnterDuration : IslandMotion.contentExitDuration
                easing.type: showCondition ? IslandMotion.easeMove : IslandMotion.easeOut
            }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 22

        PowerMenuButton {
            glyph: "\uf023"
            iconFontFamily: root.iconFontFamily
            onActivated: { lockExec.running = true; root.closeRequested() }
        }

        PowerMenuButton {
            glyph: "\uf2f5"
            iconFontFamily: root.iconFontFamily
            onActivated: { logoutExec.running = true; root.closeRequested() }
        }

        PowerMenuButton {
            glyph: "\uf186"
            iconFontFamily: root.iconFontFamily
            tinted: root.dndActive
            tintColor: Qt.rgba(0.55, 0.65, 1.0, 1)
            onActivated: root.dndToggleRequested()
        }

        PowerMenuButton {
            glyph: "\uf021"
            iconFontFamily: root.iconFontFamily
            onActivated: { reloadExec.running = true; root.closeRequested() }
        }

        PowerMenuButton {
            glyph: "\uf011"
            iconFontFamily: root.iconFontFamily
            dangerHover: true
            onActivated: { powerOffExec.running = true; root.closeRequested() }
        }

        PowerMenuButton {
            glyph: "\uf013"
            iconFontFamily: root.iconFontFamily
            onActivated: { root.openControlCenterRequested() }
        }
    }

    Process { id: lockExec;     command: ["bash", "-c", "hyprlock || swaylock"] }
    Process { id: logoutExec;   command: ["bash", "-c", "hyprctl dispatch exit"] }
    // NOTE: reload behavior is environment-specific -- SIGUSR1 is a common
    // quickshell reload convention but confirm/adjust for your actual setup.
    Process { id: reloadExec;   command: ["bash", "-c", "pkill -SIGUSR1 -f quickshell"] }
    Process { id: powerOffExec; command: ["bash", "-c", "systemctl poweroff"] }
}
