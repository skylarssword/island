import QtQuick
import Quickshell.Hyprland
import "../shared"

Item {
    id: root

    property string monitorName: ""
    property int currentWorkspace: 1
    property bool useWalColor: false
    property color walColor: "#000000"
    property real capsuleOpacityValue: 0.20
    property bool gamemodeActive: false

signal dotClicked(int workspaceId)

    property bool showTitleBubble: true

    readonly property int dotSize: 8
    readonly property int pillWidth: 22
    readonly property int dotSpacing: 8
    readonly property int sidePadding: 12
readonly property int titleMaxWidth: 440
    readonly property int titlePadding: 14
    property string textFontFamily: "sans-serif"

// ── Active window title from Hyprland ────────────────────────────────
    readonly property var focusedToplevel: {
        if (!Hyprland.toplevels || !Hyprland.toplevels.values) return null
        const all = Hyprland.toplevels.values
        for (let i = 0; i < all.length; i++) {
            if (all[i].activated) return all[i]
        }
        return null
    }

    readonly property string rawTitle: focusedToplevel ? (focusedToplevel.title || "") : ""
    readonly property string rawClass: focusedToplevel && focusedToplevel.wayland
        ? (focusedToplevel.wayland.appId || "")
        : ""

    readonly property string displayTitle: {
        if (rawTitle === "") return rawClass
        // measure if it fits; we use char count heuristic: >35 chars = too long
        return rawTitle.length > 35 ? rawClass : rawTitle
    }

    readonly property var monitorWorkspaces: {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) return []
        const all = Hyprland.workspaces.values
        const filtered = root.monitorName
            ? all.filter(w => w.monitor && w.monitor.name === root.monitorName)
            : all.slice()
        return filtered.sort((a, b) => a.id - b.id)
    }

    readonly property real bubbleContentWidth: {
        const count = monitorWorkspaces.length
        if (count === 0) return 0
        const activeExtra = pillWidth - dotSize
        return sidePadding * 2
            + count * dotSize
            + activeExtra
            + (count - 1) * dotSpacing
    }

    readonly property real bubbleWidth: Math.max(70, bubbleContentWidth)

 width: bubbleWidth + (showTitleBubble && displayTitle !== "" ? 8 + titleBubble.width : 0)
    height: 38
    y: 5

    Behavior on width {
        NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeArrive }
    }

    // ── Workspace dot pill ───────────────────────────────────────────────
    Rectangle {
        id: dotPill
        width: root.bubbleWidth
        height: 38
        radius: 19

        color: root.gamemodeActive
            ? Qt.rgba(0, 0, 0, 1.0)
            : (root.useWalColor
                ? Qt.rgba(root.walColor.r, root.walColor.g, root.walColor.b, root.capsuleOpacityValue)
                : Qt.rgba(0, 0, 0, root.capsuleOpacityValue))

Behavior on color { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }

        border.width: IslandMotion.surfaceBorderWidth
        border.color: IslandMotion.surfaceBorderColor

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: root.showTitleBubble = !root.showTitleBubble
        }

        Row {
            anchors.centerIn: parent
            spacing: root.dotSpacing

            Repeater {
                model: root.monitorWorkspaces

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool isActive: modelData.id === root.currentWorkspace

                    width: isActive ? root.pillWidth : root.dotSize
                    height: root.dotSize
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: isActive ? "white" : Qt.rgba(1, 1, 1, 0.4)

                    Behavior on width { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeArrive } }
                    Behavior on color { ColorAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeMove } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: root.dotClicked(modelData.id)
                    }
                }
            }
        }
    }

    // ── Window title bubble ──────────────────────────────────────────────
    Rectangle {
        id: titleBubble
        x: dotPill.width + 8
        y: 0
        height: 38
        radius: 19
width: Math.min(root.titleMaxWidth, titleText.implicitWidth + root.titlePadding * 2)
        visible: root.showTitleBubble && root.displayTitle !== ""
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeOut }
        }

        Behavior on width {
            NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeArrive }
        }

        color: root.gamemodeActive
            ? Qt.rgba(0, 0, 0, 1.0)
            : (root.useWalColor
                ? Qt.rgba(root.walColor.r, root.walColor.g, root.walColor.b, root.capsuleOpacityValue)
                : Qt.rgba(0, 0, 0, root.capsuleOpacityValue))

        Behavior on color { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }

        border.width: IslandMotion.surfaceBorderWidth
        border.color: IslandMotion.surfaceBorderColor

Text {
    renderType: Text.NativeRendering
            id: titleText
            anchors.centerIn: parent
            width: parent.width - root.titlePadding * 2
            text: root.displayTitle
            color: "white"
            font.family: root.textFontFamily
            font.pixelSize: 16
            font.weight: Font.Bold
            font.letterSpacing: -0.35
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }
}
