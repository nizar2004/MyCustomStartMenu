import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Phone panel (KDE Connect): device/battery card, actions, touchpad,
// send-to-phone inputs, notifications and phone media. Extracted from
// AppsTab; `tab` is the AppsTab instance.
ColumnLayout {
    id: panel
    property Item tab: null

    anchors.fill: parent
    visible: tab ? tab.phoneMode : false
    opacity: visible ? 1 : 0
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
                panel.tab.phoneMode = false;
                panel.tab.notifOpen = false;
                panel.tab.touchpadOn = false;
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
                    var d = panel.tab.phoneDev;
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
            visible: panel.tab.phoneDev !== null && DashState.phoneBattery >= 0
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
               ? Qt.alpha(panel.tab.accent, 0.15)
               : Qt.alpha(Kirigami.Theme.textColor, 0.045)
        border.width: 1
        border.color: pa.sel ? Qt.alpha(panel.tab.accent, 0.5)
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
        visible: panel.tab.phoneDev !== null
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
                    color: Qt.alpha(panel.tab.accent, 0.15)
                    border.width: 1
                    border.color: Qt.alpha(panel.tab.accent, 0.4)
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "smartphone"
                    isMask: true
                    color: panel.tab.accent
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
                    text: panel.tab.phoneDev ? panel.tab.phoneDev.name : "—"
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
                        visible: panel.tab.phoneDev && panel.tab.phoneDev.reachable
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
                enabled: panel.tab.phoneDev !== null && panel.tab.phoneDev.reachable
                sel: (modelData.act === "touchpad" && panel.tab.touchpadOn)
                  || (modelData.act === "notifs" && panel.tab.notifOpen)
                onTriggered: {
                    if (modelData.act === "touchpad") {
                        panel.tab.touchpadOn = !panel.tab.touchpadOn;
                    } else if (modelData.act === "notifs") {
                        panel.tab.notifOpen = !panel.tab.notifOpen;
                        if (panel.tab.notifOpen) { DashState.fetchPhoneNotifs(); }
                    } else {
                        DashState.phoneAction(modelData.act);
                        if (modelData.act === "ring") {
                            panel.tab.showPhoneToast("Ringing your phone…", "bell");
                        } else if (modelData.act === "ping") {
                            panel.tab.showPhoneToast("Ping sent", "preferences-desktop-notification");
                        }
                    }
                }
            }
        }
    }

    PhoneLabel {
        visible: panel.tab.phoneDev !== null && panel.tab.phoneDev.reachable
        text2: "SEND TO PHONE"
    }

    // second row: send / share actions
    RowLayout {
        visible: panel.tab.phoneDev !== null && panel.tab.phoneDev.reachable
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
                        panel.tab.showPhoneToast("Fetching phone commands…", "system-run");
                    } else {
                        DashState.phoneAction(modelData.act);
                        if (modelData.act === "clipboard") {
                            panel.tab.showPhoneToast("Clipboard sent to phone", "edit-copy");
                        } else if (modelData.act === "browse") {
                            panel.tab.showPhoneToast("Mounting phone storage…", "folder-remote");
                        }
                    }
                }
            }
        }
    }

    // virtual touchpad (mouse control)
    PhoneSection {
        open: panel.tab.touchpadOn
              && panel.tab.phoneDev !== null && panel.tab.phoneDev.reachable

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
                          ? Qt.alpha(panel.tab.accent, 0.5)
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
        visible: panel.tab.phoneDev !== null && panel.tab.phoneDev.reachable
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
        open: panel.tab.notifOpen
              && panel.tab.phoneDev !== null && panel.tab.phoneDev.reachable

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

    // phone media card
    Rectangle {
        visible: panel.tab.phoneDev !== null
                 && panel.tab.phoneDev.reachable
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
                        color: panel.tab.accent
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
                        color: panel.tab.onAccent
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
        visible: panel.tab.phoneDev === null
        Layout.alignment: Qt.AlignHCenter
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
                source: "smartphone"
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
}
