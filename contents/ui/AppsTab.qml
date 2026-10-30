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

    // ---------------- pinned-tab drag reorder ----------------
    // hold a pinned tile for 0.6 s to lift it (see AppTile), then move the
    // pointer: a floating ghost follows the dragged app and an insertion bar
    // shows the target slot; the new order is applied (and persisted) when
    // the pointer is released
    property bool pinDragActive: false
    property string pinDragId: ""
    property string pinDragName: ""
    property string pinDragIcon: ""
    property int pinDropIndex: -1
    property int pinFromIndex: -1
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

    // the ghost/bar are plain children of the scroller (no layout owns them),
    // so every position is computed in content coordinates and then mapped
    // into the target item's parent space — this stays correct no matter
    // whether the Flickable parents them to its contentItem or to itself
    function toParentOf(item, cx, cy) {
        return scroller.contentItem.mapToItem(item.parent, cx, cy);
    }

    function beginPinDrag(tile, cx, cy) {
        if (filter !== "pinned" || search !== "" || pinDragActive) { return; }
        var i = pinIndex(tile.modelData.id);
        if (i < 0) { return; }
        pinGhost.width = gridTileWNow();
        pinGhost.height = 100;
        var p = tile.mapToItem(scroller.contentItem, 0, 0);
        // y of the grid's first row (the section header sits above it)
        pinBaseY = p.y - Math.floor(i / gridColsNow()) * 102;
        pinDragId = tile.modelData.id;
        pinDragName = tile.modelData.name;
        pinDragIcon = tile.modelData.icon;
        pinFromIndex = i;
        pinDropIndex = -1;
        pinDragActive = true;
        updatePinDrag(cx, cy);
    }

    // cx/cy are the pointer position in scroller content coordinates
    function updatePinDrag(cx, cy) {
        if (!pinDragActive || pinFromIndex < 0) { return; }
        var n = pinCount();
        if (n < 1) { return; }
        var g = toParentOf(pinGhost, cx, cy);
        pinGhost.x = g.x - pinGhost.width / 2;
        pinGhost.y = g.y - pinGhost.height / 2;
        var cols = gridColsNow();
        var tw = gridTileWNow(), th = 100;
        var col = Math.floor(cx / (tw + 2));
        var row = Math.floor((cy - pinBaseY) / (th + 2));
        if (col < 0) { col = 0; }
        if (col > cols - 1) { col = cols - 1; }
        if (row < 0) { row = 0; }
        var maxRow = Math.max(0, Math.floor((n - 1) / cols));
        if (row > maxRow) { row = maxRow; }
        var idx = row * cols + col;
        if (idx > n - 1) { idx = n - 1; }
        pinDropIndex = idx;
        // insertion bar sits at the left edge of the target slot
        var b = toParentOf(pinBar, (idx % cols) * (tw + 2) - 1,
                           pinBaseY + Math.floor(idx / cols) * (th + 2) + 4);
        pinBar.x = b.x;
        pinBar.y = b.y;
        pinBar.visible = idx !== pinFromIndex;
    }

    // commit === false aborts the gesture (e.g. the pointer was stolen) and
    // leaves the pinned order untouched
    function endPinDrag(commit) {
        if (commit === undefined) { commit = true; }
        if (commit && pinDragActive && pinDropIndex >= 0 && pinFromIndex >= 0
                && pinDropIndex !== pinFromIndex) {
            var apps = sections[0].apps;
            var ids = [];
            for (var i = 0; i < apps.length; i++) { ids.push(apps[i].id); }
            var id = ids[pinFromIndex];
            ids.splice(pinFromIndex, 1);
            var to = pinDropIndex;
            if (to > ids.length) { to = ids.length; }
            ids.splice(to, 0, id);
            DashState.reorderPinned(ids);
        }
        pinDragActive = false;
        pinDragId = "";
        pinDragName = "";
        pinDragIcon = "";
        pinFromIndex = -1;
        pinDropIndex = -1;
        pinBar.visible = false;
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
        var vis = [];
        for (var k = 0; k < m.count; k++) {
            var app = m.get(k);
            if (q !== "") {
                if (app.name.toLowerCase().indexOf(q) < 0) { continue; }
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
    onSearchChanged: { clearSel(); refresh() }

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

                // floating ghost that follows the pointer during a pinned
                // reorder — it lives inside the Flickable so no ColumnLayout
                // overwrites its x/y, and it scrolls with the grid
                Rectangle {
                    id: pinGhost
                    visible: appsTab.pinDragActive
                    width: 92
                    height: 100
                    radius: 14
                    color: Qt.alpha(appsTab.accent, 0.18)
                    border.width: 1.5
                    border.color: appsTab.accent
                    opacity: 0.95
                    z: 60
                    Column {
                        width: parent.width - 10
                        anchors.centerIn: parent
                        spacing: 7
                        Kirigami.Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            source: appsTab.pinDragIcon
                            implicitWidth: 46
                            implicitHeight: 46
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignTop
                            elide: Text.ElideRight
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            font.pixelSize: 11
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                            text: appsTab.pinDragName
                        }
                    }
                }

                // insertion bar showing where the dragged pin will land
                Rectangle {
                    id: pinBar
                    visible: false
                    width: 3
                    height: 92
                    radius: 1.5
                    color: appsTab.accent
                    z: 55
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
                visible: !appsTab.detailedInfo
                opacity: appsTab.detailedInfo ? 0 : 1
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
                    Layout.preferredHeight: 104
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
                                source: "computer-symbolic"
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
        }
    }

    // ---------------------------------------------------------- app tile
    component AppTile: Item {
        id: tile
        required property var modelData

        property int tileW: 92

        // drag-to-reorder is active only inside the Pinned tab
        readonly property bool reorderable:
            appsTab.filter === "pinned" && appsTab.search === ""

        // selected when the keyboard selector points at this app's id
        readonly property bool keySel:
            appsTab.selAppId !== "" && tile.modelData.id === appsTab.selAppId

        width: tileW
        height: 100
        opacity: (appsTab.pinDragActive && appsTab.pinDragId === tile.modelData.id) ? 0.55 : 1.0
        scale: {
            if (dragArea.dragMode) { return 0.92 }                     // being dragged
            if (dragArea.pressed && tile.reorderable) { return 0.97 }  // holding
            return 1.0
        }
        Behavior on scale {
            NumberAnimation { duration: 120 }
        }
        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }

        Component.onCompleted: appsTab.registerTile(tile)
        Component.onDestruction: appsTab.unregisterTile(tile)

        // input handlers are declared before everything that binds to them,
        // so first-time binding evaluation never sees an undefined id
        HoverHandler {
            id: tileHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: tileTap
            enabled: !tile.reorderable
            onTapped: DashState.launch(tile.modelData.path, tile.modelData.id)
        }

        // keyboard-selector halo
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 15
            opacity: tile.keySel ? 1 : 0
            color: Qt.alpha(appsTab.accent, 0.10)
            Behavior on opacity {
                NumberAnimation { duration: 110 }
            }
        }

        // hold-to-drag feedback ring
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: 18
            color: "transparent"
            border.color: appsTab.accent
            border.width: dragArea.armed ? 2 : 0
            opacity: dragArea.armed ? 0.9 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on border.width { NumberAnimation { duration: 120 } }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 14
            color: tile.keySel
                   ? Qt.alpha(appsTab.accent, 0.14)
                   : Qt.alpha(Kirigami.Theme.textColor, tileHover.hovered ? 0.08 : 0)
            border.width: tile.keySel ? 1.5 : 0
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
                implicitWidth: 46
                implicitHeight: 46
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

        // hold-to-drag (Pinned tab only): press and hold 0.6 s to lift the
        // tile, then move it to choose a new slot — a quick press launches the
        // app instead. In other tabs this MouseArea is disabled and the
        // TapHandler below handles launching.
        MouseArea {
            id: dragArea
            anchors.fill: parent
            z: 100
            enabled: tile.reorderable
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor

            // pressed, not yet lifted: the tile is charging up the hold
            readonly property bool armed: pressed && !dragMode
            property bool dragMode: false
            property point dragStart: Qt.point(0, 0)
            property bool moved: false
            property double pressTime: 0

            // the lift-off delay — holding still for this long starts the drag
            Timer {
                id: holdTimer
                interval: 600
                onTriggered: {
                    if (!dragArea.pressed || dragArea.dragMode) { return; }
                    dragArea.dragMode = true
                    dragArea.preventStealing = true
                    var p = dragArea.mapToItem(scroller.contentItem,
                                                dragArea.mouseX, dragArea.mouseY)
                    appsTab.beginPinDrag(tile, p.x, p.y)
                }
            }

            onPressed: function(mouse) {
                dragArea.dragMode = false
                dragArea.moved = false
                dragArea.pressTime = Date.now()
                var p = dragArea.mapToItem(scroller.contentItem, mouse.x, mouse.y)
                dragArea.dragStart = p
                holdTimer.restart()
            }
            onPositionChanged: function(mouse) {
                var c = dragArea.mapToItem(scroller.contentItem, mouse.x, mouse.y)
                if (!dragArea.dragMode) {
                    // moving before the delay fires cancels it: that gesture is
                    // a scroll or a swipe, not a hold. The Flickable is still
                    // free to steal the pointer and scroll the grid.
                    if (Math.abs(c.x - dragArea.dragStart.x)
                            + Math.abs(c.y - dragArea.dragStart.y) > 8) {
                        dragArea.moved = true
                        holdTimer.stop()
                    }
                    return
                }
                appsTab.updatePinDrag(c.x, c.y)
            }
            onReleased: function(mouse) {
                holdTimer.stop()
                var held = Date.now() - dragArea.pressTime
                if (dragArea.dragMode) {
                    appsTab.endPinDrag(true)
                } else if (!dragArea.moved && held < 500) {
                    // quick press → launch; a near-miss on the hold stays put
                    DashState.launch(tile.modelData.path, tile.modelData.id)
                }
                dragArea.dragMode = false
                dragArea.preventStealing = false
            }
            onCanceled: function() {
                holdTimer.stop()
                if (dragArea.dragMode) { appsTab.endPinDrag(false) }
                dragArea.dragMode = false
                dragArea.preventStealing = false
            }
        }

        // pin toggle (z above dragArea so the star stays clickable in the
        // Pinned tab, where dragArea covers the whole tile)
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
