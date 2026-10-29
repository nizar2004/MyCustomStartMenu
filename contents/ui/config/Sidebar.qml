import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: page

    width: childrenRect.width
    height: childrenRect.height

    property alias cfg_showUserCard: userChk.checked
    property alias cfg_showSystemCard: sysChk.checked
    property alias cfg_showMediaCard: mediaChk.checked
    property alias cfg_showPowerButtons: powerChk.checked

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Sidebar Cards")
        }

        PC3.CheckBox {
            id: userChk
            text: i18n("Show user avatar and name")
            checked: true
        }

        PC3.CheckBox {
            id: sysChk
            text: i18n("Show system monitor card")
            checked: true
        }

        PC3.CheckBox {
            id: mediaChk
            text: i18n("Show media player card")
            checked: true
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Session")
        }

        PC3.CheckBox {
            id: powerChk
            text: i18n("Show power buttons (Log out, Reboot, Power off)")
            checked: true
        }
    }
}
