import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import IslandBackend
import "qml/shared"

Scope {
    id: shellRoot

    // ── Global Font Loaders ─────────────────────────────────────────────
    // Font paths are defined in qml/shared/IslandConfiguration.qml
    FontLoader { id: mainFont; source: IslandConfiguration.fontRegular }
    FontLoader { source: IslandConfiguration.fontMedium }
    FontLoader { source: IslandConfiguration.fontBold }

    readonly property bool screenRecordingActive: SystemServices.screenRecordingActive
    property bool shuttingDown: false

    readonly property var userConfig: UserConfig

    function forEachWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window)
                callback(window);
        }
    }

    function showNotificationAll(appName, summary, body) {
        shellRoot.forEachWindow((window) => {
            if (window && window.showNotification)
                window.showNotification(appName, summary, body);
        });
    }

    function anyOverviewOpen() {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.overviewPhase !== "closed")
                return true;
        }

        return false;
    }

    function prepareOverviewAll() {
        shellRoot.forEachWindow((window) => window.prepareOverview());
    }

    function cancelPreparedOverviewAll() {
        shellRoot.forEachWindow((window) => window.cancelPreparedOverview());
    }

    function openOverviewAll() {
        shellRoot.forEachWindow((window) => window.openOverview());
    }

    function closeOverviewAll() {
        shellRoot.forEachWindow((window) => window.closeOverview());
    }

    function toggleOverviewAll() {
        if (shellRoot.anyOverviewOpen())
            shellRoot.closeOverviewAll();
        else
            shellRoot.openOverviewAll();
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            shellRoot.toggleOverviewAll();
        }

        function open() {
            shellRoot.openOverviewAll();
        }

        function close() {
            shellRoot.closeOverviewAll();
        }

        function refreshWallpaperCache() {
            shellRoot.forEachWindow((window) => {
                if (window && window.prewarmWallpaperCache)
                    window.prewarmWallpaperCache();
            });
        }
    }

    GlobalShortcut {
        appid: userConfig.overviewGlobalShortcutAppid
        name: userConfig.overviewGlobalShortcutName

        onPressed: shellRoot.toggleOverviewAll()
    }

    Connections {
        target: SystemServices

        function onNotificationReceived(appName, summary, body) {
            shellRoot.showNotificationAll(appName, summary, body);
        }
    }

    Component.onDestruction: {
        shuttingDown = true;
    }

    Component.onCompleted: {
        if (mainFont.name !== "") {
            Qt.application.font.family = mainFont.name;
        }

        SystemServices.ensureSetupComplete(Quickshell.shellDir);
        SystemServices.requestScreenRecordingSnapshot();
    }

    Variants {
        id: panelVariants
        model: Quickshell.screens
        DynamicIslandWindow {
            required property var modelData
            screen: modelData
            shellRootController: shellRoot
        }
    }

    // One instance only, following whichever monitor is currently
    // focused. Toggled via `qs ipc call wallpaper-picker toggle`
    WallpaperPickerWindow {
        screen: Hyprland.focusedMonitor
            ? (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0])
            : Quickshell.screens[0]
    }
}
