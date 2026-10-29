import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as FileDialogs
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: page

    width: childrenRect.width
    height: childrenRect.height

    property string cfg_panelIcon: "dashboard-show"
    property int cfg_refreshInterval: 1500
    property string cfg_defaultCategory: "all"
    property string cfg_accentOverride: ""

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Panel Icon")
        }

        // icon preview + presets
        RowLayout {
            Kirigami.FormData.label: i18n("Icon:")

            Kirigami.Icon {
                source: cfg_panelIcon !== "" ? cfg_panelIcon : "dashboard-show"
                implicitWidth: 34
                implicitHeight: 34
            }

            Row {
                spacing: 8

                Repeater {
                    model: [
                        "dashboard-show", "view-grid", "applications-system",
                        "start-here-kde", "computer", "view-statistics"
                    ]

                    delegate: Rectangle {
                        id: preset
                        required property int index
                        required property var modelData
                        readonly property bool active: cfg_panelIcon === modelData

                        width: 42
                        height: 42
                        radius: 10
                        color: active ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25)
                                      : Qt.alpha(Kirigami.Theme.textColor, 0.05)
                        border.width: active ? 2 : 1
                        border.color: active ? Kirigami.Theme.highlightColor
                                             : Qt.alpha(Kirigami.Theme.textColor, 0.15)

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: parent.modelData
                            implicitWidth: 22
                            implicitHeight: 22
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cfg_panelIcon = parent.modelData
                        }
                    }
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Custom icon name:")
            spacing: 8

            PC3.TextField {
                id: iconNameField
                Layout.fillWidth: true
                text: cfg_panelIcon
                placeholderText: "any themed icon name"
                onTextChanged: cfg_panelIcon = text
            }

            PC3.Button {
                icon.name: "document-open"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Choose image file…")
                onClicked: iconFileDialog.open()
            }
        }

        FileDialogs.FileDialog {
            id: iconFileDialog
            title: i18n("Choose a custom icon")
            currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
            nameFilters: [i18n("Image files (*.png *.jpg *.jpeg *.svg *.gif *.xpm)")]
            onAccepted: {
                if (selectedFile) {
                    cfg_panelIcon = selectedFile.toString();
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Behavior")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Refresh rate:")

            QQC2.Slider {
                id: refreshSlider
                from: 500
                to: 5000
                stepSize: 250
                implicitWidth: 170
            }
            Text {
                text: (refreshSlider.value / 1000).toFixed(2) + " s"
                font.pixelSize: 12
                color: Kirigami.Theme.textColor
            }
        }

        PC3.ComboBox {
            id: catCombo
            Kirigami.FormData.label: i18n("Opens with:")
            implicitWidth: 170
            implicitHeight: 32
            textRole: "label"
            valueRole: "key"
            model: [
                { label: i18n("All Apps"), key: "all" },
                { label: i18n("Pinned"), key: "pinned" }
            ]
            onActivated: cfg_defaultCategory = currentValue
            Component.onCompleted: currentIndex = indexOfValue(cfg_defaultCategory)
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Appearance")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Accent color:")

            PC3.CheckBox {
                id: useCustom
                text: i18n("Use custom color")
                checked: cfg_accentOverride !== ""
                onToggled: cfg_accentOverride = checked ? "#3DAEE9" : ""
            }
        }

        // preset swatches
        Row {
            Layout.leftMargin: useCustom.checked ? 0 : 0
            visible: useCustom.checked
            spacing: 8

            Repeater {
                model: [
                    "#3DAEE9", "#2ECC71", "#E74C3C", "#F39C12",
                    "#9B59B6", "#1ABC9C", "#E91E63", "#5E81AC"
                ]

                delegate: Rectangle {
                    id: swatch
                    required property int index
                    required property var modelData
                    readonly property bool active: cfg_accentOverride.toUpperCase() === modelData.toUpperCase()

                    width: 30
                    height: 30
                    radius: 15
                    color: modelData
                    border.width: active ? 3 : 1
                    border.color: active ? Kirigami.Theme.textColor : Qt.alpha(Kirigami.Theme.textColor, 0.2)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cfg_accentOverride = parent.modelData
                    }
                }
            }
        }

        PC3.TextField {
            visible: useCustom.checked
            Kirigami.FormData.label: i18n("Custom hex:")
            text: cfg_accentOverride
            placeholderText: "#RRGGBB"
            onEditingFinished: {
                var t = text.trim();
                if (/^#?[0-9A-Fa-f]{6}$/.test(t)) {
                    cfg_accentOverride = t.charAt(0) === "#" ? t : "#" + t;
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: i18n("Leave \"Use custom color\" unchecked to follow the system theme accent. Applies to the selected category, buttons, bars and highlights.")
            wrapMode: Text.WordWrap
            Layout.preferredWidth: 320
            font.pixelSize: 10
            color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
        }
    }

    onCfg_defaultCategoryChanged: {
        catCombo.currentIndex = catCombo.indexOfValue(cfg_defaultCategory);
    }
}
