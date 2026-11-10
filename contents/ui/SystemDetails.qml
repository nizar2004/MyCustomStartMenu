import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "js/Utils.js" as Utils

// Detailed system information panel (the sidebar view opened by clicking
// the system card). Extracted from AppsTab; `tab` is the AppsTab instance.
ColumnLayout {
    id: detailPanel
    property Item tab: null

    anchors.fill: parent
    visible: tab ? tab.detailedInfo : false
    opacity: visible ? 1 : 0
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
            onClicked: detailPanel.tab.detailedInfo = false
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
                     : detailPanel.tab.accent
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
