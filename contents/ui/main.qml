import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "js/Utils.js" as Utils

PlasmoidItem {
    id: root

    switchWidth: Kirigami.Units.gridUnit * 5
    switchHeight: Kirigami.Units.gridUnit * 5

    // shortcut icon: explicit user choice wins; otherwise the running
    // distro's bundled logo (Arch/CachyOS/Ubuntu/Mint/Manjaro detected at
    // runtime from /etc/os-release); otherwise the generic fallback
    readonly property string shortcutIcon: {
        if (Plasmoid.configuration.panelIcon !== "") {
            return Plasmoid.configuration.panelIcon;
        }
        var logo = DashState.osLogo();
        return logo !== "" ? logo : "dashboard-show";
    }

    Plasmoid.icon: root.shortcutIcon

    toolTipMainText: DashState.osPretty !== "" ? DashState.osPretty : "Custom Start Menu"
    toolTipSubText: {
        var s = DashState.sys;
        var parts = ["CPU " + Math.round(s.cpu * 100) + "%",
                     "RAM " + Math.round(s.mem * 100) + "%"];
        var t = s.cpuTemp > 0 ? s.cpuTemp : s.temp;
        if (t > 0) { parts.push(Math.round(t) + "°C"); }
        if (s.down > 0 || s.up > 0) {
            parts.push("↓ " + Utils.fmtSpeed(s.down));
        }
        if (s.battery >= 0) { parts.push("Battery " + s.battery + "%"); }
        return parts.join("  ·  ");
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
        } else {
            // no reason to keep polling the phone while hidden
            DashState.closePhonePoll();
            DashState.closePhoneNotifs();
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
            source: root.shortcutIcon
            active: compHover.hovered
        }

        scale: compPress.pressed ? 0.88 : (compHover.hovered ? 1.06 : 1.0)
        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: compHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: compPress
            onTapped: root.expanded = !root.expanded
        }
    }
}
