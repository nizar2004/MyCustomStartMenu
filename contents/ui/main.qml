import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    switchWidth: Kirigami.Units.gridUnit * 5
    switchHeight: Kirigami.Units.gridUnit * 5

    Plasmoid.icon: Plasmoid.configuration.panelIcon !== ""
                   ? Plasmoid.configuration.panelIcon : "dashboard-show"

    toolTipMainText: "Custom Start Menu"
    toolTipSubText: {
        var s = DashState.sys;
        return "CPU " + Math.round(s.cpu * 100) + "%  ·  RAM " + Math.round(s.mem * 100)
            + "%  ·  " + (DashState.sys.battery >= 0 ? "Battery " + DashState.sys.battery + "%" : "System, media & apps");
    }

    compactRepresentation: Compact { }
    fullRepresentation: Full { }

    Component.onCompleted: {
        DashState.refreshInterval = Plasmoid.configuration.refreshInterval;
        DashState.init();
    }

    onExpandedChanged: expanded => {
        if (expanded) {
            DashState.resetView();
            // pick up newly installed/removed apps and pin changes
            DashState.rescanApps();
            DashState.readFavorites();
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onRefreshIntervalChanged() {
            DashState.refreshInterval = Plasmoid.configuration.refreshInterval;
        }
    }

    Connections {
        target: DashState
        function onRequestClose() {
            root.expanded = false;
        }
    }

    component Compact: Item {
        id: comp

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.configuration.panelIcon !== ""
                    ? Plasmoid.configuration.panelIcon : "dashboard-show"
            active: compHover.hovered
        }

        HoverHandler {
            id: compHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.expanded = !root.expanded
        }
    }
}
