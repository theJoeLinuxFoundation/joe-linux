import QtQuick
import QtQuick.Layouts

PageFrame {
    id: page
    required property string importRoot
    signal leave()

    title: qsTr("joe Linux is installed")
    body: importRoot.length > 0
        ? qsTr("Remove the installation medium, then restart. Sign in with an account from your previous system using its existing password.")
        : qsTr("Remove the installation medium, then restart. When joe Linux starts, it asks for your language, keyboard and time zone, and sets up your account.")

    DiskStrip { Layout.fillWidth: true; joe: true; fill: 1 }

    actions: [
        ActionButton { text: qsTr("Keep Using the Live System"); onClicked: page.leave() },
        Item { Layout.fillWidth: true },
        ActionButton { text: qsTr("Restart"); kind: "suggested"; focus: true; onClicked: Backend.restart() }
    ]
}
