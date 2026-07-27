import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import IslandBackend
import "qml/shared"

// ─────────────────────────────────────────────────────────────────────────
// Standalone wallpaper picker. Completely separate PanelWindow from the
// tide-island bar — toggling this never touches islandContainer/mainCapsule
// state in Island.qml. Opened via its own IpcHandler target
// ("wallpaper-picker"), the same pattern as the "tide" / toggleSearch IPC.
//
// Carousel-only, no text search box, no expanded grid, no tabs. Below the
// carousel is a row of color swatches; clicking one filters the carousel to
// wallpapers whose auto-extracted dominant color falls in that bucket.
// ─────────────────────────────────────────────────────────────────────────

PanelWindow {
    id: root

    // ── Public state ────────────────────────────────────────────────────
    // `screen` is expected to be supplied by whoever instantiates this
    // (see shell.qml integration snippet) — it is NOT wrapped in a
    // per-monitor Variants loop, since a single centered picker following
    // the focused monitor is what we want, not one per screen.
    property bool pickerVisible: false
    readonly property string iconFontFamily: UserConfig.iconFontFamily

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    visible: pickerVisible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: pickerVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    focusable: pickerVisible

    // Only the card itself accepts input; everywhere else on screen is
    // click-through, exactly like the island's own gesture-strip mask.
    mask: Region {
        Region {
            x: Math.floor(card.x)
            y: Math.floor(card.y)
            width: pickerVisible ? Math.ceil(card.width) : 0
            height: pickerVisible ? Math.ceil(card.height) : 0
        }
    }

    // ── IPC entry point ─────────────────────────────────────────────────
    // qs ipc -p /usr/share/tide-island call wallpaper-picker toggle
    IpcHandler {
        target: "wallpaper-picker"
        function toggle(): void {
            root.pickerVisible = !root.pickerVisible
        }
        function open(): void { root.pickerVisible = true }
        function close(): void { root.pickerVisible = false }
    }

    onPickerVisibleChanged: {
        if (pickerVisible) {
            loadAppearanceState()
            focusTimer.restart()
            if (allWallpapers.length === 0) {
                staticScanner.running = true
                videoScanner.running = true
            }
        }
    }

    // ── Appearance sync: read-only mirror of what Island.qml persists,
    // so this window's card matches the bar's actual capsule look
    // (opacity slider, pywal color toggle, gamemode) instead of a fixed
    // hardcoded color. Re-read every time the picker opens so it stays
    // current if you changed these in the control center since last use.
    property real capsuleOpacity: 0.20
    property bool capsuleUseWalColor: false
    property var capsuleWalColors: []
    property int capsuleWalColorIndex: 0
    readonly property color capsuleWalColor: (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
        ? capsuleWalColors[capsuleWalColorIndex]
        : "#000000"
    property bool gamemodeActive: false

    function loadAppearanceState() {
        appearanceLoader.running = true
        walColorLoader.running = true
        gamemodeLoader.running = true
    }

    Process {
        id: appearanceLoader
        property string _buf: ""
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell/appearance-settings.json\" 2>/dev/null"]
        stdout: SplitParser { onRead: appearanceLoader._buf += data }
        onRunningChanged: {
            if (!running) {
                const raw = appearanceLoader._buf.trim()
                appearanceLoader._buf = ""
                if (raw.length > 0) {
                    try {
                        const parsed = JSON.parse(raw)
                        if (typeof parsed.capsuleOpacity === "number")
                            root.capsuleOpacity = parsed.capsuleOpacity
                        if (typeof parsed.capsuleUseWalColor === "boolean")
                            root.capsuleUseWalColor = parsed.capsuleUseWalColor
                        if (typeof parsed.capsuleWalColorIndex === "number")
                            root.capsuleWalColorIndex = parsed.capsuleWalColorIndex
                    } catch (e) {
                        // keep defaults
                    }
                }
            }
        }
    }

    Process {
        id: walColorLoader
        property string _buf: ""
        command: ["bash", "-c", "cat \"$HOME/.cache/wal/colors\" 2>/dev/null"]
        stdout: SplitParser { onRead: walColorLoader._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const lines = walColorLoader._buf.trim().split("\n")
                walColorLoader._buf = ""
                const parsed = []
                for (let i = 0; i < lines.length; i++) {
                    const raw = lines[i].trim()
                    if (/^#?[0-9A-Fa-f]{6}$/.test(raw))
                        parsed.push(raw.startsWith("#") ? raw : ("#" + raw))
                }
                if (parsed.length > 0) {
                    root.capsuleWalColors = parsed
                    if (root.capsuleWalColorIndex >= parsed.length)
                        root.capsuleWalColorIndex = 0
                }
            }
        }
    }

    Process {
        id: gamemodeLoader
        property string _buf: ""
        command: ["bash", "-c",
            "[ -f \"$HOME/.config/ml4w/settings/gamemode-enabled\" ] && echo 1 || echo 0"]
        stdout: SplitParser { onRead: gamemodeLoader._buf += data }
        onRunningChanged: {
            if (!running) {
                root.gamemodeActive = gamemodeLoader._buf.trim() === "1"
                gamemodeLoader._buf = ""
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 0
        repeat: false
        onTriggered: carousel.forceActiveFocus()
    }

    // ── Config (mirrors WallpaperHub) ───────────────────────────────────
    readonly property string wallpaperFolder: "/home/userone/.config/ml4w/wallpapers"
    readonly property string thumbCacheDir:   "/home/userone/.cache/waypaper"
    readonly property string postCommand:     "/home/userone/.local/bin/wal-video-fix"
    readonly property string colorCacheFile:  "/home/userone/.cache/quickshell/wallpaper-colors.json"

    readonly property string awwwFlags:
        "--transition-type grow " +
        "--transition-step 90 " +
        "--transition-angle 0 " +
        "--transition-duration 2 " +
        "--transition-fps 60"

    // ── State ────────────────────────────────────────────────────────────
    property var staticWalls: []
    property var videoWalls: []
    property var allWallpapers: staticWalls.concat(videoWalls)
    property var thumbMap: ({})
    property var colorMap: ({})
    property string selectedBucket: "all"
    property string mediaFilter: "all"   // "all" | "photo" | "video"
    property var filteredWallpapers: {
        let base = allWallpapers
        if (mediaFilter === "photo") base = base.filter(p => !root.isVideo(p))
        else if (mediaFilter === "video") base = base.filter(p => root.isVideo(p))
        if (selectedBucket === "all") return base
        return base.filter(p => bucketFor(colorMap[p]) === selectedBucket)
    }

    function cycleMediaFilter() {
        const order = ["all", "photo", "video"]
        let idx = order.indexOf(mediaFilter)
        mediaFilter = order[(idx + 1) % order.length]
    }
    property string currentWallpaper: ""
    property string lastStaticWallpaper: ""

    property string _staticBuf: ""
    property string _videoBuf: ""

    function isVideo(path) {
        return /\.(mp4|mkv|webm|mov|avi|gif)$/i.test(path)
    }

    // ── Scanners ─────────────────────────────────────────────────────────
    Process {
        id: staticScanner
        command: ["bash", "-c",
            "find " + root.wallpaperFolder + " -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "-o -iname '*.webp' -o -iname '*.bmp' \\) 2>/dev/null | sort"
        ]
        stdout: SplitParser { onRead: root._staticBuf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                root.staticWalls = root._staticBuf.trim().split("\n").filter(l => l.trim() !== "")
                root._staticBuf = ""
                Qt.callLater(root.rebuildThumbMap)
            }
        }
    }

    Process {
        id: videoScanner
        command: ["bash", "-c",
            "find " + root.wallpaperFolder + " -type f " +
            "\\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' " +
            "-o -iname '*.mov' -o -iname '*.avi' -o -iname '*.gif' \\) " +
            "2>/dev/null | sort"
        ]
        stdout: SplitParser { onRead: root._videoBuf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                root.videoWalls = root._videoBuf.trim().split("\n").filter(l => l.trim() !== "")
                root._videoBuf = ""
                Qt.callLater(root.rebuildThumbMap)
            }
        }
    }

    // ── Thumbnail path resolver (same hash scheme as WallpaperHub, so it
    // reuses whatever thumbnails the main shell already generated) ───────
    Process {
        id: thumbMapProc
        property string _buf: ""
        stdout: SplitParser { onRead: thumbMapProc._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                let lines = thumbMapProc._buf.trim().split("\n").filter(l => l.trim() !== "")
                let map = {}
                for (let line of lines) {
                    let spaceIdx = line.indexOf("  ")
                    if (spaceIdx < 0) continue
                    let hash = line.substring(0, spaceIdx).trim()
                    let path = line.substring(spaceIdx + 2).trim()
                    map[path] = root.thumbCacheDir + "/" + hash + ".png"
                }
                root.thumbMap = map
                thumbMapProc._buf = ""
                root.queueMissingThumbs()
            }
        }
    }

    function rebuildThumbMap() {
        let all = root.allWallpapers
        if (all.length === 0) return
        let paths = all.map(p => JSON.stringify(p)).join(" ")
        thumbMapProc.command = [
            "bash", "-c",
            "for f in " + paths + "; do " +
            "r=$(readlink -f \"$f\"); " +
            "h=$(printf '%s' \"$r\" | md5sum | cut -d' ' -f1); " +
            "echo \"$h  $f\"; " +
            "done"
        ]
        thumbMapProc.running = true
    }

    property var missingThumbQueue: []
    property bool thumbGenBusy: false

    function queueMissingThumbs() {
        let queue = []
        for (let path of root.allWallpapers) {
            let target = root.thumbMap[path]
            if (!target || target === "") continue
            queue.push({ path: path, target: target })
        }
        root.missingThumbQueue = queue
        processNextMissingThumb()
    }

    function processNextMissingThumb() {
        if (root.thumbGenBusy) return
        if (root.missingThumbQueue.length === 0) {
            root.loadColorCache()
            return
        }
        let item = root.missingThumbQueue[0]
        root.missingThumbQueue = root.missingThumbQueue.slice(1)
        thumbGenProc.command = [
            "bash", "-c",
            "[ -f " + JSON.stringify(item.target) + " ] || " +
            "ffmpeg -y -i " + JSON.stringify(item.path) +
            " -vframes 1 -vf scale=240:-1 -f image2 " +
            JSON.stringify(item.target) + " >/dev/null 2>&1"
        ]
        root.thumbGenBusy = true
        thumbGenProc.running = true
    }

    Process {
        id: thumbGenProc
        onRunningChanged: {
            if (!running) {
                root.thumbGenBusy = false
                root.processNextMissingThumb()
            }
        }
    }

    // ── Color cache: load once, then extract only what's missing ────────
    Process {
        id: colorCacheLoader
        property string _buf: ""
        command: ["bash", "-c", "cat " + JSON.stringify(root.colorCacheFile) + " 2>/dev/null"]
        stdout: SplitParser { onRead: colorCacheLoader._buf += data }
        onRunningChanged: {
            if (!running) {
                let raw = colorCacheLoader._buf.trim()
                colorCacheLoader._buf = ""
                if (raw.length > 0) {
                    try {
                        root.colorMap = JSON.parse(raw)
                    } catch (e) {
                        root.colorMap = {}
                    }
                }
                root.queueMissingColors()
            }
        }
    }

    function loadColorCache() {
        colorCacheLoader.running = true
    }

    property var missingColorQueue: []
    property bool colorGenBusy: false

    function queueMissingColors() {
        let queue = []
        for (let path of root.allWallpapers) {
            if (root.colorMap[path]) continue
            let target = root.thumbMap[path]
            if (!target || target === "") continue
            queue.push({ path: path, target: target })
        }
        root.missingColorQueue = queue
        processNextMissingColor()
    }

    function processNextMissingColor() {
        if (root.colorGenBusy) return
        if (root.missingColorQueue.length === 0) {
            root.saveColorCacheTimer.restart()
            return
        }
        let item = root.missingColorQueue[0]
        root.missingColorQueue = root.missingColorQueue.slice(1)
        colorExtractProc.pendingPath = item.path
        colorExtractProc.command = [
            "bash", "-c",
            "convert " + JSON.stringify(item.target) + " -resize 1x1 txt:- 2>/dev/null | " +
            "tail -1 | grep -oE '#[0-9A-Fa-f]{6}' | head -1"
        ]
        root.colorGenBusy = true
        colorExtractProc.running = true
    }

    Process {
        id: colorExtractProc
        property string pendingPath: ""
        property string _buf: ""
        stdout: SplitParser { onRead: colorExtractProc._buf += data }
        onRunningChanged: {
            if (!running) {
                let hex = colorExtractProc._buf.trim()
                colorExtractProc._buf = ""
                if (hex !== "") {
                    let updated = Object.assign({}, root.colorMap)
                    updated[colorExtractProc.pendingPath] = hex
                    root.colorMap = updated
                }
                root.colorGenBusy = false
                root.processNextMissingColor()
            }
        }
    }

    Timer {
        id: saveColorCacheTimer
        interval: 300
        repeat: false
        onTriggered: colorCacheSaveExec.running = true
    }

    Process {
        id: colorCacheSaveExec
        command: ["bash", "-c",
            "mkdir -p \"$(dirname " + JSON.stringify(root.colorCacheFile) + ")\" && printf '%s' '" +
            JSON.stringify(root.colorMap) + "' > " + JSON.stringify(root.colorCacheFile)]
    }

    // ── Hex → bucket classification (HSV-based) ──────────────────────────
    function bucketFor(hex) {
        if (!hex) return "mono"
        let m = /^#?([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$/.exec(hex)
        if (!m) return "mono"
        let r = parseInt(m[1], 16) / 255
        let g = parseInt(m[2], 16) / 255
        let b = parseInt(m[3], 16) / 255
        let max = Math.max(r, g, b), min = Math.min(r, g, b)
        let v = max
        let s = max === 0 ? 0 : (max - min) / max
        if (s < 0.15 || v < 0.12) return "mono"

        let h = 0
        let d = max - min
        if (d !== 0) {
            if (max === r) h = 60 * (((g - b) / d) % 6)
            else if (max === g) h = 60 * ((b - r) / d + 2)
            else h = 60 * ((r - g) / d + 4)
        }
        if (h < 0) h += 360

        if (h < 15 || h >= 345) return "red"
        if (h < 45) return "orange"
        if (h < 70) return "yellow"
        if (h < 170) return "green"
        if (h < 255) return "blue"
        if (h < 290) return "purple"
        return "pink"
    }

    // ── Wallpaper setters ─────────────────────────────────────────────────
    Process {
        id: awwwProc
    }

    function setStaticWallpaper(path) {
        root.currentWallpaper = path
        root.lastStaticWallpaper = path
        awwwProc.command = [
            "bash", "-c",
            "pkill -x mpvpaper 2>/dev/null\n" +
            "awww img " + JSON.stringify(path) + " " + root.awwwFlags + " && " +
            root.postCommand + " " + JSON.stringify(path) + " --skip > /dev/null 2>&1"
        ]
        awwwProc.running = true
    }

    Process {
        id: mpvProc
    }

    function setVideoWallpaper(path) {
        root.currentWallpaper = path
        mpvProc.command = [
            "bash", "-c",
            "pkill -x mpvpaper 2>/dev/null\n" +
            "sleep 0.15\n" +
            "SOCKET=/tmp/ambxst_mpv_socket_ALL\n" +
            "MPV_OPTS=\"no-audio loop hwdec=auto scale=bilinear interpolation=no " +
            "video-sync=display-resample panscan=1.0 video-scale-x=1.0 " +
            "video-scale-y=1.0 load-scripts=no input-ipc-server=$SOCKET\"\n" +
            "nohup mpvpaper -o \"$MPV_OPTS\" ALL " + JSON.stringify(path) +
            " >/tmp/mpvpaper.log 2>&1 &\n" +
            root.postCommand + " " + JSON.stringify(path) + " --skip > /dev/null 2>&1 &"
        ]
        mpvProc.running = true
    }

    function applySelected() {
        if (carousel.currentIndex < 0 || carousel.currentIndex >= root.filteredWallpapers.length) return
        let path = root.filteredWallpapers[carousel.currentIndex]
        if (root.isVideo(path)) root.setVideoWallpaper(path)
        else root.setStaticWallpaper(path)
    }

    function applyRandom() {
        let list = root.filteredWallpapers
        if (list.length === 0) return
        let idx = Math.floor(Math.random() * list.length)
        carousel.currentIndex = idx
        let path = list[idx]
        if (root.isVideo(path)) root.setVideoWallpaper(path)
        else root.setStaticWallpaper(path)
    }

    // ── UI ───────────────────────────────────────────────────────────────
    readonly property int cellWidth: 340
    readonly property int cellHeight: 150
    readonly property int skew: 26
    readonly property real neighborScale: 0.74
    readonly property int carouselHeight: 220
    readonly property int swatchRowHeight: 44

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 700
        height: root.carouselHeight + root.swatchRowHeight + 20
        radius: 34
        clip: true
        color: root.gamemodeActive
            ? Qt.rgba(0, 0, 0, 1.0)
            : (root.capsuleUseWalColor
                ? Qt.rgba(root.capsuleWalColor.r, root.capsuleWalColor.g, root.capsuleWalColor.b, root.capsuleOpacity)
                : Qt.rgba(0, 0, 0, root.capsuleOpacity))
        opacity: root.pickerVisible ? 1 : 0
        scale: root.pickerVisible ? 1 : 0.96
        visible: opacity > 0.01

        border.width: IslandMotion.surfaceBorderWidth
        border.color: IslandMotion.surfaceBorderColor

        Behavior on color   { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }
        Behavior on opacity { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeOut } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeSpring } }

        FocusScope {
            id: focusScope
            anchors.fill: parent
            focus: root.pickerVisible

            Keys.onEscapePressed: root.pickerVisible = false

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                // ── Carousel ─────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: root.carouselHeight

                    Text {
                        anchors.centerIn: parent
                        visible: root.filteredWallpapers.length === 0
                        text: staticScanner.running || videoScanner.running ? "\uf110" : "\uf03e"
                        font.pixelSize: 26
                        color: "white"; opacity: 0.15

                        NumberAnimation on rotation {
                            from: 0; to: 360; duration: 900
                            loops: Animation.Infinite
                            running: staticScanner.running || videoScanner.running
                        }
                    }

                    ListView {
                        id: carousel
                        anchors.fill: parent
                        visible: root.filteredWallpapers.length > 0
                        model: root.filteredWallpapers.length
                        orientation: ListView.Horizontal
                        spacing: 16
                        clip: false
                        focus: true

                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: 260
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        preferredHighlightBegin: width / 2 - root.cellWidth / 2
                        preferredHighlightEnd: width / 2 + root.cellWidth / 2
                        snapMode: ListView.SnapToItem

                        onModelChanged: currentIndex = 0

                        Keys.onLeftPressed: if (currentIndex > 0) currentIndex--
                        Keys.onRightPressed: if (currentIndex < count - 1) currentIndex++
                        Keys.onReturnPressed: root.applySelected()
                        Keys.onTabPressed: root.cycleMediaFilter()
                        readonly property var bucketKeyOrder: ["all", "red", "orange", "yellow", "green", "blue", "purple", "pink", "mono"]
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_R) {
                                root.applyRandom()
                                event.accepted = true
                                return
                            }
                            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                                const idx = event.key - Qt.Key_1
                                if (idx < carousel.bucketKeyOrder.length) {
                                    root.selectedBucket = carousel.bucketKeyOrder[idx]
                                    event.accepted = true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            z: -1
                            onWheel: (wheel) => {
                                if (wheel.angleDelta.y > 0 && carousel.currentIndex > 0)
                                    carousel.currentIndex--
                                else if (wheel.angleDelta.y < 0 && carousel.currentIndex < carousel.count - 1)
                                    carousel.currentIndex++
                            }
                        }

                        delegate: Item {
                            id: cell
                            width: root.cellWidth
                            height: carousel.height

                            required property int index
                            property bool isCurrent: ListView.isCurrentItem
                            property string wallPath: root.filteredWallpapers[index] || ""
                            property bool isCurrentWallpaper: root.currentWallpaper === wallPath
                            property string thumbSrc: {
                                let cached = root.thumbMap[wallPath]
                                if (cached && cached !== "") return "file://" + cached
                                if (!root.isVideo(wallPath)) return "file://" + wallPath
                                return ""
                            }

                            Item {
                                id: shapeRoot
                                anchors.centerIn: parent
                                width: parent.width - 10
                                height: root.cellHeight

                                scale: cell.isCurrent ? 1.0 : root.neighborScale
                                opacity: cell.isCurrent ? 1.0 : 0.55
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 220 } }

                                Canvas {
                                    id: mask
                                    anchors.fill: parent
                                    visible: false
                                    onPaint: {
                                        let ctx = getContext("2d")
                                        ctx.reset()
                                        let s = root.skew
                                        ctx.beginPath()
                                        ctx.moveTo(s, 0)
                                        ctx.lineTo(width, 0)
                                        ctx.lineTo(width - s, height)
                                        ctx.lineTo(0, height)
                                        ctx.closePath()
                                        ctx.fillStyle = "white"
                                        ctx.fill()
                                    }
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    Component.onCompleted: requestPaint()
                                }

                                Item {
                                    anchors.fill: parent
                                    layer.enabled: true
                                    layer.effect: OpacityMask { maskSource: mask }

                                    Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.04) }

                                    Image {
                                        anchors.fill: parent
                                        source: cell.thumbSrc
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true; mipmap: true; cache: true
                                        sourceSize.width: 420
                                        sourceSize.height: 220
                                        visible: status === Image.Ready
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: Qt.rgba(1, 1, 1, 0.03)
                                        visible: cell.thumbSrc === ""
                                    }

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left; anchors.right: parent.right
                                        height: 20
                                        color: Qt.rgba(0.4, 0.9, 0.55, 0.85)
                                        visible: cell.isCurrentWallpaper
                                        Text {
                                            anchors.centerIn: parent
                                            text: "ACTIVE"
                                            color: "white"; font.pixelSize: 14
                                            font.family: root.iconFontFamily
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                // Always-on thin hairline (mugen-style), independent of
                                // the blue selection outline below which only shows on
                                // the currently active card.
                                Canvas {
                                    id: hairlineOutline
                                    anchors.fill: parent
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    Component.onCompleted: requestPaint()
                                    onPaint: {
                                        let ctx = getContext("2d")
                                        ctx.reset()
                                        let s = root.skew
                                        ctx.beginPath()
                                        ctx.moveTo(s, 0)
                                        ctx.lineTo(width, 0)
                                        ctx.lineTo(width - s, height)
                                        ctx.lineTo(0, height)
                                        ctx.closePath()
                                        ctx.lineWidth = IslandMotion.surfaceBorderWidth
                                        ctx.strokeStyle = IslandMotion.surfaceBorderColor
                                        ctx.stroke()
                                    }
                                }

                                Canvas {
                                    id: outline
                                    anchors.fill: parent
                                    property real outlineWidth: cell.isCurrent ? 2 : 0
                                    onOutlineWidthChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    Component.onCompleted: requestPaint()
                                    onPaint: {
                                        let ctx = getContext("2d")
                                        ctx.reset()
                                        if (outlineWidth <= 0) return
                                        let s = root.skew
                                        ctx.beginPath()
                                        ctx.moveTo(s, 0)
                                        ctx.lineTo(width, 0)
                                        ctx.lineTo(width - s, height)
                                        ctx.lineTo(0, height)
                                        ctx.closePath()
                                        ctx.lineWidth = outlineWidth
                                        ctx.strokeStyle = Qt.rgba(0.0, 0.66, 1.0, 0.85)
                                        ctx.stroke()
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (cell.isCurrent) root.applySelected()
                                        else carousel.currentIndex = cell.index
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Color swatches (no labels) ───────────────────────────
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: root.swatchRowHeight
                    spacing: 10

                    Repeater {
                        model: [
                            { key: "all",    color: "transparent" },
                            { key: "red",    color: "#e53935" },
                            { key: "orange", color: "#fb8c00" },
                            { key: "yellow", color: "#fdd835" },
                            { key: "green",  color: "#43a047" },
                            { key: "blue",   color: "#1e88e5" },
                            { key: "purple", color: "#8e24aa" },
                            { key: "pink",   color: "#d81b60" },
                            { key: "mono",   color: "#9e9e9e" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26; radius: 13
                            color: modelData.key === "all" ? "transparent" : modelData.color
                            border.width: root.selectedBucket === modelData.key ? 3 : 1
                            border.color: root.selectedBucket === modelData.key
                                          ? Qt.rgba(1, 1, 1, 0.95)
                                          : Qt.rgba(1, 1, 1, 0.25)
                            Behavior on border.width { NumberAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                visible: modelData.key === "all"
                                text: "\u2715"
                                color: "white"
                                opacity: 0.6
                                font.pixelSize: 10
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.selectedBucket = modelData.key
                            }
                        }
                    }
                }
            }

            // ── Random button — icon only, bottom-right corner of the card ──
            Rectangle {
                id: randomButton
                width: 30
                height: 30
                radius: 15
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                z: 10
                color: randomButtonMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
                border.color: Qt.rgba(1, 1, 1, 0.35)
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                scale: randomButtonMouse.pressed ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                Text {
                    anchors.centerIn: parent
                    text: "\uf522"
                    font.family: root.iconFontFamily
                    font.pixelSize: 13
                    color: "white"
                    opacity: 0.85
                }

                MouseArea {
                    id: randomButtonMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyRandom()
                }
            }

            // ── Media filter toggle — icon only, bottom-left corner ──────────
            // Cycles all → photo → video → all. Same cycle is triggered by
            // pressing Tab while the carousel has focus.
            Rectangle {
                id: mediaFilterButton
                width: 30
                height: 30
                radius: 15
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 16
                z: 10
                color: mediaFilterMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
                border.color: Qt.rgba(1, 1, 1, 0.35)
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                scale: mediaFilterMouse.pressed ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                Text {
                    anchors.centerIn: parent
                    text: root.mediaFilter === "photo" ? "\uf03e"
                        : root.mediaFilter === "video" ? "\uf144"
                        : "\uf00a"
                    font.family: root.iconFontFamily
                    font.pixelSize: 13
                    color: "white"
                    opacity: 0.85
                }

                MouseArea {
                    id: mediaFilterMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cycleMediaFilter()
                }
            }
        }
    }
}
