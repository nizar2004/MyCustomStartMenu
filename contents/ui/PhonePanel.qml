import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Phone panel (KDE Connect): device/battery card, actions (ring, ping,
// screen mirror), things you read from the phone (notifications, SMS),
// send-to-phone inputs and the send/share row. Extracted from AppsTab;
// `tab` is the AppsTab instance.
ColumnLayout {
    id: panel
    property Item tab: null

    // paired devices are listed when the header is tapped
    property bool deviceListOpen: false

    readonly property bool hasDevice: tab !== null && tab.phoneDev !== null
    readonly property bool reachable: hasDevice && tab.phoneDev.reachable

    anchors.fill: parent
    visible: tab ? tab.phoneMode : false
    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 160 }
    }
    spacing: Kirigami.Units.gridUnit * 0.4

    // collapse the device list whenever the panel is left
    onVisibleChanged: if (!visible) { deviceListOpen = false; }

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
                panel.tab.phoneMode = false;
                panel.tab.notifOpen = false;
                panel.deviceListOpen = false;
                DashState.closePhonePoll();
                DashState.closePhoneNotifs();
            }
            QQC2.ToolTip { text: "Back"; delay: 400 }
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

            // device line: dot shows reachability, and with more than one
            // paired device it becomes a tap-to-switch control
            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: !panel.hasDevice ? Qt.alpha(Kirigami.Theme.textColor, 0.3)
                         : panel.reachable ? "#4caf50"
                         : Kirigami.Theme.neutralTextColor
                }
                Text {
                    Layout.fillWidth: true
                    text: {
                        var d = panel.tab ? panel.tab.phoneDev : null;
                        if (!d) { return "No device connected"; }
                        return d.name + (!d.reachable ? " · Offline" : "");
                    }
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.55)
                }
                Kirigami.Icon {
                    visible: DashState.phoneDevices.length > 1
                    Layout.alignment: Qt.AlignVCenter
                    source: panel.deviceListOpen ? "arrow-up" : "arrow-down"
                    implicitWidth: 10
                    implicitHeight: 10
                    opacity: devPickHover.hovered ? 0.9 : 0.5
                }
                HoverHandler {
                    id: devPickHover
                    enabled: DashState.phoneDevices.length > 1
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: DashState.phoneDevices.length > 1
                    onTapped: panel.deviceListOpen = !panel.deviceListOpen
                }
            }
        }
        // battery chip
        Rectangle {
            visible: panel.hasDevice && DashState.phoneBattery >= 0
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

    // inline device switcher (only with more than one paired device)
    ColumnLayout {
        visible: panel.deviceListOpen && DashState.phoneDevices.length > 1
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: DashState.phoneDevices

            delegate: Rectangle {
                id: devRow
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 32
                radius: 9
                color: devRow.modelData.id === DashState.phoneId
                       ? Qt.alpha(panel.tab.accent, 0.15)
                       : (devRowHover.hovered
                          ? Qt.alpha(Kirigami.Theme.textColor, 0.08)
                          : Qt.alpha(Kirigami.Theme.textColor, 0.04))
                border.width: 1
                border.color: devRow.modelData.id === DashState.phoneId
                              ? Qt.alpha(panel.tab.accent, 0.4)
                              : Qt.alpha(Kirigami.Theme.textColor, 0.07)
                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 7

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: devRow.modelData.reachable ? "#4caf50"
                             : Qt.alpha(Kirigami.Theme.textColor, 0.3)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: devRow.modelData.name
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                    }
                    Kirigami.Icon {
                        visible: devRow.modelData.id === DashState.phoneId
                        Layout.alignment: Qt.AlignVCenter
                        source: "dialog-ok"
                        implicitWidth: 12
                        implicitHeight: 12
                        color: panel.tab.accent
                    }
                }

                HoverHandler {
                    id: devRowHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: {
                        DashState.selectPhone(devRow.modelData.id);
                        panel.deviceListOpen = false;
                        panel.tab.notifOpen = false;
                    }
                }
            }
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
        // NOTE: must be driven by `open`, not `height > 0` — a Layout skips
        // invisible items, so a height-driven visibility would deadlock at 0
        // and the section could never expand.
        visible: open || height > 0
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
        property string tip: ""
        property bool sel: false
        signal triggered()
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        radius: 12
        color: paHv.hovered
               ? Qt.alpha(Kirigami.Theme.textColor, 0.07)
               : pa.sel
               ? Qt.alpha(panel.tab.accent, 0.15)
               : Qt.alpha(Kirigami.Theme.textColor, 0.045)
        border.width: 1
        border.color: pa.sel ? Qt.alpha(panel.tab.accent, 0.5)
                             : Qt.alpha(Kirigami.Theme.textColor, 0.08)
        opacity: enabled ? 1 : 0.4
        scale: paTap.pressed ? 0.95 : 1.0
        Behavior on color {
            ColorAnimation { duration: 130 }
        }
        Behavior on opacity {
            NumberAnimation { duration: 130 }
        }
        Behavior on scale {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.centerIn: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 5

            Kirigami.Icon {
                source: pa.icn
                isMask: true
                implicitWidth: 17
                implicitHeight: 17
                color: pa.enabled ? Qt.alpha(Kirigami.Theme.textColor, 0.85)
                     : Qt.alpha(Kirigami.Theme.textColor, 0.35)
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: pa.lbl
                font.pixelSize: 9
                color: pa.sel ? panel.tab.accent
                     : Qt.alpha(Kirigami.Theme.textColor, 0.6)
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: pa.width - 8
                elide: Text.ElideRight
            }
        }

        HoverHandler {
            id: paHv
            cursorShape: Qt.PointingHandCursor
            enabled: pa.enabled
        }
        TapHandler {
            id: paTap
            enabled: pa.enabled
            onTapped: pa.triggered()
        }
        QQC2.ToolTip {
            visible: paHv.hovered && pa.tip !== ""
            text: pa.tip
            delay: 500
        }
    }

    // section header: label on the left, optional refresh/close on the right
    component SectionHeader: RowLayout {
        id: sh
        property string title
        property string actionIcon: ""
        property string actionTip: ""
        property bool closable: false
        signal actionClicked()
        signal closeClicked()

        Layout.fillWidth: true
        spacing: 6

        Text {
            text: sh.title
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
        }
        Item { Layout.fillWidth: true }
        PC3.ToolButton {
            visible: sh.actionIcon !== ""
            implicitWidth: 22
            implicitHeight: 22
            icon.name: sh.actionIcon
            display: QQC2.AbstractButton.IconOnly
            onClicked: sh.actionClicked()
            QQC2.ToolTip { visible: parent.hovered; text: sh.actionTip; delay: 400 }
        }
        PC3.ToolButton {
            visible: sh.closable
            implicitWidth: 22
            implicitHeight: 22
            icon.name: "window-close"
            display: QQC2.AbstractButton.IconOnly
            onClicked: sh.closeClicked()
            QQC2.ToolTip { visible: parent.hovered; text: "Close"; delay: 400 }
        }
    }

    // small cellular signal strength indicator (4 bars)
    component SignalBars: Item {
        id: sb
        property int strength: 0          // 0..4
        implicitWidth: 4 * 3 + 3 * 2
        implicitHeight: 12

        RowLayout {
            anchors.bottom: parent.bottom
            spacing: 2

            Repeater {
                model: 4

                delegate: Rectangle {
                    required property int index
                    Layout.alignment: Qt.AlignBottom
                    Layout.preferredWidth: 3
                    Layout.preferredHeight: 4 + index * 2
                    radius: 1
                    color: index < sb.strength
                           ? Qt.alpha(Kirigami.Theme.textColor, 0.8)
                           : Qt.alpha(Kirigami.Theme.textColor, 0.18)
                }
            }
        }
    }

    // device + battery card
    Rectangle {
        visible: panel.hasDevice
        Layout.fillWidth: true
        Layout.preferredHeight: panel.reachable ? 86 : 104
        radius: 14
        color: Qt.alpha(Kirigami.Theme.textColor, 0.045)
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
        Behavior on Layout.preferredHeight {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

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
                    color: Qt.alpha(panel.tab.accent, 0.15)
                    border.width: 1
                    border.color: Qt.alpha(panel.tab.accent, 0.4)
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "phone"
                    isMask: true
                    color: panel.tab.accent
                    implicitWidth: 22
                    implicitHeight: 22
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: panel.tab.phoneDev ? panel.tab.phoneDev.name : "—"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: Kirigami.Theme.textColor
                }

                // battery / signal line — only meaningful while connected
                // (the phone's battery comes from KDE Connect, so it is
                // unavailable when the device is offline)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: panel.reachable

                    Kirigami.Icon {
                        visible: DashState.phoneBattery >= 0
                        source: {
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
                        visible: DashState.phoneBattery >= 0
                        text: DashState.phoneBattery + "%"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
                    }
                    Kirigami.Icon {
                        visible: DashState.phoneCharging
                        source: "battery-charging"
                        implicitWidth: 12
                        implicitHeight: 12
                        color: "#4fc3f7"
                    }
                    Text {
                        visible: DashState.phoneNetType !== ""
                        text: "· " + DashState.phoneNetType
                        font.pixelSize: 10
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                    }
                    Item { Layout.fillWidth: true }
                    // cellular strength (falls back to a Wi-Fi icon when the
                    // phone reports no cellular data)
                    SignalBars {
                        visible: DashState.phoneSignal >= 0
                        Layout.alignment: Qt.AlignVCenter
                        strength: Math.max(0, Math.min(4, DashState.phoneSignal))
                    }
                    Kirigami.Icon {
                        visible: DashState.phoneSignal < 0
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
                                ? Kirigami.Theme.negativeTextColor : panel.tab.accent)
                        Behavior on width {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }
                }

                // offline hint: the device is paired but not reachable
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    visible: !panel.reachable
                    spacing: 5

                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignVCenter
                        source: "network-disconnect"
                        isMask: true
                        implicitWidth: 11
                        implicitHeight: 11
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.55)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Offline — actions are unavailable until it reconnects"
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.55)
                    }
                }
            }
        }
    }

    // ================= actions that make the phone do something ==========
    PhoneLabel {
        visible: panel.hasDevice
        text2: "ACTIONS"
    }

    RowLayout {
        visible: panel.hasDevice
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { lbl: "Ring",   icn: "notification-active",         act: "ring",   tip: "Ring the phone" },
                { lbl: "Ping",   icn: "document-send",               act: "ping",   tip: "Send a ping to the phone" },
                { lbl: "Mirror", icn: "preferences-desktop-display", act: "mirror", tip: "Mirror the screen (scrcpy over Wi-Fi)" }
            ]

            delegate: PhoneAction {
                required property var modelData
                lbl: (modelData.act === "mirror" && DashState.mirroring) ? "Stop" : modelData.lbl
                icn: (modelData.act === "mirror" && DashState.mirroring) ? "window-close" : modelData.icn
                tip: (modelData.act === "mirror" && DashState.mirroring)
                     ? "Stop the phone mirror" : modelData.tip
                // mirroring goes over adb/Wi-Fi, so it stays usable even when
                // KDE Connect reports the phone as offline
                enabled: modelData.act === "mirror" ? panel.hasDevice : panel.reachable
                sel: modelData.act === "mirror" && DashState.mirroring
                onTriggered: {
                    if (modelData.act === "mirror") {
                        if (DashState.mirroring) {
                            DashState.mirrorStop();
                            panel.tab.showPhoneToast("Closing the phone mirror", "window-close");
                        } else {
                            DashState.mirrorStart();
                            panel.tab.showPhoneToast("Starting the phone mirror…", "preferences-desktop-display");
                        }
                    } else if (modelData.act === "ring") {
                        DashState.phoneAction("ring");
                        panel.tab.showPhoneToast("Ringing your phone…", "notification-active");
                    } else if (modelData.act === "ping") {
                        DashState.phoneAction("ping");
                        panel.tab.showPhoneToast("Ping sent", "document-send");
                    }
                }
            }
        }
    }

    // ================= things you read from the phone ====================
    PhoneLabel {
        visible: panel.hasDevice
        text2: "FROM PHONE"
    }

    RowLayout {
        visible: panel.hasDevice
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { lbl: "Notifications", icn: "notifications", act: "notifs", tip: "Read the phone's notifications" },
                { lbl: "Messages", icn: "dialog-messages", act: "messages", tip: "Read & send SMS (KDE Connect SMS)" }
            ]

            delegate: PhoneAction {
                required property var modelData
                lbl: modelData.lbl
                icn: modelData.icn
                tip: modelData.tip
                enabled: panel.reachable
                sel: modelData.act === "notifs" && panel.tab.notifOpen
                onTriggered: {
                    if (modelData.act === "notifs") {
                        panel.tab.notifOpen = !panel.tab.notifOpen;
                        if (panel.tab.notifOpen) { DashState.fetchPhoneNotifs(); }
                    } else if (modelData.act === "messages") {
                        DashState.phoneAction("messages");
                        panel.tab.showPhoneToast("Opening SMS…", "dialog-messages");
                    }
                }
            }
        }
    }

    // ================= things you send to the phone ======================
    PhoneLabel {
        visible: panel.reachable
        text2: "SEND TO PHONE"
    }

    RowLayout {
        visible: panel.reachable
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { lbl: "File",      icn: "mail-attachment", act: "file",      tip: "Send a file to the phone" },
                { lbl: "Clipboard", icn: "edit-copy",       act: "clipboard", tip: "Send the desktop clipboard" },
                { lbl: "Browse",    icn: "folder-android",  act: "browse",    tip: "Browse phone storage" }
            ]

            delegate: PhoneAction {
                required property var modelData
                lbl: modelData.lbl
                icn: modelData.icn
                tip: modelData.tip
                onTriggered: {
                    if (modelData.act === "file") {
                        DashState.phoneAction("sharefile");
                    } else {
                        DashState.phoneAction(modelData.act);
                        if (modelData.act === "clipboard") {
                            panel.tab.showPhoneToast("Clipboard sent to phone", "edit-copy");
                        } else if (modelData.act === "browse") {
                            panel.tab.showPhoneToast("Mounting phone storage…", "folder-android");
                        }
                    }
                }
            }
        }
    }

    // inputs: send a link + type on the phone
    ColumnLayout {
        visible: panel.reachable
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
                          ? Qt.alpha(panel.tab.accent, 0.5)
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
                    onAccepted: panel.tab.sendPhoneLink()
                }
                PC3.ToolButton {
                    icon.name: "document-send"
                    icon.width: 14
                    icon.height: 14
                    display: QQC2.AbstractButton.IconOnly
                    enabled: linkInput.text.length > 0
                    opacity: enabled ? 1 : 0.35
                    onClicked: panel.tab.sendPhoneLink()
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
                          ? Qt.alpha(panel.tab.accent, 0.5)
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
                    onAccepted: panel.tab.typeOnPhone()
                }
                PC3.ToolButton {
                    icon.name: "document-send"
                    icon.width: 14
                    icon.height: 14
                    display: QQC2.AbstractButton.IconOnly
                    enabled: typeInput.text.length > 0
                    opacity: enabled ? 1 : 0.35
                    onClicked: panel.tab.typeOnPhone()
                    QQC2.ToolTip { text: "Type into the phone"; delay: 300 }
                }
            }
        }
    }

    // phone notifications
    PhoneSection {
        open: panel.tab.notifOpen && panel.reachable

        SectionHeader {
            title: "PHONE NOTIFICATIONS"
            actionIcon: "view-refresh"
            actionTip: "Refresh"
            closable: true
            onActionClicked: DashState.fetchPhoneNotifs()
            onCloseClicked: panel.tab.notifOpen = false
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
                            color: Qt.alpha(panel.tab.accent, 0.9)
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
                                    panel.tab.showPhoneToast("Notification dismissed", "window-close");
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

    // empty state
    ColumnLayout {
        visible: !panel.hasDevice
        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 8

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64

            Rectangle {
                anchors.fill: parent
                radius: 32
                color: Qt.alpha(panel.tab.accent, 0.12)
                border.width: 1
                border.color: Qt.alpha(panel.tab.accent, 0.4)
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                source: "phone"
                isMask: true
                color: panel.tab.accent
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
            text: "Pair a device with KDE Connect, then search again."
            font.pixelSize: 10
            color: Qt.alpha(Kirigami.Theme.textColor, 0.45)
            Layout.alignment: Qt.AlignHCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            PC3.Button {
                Layout.fillWidth: true
                text: "Search again"
                icon.name: "view-refresh"
                onClicked: {
                    DashState.phoneAction("refresh");
                    phoneRefreshTimer.restart();
                    panel.tab.showPhoneToast("Searching for devices…", "view-refresh");
                }
            }
            PC3.Button {
                Layout.fillWidth: true
                text: "Open KDE Connect"
                icon.name: "phone"
                onClicked: DashState.openKdeConnect()
            }
        }
    }
        }
    }
}
