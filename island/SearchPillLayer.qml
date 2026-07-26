import QtQuick
import QtQuick.Controls
import Quickshell.Io
import IslandBackend

Item {
    id: root

    property string iconFontFamily: ""
    property string textFontFamily: ""

    signal closeRequested()
    signal launchRequested(string cmd, bool isCommand)

    // ── Sizing ───────────────────────────────────────────────────────────
    // The whole thing (input row + results) now lives in ONE capsule that
    // grows in place. No separate box is rendered below it anymore.
    readonly property int inputRowHeight: 44
    readonly property int iconCellSize: 78        // was 64 — more spacing between icons
    readonly property int iconSize: 32             // was 30, scaled up slightly to match
    readonly property int gridRowCount: 2
    readonly property int gridTopMargin: 6
    readonly property int gridSideMargin: 14
    readonly property int gridBottomMargin: 12

    // Columns are driven by how many apps we actually have, capped so the
    // capsule doesn't run off-screen. Tune maxCols to taste.
    readonly property int minCols: 6
    readonly property int maxCols: 10
    readonly property int appCountForLayout: isWallpaperMode
        ? 0
        : (filteredApps.length > 0 ? filteredApps.length : allApps.length)
    readonly property int gridCols: {
        if (isWallpaperMode) return wallpaperHubLoader.item ? wallpaperHubLoader.item.gridCols : 8
        let need = Math.ceil(appCountForLayout / gridRowCount)
        return Math.max(minCols, Math.min(maxCols, need))
    }

    readonly property bool hasResults: true   // grid is now always present
    readonly property int appGridHeight: gridTopMargin + (iconCellSize * gridRowCount) + gridBottomMargin

    // Total capsule width/height the parent (mainCapsule) should bind to.
    // NOTE: explicitly reads wallpaperHubLoader.item.viewMode (even though
    // unused in the expression below) to guarantee QML's dependency tracker
    // registers viewMode as a tracked dependency — without this, switching
    // between quick/grid mode could fail to re-trigger this binding if the
    // tracker's initial evaluation happened before wallpaperHubLoader.item
    // existed, silently freezing capsuleHeight on a stale value.
    property int capsuleWidth: isWallpaperMode
        ? (wallpaperHubLoader.item
            ? (wallpaperHubLoader.item.viewMode, wallpaperHubLoader.item.capsuleWidth)
            : 700)
        : Math.max(620, gridCols * iconCellSize + gridSideMargin * 2)
    property int capsuleHeight: isWallpaperMode
        ? (wallpaperHubLoader.item
            ? (wallpaperHubLoader.item.viewMode, root.inputRowHeight + wallpaperHubLoader.item.capsuleHeight)
            : (inputRowHeight + 360))
        : (inputRowHeight + appGridHeight)

    property bool isCommandMode: false
    property var filteredApps: []
    property var allApps: []
    property var displayApps: filteredApps
    property string searchText: ""

    // ── WallpaperHub trigger ───────────────────────────────────────────
    readonly property bool isWallpaperMode: {
        let q = searchText.trim().toLowerCase()
        return q === "wallpaper"   || q === "wallpapers" ||
               q === "wp"          || q === "background"  ||
               q === "backgrounds" || q === "bg"          ||
               q.startsWith("wallpaper ") || q.startsWith("wp ")
    }
    property string _appBuf: ""
    property int selectedIndex: 0

    onIsWallpaperModeChanged: {
        if (isWallpaperMode) {
            // Outer input freezes on whatever triggered the mode (e.g. "wallpaper").
            // Focus hands off to WallpaperHub's own search box.
            wallpaperFocusTimer.restart()
        } else {
            // Coming back from wallpaper mode — clear the outer text and
            // reclaim focus/keystrokes here.
            searchInput.text = ""
            root.searchText = ""
            searchInput.forceActiveFocus()
        }
    }

    Timer {
        id: wallpaperFocusTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (wallpaperHubLoader.item) wallpaperHubLoader.item.focusInput()
        }
    }

    onSearchTextChanged: {
        selectedIndex = 0
        rebuildFiltered()
    }

    // ── App cache loader ─────────────────────────────────────────────────
    Process {
        id: appCacheLoader
        command: ["bash", "-c",
    "f=\"$HOME/.cache/quickshell/dock-apps-v2.tsv\"\n" +
    "if [ ! -f \"$f\" ]; then\n" +
    "  mkdir -p \"$(dirname \"$f\")\"\n" +
    "  find /usr/share/applications /usr/local/share/applications " +
    "\"$HOME/.local/share/applications\" \\\n" +
    "    -maxdepth 1 -name '*.desktop' 2>/dev/null | while read f2; do\n" +
    "    name=$(grep -m1 '^Name=' \"$f2\" | cut -d= -f2-)\n" +
    "    exec=$(grep -m1 '^Exec=' \"$f2\" | cut -d= -f2- | sed 's/ *%[^ ]*//g')\n" +
    "    icon=$(grep -m1 '^Icon=' \"$f2\" | cut -d= -f2-)\n" +
    "    nodisp=$(grep -m1 '^NoDisplay=' \"$f2\" | cut -d= -f2-)\n" +
    "    [ -z \"$name\" ] || [ \"$nodisp\" = \"true\" ] && continue\n" +
    "    if [ -n \"$icon\" ] && [ ! -f \"$icon\" ]; then\n" +
    "      resolved=$(find \"$HOME/.local/share/icons/kora\" \\\n" +
    "        -name \"${icon}.png\" -o -name \"${icon}.svg\" 2>/dev/null | \\\n" +
    "        grep '/apps/' | grep -v 'symbolic\\|panel' | head -1)\n" +
    "      if [ -z \"$resolved\" ]; then\n" +
    "        resolved=$(find \"$HOME/.local/share/icons\" /usr/share/icons /usr/share/pixmaps \\\n" +
    "          -name \"${icon}.png\" -o -name \"${icon}.svg\" 2>/dev/null | \\\n" +
    "          grep -v 'bes-rainbow\\|symbolic\\|panel' | head -1)\n" +
    "      fi\n" +
    "      [ -n \"$resolved\" ] && icon=\"$resolved\"\n" +
    "    fi\n" +
    "    printf '%s\\t%s\\t%s\\t\\n' \"$name\" \"$exec\" \"$icon\"\n" +
    "  done | sort -u > \"$f\"\n" +
    "fi\n" +
    "cat \"$f\""
]
        stdout: SplitParser {
            onRead: { root._appBuf += data + "\n" }
        }
        onRunningChanged: {
            if (!running) {
                let lines = root._appBuf.trim().split("\n")
                root._appBuf = ""
                let apps = []
                for (let l of lines) {
                    let parts = l.split("\t")
                    if (parts.length >= 2 && parts[0].trim() !== "") {
                        apps.push({
                            appName: parts[0].trim(),
                            appExec: parts[1].trim(),
                            appIcon: parts.length > 2 ? parts[2].trim() : "",
                            appKeys: parts.length > 3 ? parts[3].trim() : ""
                        })
                    }
                }
                root.allApps = apps.slice()
                // Default-populated: show everything immediately, no need to type first.
                root.filteredApps = apps.slice()
            }
        }
    }

    function focusInput() {
        searchInput.forceActiveFocus()
    }

    function inputHasFocus() {
        return searchInput.activeFocus || (wallpaperHubLoader.item && wallpaperHubLoader.item.inputHasFocus && wallpaperHubLoader.item.inputHasFocus())
    }

    onVisibleChanged: {
        if (visible) {
            if (root.isWallpaperMode) wallpaperFocusTimer.restart()
            else searchInput.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        appCacheLoader.running = true
        searchInput.forceActiveFocus()
    }

    function rebuildFiltered() {
        if (isWallpaperMode) {
            // Hub mode owns its own filtering entirely; nothing to do here.
            return
        }

        let q = searchText.toLowerCase().trim()
        if (q === "") {
            filteredApps = allApps.slice()
        } else {
            filteredApps = allApps.filter(a =>
                a.appName.toLowerCase().includes(q) ||
                (a.appKeys && a.appKeys.toLowerCase().includes(q))
            )
        }

        let raw = searchText.trim()
        isCommandMode = raw.length > 0 && (
            raw.startsWith("/") ||
            raw.includes(" ") ||
            (filteredApps.length === 0 && raw.length > 1)
        )
    }

    // Reclaim focus if anything inside the pill is hovered (app-search mode only —
    // wallpaper mode manages its own focus once active).
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: true
        enabled: !root.isWallpaperMode
        onEntered: searchInput.forceActiveFocus()
        onClicked: (mouse) => mouse.accepted = false
        onPressed: (mouse) => mouse.accepted = false
    }

    Column {
        id: contentColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // ── Search pill input row ───────────────────────────────────────
        Item {
            width: parent.width
            height: root.inputRowHeight

            Row {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    renderType: Text.NativeRendering
                    text: root.isCommandMode ? "\uf120" : "\uf002"
                    font.family: root.iconFontFamily
                    font.pixelSize: 14
                    color: root.isCommandMode ? "#a78bfa" : "white"
                    opacity: root.isCommandMode ? 0.9 : 0.5
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                TextInput {
                    id: searchInput
                    width: root.capsuleWidth - 60
                    height: 38
                    color: "white"
                    font.pixelSize: 14
                    font.family: root.textFontFamily
                    verticalAlignment: TextInput.AlignVCenter
                    activeFocusOnPress: true
                    clip: true
                    // Frozen/read-only once wallpaper mode has taken over —
                    // it still displays the trigger text but stops eating keys.
                    enabled: !root.isWallpaperMode

                    onTextChanged: root.searchText = text

                    Keys.onEscapePressed: root.closeRequested()
                    Keys.onReturnPressed: {
                        if (root.isCommandMode) {
                            root.launchRequested(
                                "kitty -- bash -c " + JSON.stringify(root.searchText + "; echo; read -rsp 'Press any key...' -n1"),
                                true
                            )
                        } else if (root.filteredApps.length > 0) {
                            root.launchRequested(root.filteredApps[root.selectedIndex].appExec, false)
                        }
                    }
                    Keys.onLeftPressed: {
                        if (!root.isCommandMode && root.filteredApps.length > 0)
                            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                    }
                    Keys.onRightPressed: {
                        if (!root.isCommandMode && root.filteredApps.length > 0)
                            root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + 1)
                    }
                    Keys.onUpPressed: {
                        if (!root.isCommandMode && root.filteredApps.length > 0)
                            root.selectedIndex = Math.max(0, root.selectedIndex - root.gridCols)
                    }
                    Keys.onDownPressed: {
                        if (!root.isCommandMode && root.filteredApps.length > 0)
                            root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + root.gridCols)
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search apps or run a command…"
                        color: "white"; opacity: 0.25
                        font.pixelSize: 14; font.family: root.textFontFamily
                        visible: searchInput.text.length === 0
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    text: "\uf00d"
                    font.family: root.iconFontFamily
                    font.pixelSize: 12
                    color: "white"
                    opacity: closeMouse.containsMouse ? 0.7 : 0.3
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length > 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    MouseArea {
                        id: closeMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
                    }
                }
            }
        }

        // ── Wallpaper hub (swapped in below the input row) ───────────────
        Loader {
            id: wallpaperHubLoader
            width: parent.width
            height: item ? item.height : 0
            active: root.isWallpaperMode
            visible: active
            asynchronous: false

            sourceComponent: Component {
                WallpaperHub {
                    iconFontFamily: root.iconFontFamily
                    textFontFamily: root.textFontFamily
                    onCloseRequested: root.closeRequested()
                }
            }
        }

        // ── Command mode hint (unchanged behavior, just relocated) ──────
        Item {
            width: parent.width
            height: root.appGridHeight
            visible: root.isCommandMode && !root.isWallpaperMode

            Column {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\uf120"
                    font.family: root.iconFontFamily
                    font.pixelSize: 28
                    color: "white"; opacity: 0.2
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Run in terminal"
                    color: "white"; opacity: 0.4
                    font.pixelSize: 11; font.family: root.textFontFamily
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(cmdRunLabel.implicitWidth + 32, 460)
                    height: 36; radius: 12
                    color: cmdRunMouse.containsMouse
                           ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.12)
                    Behavior on color { ColorAnimation { duration: 130 } }
                    scale: cmdRunMouse.pressed ? 0.97 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: cmdRunLabel
                        anchors.centerIn: parent
                        text: "\uf120  " + root.searchText
                        color: "white"; font.pixelSize: 13
                        font.family: "monospace"; font.weight: Font.Bold
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 430)
                    }
                    MouseArea {
                        id: cmdRunMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            root.launchRequested(
                                "kitty -- bash -c " + JSON.stringify(root.searchText + "; echo; read -rsp 'Press any key...' -n1"),
                                true
                            )
                        }
                    }
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Press Enter or click above"
                    color: "white"; opacity: 0.25
                    font.pixelSize: 9; font.family: root.textFontFamily
                }
            }
        }

        // ── App grid (always visible, no command mode, no wallpaper mode) ─
        GridView {
            id: searchGridView
            width: parent.width
            height: root.appGridHeight
            anchors.leftMargin: root.gridSideMargin
            anchors.rightMargin: root.gridSideMargin
            visible: !root.isCommandMode && !root.isWallpaperMode
            clip: true

            cellWidth: Math.floor((root.capsuleWidth - root.gridSideMargin * 2) / Math.max(1, root.gridCols))
            cellHeight: root.iconCellSize

            model: root.filteredApps.length

            interactive: true
            boundsBehavior: Flickable.StopAtBounds

            property int trackedIndex: root.selectedIndex
            onTrackedIndexChanged: {
                let row = Math.floor(trackedIndex / Math.max(1, root.gridCols))
                let rowY = row * cellHeight
                let visibleTop = contentY
                let visibleBottom = contentY + height

                if (rowY < visibleTop) {
                    contentY = rowY
                } else if (rowY + cellHeight > visibleBottom) {
                    contentY = rowY + cellHeight - height
                }
            }

            delegate: Item {
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight

                property var app: root.filteredApps[index] || {}
                property bool isSelected: root.selectedIndex === index

                // Hover/selected overlay — transparent at rest, white wash on hover.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 6
                    height: parent.height - 6
                    radius: 14
                    color: parent.isSelected
                           ? Qt.rgba(1, 1, 1, 0.16)
                           : (gridAppMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0))
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Item {
                        width: root.iconSize; height: root.iconSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        scale: parent.parent.parent.isSelected ? 1.12
                               : (gridAppMouse.containsMouse ? 1.08 : 1.0)
                        Behavior on scale {
                            NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                        }

                        Image {
                            id: gridAppIcon
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true; cache: true
                            source: app.appIcon && app.appIcon !== ""
                                    ? "file://" + app.appIcon : ""
                        }
                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: "\uf1b2"
                            font.family: root.iconFontFamily
                            font.pixelSize: root.iconSize * 0.7
                            color: "white"; opacity: 0.2
                            visible: gridAppIcon.status !== Image.Ready
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: app.appName || ""
                        color: "white"
                        opacity: parent.parent.isSelected ? 0.95 : 0.65
                        font.pixelSize: 9
                        font.family: root.textFontFamily
                        font.weight: parent.parent.isSelected ? Font.Medium : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                }

                MouseArea {
                    id: gridAppMouse
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: root.selectedIndex = index
                    onClicked: {
                        root.selectedIndex = index
                        root.launchRequested(app.appExec, false)
                    }
                }
            }
        }
    }
}
