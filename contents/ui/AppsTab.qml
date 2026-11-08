import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
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
    property bool touchpadOn: false      // virtual touchpad (mouse control) open

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
    // (tile width + 2 spacing, 102 per row)
    function pinSlotPos(idx) {
        var cols = gridColsNow();
        var tw = gridTileWNow();
        return Qt.point((idx % cols) * (tw + 2),
                        Math.floor(idx / cols) * 102);
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
        pinBaseY = p.y - Math.floor(i / gridColsNow()) * 102;
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
        var tw = gridTileWNow(), th = 100;
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
        var out = [
            { key: "all", name: "All Apps", icon: "view-grid" },
            { key: "pinned", name: "Pinned", icon: "starred" }
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
        // pinned → one section; search & "all" → grouped by category
        var secs = [];
        if (q === "" && filter === "pinned") {
            secs = [{ name: "Pinned", icon: "starred", apps: vis }];
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
        function onResetView() {
            appsTab.filter = Plasmoid.configuration.defaultCategory !== ""
                             ? Plasmoid.configuration.defaultCategory : "all";
            appsTab.detailedInfo = false;
            appsTab.phoneMode = false;
            appsTab.notifOpen = false;
            appsTab.touchpadOn = false;
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
        "view-grid": "all-apps.svg"
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
                // Kickoff's views are not mouse-flickable either — only the
                // wheel and the scrollbar scroll them. This keeps every drag
                // on a tile a pure app-drag (to the taskbar or inside the
                // Pinned grid) instead of a fight with the Flickable, and
                // clicks stay reliable (wobble ≤ drag threshold = launch)
                interactive: false

                QQC2.ScrollBar.vertical: PC3.ScrollBar { }

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

                            Flow {
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: section.modelData.apps

                                    delegate: AppTile {
                                        tileW: section.gridTileWidth
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
            ColumnLayout {
                anchors.fill: parent
                visible: appsTab.detailedInfo
                opacity: appsTab.detailedInfo ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 160 }
                }
                spacing: Kirigami.Units.gridUnit * 0.4

                // header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    PC3.ToolButton {
                        icon.name: "go-previous"
                        display: QQC2.AbstractButton.IconOnly
                        onClicked: appsTab.detailedInfo = false
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: "System Info"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Kirigami.Theme.textColor
                        }
                        Text {
                            text: {
                                var si = DashState.sysInfo;
                                return (si.HOST ? si.HOST : "localhost") + (si.OS ? " · " + si.OS : "");
                            }
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                        }
                    }
                }

                component SectionLabel: Text {
                    property string text2
                    text: text2
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
                }

                component InfoRow: RowLayout {
                    property string lbl
                    property string val
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: parent.lbl
                        font.pixelSize: 10
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: parent.val
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.88)
                        elide: Text.ElideRight
                        Layout.maximumWidth: 128
                    }
                }

                component BarRow: ColumnLayout {
                    id: barRow
                    property string lbl
                    property string val
                    property real pct: 0
                    property bool invertWarning: false
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: barRow.lbl
                            font.pixelSize: 10
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.55)
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: barRow.val
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 5
                        radius: 2.5
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.1)
                        Rectangle {
                            width: Math.max(0.02, Math.min(1, barRow.pct)) * parent.width
                            height: parent.height
                            radius: 2.5
                            readonly property real effPct: barRow.invertWarning ? 1 - barRow.pct : barRow.pct
                            color: effPct > 0.9 ? Kirigami.Theme.negativeTextColor
                                 : effPct > 0.72 ? Kirigami.Theme.neutralTextColor
                                 : appsTab.accent
                            Behavior on width {
                                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                Flickable {
                    id: infoScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.rightMargin: -20
                    clip: true
                    contentWidth: width
                    contentHeight: infoCol.height
                    boundsBehavior: Flickable.StopAtBounds

                    QQC2.ScrollBar.vertical: PC3.ScrollBar { }

                    ColumnLayout {
                        id: infoCol
                        width: infoScroll.width - 26
                        spacing: 12

                        readonly property var si: DashState.sysInfo
                        readonly property var sy: DashState.sys

                        // ----- device section -----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            SectionLabel { text2: "DEVICE"; Layout.fillWidth: true }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: 12
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
                                border.width: 1
                                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                                implicitHeight: devRows.height + 20

                                ColumnLayout {
                                    id: devRows
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    spacing: 8

                                    InfoRow { Layout.fillWidth: true; lbl: "User";         val: infoCol.si.USER ? infoCol.si.USER : "—" }
                                    InfoRow { Layout.fillWidth: true; lbl: "Hostname";     val: infoCol.si.HOST ? infoCol.si.HOST : "—" }
                                    InfoRow { Layout.fillWidth: true; lbl: "OS";           val: infoCol.si.OS ? infoCol.si.OS : "—" }
                                    InfoRow { Layout.fillWidth: true; lbl: "Kernel";       val: infoCol.si.KERNEL ? infoCol.si.KERNEL : "—" }
                                    InfoRow { Layout.fillWidth: true; lbl: "Desktop";      val: infoCol.si.PLASMA ? "Plasma " + infoCol.si.PLASMA : "Plasma" }
                                    InfoRow { Layout.fillWidth: true; lbl: "Architecture"; val: infoCol.si.ARCH ? infoCol.si.ARCH : "—" }
                                }
                            }
                        }

                        // ----- resources section -----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            SectionLabel { text2: "RESOURCES"; Layout.fillWidth: true }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: 12
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
                                border.width: 1
                                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                                implicitHeight: resRows.height + 20

                                ColumnLayout {
                                    id: resRows
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    spacing: 10

                                    BarRow {
                                        Layout.fillWidth: true
                                        lbl: "CPU"
                                        val: Math.round(infoCol.sy.cpu * 100) + "%"
                                             + (infoCol.sy.cpuTemp > 0 ? " · " + Math.round(infoCol.sy.cpuTemp) + "°C" : "")
                                        pct: infoCol.sy.cpu
                                    }

                                    Repeater {
                                        model: infoCol.sy.gpus ? infoCol.sy.gpus : []

                                        delegate: BarRow {
                                            required property int index
                                            required property var modelData
                                            Layout.fillWidth: true
                                            visible: modelData.busy >= 0 || modelData.temp > 0
                                            lbl: "GPU · " + modelData.name
                                            val: (modelData.busy >= 0 ? Math.round(modelData.busy * 100) + "%" : "—")
                                                 + (modelData.temp > 0 ? " · " + Math.round(modelData.temp) + "°C" : "")
                                            pct: modelData.busy >= 0 ? modelData.busy : 0
                                        }
                                    }

                                    BarRow {
                                        Layout.fillWidth: true
                                        lbl: "Memory"
                                        val: Utils.fmtSize(infoCol.sy.memUsed) + " / " + Utils.fmtSize(infoCol.sy.memTotal)
                                        pct: infoCol.sy.mem
                                    }
                                    BarRow {
                                        Layout.fillWidth: true
                                        visible: infoCol.sy.swapTotal > 0
                                        lbl: "Swap"
                                        val: Utils.fmtSize(infoCol.sy.swapTotal * infoCol.sy.swap) + " / " + Utils.fmtSize(infoCol.sy.swapTotal)
                                        pct: infoCol.sy.swap
                                    }
                                    BarRow {
                                        Layout.fillWidth: true
                                        lbl: "Disk"
                                        val: Utils.fmtSize(infoCol.sy.diskUsed) + " / " + Utils.fmtSize(infoCol.sy.diskTotal)
                                        pct: infoCol.sy.disk
                                    }
                                    BarRow {
                                        Layout.fillWidth: true
                                        visible: infoCol.sy.battery >= 0
                                        lbl: "Battery"
                                        val: infoCol.sy.battery + "%"
                                        pct: infoCol.sy.battery / 100
                                        invertWarning: true
                                    }
                                    InfoRow { Layout.fillWidth: true; lbl: "Uptime"; val: Utils.fmtUptime(infoCol.sy.uptime) }
                                }
                            }
                        }

                        // ----- processor footer -----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            SectionLabel { text2: "PROCESSOR"; Layout.fillWidth: true }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: 12
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
                                border.width: 1
                                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                                implicitHeight: cpuCol.height + 20

                                ColumnLayout {
                                    id: cpuCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: infoCol.si.CPU ? infoCol.si.CPU : "—"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        text: infoCol.si.CORES ? infoCol.si.CORES + " cores" : ""
                                        font.pixelSize: 10
                                        color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                                    }
                                }
                            }
                        }

                        // ----- graphics section -----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            SectionLabel { text2: "GRAPHICS"; Layout.fillWidth: true }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: 12
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
                                border.width: 1
                                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
                                implicitHeight: gpuRows.height + 20

                                ColumnLayout {
                                    id: gpuRows
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    spacing: 8

                                    Repeater {
                                        model: infoCol.si.GPUS ? infoCol.si.GPUS : []

                                        delegate: Text {
                                            required property int index
                                            required property var modelData
                                            Layout.fillWidth: true
                                            text: modelData
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- phone panel (KDE Connect) ----------
            ColumnLayout {
                anchors.fill: parent
                visible: appsTab.phoneMode
                opacity: appsTab.phoneMode ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 160 }
                }
                spacing: Kirigami.Units.gridUnit * 0.4

                // re-run the device search a moment after --refresh
                Timer {
                    id: phoneRefreshTimer
                    interval: 2500
                    onTriggered: DashState.refreshPhone()
                }

                // header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    PC3.ToolButton {
                        icon.name: "go-previous"
                        display: QQC2.AbstractButton.IconOnly
                        onClicked: {
                            appsTab.phoneMode = false;
                            appsTab.notifOpen = false;
                            appsTab.touchpadOn = false;
                            DashState.closePhonePoll();
                            DashState.closePhoneNotifs();
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: "My Phone"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Kirigami.Theme.textColor
                        }
                        Text {
                            text: {
                                var d = appsTab.phoneDev;
                                if (!d) { return "KDE Connect"; }
                                return d.name + (d.reachable ? " · Connected" : " · Offline");
                            }
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                        }
                    }
                    // battery chip
                    Rectangle {
                        visible: appsTab.phoneDev !== null && DashState.phoneBattery >= 0
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: phoneBatChip.implicitWidth + 14
                        implicitHeight: 22
                        radius: 11
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
                        border.width: 1
                        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

                        RowLayout {
                            id: phoneBatChip
                            anchors.centerIn: parent
                            spacing: 4

                            Kirigami.Icon {
                                source: {
                                    if (DashState.phoneCharging) { return "battery-good-charging"; }
                                    var b = DashState.phoneBattery;
                                    return b > 80 ? "battery-full"
                                         : b > 50 ? "battery-good"
                                         : b > 20 ? "battery-low"
                                         : "battery-caution";
                                }
                                implicitWidth: 12
                                implicitHeight: 12
                            }
                            Text {
                                text: DashState.phoneBattery + "%"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                            }
                        }
                    }
                    Kirigami.Icon {
                        source: "kdeconnect"
                        implicitWidth: 16
                        implicitHeight: 16
                        opacity: 0.55
                    }
                }

                Flickable {
                    id: phoneScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.rightMargin: -20
                    clip: true
                    contentWidth: width
                    contentHeight: phoneBody.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    QQC2.ScrollBar.vertical: PC3.ScrollBar { }

                    ColumnLayout {
                        id: phoneBody
                        width: phoneScroll.width - 26
                        spacing: Kirigami.Units.gridUnit * 0.4

                component PhoneLabel: Text {
                    property string text2
                    text: text2
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
                }

                component PhoneSection: Item {
                    id: psec
                    // .data (not .children) so non-visual children (Timer,
                    // Repeater) are accepted too
                    default property alias content: psecCol.data
                    property bool open: false
                    visible: height > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: open ? psecCol.implicitHeight : 0
                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    opacity: open ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 160 }
                    }
                    clip: true

                    ColumnLayout {
                        id: psecCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 8
                    }
                }

                component PhoneAction: Rectangle {
                    id: pa
                    property string lbl
                    property string icn
                    property bool sel: false
                    signal triggered()
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: 12
                    color: paHv.hovered
                           ? Qt.alpha(Kirigami.Theme.textColor, 0.07)
                           : pa.sel
                           ? Qt.alpha(appsTab.accent, 0.15)
                           : Qt.alpha(Kirigami.Theme.textColor, 0.045)
                    border.width: 1
                    border.color: pa.sel ? Qt.alpha(appsTab.accent, 0.5)
                                         : Qt.alpha(Kirigami.Theme.textColor, 0.08)
                    opacity: enabled ? 1 : 0.4
                    Behavior on color {
                        ColorAnimation { duration: 130 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 130 }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        Kirigami.Icon {
                            source: pa.icn
                            isMask: true
                            implicitWidth: 17
                            implicitHeight: 17
                            color: pa.enabled
                                   ? Qt.alpha(Kirigami.Theme.textColor, 0.8)
                                   : Qt.alpha(Kirigami.Theme.textColor, 0.35)
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: pa.lbl
                            font.pixelSize: 9
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    HoverHandler {
                        id: paHv
                        cursorShape: Qt.PointingHandCursor
                        enabled: pa.enabled
                    }
                    TapHandler {
                        enabled: pa.enabled
                        onTapped: pa.triggered()
                    }
                }

                // device + battery card
                Rectangle {
                    visible: appsTab.phoneDev !== null
                    Layout.fillWidth: true
                    Layout.preferredHeight: 86
                    radius: 14
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.045)
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 11
                                color: Qt.alpha(appsTab.accent, 0.15)
                                border.width: 1
                                border.color: Qt.alpha(appsTab.accent, 0.4)
                            }
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                source: "smartphone"
                                isMask: true
                                color: appsTab.accent
                                implicitWidth: 20
                                implicitHeight: 20
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 5

                            Text {
                                Layout.fillWidth: true
                                text: appsTab.phoneDev ? appsTab.phoneDev.name : "—"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                color: Kirigami.Theme.textColor
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Kirigami.Icon {
                                    source: {
                                        if (DashState.phoneBattery < 0) { return "battery-missing"; }
                                        if (DashState.phoneCharging) { return "battery-good-charging"; }
                                        var b = DashState.phoneBattery;
                                        return b > 80 ? "battery-full"
                                             : b > 50 ? "battery-good"
                                             : b > 20 ? "battery-low"
                                             : "battery-caution";
                                    }
                                    implicitWidth: 14
                                    implicitHeight: 14
                                }
                                Text {
                                    text: DashState.phoneBattery >= 0
                                          ? DashState.phoneBattery + "%" : "—"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                                }
                                Text {
                                    visible: DashState.phoneSignal >= 0 && DashState.phoneNetType !== ""
                                    text: "· " + DashState.phoneNetType
                                    font.pixelSize: 10
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                                }
                                Text {
                                    visible: DashState.phoneCharging
                                    text: "· charging"
                                    font.pixelSize: 10
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                                }
                                Item { Layout.fillWidth: true }
                                Kirigami.Icon {
                                    visible: appsTab.phoneDev && appsTab.phoneDev.reachable
                                    source: "network-wireless-connected"
                                    implicitWidth: 12
                                    implicitHeight: 12
                                    opacity: 0.55
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 4
                                radius: 2
                                visible: DashState.phoneBattery >= 0
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.1)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * Math.max(0, Math.min(1, DashState.phoneBattery / 100))
                                    radius: 2
                                    color: DashState.phoneCharging ? "#4fc3f7"
                                         : (DashState.phoneBattery >= 0 && DashState.phoneBattery <= 20
                                            ? Kirigami.Theme.negativeTextColor : appsTab.accent)
                                    Behavior on width {
                                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }
                    }
                }

                PhoneLabel { text2: "ACTIONS" }

                // actions
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { lbl: "Ring",    icn: "bell",                             act: "ring"     },
                            { lbl: "Ping",    icn: "preferences-desktop-notification", act: "ping"     },
                            { lbl: "Control", icn: "input-mouse",                      act: "touchpad" },
                            { lbl: "Notifs",  icn: "dialog-information",               act: "notifs"   }
                        ]

                        delegate: PhoneAction {
                            required property var modelData
                            lbl: modelData.lbl
                            icn: modelData.icn
                            enabled: appsTab.phoneDev !== null && appsTab.phoneDev.reachable
                            sel: (modelData.act === "touchpad" && appsTab.touchpadOn)
                              || (modelData.act === "notifs" && appsTab.notifOpen)
                            onTriggered: {
                                if (modelData.act === "touchpad") {
                                    appsTab.touchpadOn = !appsTab.touchpadOn;
                                } else if (modelData.act === "notifs") {
                                    appsTab.notifOpen = !appsTab.notifOpen;
                                    if (appsTab.notifOpen) { DashState.fetchPhoneNotifs(); }
                                } else {
                                    DashState.phoneAction(modelData.act);
                                    if (modelData.act === "ring") {
                                        appsTab.showPhoneToast("Ringing your phone…", "bell");
                                    } else if (modelData.act === "ping") {
                                        appsTab.showPhoneToast("Ping sent", "preferences-desktop-notification");
                                    }
                                }
                            }
                        }
                    }
                }

                PhoneLabel {
                    visible: appsTab.phoneDev !== null && appsTab.phoneDev.reachable
                    text2: "SEND TO PHONE"
                }

                // second row: send / share actions
                RowLayout {
                    visible: appsTab.phoneDev !== null && appsTab.phoneDev.reachable
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { lbl: "File",     icn: "document-send", act: "file"      },
                            { lbl: "Clipboard",icn: "edit-copy",     act: "clipboard" },
                            { lbl: "Browse",   icn: "folder-remote", act: "browse"    },
                            { lbl: "Commands", icn: "system-run",    act: "commands"  }
                        ]

                        delegate: PhoneAction {
                            required property var modelData
                            lbl: modelData.lbl
                            icn: modelData.icn
                            onTriggered: {
                                if (modelData.act === "file") {
                                    DashState.phoneAction("sharefile");
                                } else if (modelData.act === "commands") {
                                    DashState.phoneAction("notifycommands");
                                    appsTab.showPhoneToast("Fetching phone commands…", "system-run");
                                } else {
                                    DashState.phoneAction(modelData.act);
                                    if (modelData.act === "clipboard") {
                                        appsTab.showPhoneToast("Clipboard sent to phone", "edit-copy");
                                    } else if (modelData.act === "browse") {
                                        appsTab.showPhoneToast("Mounting phone storage…", "folder-remote");
                                    }
                                }
                            }
                        }
                    }
                }

                // virtual touchpad (mouse control)
                PhoneSection {
                    open: appsTab.touchpadOn
                          && appsTab.phoneDev !== null && appsTab.phoneDev.reachable

                    Rectangle {
                        id: touchpad
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        radius: 14
                        color: touchDrag.containsMouse
                               ? Qt.alpha(Kirigami.Theme.textColor, 0.06)
                               : Qt.alpha(Kirigami.Theme.textColor, 0.045)
                        border.width: 1
                        border.color: touchDrag.pressed
                                      ? Qt.alpha(appsTab.accent, 0.5)
                                      : Qt.alpha(Kirigami.Theme.textColor, 0.08)
                        Behavior on border.color {
                            ColorAnimation { duration: 130 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: touchDrag.pressed ? "controlling…" : "drag to move · tap to click · scroll to scroll"
                            font.pixelSize: 10
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
                        }

                        MouseArea {
                            id: touchDrag
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.BlankCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            property real accX: 0
                            property real accY: 0
                            property point last: Qt.point(0, 0)

                            onPressed: (mouse) => {
                                last = Qt.point(mouse.x, mouse.y);
                                accX = 0;
                                accY = 0;
                                cursorTimer.restart();
                            }
                            onPositionChanged: (mouse) => {
                                accX += mouse.x - last.x;
                                accY += mouse.y - last.y;
                                last = Qt.point(mouse.x, mouse.y);
                            }
                            onReleased: (mouse) => {
                                cursorTimer.stop();
                                if (Math.abs(accX) + Math.abs(accY) < 4) {
                                    DashState.phoneAction("click", "single");  // tap = left click
                                } else {
                                    DashState.phoneAction("cursor", Math.round(accX), Math.round(accY));
                                }
                                accX = 0;
                                accY = 0;
                            }
                            onCanceled: cursorTimer.stop()
                            onWheel: (wheel) => {
                                var steps = wheel.angleDelta.y / 120;
                                if (steps === 0) { steps = wheel.angleDelta.y > 0 ? 1 : -1; }
                                DashState.phoneAction("scroll", Math.round(steps));
                            }
                        }
                    }

                    Timer {
                        id: cursorTimer
                        interval: 60
                        repeat: true
                        running: false
                        onTriggered: {
                            if (Math.abs(touchDrag.accX) + Math.abs(touchDrag.accY) >= 1) {
                                DashState.phoneAction("cursor",
                                                      Math.round(touchDrag.accX),
                                                      Math.round(touchDrag.accY));
                                touchDrag.accX = 0;
                                touchDrag.accY = 0;
                            }
                        }
                    }

                    // click buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { lbl: "Left",   icn: "input-mouse", act: "single" },
                                { lbl: "Double", icn: "input-mouse", act: "double" },
                                { lbl: "Right",  icn: "input-mouse", act: "right"  }
                            ]

                            delegate: PhoneAction {
                                required property var modelData
                                lbl: modelData.lbl
                                icn: modelData.icn
                                onTriggered: DashState.phoneAction("click", modelData.act)
                            }
                        }
                    }
                }

                // inputs: send a link + type on the phone
                ColumnLayout {
                    visible: appsTab.phoneDev !== null && appsTab.phoneDev.reachable
                    Layout.fillWidth: true
                    spacing: 8

                    // send-a-link input
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 10
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.045)
                        border.width: 1
                        border.color: linkInput.activeFocus
                                      ? Qt.alpha(appsTab.accent, 0.5)
                                      : Qt.alpha(Kirigami.Theme.textColor, 0.08)
                        Behavior on border.color {
                            ColorAnimation { duration: 130 }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 6

                            Kirigami.Icon {
                                source: "insert-link"
                                implicitWidth: 14
                                implicitHeight: 14
                                opacity: 0.55
                            }
                            QQC2.TextField {
                                id: linkInput
                                Layout.fillWidth: true
                                placeholderText: "Paste a link to send…"
                                font.pixelSize: 11
                                color: Kirigami.Theme.textColor
                                background: null
                                selectByMouse: true
                                onAccepted: appsTab.sendPhoneLink()
                            }
                            PC3.ToolButton {
                                icon.name: "document-send"
                                icon.width: 14
                                icon.height: 14
                                display: QQC2.AbstractButton.IconOnly
                                enabled: linkInput.text.length > 0
                                opacity: enabled ? 1 : 0.35
                                onClicked: appsTab.sendPhoneLink()
                                QQC2.ToolTip { text: "Send link to phone"; delay: 300 }
                            }
                        }
                    }

                    // type-on-phone input
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 10
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.045)
                        border.width: 1
                        border.color: typeInput.activeFocus
                                      ? Qt.alpha(appsTab.accent, 0.5)
                                      : Qt.alpha(Kirigami.Theme.textColor, 0.08)
                        Behavior on border.color {
                            ColorAnimation { duration: 130 }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 6

                            Kirigami.Icon {
                                source: "input-keyboard"
                                implicitWidth: 14
                                implicitHeight: 14
                                opacity: 0.55
                            }
                            QQC2.TextField {
                                id: typeInput
                                Layout.fillWidth: true
                                placeholderText: "Type on your phone…"
                                font.pixelSize: 11
                                color: Kirigami.Theme.textColor
                                background: null
                                selectByMouse: true
                                onAccepted: appsTab.typeOnPhone()
                            }
                            PC3.ToolButton {
                                icon.name: "document-send"
                                icon.width: 14
                                icon.height: 14
                                display: QQC2.AbstractButton.IconOnly
                                enabled: typeInput.text.length > 0
                                opacity: enabled ? 1 : 0.35
                                onClicked: appsTab.typeOnPhone()
                                QQC2.ToolTip { text: "Type into the phone"; delay: 300 }
                            }
                        }
                    }
                }

                // phone notifications
                PhoneSection {
                    open: appsTab.notifOpen
                          && appsTab.phoneDev !== null && appsTab.phoneDev.reachable

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            text: "PHONE NOTIFICATIONS"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.2
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
                        }
                        Item { Layout.fillWidth: true }
                        PC3.ToolButton {
                            icon.name: "view-refresh"
                            implicitWidth: 22
                            implicitHeight: 22
                            display: QQC2.AbstractButton.IconOnly
                            onClicked: DashState.fetchPhoneNotifs()
                            QQC2.ToolTip { text: "Refresh"; delay: 300 }
                        }
                    }

                    Text {
                        visible: DashState.phoneNotifs.length === 0
                        text: "No notifications on your phone"
                        font.pixelSize: 10
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.45)
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: DashState.phoneNotifs

                        delegate: Rectangle {
                            id: notifRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: notifCol.implicitHeight + 16
                            radius: 10
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
                            border.width: 1
                            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.07)

                            ColumnLayout {
                                id: notifCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 8
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: notifRow.modelData.app !== ""
                                              ? notifRow.modelData.app : "Notification"
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.5
                                        elide: Text.ElideRight
                                        color: Qt.alpha(appsTab.accent, 0.9)
                                    }
                                    Kirigami.Icon {
                                        visible: notifRow.modelData.dismissable
                                        source: "window-close"
                                        isMask: true
                                        implicitWidth: 12
                                        implicitHeight: 12
                                        opacity: notifDismissHover.hovered ? 0.9 : 0.5
                                        Layout.alignment: Qt.AlignVCenter

                                        HoverHandler { id: notifDismissHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                DashState.phoneAction("notifdismiss", notifRow.modelData.id);
                                                appsTab.showPhoneToast("Notification dismissed", "window-close");
                                                notifDismissTimer.restart();
                                            }
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: notifRow.modelData.title !== ""
                                          ? notifRow.modelData.title : "—"
                                    font.pixelSize: 10
                                    wrapMode: Text.WordWrap
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.8)
                                }
                            }
                        }
                    }

                    Timer {
                        id: notifDismissTimer
                        interval: 900
                        onTriggered: DashState.fetchPhoneNotifs()
                    }
                }

                // phone media card
                Rectangle {
                    visible: appsTab.phoneDev !== null
                             && appsTab.phoneDev.reachable
                             && DashState.phoneMedia !== null
                    Layout.fillWidth: true
                    Layout.preferredHeight: 108
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
                                    visible: phoneArt.status !== Image.Ready
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
                                    id: phoneArt
                                    anchors.fill: parent
                                    visible: false
                                    source: DashState.phoneMedia && DashState.phoneMedia.art
                                            ? DashState.phoneMedia.art : ""
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    asynchronous: true
                                }

                                MultiEffect {
                                    anchors.fill: parent
                                    source: phoneArt
                                    maskEnabled: true
                                    maskSource: Rectangle {
                                        width: 40
                                        height: 40
                                        radius: 10
                                        visible: false
                                    }
                                    maskThresholdMin: 0.1
                                    maskSpreadAtMin: 1.0
                                    visible: phoneArt.status === Image.Ready
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: DashState.phoneMedia && DashState.phoneMedia.title
                                          ? DashState.phoneMedia.title
                                          : "Nothing playing on your phone"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    color: DashState.phoneMedia ? Kirigami.Theme.textColor
                                         : Qt.alpha(Kirigami.Theme.textColor, 0.45)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: DashState.phoneMedia && DashState.phoneMedia.artist
                                          ? DashState.phoneMedia.artist : "—"
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
                                onClicked: DashState.phoneAction("prev")
                            }

                            Item {
                                width: 34
                                height: 34
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 17
                                    color: appsTab.accent
                                    scale: phonePlayHover.hovered ? 1.1 : 1.0
                                    Behavior on scale {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                    }
                                }
                                HoverHandler { id: phonePlayHover }
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: DashState.phoneMedia && DashState.phoneMedia.status === "Playing"
                                            ? "media-playback-pause" : "media-playback-start"
                                    isMask: true
                                    color: appsTab.onAccent
                                    implicitWidth: 15
                                    implicitHeight: 15
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (DashState.phoneMedia && DashState.phoneMedia.status === "Playing") {
                                            DashState.phoneAction("pause");
                                        } else {
                                            DashState.phoneAction("play");
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
                                onClicked: DashState.phoneAction("next")
                            }
                        }
                    }
                }

                // empty state
                ColumnLayout {
                    visible: appsTab.phoneDev === null
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64

                        Rectangle {
                            anchors.fill: parent
                            radius: 32
                            color: Qt.alpha(appsTab.accent, 0.12)
                            border.width: 1
                            border.color: Qt.alpha(appsTab.accent, 0.4)
                        }
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "smartphone"
                            isMask: true
                            color: appsTab.accent
                            implicitWidth: 28
                            implicitHeight: 28
                        }
                    }
                    Text {
                        text: "No phone connected"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "Pair a device with KDE Connect, or search again."
                        font.pixelSize: 10
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.45)
                        Layout.alignment: Qt.AlignHCenter
                    }
                    PC3.Button {
                        text: "Search again"
                        icon.name: "view-refresh"
                        Layout.alignment: Qt.AlignHCenter
                        onClicked: {
                            DashState.phoneAction("refresh");
                            phoneRefreshTimer.restart();
                        }
                    }
                }
                    }
                }

                // toast feedback
                Rectangle {
                    id: phoneToast
                    property bool shown: appsTab._phoneToast !== ""
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
                    source: "smartphone"
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

    // ---------------------------------------------------------- app tile
    component AppTile: Item {
        id: tile
        required property var modelData
        required property int index

        property int tileW: 92

        // drag-to-reorder is active only inside the Pinned tab
        readonly property bool reorderable:
            appsTab.filter === "pinned" && appsTab.search === ""

        // selected when the keyboard selector points at this app's id
        readonly property bool keySel:
            appsTab.selAppId !== "" && tile.modelData.id === appsTab.selAppId

        // this tile is the one being dragged (it rides to the hovered slot)
        readonly property bool dragSel:
            appsTab.pinDragActive && appsTab.pinDragId === tile.modelData.id

        // a tap right after a real drag must not launch the app
        property bool wasDragged: false

        // the app as a URL — this is what the taskbar's drop handler requires:
        // Backend::isApplication() only accepts LOCAL FILE urls of desktop
        // files (url.isLocalFile() + KDesktopFile check), i.e. the exact
        // payload the KDE launcher hands over on a drag. Our scanned paths
        // always live in standard application dirs, so KSycoca knows them.
        readonly property string appUrl:
            "file://" + encodeURI(tile.modelData.path || "")

        width: tileW
        height: 100

        // Kickoff-style live shuffle: while a pinned drag is active, every
        // tile translates to open the slot under the pointer — the dragged
        // tile rides to the hovered slot and the ones in between slide one
        // slot toward the source, so the grid seems to flow around the drag
        transform: Translate {
            x: appsTab.pinDisplacement(tile.index).x
            y: appsTab.pinDisplacement(tile.index).y

            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        Component.onCompleted: appsTab.registerTile(tile)
        Component.onDestruction: appsTab.unregisterTile(tile)

        // native system drag (exactly how the KDE launcher's delegates do
        // it): press + move lifts the app out of the widget with a snapshot
        // of the tile as the drag image. Drop it on the taskbar to add a
        // launcher, on the desktop, or on any window — or keep it inside the
        // widget to reorder the Pinned grid (the content DropArea handles
        // the shuffle and the undo-on-exit).
        DragHandler {
            id: tileDrag
            target: null
            onActiveChanged: {
                if (active) {
                    tile.wasDragged = true
                    appsTab.noteTileDrag(tile)
                    tile.grabToImage(function(result) {
                        tile.Drag.imageSource = result.url
                        tile.Drag.active = true
                    })
                } else {
                    tile.Drag.active = false
                    // clear immediately: a tap cancelled by this drag must
                    // never swallow the NEXT click's launch
                    tile.wasDragged = false
                    appsTab.endTileDrag()
                }
            }
        }
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.proposedAction: Qt.CopyAction
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        Drag.mimeData: { "text/uri-list": [tile.appUrl] }

        // input handlers are declared before everything that binds to them,
        // so first-time binding evaluation never sees an undefined id
        HoverHandler {
            id: tileHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: tileTap
            onTapped: {
                if (!tile.wasDragged) {
                    DashState.launch(tile.modelData.path, tile.modelData.id)
                }
                tile.wasDragged = false
            }
        }

        // keyboard-selector halo / dragged-tile highlight
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 15
            opacity: (tile.keySel || tile.dragSel) ? 1 : 0
            color: Qt.alpha(appsTab.accent, 0.10)
            Behavior on opacity {
                NumberAnimation { duration: 110 }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 14
            color: (tile.keySel || tile.dragSel)
                   ? Qt.alpha(appsTab.accent, 0.14)
                   : Qt.alpha(Kirigami.Theme.textColor, tileHover.hovered ? 0.08 : 0)
            border.width: (tile.keySel || tile.dragSel) ? 1.5 : 0
            border.color: appsTab.accent
            scale: tileTap.pressed ? 0.94 : 1.0
            Behavior on color {
                ColorAnimation { duration: 120 }
            }
            Behavior on border.width {
                NumberAnimation { duration: 100 }
            }
            Behavior on scale {
                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
            }
        }

        Column {
            width: parent.width - 10
            anchors.centerIn: parent
            spacing: 7

            Kirigami.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: tile.modelData.icon
                implicitWidth: 47
                implicitHeight: 47
            }

            Text {
                width: parent.width
                height: 30
                text: tile.modelData.name
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                maximumLineCount: 2
                font.pixelSize: 11
                color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
            }
        }

        // pin toggle (the star stays clickable everywhere on the tile)
        Item {
            width: 24
            height: 24
            z: 101
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 4
            visible: tileHover.hovered || tile.modelData.pinned
            opacity: tile.modelData.pinned ? 1.0 : (tileHover.hovered ? 0.7 : 0)
            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: pinArea.containsMouse ? Qt.alpha(appsTab.accent, 0.18) : "transparent"
            }
            Kirigami.Icon {
                anchors.fill: parent
                anchors.margins: 5
                source: tile.modelData.pinned ? "starred" : "non-starred"
                isMask: true
                color: tile.modelData.pinned ? appsTab.accent : Qt.alpha(Kirigami.Theme.textColor, 0.7)
            }
            MouseArea {
                id: pinArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: DashState.togglePin(tile.modelData.id)
            }
        }
    }
}
