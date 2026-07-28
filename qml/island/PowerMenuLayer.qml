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
            onActivated: { powerExec.run("pidof hyprlock || hyprlock"); root.closeRequested() }
        }

        PowerMenuButton {
            glyph: "\uf2f5"
            iconFontFamily: root.iconFontFamily
            onActivated: { powerExec.run("uwsm stop"); root.closeRequested() }
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
            // NOTE: reload behavior is environment-specific -- SIGUSR1 is a
            // common quickshell reload convention but confirm/adjust for
            // your actual setup if it doesn't reload for you.
            onActivated: { powerExec.run("pkill -SIGUSR1 -f quickshell"); root.closeRequested() }
        }

        PowerMenuButton {
            glyph: "\uf011"
            iconFontFamily: root.iconFontFamily
            dangerHover: true
            onActivated: { powerExec.run("systemctl poweroff"); root.closeRequested() }
        }

        PowerMenuButton {
            glyph: "\uf013"
            iconFontFamily: root.iconFontFamily
            onActivated: { root.openControlCenterRequested() }
        }
    }

    // Same run(cmd) pattern ControlCenterLayer's power menu already uses
    // successfully -- assigning `command` then flipping `running` on a
    // single reusable Process, rather than pre-baking one Process per
    // button and toggling `.running = true` directly on each.
    Process {
        id: powerExec
        function run(cmd) { command = ["bash", "-c", cmd]; running = true }
    }
}
