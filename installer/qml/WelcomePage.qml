import QtQuick
import QtQuick.Layouts

PageFrame {
    id: page
    signal proceed()
    signal leave()

    title: qsTr("Install %1").arg(Backend.systemName)
    body: qsTr("joe Linux can be installed beside the system already on this computer, in free space on its disk, or take a whole disk. Nothing is changed until you confirm.\n\nThis is a beta release for testing. Keep copies of anything that matters to you.")

    actions: [
        ActionButton { text: qsTr("Try joe Linux"); onClicked: page.leave() },
        Item { Layout.fillWidth: true },
        ActionButton { text: qsTr("Install"); kind: "suggested"; focus: true; onClicked: page.proceed() }
    ]
}
