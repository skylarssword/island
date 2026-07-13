import QtQuick

Item {
    id: flyout

    // ── External wiring ──────────────────────────────────────────────
    property var anchorItem: null
property real gap: -19
    property bool open: false
    property alias panelLoader: contentLoader
    property Component panelComponent: null

    readonly property real contentWidth: contentLoader.item ? contentLoader.item.panelWidth : 320
    readonly property real contentHeight: contentLoader.item ? contentLoader.item.panelHeight : 300

    width: contentWidth
    height: contentHeight

    // Anchored directly to the button — no manual coordinate math, so
    // it can never drift regardless of panel height or window layout.
    anchors.left: anchorItem ? anchorItem.right : undefined
    anchors.leftMargin: gap
    anchors.verticalCenter: anchorItem ? anchorItem.verticalCenter : undefined

    visible: scale > 0.02
    scale: open ? 1.0 : 0.001
    opacity: open ? 1 : 0
    transformOrigin: Item.Left

    Behavior on scale {
        NumberAnimation { duration: 320; easing.type: Easing.OutQuint }
    }
    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

Rectangle {
        anchors.fill: parent
        radius: 28
        color: Qt.rgba(0, 0, 0, 0.20)
        clip: true

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: true
            sourceComponent: flyout.panelComponent
        }
    }
}
