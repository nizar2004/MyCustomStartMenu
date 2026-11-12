import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami
import "js/Utils.js" as Utils

Item {
    id: appsTab

    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 160 }
    }

    // drop any pending yes/no prompt when the popup closes. The item itself
    // stays "visible" inside the hidden window, so watch the window, not
    // the item — otherwise the prompt would still be up on reopen.
    readonly property var popupWindow: Window.window
    Connections {
        target: appsTab.popupWindow
        function onVisibleChanged() {
            var w = appsTab.popupWindow;
            if (w && !w.visible) { appsTab.pendingPower = ""; }
        }
    }

    property string filter: "all"        // "all" (first) | "pinned" | category name
    property string search: ""
    property bool detailedInfo: false
    property bool phoneMode: false       // right panel switched to phone control
    property bool notifOpen: false       // phone notifications list expanded

    // tiny toast for action feedback inside the phone panel
    property string _phoneToast: ""
    property string _phoneToastIcon: ""
    function showPhoneToast(msg, icon) {
        _phoneToastIcon = icon || "";
        _phoneToast = msg;
        phoneToastTimer.restart();
    }
    Timer {
        id: phoneToastTimer
        interval: 2200
        onTriggered: appsTab._phoneToast = ""
    }

    // the currently selected phone device (or null)
    readonly property var phoneDev: {
        var devs = DashState.phoneDevices;
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].id === DashState.phoneId) { return devs[i]; }
        }
        return null;
    }

    function sendPhoneLink() {
        var t = linkInput.text.trim();
        if (t === "") { return; }
        if (!/^https?:\/\//i.test(t)) { t = "https://" + t; }
        DashState.phoneAction("share", t);
        linkInput.text = "";
        showPhoneToast("Link sent to phone", "insert-link");
    }

    function typeOnPhone() {
        var t = typeInput.text;
        if (t === "") { return; }
        DashState.phoneAction("type", t);
        typeInput.text = "";
        showPhoneToast("Typed on your phone", "input-keyboard");
    }

    // power action waiting for a yes/no confirmation
    // "" | "logout" | "reboot" | "poweroff"
    property string pendingPower: ""

    function askPower(action) {
        pendingPower = action;
    }

    function cancelPower() {
        pendingPower = "";
    }

    function confirmPower() {
        var a = pendingPower;
        pendingPower = "";
        if (a === "logout") { DashState.logOut(); }
        else if (a === "reboot") { DashState.reboot(); }
        else if (a === "poweroff") { DashState.powerOff(); }
    }

    property var chips: []
    property var visibleApps: []
    property var sections: []

    property bool _refreshQueued: false

    // entrance animation state (replayed on every open)
    property bool entered: false
    Timer {
        id: enterTimer
        interval: 40
        onTriggered: appsTab.entered = true
    }

    // ---------------- keyboard app selector ----------------
    // navigation uses (section, position) for grid math, but the selected
    // app is tracked by its unique desktop id — tiles compare their own
    // model id against it, which is immune to binding/context quirks
    property int selSection: -1
    property int selPos: -1
    property string selAppId: ""
    property var tileMap: ({})

    function clearSel() {
        selSection = -1;
        selPos = -1;
        selAppId = "";
    }

    function setSel(s, p) {
        var secs = sections;
        if (!secs || s < 0 || s >= secs.length || !secs[s].apps) { clearSel(); return; }
        var n = secs[s].apps.length;
        if (p < 0) { p = 0; }
        if (p > n - 1) { p = n - 1; }
        selSection = s;
        selPos = p;
        selAppId = secs[s].apps[p] ? secs[s].apps[p].id : "";
        ensureSelVisible();
    }

    function registerTile(t) {
        if (t.modelData && t.modelData.id) {
            tileMap[t.modelData.id] = t;
        }
    }

    function unregisterTile(t) {
        if (t.modelData && t.modelData.id && tileMap[t.modelData.id] === t) {
            delete tileMap[t.modelData.id];
        }
    }

    // columns per row — same formula the app-grid sections use
    function gridColsNow() {
        return Math.max(1, Math.floor((sectionsCol.width + 2) / 94));
    }

    function moveSel(dir) {
        var secs = sections;
        if (!secs || secs.length === 0) { return; }
        var cols = gridColsNow();
        var s = selSection, p = selPos;
        if (s < 0 || s >= secs.length || !secs[s].apps || p < 0 || p >= secs[s].apps.length) {
            // nothing selected yet → start from the corner we came from
            if (dir === "up" || dir === "left") {
                s = secs.length - 1;
                p = secs[s].apps.length - 1;
            } else {
                s = 0;
                p = 0;
            }
        } else {
            var n = secs[s].apps.length;
            if (dir === "right") {
                if (p < n - 1) { p++; }
                else if (s < secs.length - 1) { s++; p = 0; }
            } else if (dir === "left") {
                if (p > 0) { p--; }
                else if (s > 0) { s--; p = secs[s].apps.length - 1; }
            } else if (dir === "down") {
                if (p + cols < n) { p += cols; }
                else if (s < secs.length - 1) { s++; p = 0; }
            } else { // up
                if (p - cols >= 0) { p -= cols; }
                else if (s > 0) { s--; p = secs[s].apps.length - 1; }
            }
        }
        selSection = s;
        selPos = p;
        selAppId = secs[s].apps[p] ? secs[s].apps[p].id : "";
        ensureSelVisible();
    }

    // Tab / Shift+Tab: walk the category rail without leaving the search box
    function cycleCategory(dir) {
        var n = chips.length;
        if (n === 0) { return; }
        var idx = 0;
        for (var i = 0; i < n; i++) {
            if (chips[i].key === filter) { idx = i; break; }
        }
        idx = (idx + dir + n) % n;
        filter = chips[idx].key;
        detailedInfo = false;
        search = "";
        searchField.text = "";
        clearSel();
        Qt.callLater(function() {
            if (appsTab.sections.length > 0 && appsTab.sections[0].apps.length > 0) {
                appsTab.setSel(0, 0);
            }
        });
    }

    // PageUp / PageDown: jump one viewport of tiles vertically
    function pageSel(dir) {
        if (sections.length === 0) { return; }
        if (selSection < 0) { setSel(0, 0); return; }
        var rows = Math.max(1, Math.floor(scroller.height / (overviewTileH + 2)));
        var step = Math.max(1, gridColsNow() * rows);
        for (var i = 0; i < step; i++) {
            moveSel(dir > 0 ? "down" : "up");
        }
    }

    function launchSelected() {
        var app = null;
        if (selSection >= 0 && selSection < sections.length && sections[selSection].apps) {
            app = sections[selSection].apps[selPos];
        }
        if (!app && visibleApps.length > 0) { app = visibleApps[0]; }
        if (app) { DashState.launch(app.path, app.id); }
    }

    // keep the keyboard-selected tile inside the viewport
    function ensureSelVisible() {
        var t = tileMap[selAppId];
        if (!t) { return; }
        var y = t.mapToItem(scroller.contentItem, 0, 0).y;
        var top = scroller.contentY + 4;
        var bottom = scroller.contentY + scroller.height - 4;
        if (y < top) {
            scroller.contentY = Math.max(0, y - 8);
        } else if (y + t.height > bottom) {
            var maxY = Math.max(0, scroller.contentHeight - scroller.height);
            scroller.contentY = Math.min(maxY, y + t.height - scroller.height + 8);
        }
    }

    // ---------------- pinned-tab drag reorder (Kickoff-style) ----------------
    // press a pinned tile and move: the tile lifts immediately (no hold
    // delay), a floating copy follows the pointer and the other tiles slide
    // aside in real time to open the slot under the cursor — exactly like
    // KDE's application launcher grid. Releasing inside the grid commits
    // the new order; while the pointer is outside the grid every tile
    // springs back to its original slot (Kickoff's DropArea "undo on exit").
    // Height of an Overview (pinned) tile: icon-only, so shorter than the
    // labelled grid tiles. The pin-drag maths below must use the same value.
    readonly property int overviewTileH: 78

    property bool pinDragActive: false
    property string pinDragId: ""
    property string pinDragName: ""
    property string pinDragIcon: ""
    property int pinFromIndex: -1    // slot the drag started in
    property int pinHoverIndex: -1   // slot currently opened for the tile (-1 = outside)
    property real pinBaseY: 0

    function pinCount() {
        return (sections.length > 0 && sections[0].apps) ? sections[0].apps.length : 0;
    }

    function pinIndex(id) {
        var apps = sections.length > 0 ? sections[0].apps : null;
        if (!apps) { return -1; }
        for (var i = 0; i < apps.length; i++) {
            if (apps[i].id === id) { return i; }
        }
        return -1;
    }

    function gridTileWNow() {
        var c = gridColsNow();
        return Math.max(40, Math.floor((sectionsCol.width - 2 * (c - 1)) / c));
    }

    // top-left corner of slot `idx` using the same pitch as the Flow
    // (tile width + 2 spacing, overviewTileH + 2 per row)
    function pinSlotPos(idx) {
        var cols = gridColsNow();
        var tw = gridTileWNow();
        return Qt.point((idx % cols) * (tw + 2),
                        Math.floor(idx / cols) * (overviewTileH + 2));
    }

    // displacement for tile `myIndex` while a drag is live — this is what
    // makes the grid shuffle like Kickoff: the dragged tile travels to the
    // hovered slot and everything in between slides one slot toward the
    // source, leaving an open gap at the hover position. Fed to a Translate
    // transform on each tile, so the slides are animated.
    function pinDisplacement(myIndex) {
        if (!pinDragActive || pinFromIndex < 0 || pinHoverIndex < 0) {
            return Qt.point(0, 0);
        }
        var n = pinCount();
        if (myIndex < 0 || myIndex >= n) { return Qt.point(0, 0); }
        var target = -1;
        if (myIndex === pinFromIndex) {
            target = pinHoverIndex;
        } else {
            var s = pinFromIndex, h = pinHoverIndex;
            if (s < h && myIndex > s && myIndex <= h) { target = myIndex - 1; }
            else if (h < s && myIndex >= h && myIndex < s) { target = myIndex + 1; }
        }
        if (target < 0 || target === myIndex) { return Qt.point(0, 0); }
        var a = pinSlotPos(myIndex);
        var b = pinSlotPos(target);
        return Qt.point(b.x - a.x, b.y - a.y);
    }

    // ---------------- app drag & drop (Kickoff-style) ----------------
    // Every app tile is a real system drag (DragHandler + Drag.Automatic
    // carrying the desktop file URL): press an app and move — inside the
    // widget the Pinned grid shuffles live like the KDE launcher, and if the
    // pointer leaves the grid the tiles spring back while the drag keeps
    // going, so it can be dropped on the taskbar (adds a launcher), the
    // desktop or any other window — exactly how Kickoff does it.
    property string currentDragId: ""     // app id being dragged (native drag)
    property Item currentDragTile: null   // the tile that started it

    function noteTileDrag(tile) {
        currentDragTile = tile;
        currentDragId = tile.modelData.id;
        // on the Pinned tab the shuffle arms immediately; the slot-following
        // starts with the first drag-move event over the content area
        beginPinDrag(tile);
    }

    function endTileDrag() {
        currentDragId = "";
        currentDragTile = null;
        if (pinDragActive) { endPinDrag(false); }
    }

    function beginPinDrag(tile) {
        if (filter !== "pinned" || search !== "" || pinDragActive) { return; }
        if (!tile) { return; }
        var i = pinIndex(tile.modelData.id);
        if (i < 0) { return; }
        var p = tile.mapToItem(scroller.contentItem, 0, 0);
        // y of the grid's first row (the section header sits above it)
        pinBaseY = p.y - Math.floor(i / gridColsNow()) * (overviewTileH + 2);
        pinDragId = tile.modelData.id;
        pinDragName = tile.modelData.name;
        pinDragIcon = tile.modelData.icon;
        pinFromIndex = i;
        pinHoverIndex = -1;
        pinDragActive = true;
    }

    // a native drag event over the content area — one entry point for
    // entering and moving, same idea as Kickoff's KickoffDropArea
    function nativeDragMove(drag) {
        if (currentDragId === "") { return; }
        if (!pinDragActive) { beginPinDrag(currentDragTile); }
        if (!pinDragActive) { return; }
        var c = pinDropArea.mapToItem(scroller.contentItem, drag.x, drag.y);
        updatePinDrag(c.x, c.y);
    }

    // cx/cy are the pointer position in scroller content coordinates —
    // inside the grid → open the hovered slot; outside → every tile springs
    // back (pinHoverIndex = -1), matching Kickoff's undo-on-exit
    function updatePinDrag(cx, cy) {
        if (!pinDragActive || pinFromIndex < 0) { return; }
        var n = pinCount();
        if (n < 1) { return; }
        var cols = gridColsNow();
        var tw = gridTileWNow(), th = overviewTileH;
        var idx = -1;
        var maxX = cols * (tw + 2) - 2;
        var maxY = pinBaseY + Math.ceil(n / cols) * (th + 2);
        if (cx >= -2 && cx <= maxX && cy >= pinBaseY - 6 && cy <= maxY + 6) {
            var col = Math.floor(cx / (tw + 2));
            var row = Math.floor((cy - pinBaseY) / (th + 2));
            if (col < 0) { col = 0; }
            if (col > cols - 1) { col = cols - 1; }
            if (row < 0) { row = 0; }
            var maxRow = Math.max(0, Math.floor((n - 1) / cols));
            if (row > maxRow) { row = maxRow; }
            idx = row * cols + col;
            if (idx > n - 1) { idx = n - 1; }
        }
        pinHoverIndex = idx;
    }

    // commit === false aborts the gesture (pointer left the grid, was
    // stolen, …) and leaves the pinned order untouched
    function endPinDrag(commit) {
        if (commit === undefined) { commit = true; }
        var from = pinFromIndex;
        var to = pinHoverIndex;
        var ok = commit && pinDragActive && to >= 0 && from >= 0 && to !== from;
        // clear first: the commit below recreates the tiles, and they must
        // come back with a zero displacement (they render at their new slots)
        pinDragActive = false;
        pinDragId = "";
        pinDragName = "";
        pinDragIcon = "";
        pinFromIndex = -1;
        pinHoverIndex = -1;
        if (ok) {
            var apps = sections[0].apps;
            var ids = [];
            for (var i = 0; i < apps.length; i++) { ids.push(apps[i].id); }
            var id = ids[from];
            ids.splice(from, 1);
            if (to > ids.length) { to = ids.length; }
            ids.splice(to, 0, id);
            DashState.reorderPinned(ids);
        }
    }

    // theme-driven accent, with optional user override from settings
    readonly property color accent: {
        var custom = Plasmoid.configuration.accentOverride;
        return (custom && custom.length > 0) ? custom : Kirigami.Theme.highlightColor;
    }
    readonly property color onAccent: Kirigami.Theme.highlightedTextColor

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    // Clipboard helper for the tile context menu. Qt's TextEdit.copy()
    // populates the system clipboard directly — no wl-copy/xclip needed
    // (neither is installed on every Plasma system).
    function copyToClipboard(text) {
        if (text === undefined || text === null || String(text) === "") { return; }
        clipHelper.text = String(text);
        clipHelper.selectAll();
        clipHelper.copy();
        clipHelper.text = "";
    }
    TextEdit {
        id: clipHelper
        visible: false
        width: 0
        height: 0
    }

    // single shared context menu for app tiles (Plasma's native menu —
    // a QQC2 popup inside a Plasma applet popup misbehaves on Wayland)
    property var menuApp: null

    function showTileMenu(app, anchor, pos) {
        if (!app) { return; }
        menuApp = app;
        tileMenu.visualParent = anchor;
        if (pos) { tileMenu.open(pos.x, pos.y); }
        else { tileMenu.open(); }
    }

    PlasmaExtras.Menu {
        id: tileMenu

        PlasmaExtras.MenuItem {
            text: "Launch"
            icon: "media-playback-start"
            onClicked: {
                if (appsTab.menuApp) {
                    DashState.launch(appsTab.menuApp.path, appsTab.menuApp.id);
                }
            }
        }
        PlasmaExtras.MenuItem {
            text: appsTab.menuApp && appsTab.menuApp.pinned
                  ? "Unpin from Pinned" : "Pin to Pinned"
            icon: appsTab.menuApp && appsTab.menuApp.pinned
                  ? "starred" : "non-starred"
            onClicked: {
                if (appsTab.menuApp) { DashState.togglePin(appsTab.menuApp.id); }
            }
        }
        PlasmaExtras.MenuItem {
            text: "Open Containing Folder"
            icon: "folder-open"
            onClicked: {
                if (appsTab.menuApp) { DashState.openContainingFolder(appsTab.menuApp.path); }
            }
        }
        PlasmaExtras.MenuItem {
            text: "Copy Command"
            icon: "edit-copy"
            enabled: appsTab.menuApp && appsTab.menuApp.exec !== undefined
                     && appsTab.menuApp.exec !== ""
            onClicked: {
                if (appsTab.menuApp) { appsTab.copyToClipboard(appsTab.menuApp.exec); }
            }
        }
    }

    // focus the search bar shortly after the popup is created, so typing
    // immediately goes to search
    Timer {
        id: focusTimer
        interval: 150
        repeat: false
        onTriggered: appsTab.focusSearch()
    }

    // coalesced refresh: one pass per event-loop iteration
    function refresh() {
        if (_refreshQueued) { return; }
        _refreshQueued = true;
        Qt.callLater(function() {
            _refreshQueued = false;
            doRefresh();
        });
    }

    function doRefresh() {
        // ----- rail model: All Apps first, then Pinned, then categories -----
        // rail order: Pinned first, then All Apps, then the categories.
        // NOTE: the chips' `icon` keys are looked up in customCatIcons below
        // (view-grid → all-apps.svg for Pinned, apps-grid → the 2×2 grid SVG
        // for All Apps).
        var out = [
            { key: "pinned", name: "Overview", icon: "view-grid" },
            { key: "all", name: "All Apps", icon: "apps-grid" }
        ];
        var cats = {};
        var m = DashState.appsModel;
        for (var i = 0; i < m.count; i++) {
            var a = m.get(i);
            if (!cats[a.cat]) {
                cats[a.cat] = { key: a.cat, name: a.cat, icon: a.catIcon };
            }
        }
        var names = Object.keys(cats);
        names.sort(function(x, y) {
            return Utils.catOrder(x) - Utils.catOrder(y) || x.localeCompare(y);
        });
        for (var j = 0; j < names.length; j++) { out.push(cats[names[j]]); }
        chips = out;

        // ----- visible apps -----
        var q = search.toLowerCase();
        var toks = q.split(/\s+/).filter(function(t) { return t !== ""; });
        if (toks.length === 0) { q = ""; }   // whitespace-only = empty search
        var vis = [];
        for (var k = 0; k < m.count; k++) {
            var app = m.get(k);
            if (toks.length > 0) {
                // match every word against name, generic name, keywords,
                // command and category — e.g. "browser" finds Firefox via its
                // GenericName, "ide" finds editors via Keywords
                var hay = (app.name + " " + (app.generic || "") + " "
                        + (app.keywords || "") + " " + app.exec + " "
                        + app.cat).toLowerCase();
                var hit = true;
                for (var t = 0; t < toks.length; t++) {
                    if (hay.indexOf(toks[t]) < 0) { hit = false; break; }
                }
                if (!hit) { continue; }
            } else {
                if (filter === "pinned" && !app.pinned) { continue; }
                if (filter !== "all" && filter !== "pinned" && app.cat !== filter) { continue; }
            }
            vis.push(app);
        }
        // the Pinned tab follows the user's pin order (drag to reorder there)
        if (q === "" && filter === "pinned") {
            var order = DashState.pinnedIds;
            vis.sort(function(a, b) {
                var ia = order.indexOf(a.id); if (ia < 0) { ia = 999999; }
                var ib = order.indexOf(b.id); if (ib < 0) { ib = 999999; }
                return ia - ib;
            });
        }
        visibleApps = vis;

        // ----- sections -----
        // Overview (pinned) → an icon-only grid on top plus a "Recently Used"
        // list below; search & "all" → grouped by category.
        var secs = [];
        if (q === "" && filter === "pinned") {
            secs = [{ name: "Pinned", icon: "starred", apps: vis, compact: true }];

            // recently launched apps, newest first, resolved against the model
            var recentApps = [];
            var rids = DashState.recentIds;
            for (var ri = 0; ri < rids.length; ri++) {
                for (var ci = 0; ci < m.count; ci++) {
                    var crow = m.get(ci);
                    if (crow.id === rids[ri]) { recentApps.push(crow); break; }
                }
            }
            if (recentApps.length > 0) {
                secs.push({
                    name: "Recently Used", icon: "document-open-recent",
                    apps: recentApps, type: "list"
                });
            }
        } else {
            var map = {};
            for (var s = 0; s < vis.length; s++) {
                var b = vis[s];
                if (!map[b.cat]) {
                    map[b.cat] = { name: b.cat, icon: b.catIcon, apps: [] };
                    secs.push(map[b.cat]);
                }
                map[b.cat].apps.push(b);
            }
            secs.sort(function(x, y) {
                return Utils.catOrder(x.name) - Utils.catOrder(y.name);
            });
        }
        sections = secs;
    }

    onFilterChanged: { clearSel(); refresh() }
    // Kickoff behavior: while a search is active the first result is
    // selected as soon as results update — the keyboard-selector halo sits
    // on it and Enter launches it. Clearing the search returns to the
    // plain, unselected grid. The selection is applied via Qt.callLater so
    // it lands AFTER the coalesced doRefresh() has rebuilt `sections` from
    // the new query (callLater runs callbacks in registration order, and
    // refresh() registers doRefresh first, so ordering is guaranteed).
    onSearchChanged: {
        refresh();
        if (search.trim() === "") { clearSel(); return; }
        Qt.callLater(function() {
            if (sections.length > 0 && sections[0].apps && sections[0].apps.length > 0) {
                setSel(0, 0);
            } else {
                clearSel();   // no hits → nothing to highlight
            }
        });
    }

    Component.onCompleted: {
        filter = Plasmoid.configuration.defaultCategory !== ""
                 ? Plasmoid.configuration.defaultCategory : "all";
        refresh();
        focusTimer.start();
        enterTimer.start();
    }

    Connections {
        target: DashState
        function onAppListChanged() { appsTab.refresh() }
        function onPinnedIdsChanged() { appsTab.refresh() }
        function onRecentIdsChanged() { appsTab.refresh() }
        function onResetView() {
            appsTab.filter = Plasmoid.configuration.defaultCategory !== ""
                             ? Plasmoid.configuration.defaultCategory : "all";
            appsTab.detailedInfo = false;
            appsTab.phoneMode = false;
            appsTab.notifOpen = false;
            DashState.closePhonePoll();
            DashState.closePhoneNotifs();
            appsTab.clearSel();
            searchField.text = "";
            scroller.contentY = 0;
            appsTab.refresh();
            focusTimer.restart();
            appsTab.entered = false;
            enterTimer.restart();
        }
    }

    Connections {
        target: DashState.appsModel
        function onCountChanged() { appsTab.refresh() }
    }

    // live media helpers
    readonly property var mpl: DashState.mpris.currentPlayer
    readonly property bool mediaPlaying:
        mpl !== null && mpl.playbackStatus === Mpris.PlaybackStatus.Playing

    // custom category icons: theme icon name → bundled SVG
    readonly property var customCatIcons: ({
        "applications-multimedia": "note-music.svg",
        "applications-office": "office-document.svg",
        "applications-development": "development-code.svg",
        "applications-internet": "internet-globe.svg",
        "applications-graphics": "graphics-paint.svg",
        "applications-games": "games-gamepad.svg",
        "preferences-desktop": "settings-gear.svg",
        "applications-system": "system-sliders.svg",
        "applications-other": "other-dots.svg",
        "applications-utilities": "accessories-toolbox.svg",
        "applications-education": "education-cap.svg",
        "applications-science": "science-flask.svg",
        "starred": "pinned-pin.svg",
        "view-grid": "all-apps.svg",
        "apps-grid": "apps-grid.svg"
    })

    function catIconSource(name) {
        if (customCatIcons[name] !== undefined) {
            return Qt.resolvedUrl("../icons/" + customCatIcons[name]);
        }
        return name;
    }

    // custom SVGs render optically smaller → give them a size bump
    function isCustomCatIcon(name) {
        return customCatIcons[name] !== undefined;
    }

    // opens the app that is playing the media
    function openPlayerApp() {
        var pl = appsTab.mpl;
        if (!pl) { return; }
        if (pl.canRaise) {
            pl.Raise();
            DashState.requestClose();
            return;
        }
        if (pl.desktopEntry) {
            var a = DashState.appList;
            for (var i = 0; i < a.length; i++) {
                if (a[i].id === pl.desktopEntry + ".desktop") {
                    DashState.launch(a[i].path, a[i].id);
                    return;
                }
            }
        }
    }

    // =====================================================================
    // layout: rail | apps | sidebar
    // =====================================================================
    // sits under everything, so it only catches presses on empty space —
    // any click elsewhere in the menu dismisses a pending confirmation
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: appsTab.pendingPower !== ""
        onPressed: appsTab.cancelPower()
    }

    RowLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.gridUnit * 0.6

        // ---------------------------------------------------- LEFT rail
        Item {
            Layout.preferredWidth: 50
            Layout.fillHeight: true
            opacity: appsTab.entered ? 1 : 0
            transform: Translate {
                x: appsTab.entered ? 0 : -16
                Behavior on x {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            ListView {
                id: rail
                anchors.fill: parent
                model: appsTab.chips
                spacing: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: railItem
                    required property int index
                    required property var modelData
                    readonly property bool active:
                        appsTab.filter === modelData.key && appsTab.search === ""

                    width: 50
                    height: 46

                    Rectangle {
                        id: railPill
                        anchors.fill: parent
                        anchors.leftMargin: 3
                        anchors.rightMargin: 13
                        anchors.topMargin: 5
                        anchors.bottomMargin: 5
                        radius: 11
                        color: railItem.active
                               ? Qt.alpha(appsTab.accent, 0.20)
                               : (railHover.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.07) : "transparent")
                        border.width: 1
                        border.color: railItem.active
                                      ? Qt.alpha(appsTab.accent, 0.35)
                                      : Qt.alpha(Kirigami.Theme.textColor, 0.07)
                        scale: railPress.pressed ? 0.92 : 1.0
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                        }
                    }

                    Rectangle {
                        visible: railItem.active
                        width: 3
                        height: 18
                        radius: 1.5
                        x: 0
                        anchors.verticalCenter: parent.verticalCenter
                        color: appsTab.accent
                    }

                    Kirigami.Icon {
                        anchors.centerIn: railPill
                        source: appsTab.catIconSource(railItem.modelData.icon)
                        implicitWidth: appsTab.isCustomCatIcon(railItem.modelData.icon) ? 25 : 20
                        implicitHeight: appsTab.isCustomCatIcon(railItem.modelData.icon) ? 25 : 20
                        isMask: true
                        color: railItem.active ? appsTab.accent : Kirigami.Theme.textColor
                        opacity: railItem.active ? 1 : 0.75
                    }

                    HoverHandler {
                        id: railHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        id: railPress
                        onTapped: {
                            appsTab.filter = railItem.modelData.key;
                            appsTab.detailedInfo = false;
                            searchField.text = "";
                        }
                    }

                    QQC2.ToolTip {
                        visible: railHover.hovered
                        text: railItem.modelData.name
                        delay: 450
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Layout.leftMargin: -10
            color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
        }

        // ---------------------------------------------------- MIDDLE apps
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            opacity: appsTab.entered ? 1 : 0
            transform: Translate {
                y: appsTab.entered ? 0 : 18
                Behavior on y {
                    SequentialAnimation { PauseAnimation { duration: 60 } NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                }
            }
            Behavior on opacity {
                SequentialAnimation { PauseAnimation { duration: 60 } NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            }
            spacing: Kirigami.Units.gridUnit * 0.5

            PC3.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Search apps…"
                onTextChanged: appsTab.search = text
                onAccepted: if (appsTab.pendingPower === "") { appsTab.launchSelected() }

                Keys.onPressed: (event) => {
                    var k = event.key;
                    // while a power confirmation is up it owns Enter/Esc
                    if (appsTab.pendingPower !== "") {
                        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                            appsTab.confirmPower();
                            event.accepted = true;
                            return;
                        }
                        if (k === Qt.Key_Escape) {
                            appsTab.cancelPower();
                            event.accepted = true;
                            return;
                        }
                    }
                    if (k === Qt.Key_Tab) {
                        appsTab.cycleCategory(1);
                        event.accepted = true;
                        return;
                    }
                    if (k === Qt.Key_Backtab) {
                        appsTab.cycleCategory(-1);
                        event.accepted = true;
                        return;
                    }
                    if (k === Qt.Key_PageDown) {
                        appsTab.pageSel(1);
                        event.accepted = true;
                        return;
                    }
                    if (k === Qt.Key_PageUp) {
                        appsTab.pageSel(-1);
                        event.accepted = true;
                        return;
                    }
                    if (k === Qt.Key_Down) {
                        appsTab.moveSel("down");
                        event.accepted = true;
                    } else if (k === Qt.Key_Up) {
                        appsTab.moveSel("up");
                        event.accepted = true;
                    } else if (k === Qt.Key_Right) {
                        appsTab.moveSel("right");
                        event.accepted = true;
                    } else if (k === Qt.Key_Left) {
                        appsTab.moveSel("left");
                        event.accepted = true;
                    } else if (k === Qt.Key_Home) {
                        appsTab.setSel(0, 0);
                        event.accepted = true;
                    } else if (k === Qt.Key_End) {
                        var last = appsTab.sections.length - 1;
                        if (last >= 0) {
                            appsTab.setSel(last, appsTab.sections[last].apps.length - 1);
                        }
                        event.accepted = true;
                    } else if (k === Qt.Key_Escape) {
                        // Esc walks back a level: details → selection → close
                        if (appsTab.detailedInfo) {
                            appsTab.detailedInfo = false;
                            event.accepted = true;
                        } else if (appsTab.selSection >= 0) {
                            appsTab.clearSel();
                            event.accepted = true;
                        } else {
                            DashState.requestClose();
                            event.accepted = true;
                        }
                    }
                }

                leftPadding: 36

                Kirigami.Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    source: "edit-find"
                    implicitWidth: 16
                    implicitHeight: 16
                    opacity: 0.6
                }

                PC3.ToolButton {
                    visible: searchField.text.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    icon.name: "edit-clear-all"
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: searchField.clear()
                }
            }

            Flickable {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.rightMargin: -20
                clip: true
                contentWidth: width
                contentHeight: sectionsCol.height
                boundsBehavior: Flickable.StopAtBounds
                // Pointer FLICKING stays off: every drag on a tile must be a
                // pure app-drag (to the taskbar or inside the Pinned grid)
                // instead of a fight with the Flickable, and clicks stay
                // reliable (wobble ≤ drag threshold = launch).
                // CAVEAT: in Qt 6 `interactive: false` also kills the
                // Flickable's OWN wheel/touchpad scrolling (see
                // QQuickFlickable::wheelEvent — it bails when !interactive),
                // so the WheelHandler below scrolls contentY by hand.
                interactive: false

                QQC2.ScrollBar.vertical: PC3.ScrollBar { }

                // Scroll the app grid with a mouse wheel or a two-finger
                // touchpad gesture. WheelHandler defaults to Mouse only
                // (its ctor sets acceptedDevices = Mouse), so TouchPad must
                // be added explicitly or touchpad scrolling is dropped.
                // pixelDelta (touchpad / high-resolution wheel) gives the
                // smooth native glide; a clicky mouse wheel only reports
                // angleDelta, so fall back to a fixed step per notch.
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        // 72px/notch = Qt's own default (wheelScrollLines 3 × 24)
                        var dy = (event.pixelDelta && event.pixelDelta.y !== 0)
                               ? event.pixelDelta.y
                               : (event.angleDelta.y / 120) * 72;
                        var maxY = Math.max(0, scroller.contentHeight - scroller.height);
                        scroller.contentY = Math.max(0, Math.min(maxY, scroller.contentY - dy));
                        event.accepted = true;
                    }
                }

                Column {
                    id: sectionsCol
                    width: scroller.width - 20
                    spacing: 14

                    // empty state
                    ColumnLayout {
                        visible: appsTab.sections.length === 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10

                        Item { height: 12 }
                        Kirigami.Icon {
                            Layout.alignment: Qt.AlignHCenter
                            source: appsTab.filter === "pinned" ? "starred" : "edit-find"
                            implicitWidth: 42
                            implicitHeight: 42
                            opacity: 0.35
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: appsTab.filter === "pinned" ? "Nothing pinned yet" : "No apps found"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.75)
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: appsTab.filter === "pinned"
                                  ? "Open All Apps, hover any app and tap the ☆ to pin it here"
                                  : "Try a different search term"
                            font.pixelSize: 11
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.45)
                        }
                    }

                    Repeater {
                        model: appsTab.sections

                        delegate: Column {
                            id: section
                            required property int index
                            required property var modelData
                            width: parent.width

                            // number of app columns that fit, and the tile width
                            // that makes the grid span the full column exactly
                            readonly property int gridCols:
                                Math.max(1, Math.floor((width + 2) / 94))
                            readonly property int gridTileWidth:
                                Math.floor((width - 2 * (gridCols - 1)) / gridCols)

                            // "list" sections (Recently Used) render rows;
                            // "compact" sections (Overview) show icon-only tiles
                            readonly property bool isList: section.modelData.type === "list"
                            readonly property bool compact: section.modelData.compact === true

                            Row {
                                width: parent.width
                                height: 28
                                spacing: 8

                                Kirigami.Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: appsTab.catIconSource(section.modelData.icon)
                                    implicitWidth: appsTab.isCustomCatIcon(section.modelData.icon) ? 19 : 16
                                    implicitHeight: appsTab.isCustomCatIcon(section.modelData.icon) ? 19 : 16
                                    isMask: true
                                    color: Kirigami.Theme.textColor
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: section.modelData.name
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: countLabel.implicitWidth + 14
                                    implicitHeight: 17
                                    radius: 8.5
                                    color: Qt.alpha(appsTab.accent, 0.18)
                                    Text {
                                        id: countLabel
                                        anchors.centerIn: parent
                                        text: section.modelData.apps.length
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: appsTab.accent
                                    }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - x - 22
                                    height: 1
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                                }
                            }

                            // nothing pinned yet → short hint (Overview tab)
                            Text {
                                visible: section.compact && !section.isList
                                         && section.modelData.apps.length === 0
                                width: parent.width
                                text: "Nothing pinned yet — open All Apps, hover an app "
                                      + "and tap the ☆ to pin it here"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.45)
                            }

                            Flow {
                                visible: !section.isList
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: section.modelData.apps

                                    delegate: AppTile {
                                        tab: appsTab
                                        tileW: section.gridTileWidth
                                        compact: section.compact
                                        tileH: section.compact ? appsTab.overviewTileH : 100
                                    }
                                }
                            }

                            // list body (Recently Used)
                            Column {
                                visible: section.isList
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: section.modelData.apps

                                    delegate: RecentRow {
                                        tab: appsTab
                                    }
                                }
                            }
                        }
                    }
                }

                // receives the native drag events while an app tile is being
                // dragged — the same mechanism as Kickoff's KickoffDropArea:
                // moving over the grid drives the Pinned-tab live shuffle,
                // leaving the area undoes every move (tiles spring back) and
                // lets the pointer carry the drag out to the taskbar, desktop
                // or any window that accepts the app's URL
                DropArea {
                    id: pinDropArea
                    x: 0
                    y: 0
                    width: scroller.contentWidth
                    height: scroller.contentHeight
                    enabled: appsTab.currentDragId !== ""
                    onEntered: drag => appsTab.nativeDragMove(drag)
                    onPositionChanged: drag => appsTab.nativeDragMove(drag)
                    onExited: {
                        if (appsTab.currentDragId !== "") { appsTab.endPinDrag(false) }
                    }
                    onDropped: drag => {
                        if (appsTab.currentDragId !== "") { appsTab.endPinDrag(true) }
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Layout.leftMargin: 20
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
        }

        // ---------------------------------------------------- RIGHT sidebar
        Item {
            Layout.preferredWidth: 232
            Layout.fillHeight: true
            opacity: appsTab.entered ? 1 : 0
            transform: Translate {
                x: appsTab.entered ? 0 : 16
                Behavior on x {
                    SequentialAnimation { PauseAnimation { duration: 110 } NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }
            Behavior on opacity {
                SequentialAnimation { PauseAnimation { duration: 110 } NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            }

            // ---------- main sidebar ----------
            ColumnLayout {
                anchors.fill: parent
                visible: !appsTab.detailedInfo && !appsTab.phoneMode
                opacity: (appsTab.detailedInfo || appsTab.phoneMode) ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: 160 }
                }
                spacing: Kirigami.Units.gridUnit * 0.55

                // big user avatar
                Item {
                    visible: Plasmoid.configuration.showUserCard
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 68
                    Layout.preferredHeight: 68
                    opacity: appsTab.entered ? 1 : 0
                    transform: Translate {
                        y: appsTab.entered ? 0 : 12
                        Behavior on y {
                            SequentialAnimation { PauseAnimation { duration: 140 } NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        }
                    }
                    Behavior on opacity {
                        SequentialAnimation { PauseAnimation { duration: 140 } NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 34
                        visible: faceImg.status !== Image.Ready
                        color: Qt.alpha(appsTab.accent, 0.15)
                        border.width: 2
                        border.color: Qt.alpha(appsTab.accent, 0.5)
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "user-identity"
                            isMask: true
                            color: appsTab.accent
                            implicitWidth: 30
                            implicitHeight: 30
                        }
                    }

                    Image {
                        id: faceImg
                        anchors.fill: parent
                        visible: false
                        source: DashState.sysInfo.FACE ? DashState.sysInfo.FACE : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: faceImg
                        maskEnabled: true
                        maskSource: Rectangle {
                            width: 68
                            height: 68
                            radius: 34
                            visible: false
                        }
                        maskThresholdMin: 0.1
                        maskSpreadAtMin: 1.0
                        visible: faceImg.status === Image.Ready
                    }
                }

                // username
                Text {
                    visible: Plasmoid.configuration.showUserCard
                    Layout.alignment: Qt.AlignHCenter
                    opacity: appsTab.entered ? 1 : 0
                    Behavior on opacity {
                        SequentialAnimation { PauseAnimation { duration: 180 } NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    text: {
                        var si = DashState.sysInfo;
                        return (si.FULLNAME && si.FULLNAME.length > 0) ? si.FULLNAME : (si.USER ? si.USER : "User");
                    }
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Kirigami.Theme.textColor
                    elide: Text.ElideRight
                    Layout.maximumWidth: parent.width
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    visible: Plasmoid.configuration.showUserCard
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        var si = DashState.sysInfo;
                        return (si.USER ? si.USER : "user") + "@" + (si.HOST ? si.HOST : "localhost");
                    }
                    font.pixelSize: 10
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                    elide: Text.ElideRight
                    Layout.maximumWidth: parent.width
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    visible: Plasmoid.configuration.showUserCard
                             && (Plasmoid.configuration.showSystemCard || Plasmoid.configuration.showMediaCard)
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                }

                // system monitor (click for details)
                Rectangle {
                    id: sysCard
                    visible: Plasmoid.configuration.showSystemCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 126
                    opacity: appsTab.entered ? 1 : 0
                    transform: Translate {
                        y: appsTab.entered ? 0 : 12
                        Behavior on y {
                            SequentialAnimation { PauseAnimation { duration: 210 } NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        }
                    }
                    Behavior on opacity {
                        SequentialAnimation { PauseAnimation { duration: 210 } NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    radius: 14
                    color: sysHover.hovered
                           ? Qt.alpha(Kirigami.Theme.textColor, 0.07)
                           : Qt.alpha(Kirigami.Theme.textColor, 0.045)
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                    Behavior on color {
                        ColorAnimation { duration: 130 }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            Kirigami.Icon {
                                // direct property reads so this updates when
                                // osid.sh reports the distro (a function call
                                // here would freeze on its first evaluation)
                                source: DashState.osLogos[DashState.osId]
                                        ? Qt.resolvedUrl("../icons/" + DashState.osLogos[DashState.osId]).toString()
                                        : "computer-symbolic"
                                implicitWidth: 14
                                implicitHeight: 14
                            }
                            Text {
                                text: "System"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.4
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                            }
                            Text {
                                visible: (DashState.sys.cpuTemp > 0 || DashState.sys.temp > 0)
                                text: Math.round(DashState.sys.cpuTemp > 0 ? DashState.sys.cpuTemp : DashState.sys.temp) + "°C"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: (DashState.sys.cpuTemp > 75 || DashState.sys.temp > 75)
                                       ? Kirigami.Theme.negativeTextColor
                                       : Qt.alpha(Kirigami.Theme.textColor, 0.55)
                            }
                            Item { Layout.fillWidth: true }
                            Kirigami.Icon {
                                source: "go-next"
                                implicitWidth: 12
                                implicitHeight: 12
                                opacity: 0.5
                            }
                        }

                        component MiniRow: RowLayout {
                            property string lbl
                            property string val
                            spacing: 7
                            Text {
                                text: parent.lbl
                                font.pixelSize: 11
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.55)
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: parent.val
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                            }
                        }

                        MiniRow {
                            Layout.fillWidth: true
                            lbl: "Uptime"
                            val: Utils.fmtUptime(DashState.sys.uptime)
                        }
                        MiniRow {
                            Layout.fillWidth: true
                            lbl: "Memory"
                            val: Math.round(DashState.sys.mem * 100) + "%"
                        }
                        MiniRow {
                            Layout.fillWidth: true
                            lbl: "Disk"
                            val: Math.round(DashState.sys.disk * 100) + "%"
                        }
                        MiniRow {
                            Layout.fillWidth: true
                            lbl: "Network"
                            val: "↓ " + Utils.fmtSpeed(DashState.sys.down)
                                 + "  ↑ " + Utils.fmtSpeed(DashState.sys.up)
                        }
                    }

                    HoverHandler {
                        id: sysHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: {
                            DashState.readSysInfo();
                            appsTab.detailedInfo = true;
                        }
                    }
                }

                // media player card
                Rectangle {
                    id: mediaCard
                    visible: Plasmoid.configuration.showMediaCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 108
                    opacity: appsTab.entered ? 1 : 0
                    transform: Translate {
                        y: appsTab.entered ? 0 : 12
                        Behavior on y {
                            SequentialAnimation { PauseAnimation { duration: 250 } NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        }
                    }
                    Behavior on opacity {
                        SequentialAnimation { PauseAnimation { duration: 250 } NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    radius: 14
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.045)
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Item {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    visible: miniArt.status !== Image.Ready
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: "audio-x-generic"
                                        isMask: true
                                        color: Qt.alpha(Kirigami.Theme.textColor, 0.55)
                                        implicitWidth: 18
                                        implicitHeight: 18
                                    }
                                }

                                Image {
                                    id: miniArt
                                    anchors.fill: parent
                                    visible: false
                                    source: appsTab.mpl && appsTab.mpl.artUrl ? appsTab.mpl.artUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    asynchronous: true
                                }

                                MultiEffect {
                                    anchors.fill: parent
                                    source: miniArt
                                    maskEnabled: true
                                    maskSource: Rectangle {
                                        width: 40
                                        height: 40
                                        radius: 10
                                        visible: false
                                    }
                                    maskThresholdMin: 0.1
                                    maskSpreadAtMin: 1.0
                                    visible: miniArt.status === Image.Ready
                                }

                                // click the art → open the player app
                                HoverHandler {
                                    id: artHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: appsTab.openPlayerApp()
                                }
                                QQC2.ToolTip {
                                    visible: artHover.hovered && appsTab.mpl !== null
                                    text: "Open " + (appsTab.mpl && appsTab.mpl.identity ? appsTab.mpl.identity : "player")
                                    delay: 400
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: appsTab.mpl && appsTab.mpl.track ? appsTab.mpl.track : "No media playing"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    color: appsTab.mpl ? Kirigami.Theme.textColor : Qt.alpha(Kirigami.Theme.textColor, 0.45)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: appsTab.mpl && appsTab.mpl.artist ? appsTab.mpl.artist : "—"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                                }
                            }
                        }

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 14

                            PC3.ToolButton {
                                anchors.verticalCenter: parent.verticalCenter
                                icon.name: "media-skip-backward"
                                icon.width: 15
                                icon.height: 15
                                display: QQC2.AbstractButton.IconOnly
                                enabled: appsTab.mpl && appsTab.mpl.canGoPrevious
                                onClicked: appsTab.mpl.Previous()
                            }

                            Item {
                                width: 34
                                height: 34
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 17
                                    color: appsTab.accent
                                    opacity: (appsTab.mpl && (appsTab.mpl.canPlay || appsTab.mpl.canPause)) ? 1 : 0.35
                                    scale: miniPlayHover.hovered ? 1.1 : 1.0
                                    Behavior on scale {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                    }
                                }
                                HoverHandler { id: miniPlayHover }
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: appsTab.mediaPlaying ? "media-playback-pause" : "media-playback-start"
                                    isMask: true
                                    color: appsTab.onAccent
                                    implicitWidth: 15
                                    implicitHeight: 15
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: appsTab.mpl && (appsTab.mpl.canPlay || appsTab.mpl.canPause)
                                    onClicked: {
                                        if (!appsTab.mpl) { return; }
                                        if (appsTab.mediaPlaying) {
                                            if (appsTab.mpl.canPause) { appsTab.mpl.Pause(); }
                                        } else {
                                            if (appsTab.mpl.canPlay) { appsTab.mpl.Play(); }
                                        }
                                    }
                                }
                            }

                            PC3.ToolButton {
                                anchors.verticalCenter: parent.verticalCenter
                                icon.name: "media-skip-forward"
                                icon.width: 15
                                icon.height: 15
                                display: QQC2.AbstractButton.IconOnly
                                enabled: appsTab.mpl && appsTab.mpl.canGoNext
                                onClicked: appsTab.mpl.Next()
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // small yes/no confirmation shown above the power buttons —
                // styled like the sidebar cards (neutral translucent card,
                // accent only as a tint) so it melts into the panel
                Rectangle {
                    id: pwrConfirm
                    visible: appsTab.pendingPower !== ""
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 212
                    Layout.preferredHeight: 42
                    opacity: visible ? 1 : 0
                    scale: visible ? 1 : 0.94
                    radius: 14
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 8
                        anchors.topMargin: 7
                        anchors.bottomMargin: 7
                        spacing: 8

                        Kirigami.Icon {
                            source: appsTab.pendingPower === "logout" ? "system-log-out"
                                  : appsTab.pendingPower === "reboot" ? "system-reboot"
                                  : "system-shutdown"
                            isMask: true
                            color: appsTab.accent
                            implicitWidth: 16
                            implicitHeight: 16
                            opacity: 0.9
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: appsTab.pendingPower === "logout" ? "Log out?"
                                : appsTab.pendingPower === "reboot" ? "Reboot?"
                                : "Shut down?"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Kirigami.Theme.textColor
                        }

                        // buttons reuse the PowerButton look: neutral card fill,
                        // accent-tinted hover; "Yes" is accent-tinted as primary
                        component ConfirmBtn: Rectangle {
                            id: cbtn
                            property string label
                            property bool primary: false
                            signal tapped()

                            implicitWidth: cbtn.primary ? 46 : 38
                            implicitHeight: 27
                            radius: 9
                            color: cbtn.primary
                                   ? (cHover.hovered ? Qt.alpha(appsTab.accent, 0.30)
                                                     : Qt.alpha(appsTab.accent, 0.16))
                                   : (cHover.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.10)
                                                     : Qt.alpha(Kirigami.Theme.textColor, 0.05))
                            border.width: 1
                            border.color: cbtn.primary
                                          ? Qt.alpha(appsTab.accent, 0.35)
                                          : Qt.alpha(Kirigami.Theme.textColor, 0.08)
                            scale: cTap.pressed ? 0.92 : 1.0
                            Behavior on color {
                                ColorAnimation { duration: 130 }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: cbtn.label
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: cbtn.primary ? appsTab.accent
                                                    : Qt.alpha(Kirigami.Theme.textColor, 0.85)
                            }
                            HoverHandler {
                                id: cHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                id: cTap
                                onTapped: cbtn.tapped()
                            }
                        }

                        ConfirmBtn {
                            label: "Yes"
                            primary: true
                            onTapped: appsTab.confirmPower()
                        }
                        ConfirmBtn {
                            label: "No"
                            onTapped: appsTab.cancelPower()
                        }
                    }
                }

                // power buttons
                Row {
                    visible: Plasmoid.configuration.showPowerButtons
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    opacity: appsTab.entered ? 1 : 0
                    transform: Translate {
                        y: appsTab.entered ? 0 : 12
                        Behavior on y {
                            SequentialAnimation { PauseAnimation { duration: 290 } NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        }
                    }
                    Behavior on opacity {
                        SequentialAnimation { PauseAnimation { duration: 290 } NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }

                    component PowerButton: Rectangle {
                        id: pwrBtn
                        property string icon
                        property string tip
                        property string action
                        signal activated()

                        width: 46
                        height: 40
                        radius: 12
                        // stays accent-tinted while its confirmation is pending
                        color: appsTab.pendingPower === pwrBtn.action
                               ? Qt.alpha(appsTab.accent, 0.22)
                               : (pwrHover.hovered
                                  ? Qt.alpha(appsTab.accent, 0.16)
                                  : Qt.alpha(Kirigami.Theme.textColor, 0.05))
                        border.width: 1
                        border.color: appsTab.pendingPower === pwrBtn.action
                                      ? Qt.alpha(appsTab.accent, 0.45)
                                      : Qt.alpha(Kirigami.Theme.textColor, 0.08)
                        scale: pwrPress.pressed ? 0.92 : 1.0
                        Behavior on color {
                            ColorAnimation { duration: 130 }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: pwrBtn.icon
                            implicitWidth: 18
                            implicitHeight: 18
                            opacity: 0.8
                        }

                        HoverHandler {
                            id: pwrHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            id: pwrPress
                            onTapped: pwrBtn.activated()
                        }
                        QQC2.ToolTip {
                            visible: pwrHover.hovered
                            text: pwrBtn.tip
                            delay: 450
                        }
                    }

                    PowerButton {
                        icon: "system-log-out"
                        tip: "Log Out"
                        action: "logout"
                        onActivated: appsTab.askPower("logout")
                    }
                    PowerButton {
                        icon: "system-reboot"
                        tip: "Reboot"
                        action: "reboot"
                        onActivated: appsTab.askPower("reboot")
                    }
                    PowerButton {
                        icon: "system-shutdown"
                        tip: "Power Off"
                        action: "poweroff"
                        onActivated: appsTab.askPower("poweroff")
                    }
                }

            }

            // ---------- detailed system info ----------
            SystemDetails {
                anchors.fill: parent
                tab: appsTab
            }

            // ---------- phone panel (KDE Connect) ----------
            PhonePanel {
                anchors.fill: parent
                tab: appsTab
            }


            // toast feedback (overlay child of the sidebar, not of the
            // ColumnLayout — anchoring inside a layout is a warning)
            Rectangle {
                id: phoneToast
                property bool shown: appsTab.phoneMode && appsTab._phoneToast !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                width: Math.min(parent.width - 24, toastText.implicitWidth + 30)
                height: 30
                radius: 15
                color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.95)
                border.width: 1
                border.color: Qt.alpha(appsTab.accent, 0.45)
                opacity: shown ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }
                z: 10

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Kirigami.Icon {
                        source: appsTab._phoneToastIcon !== ""
                                ? appsTab._phoneToastIcon : "dialog-information"
                        isMask: true
                        implicitWidth: 13
                        implicitHeight: 13
                        color: appsTab.accent
                        visible: appsTab._phoneToastIcon !== ""
                    }
                    Text {
                        id: toastText
                        text: appsTab._phoneToast
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: Kirigami.Theme.textColor
                    }
                }
            }

            // phone panel toggle (top-right corner of the sidebar)
            Rectangle {
                id: phoneBtn
                visible: !appsTab.phoneMode && !appsTab.detailedInfo
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 2
                anchors.rightMargin: 2
                width: 26
                height: 26
                radius: 13
                color: phoneBtnHover.hovered
                       ? Qt.alpha(Kirigami.Theme.textColor, 0.09)
                       : Qt.alpha(Kirigami.Theme.textColor, 0.045)
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                Behavior on color {
                    ColorAnimation { duration: 130 }
                }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "phone"
                    isMask: true
                    implicitWidth: 13
                    implicitHeight: 13
                    color: phoneBtnHover.hovered ? appsTab.accent
                          : Qt.alpha(Kirigami.Theme.textColor, 0.65)
                    Behavior on color {
                        ColorAnimation { duration: 130 }
                    }
                }

                HoverHandler {
                    id: phoneBtnHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: {
                        appsTab.phoneMode = true;
                        DashState.refreshPhone();
                        DashState.refreshMirrorState();
                    }
                }
                QQC2.ToolTip {
                    visible: phoneBtnHover.hovered
                    text: "Phone · KDE Connect"
                    delay: 400
                }
            }
        }
    }
}
