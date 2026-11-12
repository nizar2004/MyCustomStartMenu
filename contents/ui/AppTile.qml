import QtQuick
import org.kde.kirigami as Kirigami

// One application tile in the app grid.
//
// Extracted from AppsTab so the 3000-line file stays navigable. The `tab`
// property is the AppsTab instance: it carries the selection/drag state and
// the helpers (registerTile, noteTileDrag, showTileMenu, accent…).
Item {
    id: tile
    required property var modelData
    required property int index
    property Item tab: null

    property int tileW: 92
    property int tileH: 100
    // Overview tab: icon-only tiles (no name label) in a shorter cell
    property bool compact: false

    // selected when the keyboard selector points at this app's id
    readonly property bool keySel:
        tab.selAppId !== "" && tile.modelData.id === tab.selAppId

    // this tile is the one being dragged (it rides to the hovered slot)
    readonly property bool dragSel:
        tab.pinDragActive && tab.pinDragId === tile.modelData.id

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
    height: tileH

    // Kickoff-style live shuffle: while a pinned drag is active, every
    // tile translates to open the slot under the pointer — the dragged
    // tile rides to the hovered slot and the ones in between slide one
    // slot toward the source, so the grid seems to flow around the drag
    transform: Translate {
        x: tab.pinDisplacement(tile.index).x
        y: tab.pinDisplacement(tile.index).y

        Behavior on x {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    Component.onCompleted: tab.registerTile(tile)
    Component.onDestruction: tab.unregisterTile(tile)

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
                tab.noteTileDrag(tile)
                tile.grabToImage(function(result) {
                    tile.Drag.imageSource = result.url
                    tile.Drag.active = true
                })
            } else {
                tile.Drag.active = false
                // clear immediately: a tap cancelled by this drag must
                // never swallow the NEXT click's launch
                tile.wasDragged = false
                tab.endTileDrag()
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

    // right-click: Kickoff-style tile menu (one shared menu instance
    // lives in AppsTab — creating a popup per tile would be heavy)
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint) => tab.showTileMenu(tile.modelData, tile, eventPoint.position)
    }

    // keyboard-selector halo / dragged-tile highlight
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 15
        opacity: (tile.keySel || tile.dragSel) ? 1 : 0
        color: Qt.alpha(tab.accent, 0.10)
        Behavior on opacity {
            NumberAnimation { duration: 110 }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 14
        color: (tile.keySel || tile.dragSel)
               ? Qt.alpha(tab.accent, 0.14)
               : Qt.alpha(Kirigami.Theme.textColor, tileHover.hovered ? 0.08 : 0)
        border.width: (tile.keySel || tile.dragSel) ? 1.5 : 0
        border.color: tab.accent
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
            implicitWidth: tile.compact ? 48 : 47
            implicitHeight: tile.compact ? 48 : 47
        }

        Text {
            visible: !tile.compact
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
            color: pinArea.containsMouse ? Qt.alpha(tab.accent, 0.18) : "transparent"
        }
        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: 5
            source: tile.modelData.pinned ? "starred" : "non-starred"
            isMask: true
            color: tile.modelData.pinned ? tab.accent : Qt.alpha(Kirigami.Theme.textColor, 0.7)
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
