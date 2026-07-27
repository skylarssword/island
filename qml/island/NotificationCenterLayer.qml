import QtQuick
import "../shared"

// Notification center island state -- "Notifications" title, a small
// bell badge top-right, and either "No notifications" or the history
// list. Rendered inside the capsule like every other layer.
Item {
    id: root

    property string iconFontFamily: "monospace"
    property string textFontFamily: "sans-serif"
    property var notificationHistory: []
    property bool showCondition: true

    // Read by mainCapsule's height switch (case "notification_center")
    readonly property int contentHeight: 92 + Math.max(1, notificationHistory.length) * 64

    signal clearRequested()
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

    Item {
        anchors.fill: parent
        anchors.margins: 18

        Text {
            renderType: Text.NativeRendering
            id: titleText
            text: "Notifications"
            color: IslandMotion.textPrimary
            font.family: root.textFontFamily
            font.pixelSize: 18
            font.weight: Font.Medium
            anchors.top: parent.top
            anchors.left: parent.left
        }

        // Bell badge, top-right -- green when there's history, matching
        // the mockup's small circular badge.
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            width: 30; height: 30; radius: 15
            color: root.notificationHistory.length > 0
                ? Qt.rgba(0.25, 0.7, 0.45, 0.9)
                : Qt.rgba(1, 1, 1, 0.08)
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: "\uf0f3"
                font.family: root.iconFontFamily
                font.pixelSize: 14
                color: "white"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.clearRequested()
            }
        }

        // ── Empty state ──────────────────────────────────────────────
        Text {
            renderType: Text.NativeRendering
            anchors.centerIn: parent
            text: "No notifications"
            color: IslandMotion.textFaint
            font.family: root.textFontFamily
            font.pixelSize: 13
            visible: root.notificationHistory.length === 0
        }

        // ── History list ─────────────────────────────────────────────
        ListView {
            anchors.top: titleText.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 8
            clip: true
            visible: root.notificationHistory.length > 0
            model: root.notificationHistory

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 56
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: IslandMotion.surfaceBorderWidth
                border.color: IslandMotion.surfaceBorderColor

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 2

                    Text {
                        renderType: Text.NativeRendering
                        text: modelData.appName || "Notification"
                        color: IslandMotion.textFaint
                        font.pixelSize: 10
                        font.family: root.textFontFamily
                    }
                    Text {
                        renderType: Text.NativeRendering
                        text: modelData.summary || ""
                        color: IslandMotion.textPrimary
                        font.pixelSize: 12
                        font.family: root.textFontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }
        }
    }
}
