import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 44
    Layout.minimumHeight: Kirigami.Units.gridUnit * 30
    Layout.preferredWidth: Kirigami.Units.gridUnit * 52
    Layout.preferredHeight: Kirigami.Units.gridUnit * 34
    Layout.maximumWidth: Kirigami.Units.gridUnit * 52
    Layout.maximumHeight: Kirigami.Units.gridUnit * 34

    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight

    AppsTab {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit * 0.75
    }
}
