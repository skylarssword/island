import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell._Window
import Quickshell.Services.SystemTray
import "../shared"

Rectangle {
    id: root

    property bool useWalColor: false
    property color walColor: "#000000"
    property real capsuleOpacityValue: 0.20
    property bool gamemodeActive: false
    property string iconFontFamily: "monospace"
    property string textFontFamily: "sans-serif"

    property bool dndActive: false
    signal dndToggleRequested()
    signal notificationCenterRequested()
    signal powerMenuRequested()

    property bool expanded: false
    readonly property string archGlyph: "󰣇"
    readonly property string bellGlyph: "\uf0f3"
    readonly property string bellSlashGlyph: "\uf1f6"
readonly property string packageGlyph: "\uf487" // nf-fa-cube (fontawesome)
    readonly property string powerGlyph: "\uf011" // nf-fa-power_off (fontawesome, matches ControlCenterLayer)

    readonly property int glyphSlotWidth: 38
    readonly property int fixedIconPixelSize: 16 // shared size for notification + power glyphs
    readonly property int trayIconSize: 16
    readonly property int trayIconSpacing: 8
    readonly property int trayGap: 10
    readonly property int itemCount: trayRepeater.count

    readonly property int dividerWidth: 2
    readonly property int dividerHeight: 16
    readonly property color dividerColor: IslandMotion.surfaceBorderColor
    readonly property int edgePadding: 12 // breathing room on the arch side and the power side

    property int updatesCount: 0

    Process {
        id: updatesQuery
        property string _buf: ""
        command: ["bash", "-c",
            "echo $(( $(checkupdates 2>/dev/null | wc -l) + $(paru -Qum 2>/dev/null | wc -l) ))"]
        stdout: SplitParser { onRead: updatesQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                const parsed = parseInt(updatesQuery._buf.trim(), 10)
                root.updatesCount = isNaN(parsed) ? 0 : parsed
                updatesQuery._buf = ""
            }
        }
    }

Process {
        id: updatesRunner
        command: ["kitty", "-e", "bash", "-c", "~/.config/ml4w/scripts/ml4w-install-system-updates"]
        onRunningChanged: {
            if (!running) updatesQuery.running = true
        }
    }

    Timer {
        id: updatesPollTimer
        interval: 3600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!updatesQuery.running) updatesQuery.running = true
        }
    }

width: Math.max(glyphSlotWidth + edgePadding * 2, fixedRow.implicitWidth + edgePadding * 2)
    height: 38
    radius: 19
    y: 5
    clip: true

    Behavior on width {
        NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive }
    }

    color: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    Behavior on color { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }

    border.width: IslandMotion.surfaceBorderWidth
    border.color: IslandMotion.surfaceBorderColor

    // ── Reusable divider ────────────────────────────────────────────────
    component Divider: Rectangle {
        width: root.dividerWidth
        height: root.dividerHeight
        radius: root.dividerWidth / 2
        color: root.dividerColor
        anchors.verticalCenter: parent.verticalCenter
    }

    // ── Whole bubble laid out as one Row, right-anchored. Order left to
    // right: [expandable tray, revealed on arch click] · arch · | ·
    // notification · | · power. Power sits pinned to the far right edge;
    // the Row auto-collapses to just arch+notification+power when the
    // tray section's `visible` goes false (Positioners skip invisible
    // children entirely, so no manual width math needed here). ──────────
    Row {
        id: fixedRow
        anchors.right: parent.right
        anchors.rightMargin: root.edgePadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayIconSpacing

        // ── Expandable tray: updates + real tray icons ───────────────────
        Row {
            id: trayRow
            spacing: root.trayIconSpacing
            anchors.verticalCenter: parent.verticalCenter
opacity: root.expanded ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeOut } }

