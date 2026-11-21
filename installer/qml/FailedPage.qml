import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

PageFrame {
    id: page
    signal leave()
    signal again()

    readonly property bool installing: Backend.failedDuring === Backend.Installing
    title: installing ? qsTr("The installation didn't finish")
        : Backend.failedDuring === Backend.Listing ? qsTr("Couldn't list the disks")
        : qsTr("Couldn't look for accounts to import")
    body: Backend.error

    Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        visible: page.installing && Backend.log.length > 0
        text: qsTr("The chosen disk may be partly written; no other disk was changed. What happened is below.")
        font.family: Theme.family
        font.pixelSize: Theme.bodySize
        color: Theme.ink
    }
    ScrollView {
        visible: page.installing && Backend.log.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: 260
        clip: true
        background: Rectangle { radius: Theme.radius; color: Theme.surface; border.width: 1; border.color: Theme.hairline }
        TextArea {
            readOnly: true
            text: Backend.log
            wrapMode: TextEdit.Wrap
            font.family: Theme.monoFamily
            font.pixelSize: Theme.smallSize - 1
            color: Theme.ink
            padding: 14
            background: null
        }
    }

    actions: [
        ActionButton { text: qsTr("Close"); onClicked: page.leave() },
        Item { Layout.fillWidth: true },
        ActionButton { text: page.installing ? qsTr("Start Over") : qsTr("Retry"); kind: "suggested"; onClicked: page.again() }
    ]
}
