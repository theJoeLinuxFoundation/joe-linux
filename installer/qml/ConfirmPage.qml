import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

PageFrame {
    id: page
    property var disk: ({})
    // Into the free space, keeping what is on the disk.
    property bool beside: false
    property alias understood: understood.checked
    property alias enforce: enforce.checked
    // Where another system is mounted, whose accounts are brought over; ""
    // for none. Chosen from Backend.systems.
    property string importRoot: ""
    signal back()
    signal proceed()

    title: beside ? qsTr("Install beside %1?").arg(disk.besideWhat) : qsTr("Erase %1?").arg(disk.name)
    body: beside
        ? qsTr("joe Linux goes into the %1 of free space on %2. %3 and everything else on the disk are kept. When the computer starts, a menu lets you choose which system to use; it starts joe Linux unless you choose otherwise.")
            .arg(disk.besideSizeText).arg(disk.name).arg(disk.besideWhat)
        : qsTr("Everything on %1 (%2) is deleted and joe Linux is installed in its place. This can't be undone.").arg(disk.name).arg(disk.sizeText)

    Text {
        text: qsTr("The disk now")
        font.family: Theme.family
        font.pixelSize: Theme.smallSize
        font.weight: Font.Medium
        color: Theme.muted
    }
    DiskStrip {
        Layout.fillWidth: true
        segments: page.disk.segments || []
        layout: page.disk.layout || []
        Text {
            visible: (!page.disk.segments || page.disk.segments.length === 0) && (!page.disk.layout || page.disk.layout.length === 0)
            anchors.centerIn: parent
            text: qsTr("Nothing the installer recognizes")
            font.family: Theme.family
            font.pixelSize: Theme.smallSize
            color: Theme.muted
        }
    }
    Text {
        text: qsTr("After installing")
        topPadding: 6
        font.family: Theme.family
        font.pixelSize: Theme.smallSize
        font.weight: Font.Medium
        color: Theme.muted
    }
    DiskStrip {
        Layout.fillWidth: true
        joe: true
        layout: page.beside ? (page.disk.layout || []) : []
        region: page.beside ? { start: page.disk.besideStart, size: page.disk.besideFraction } : null
    }

    CheckOption {
        id: understood
        visible: !page.beside
        Layout.topMargin: 14
        text: qsTr("I understand that everything on %1 will be erased").arg(page.disk.name)
        tint: Theme.destructive
        onTint: Theme.onDestructive
    }

    // The security module only logs unless the installed system is booted
    // with joe=enforce; this is where a person opts in (dave install-system
    // --enforce).
    CheckOption {
        id: enforce
        Layout.topMargin: page.beside ? 14 : 4
        text: qsTr("Enforce the security module")
    }
    Text {
        Layout.fillWidth: true
        leftPadding: 34
        text: qsTr("Programs that run with administrator rights are held to what their packages declare, and anything else they try is refused. Without this, joe Linux only records what it would have refused. Some programs may not work while enforcing.")
        font.family: Theme.family
        font.pixelSize: Theme.smallSize
        wrapMode: Text.Wrap
        color: Theme.muted
    }

    // Accounts from another Linux system (pour): offered for the systems
    // that are mounted, which are on other disks, since a disk in use cannot
    // be installed onto.
    Text {
        text: qsTr("Accounts")
        topPadding: 10
        font.family: Theme.family
        font.pixelSize: Theme.smallSize
        font.weight: Font.Medium
        color: Theme.muted
    }
    ComboBox {
        id: importChoice
        Layout.fillWidth: true
        visible: Backend.systems.length > 0
        model: [qsTr("Create an account when joe Linux first starts")].concat(
            Backend.systems.map(s => qsTr("Bring the accounts and homes from %1 (%2)").arg(s.name).arg(s.device)))
        font.family: Theme.family
        font.pixelSize: Theme.bodySize
        currentIndex: Math.max(0, Backend.systems.findIndex(s => s.root === page.importRoot) + 1)
        onActivated: index => page.importRoot = index === 0 ? "" : Backend.systems[index - 1].root
    }
    Text {
        Layout.fillWidth: true
        text: Backend.systems.length > 0
            ? qsTr("Brought-over accounts keep their passwords, and those who could administer that system can administer this one. The first-run setup is then skipped.")
            : qsTr("To bring accounts and homes from another Linux system on another disk, open that disk in Files, then look again.")
        font.family: Theme.family
        font.pixelSize: Theme.smallSize
        wrapMode: Text.Wrap
        color: Theme.muted
    }
    ActionButton {
        visible: Backend.systems.length === 0
        text: qsTr("Look Again")
        enabled: Backend.state === Backend.Idle
        onClicked: Backend.findSystems()
    }

    actions: [
        ActionButton { text: qsTr("Back"); enabled: Backend.state === Backend.Idle; onClicked: page.back() },
        Item { Layout.fillWidth: true },
        ActionButton {
            text: page.beside ? qsTr("Install") : qsTr("Erase and Install")
            kind: page.beside ? "suggested" : "destructive"
            enabled: Backend.state === Backend.Idle && (page.beside || understood.checked)
            onClicked: page.proceed()
        }
    ]
}
