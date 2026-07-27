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

    property bool expanded: false
    readonly property string archGlyph: "󰣇"
    readonly property string bellGlyph: "\uf0f3"
    readonly property string bellSlashGlyph: "\uf1f6"
readonly property string packageGlyph: "\uf487" // nf-fa-cube (fontawesome)

    readonly property int glyphSlotWidth: 38
    readonly property int trayIconSize: 16
    readonly property int trayIconSpacing: 8
    readonly property int trayGap: 10
    readonly property int itemCount: trayRepeater.count

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

    readonly property real expandedTrayWidth: {
        let w = 0
        let segments = 0
        // dnd icon
        w += trayIconSize
        segments += 1
        // updates icon + count
        w += trayIconSize + 4 + updatesText.implicitWidth
        segments += 1
        // real tray icons
        if (itemCount > 0) {
            w += itemCount * trayIconSize
            segments += itemCount
        }
        return w + Math.max(0, segments - 1) * trayIconSpacing
    }

    readonly property real contentWidth: expanded
        ? glyphSlotWidth + trayGap + expandedTrayWidth + 10
        : glyphSlotWidth

width: Math.max(glyphSlotWidth, contentWidth)
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

    // ── Icons — revealed to the left of the arch glyph when expanded ──────
    Row {
        id: trayRow
        anchors.right: archIconItem.left
        anchors.rightMargin: root.expanded ? root.trayGap : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayIconSpacing
opacity: root.expanded ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeOut } }

        // ── DND toggle — always first ──────────────────────────────────
        Item {
            width: root.trayIconSize
            height: root.trayIconSize
            anchors.verticalCenter: parent.verticalCenter

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: root.dndActive ? root.bellSlashGlyph : root.bellGlyph
                font.family: root.iconFontFamily
                font.pixelSize: root.trayIconSize
                color: "white"
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                z: 10
                enabled: root.expanded
                onClicked: root.dndToggleRequested()
            }
        }

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

    // ── Arch / CachyOS glyph — permanent toggle, always visible ────────────
    Item {
        id: archIconItem
        width: root.glyphSlotWidth
        height: parent.height
        anchors.right: parent.right

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
}
