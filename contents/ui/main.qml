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
    // runtime from /etc/os-release); otherwise the generic fallback.
    // NOTE: reads DashState.osId/osLogos DIRECTLY so the binding re-evaluates
    // when osid.sh reports in (a function call like osLogo() would freeze
    // on its first evaluation — that's why the icon stayed blank).
    readonly property string shortcutIcon: {
        var cfg = Plasmoid.configuration.panelIcon;
        if (cfg !== "") { return cfg; }
        var file = DashState.osLogos[DashState.osId];
        return file ? Qt.resolvedUrl("../icons/" + file).toString() : "dashboard-show";
    }

    // meta icon (widget explorer, tooltips): theme-safe name — the visible
    // panel button is drawn by Compact below, using the distro logo
    Plasmoid.icon: Plasmoid.configuration.panelIcon !== ""
                   ? Plasmoid.configuration.panelIcon : "dashboard-show"

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
        // fast refresh while open, slow idle tick while collapsed
        DashState.setSysPollForeground(expanded);
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

        // Bundled distro logos are local file URLs → render with Image (PNG is
        // bulletproof in QML). If the image errors or is empty, fall back to
        // the generic theme icon so the button is never blank.
        Image {
            id: logoImg
            anchors.fill: parent
            // slightly smaller than the button slot so it doesn't touch the edges
            anchors.margins: Math.round(parent.width * 0.10)
            source: {
                var s = root.shortcutIcon;
                return (s && s.indexOf("file://") === 0) ? s : "";
            }
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: false
        }

        Kirigami.Icon {
            anchors.fill: parent
            visible: logoImg.source === "" || logoImg.status === Image.Error
            source: "dashboard-show"
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