// ── Update count ─────────────────────────────────────────────────
            Item {
                width: updatesRow.implicitWidth
                height: root.trayIconSize
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: updatesRow
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        renderType: Text.NativeRendering
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.packageGlyph
                        font.family: root.iconFontFamily
                        font.pixelSize: root.trayIconSize
                        color: "white"
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: updatesText
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(root.updatesCount)
                        font.family: root.textFontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "white"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    z: 10
                    enabled: root.expanded
                    onClicked: updatesRunner.running = true
                }
            }

            Repeater {
                id: trayRepeater
                model: SystemTray.items

delegate: Item {
                    id: trayIconDelegate
                    width: root.trayIconSize
                    height: root.trayIconSize
                    anchors.verticalCenter: parent.verticalCenter

                    // ── Ported verbatim from the working SwipeLyricsLayer tray
                    // implementation — real popup menu with submenu support.
                    PopupWindow {
                        id: menuPopup
                        visible: false
                        color: "transparent"
                        anchor.item: trayIconDelegate
                        anchor.rect.x: -200 + trayIconDelegate.width
                        anchor.rect.y: trayIconDelegate.height + 8
                        implicitWidth: 200
                        implicitHeight: menuColumn.implicitHeight + 16

                        QsMenuOpener {
                            id: menuOpener
                            menu: modelData.hasMenu ? modelData.menu : null
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "#1e1e1e"
                            radius: 8

                            Column {
                                id: menuColumn
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 8
                                spacing: 2

                                Repeater {
                                    model: menuOpener.children ? menuOpener.children.values : []

                                    delegate: Item {
                                        id: menuItemRect
                                        width: parent.width
                                        height: modelData.isSeparator ? 0 : (28 + (submenuExpanded ? subCol.implicitHeight : 0))
                                        visible: !modelData.isSeparator
                                        clip: false
                                        property bool submenuExpanded: false

                                        Text {
                                            renderType: Text.NativeRendering
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            text: (modelData.text || "") + (modelData.hasChildren ? " ▶" : "")
                                            color: "white"
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: menuItemArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                if (modelData.hasChildren) {
                                                    menuItemRect.submenuExpanded = !menuItemRect.submenuExpanded
                                                } else {
                                                    if (modelData.triggered)
                                                        modelData.triggered()
                                                    menuPopup.visible = false
                                                }
                                            }
                                        }

                                        Column {
                                            id: subCol
                                            visible: menuItemRect.submenuExpanded && modelData.hasChildren
                                            anchors.top: parent.bottom
                                            anchors.left: parent.left
                                            width: parent.width
                                            spacing: 2

                                            QsMenuOpener {
                                                id: subMenuOpener
                                                menu: modelData.hasChildren ? modelData : null
                                            }

                                            Repeater {
                                                model: subMenuOpener.children ? subMenuOpener.children.values : []

                                                delegate: Rectangle {
                                                    width: parent.width
                                                    height: 28
                                                    color: subMenuArea.containsMouse ? "#333333" : "transparent"
                                                    radius: 4
                                                    visible: !modelData.isSeparator

                                                    Text {
                                                        renderType: Text.NativeRendering
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 16
                                                        text: modelData.text || ""
                                                        color: "white"
                                                        font.pixelSize: 12
                                                    }

                                                    MouseArea {
                                                        id: subMenuArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: {
                                                            if (modelData.triggered)
                                                                modelData.triggered()
                                                            menuPopup.visible = false
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Image {
                        id: trayIcon
                        anchors.fill: parent
                        source: {
                            const icon = modelData.icon
                            if (!icon || icon === "") return ""
                            return icon
                        }
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                        sourceSize: Qt.size(root.trayIconSize * 2, root.trayIconSize * 2)
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        visible: trayIcon.status !== Image.Ready

                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: modelData.title ? modelData.title[0] : "?"
                            color: "white"
                            font.pixelSize: root.trayIconSize - 2
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        z: 10
                        enabled: root.expanded
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            mouse.accepted = true
                            if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                                menuPopup.visible = !menuPopup.visible
                            } else if (modelData.activate) {
                                modelData.activate()
                            }
                        }
                    }
                }
            }
        }

        // ── Divider between tray section and arch — only when expanded ──
        Divider { visible: root.expanded }

        // ── Arch / CachyOS glyph — expand/collapse trigger ────────────────
        Item {
            id: archIconItem
            width: root.glyphSlotWidth
            height: root.height
            anchors.verticalCenter: parent.verticalCenter

Text {
    renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: root.archGlyph
                font.family: root.iconFontFamily
                font.pixelSize: 22
                color: "white"
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                z: 20
                onClicked: root.expanded = !root.expanded
            }
        }

        Divider {}

        // ── Notification / DND toggle — same click-to-toggle-DND behavior
        // as before, permanently visible now instead of expand-gated ──────
        Item {
            id: notificationIconItem
            width: root.glyphSlotWidth
            height: root.height
            anchors.verticalCenter: parent.verticalCenter

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: root.dndActive ? root.bellSlashGlyph : root.bellGlyph
                font.family: root.iconFontFamily
                font.pixelSize: root.fixedIconPixelSize
                color: IslandMotion.textPrimary
                scale: notificationMouse.pressed ? 0.82 : 1.0
                Behavior on scale { NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeOut } }
            }

            MouseArea {
                id: notificationMouse
                anchors.fill: parent
                anchors.margins: -4
                z: 20
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        root.dndToggleRequested()
                    else
                        root.notificationCenterRequested()
                }
            }
        }

        Divider {}

        // ── Power — pinned to the far right edge. Tokenized press-down
        // feedback only; intentionally wired to do nothing else for now ────
        Item {
            id: powerIconItem
            width: root.glyphSlotWidth
            height: root.height
            anchors.verticalCenter: parent.verticalCenter

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: root.powerGlyph
                font.family: root.iconFontFamily
                font.pixelSize: root.fixedIconPixelSize
                color: IslandMotion.textPrimary
                scale: powerMouse.pressed ? 0.82 : 1.0
                Behavior on scale { NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeOut } }
            }

            MouseArea {
                id: powerMouse
                anchors.fill: parent
                anchors.margins: -4
                z: 20
                onClicked: root.powerMenuRequested()
            }
        }
    }
}
