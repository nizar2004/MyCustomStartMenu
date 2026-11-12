import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A row in the Overview tab's "Recently Used" list: app icon, name and its
// GenericName as a subtitle. The `tab` property is the AppsTab instance.
Item {
    id: row
    required property var modelData
    property Item tab: null

    // keyboard-selection highlight (same idea as AppTile)
    readonly property bool keySel:
        tab.selAppId !== "" && row.modelData.id === tab.selAppId

    width: parent ? parent.width : 0
    height: 48

    // register so ensureSelVisible() can scroll to it
    Component.onCompleted: tab.registerTile(row)
    Component.onDestruction: tab.unregisterTile(row)

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: row.keySel
               ? Qt.alpha(row.tab.accent, 0.14)
               : (rowHover.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.07) : "transparent")
        border.width: row.keySel ? 1 : 0
        border.color: row.tab.accent
        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 10
        spacing: 10

        Kirigami.Icon {
            Layout.alignment: Qt.AlignVCenter
            source: row.modelData.icon
            implicitWidth: 30
            implicitHeight: 30
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: row.modelData.name
                elide: Text.ElideRight
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: Qt.alpha(Kirigami.Theme.textColor, 0.9)
            }
            Text {
                Layout.fillWidth: true
                text: (row.modelData.generic && row.modelData.generic !== "")
                      ? row.modelData.generic : row.modelData.cat
                elide: Text.ElideRight
                font.pixelSize: 9
                color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
            }
        }
    }

    HoverHandler {
        id: rowHover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: DashState.launch(row.modelData.path, row.modelData.id)
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint) => row.tab.showTileMenu(row.modelData, row, eventPoint.position)
    }
}
