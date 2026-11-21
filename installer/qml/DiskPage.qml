import QtQuick
import QtQuick.Layouts

PageFrame {
    id: page
    property int chosen: -1
    // Whether joe goes into the chosen disk's free space, keeping what is
    // there, rather than over the whole disk.
    property bool beside: false
    readonly property var disk: chosen >= 0 ? Backend.disks.get(chosen) : ({})
    signal back()
    signal proceed()

    onChosenChanged: beside = chosen >= 0 && disk.canBeside === true

    title: qsTr("Choose a disk")
    body: qsTr("joe Linux can go into free space on a disk, beside the system already there, or take a whole disk. You confirm before anything is changed.")

    Text {
        visible: Backend.state === Backend.Listing
        text: qsTr("Looking for disks…")
        font.family: Theme.family
        font.pixelSize: Theme.bodySize
        color: Theme.muted
    }
    Text {
        visible: Backend.state !== Backend.Listing && Backend.disks.usableCount === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Backend.disks.minimumDiskSizeText && Backend.disks.minimumBesideSizeText
              ? qsTr("None of this computer's disks can be used. joe Linux needs a disk of at least %1, or %2 of free space beside another system, not counting the installation medium, with nothing on it in use.")
                    .arg(Backend.disks.minimumDiskSizeText).arg(Backend.disks.minimumBesideSizeText)
              : qsTr("None of this computer's disks can be used.")
        font.family: Theme.family
        font.pixelSize: Theme.bodySize
        color: Theme.ink
    }

    // The disks as one group, in the manner of GNOME's boxed lists.
    Rectangle {
        visible: Backend.disks.count > 0 && Backend.state !== Backend.Listing
        Layout.fillWidth: true
        implicitHeight: rows.implicitHeight
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.hairline
        clip: true

        Column {
            id: rows
            width: parent.width
            Repeater {
                model: Backend.disks
                delegate: Rectangle {
                    id: row
                    required property int index
                    required property string name
                    required property string sizeText
                    required property string transportText
                    required property bool usable
                    required property bool selectable
                    required property string reason
                    required property bool canBeside
                    required property string besideWhat
                    required property string besideSizeText
                    required property var contents
                    readonly property bool selected: page.chosen === index
                    width: rows.width
                    implicitHeight: text.implicitHeight + 32
                    color: "transparent"
                    Rectangle { visible: row.index > 0; anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.hairline }
                    // The selection, inset so that it never meets the
                    // group's rounded corners.
                    Rectangle {
                        anchors { fill: parent; margins: 4 }
                        radius: Theme.radius - 4
                        color: row.selected ? Qt.alpha(Theme.accent, 0.12)
                             : (hover.hovered && row.selectable ? Qt.alpha(Theme.ink, 0.04) : "transparent")
                    }

                    HoverHandler { id: hover }
                    TapHandler { enabled: row.selectable; onTapped: page.chosen = row.index }
                    activeFocusOnTab: selectable
                    Keys.onSpacePressed: if (selectable) page.chosen = index
                    Rectangle {
                        anchors.fill: parent
                        visible: row.activeFocus
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.accent
                        radius: 4
                    }

                    // The choice marker.
                    Rectangle {
                        id: mark
                        anchors { left: parent.left; leftMargin: 18; top: parent.top; topMargin: 18 }
                        width: 20; height: 20; radius: 10
                        color: "transparent"
                        border.width: row.selected ? 6 : 2
                        border.color: row.selected ? Theme.accent : Theme.muted
                        opacity: row.selectable ? 1 : 0.35
                    }
                    Column {
                        id: text
                        anchors { left: mark.right; leftMargin: 14; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 16 }
                        spacing: 3
                        opacity: row.selectable ? 1 : 0.55
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: row.name
                            font.family: Theme.family
                            font.pixelSize: Theme.bodySize + 1
                            font.weight: Font.Bold
                            color: Theme.ink
                        }
                        Text {
                            width: parent.width
                            text: [row.sizeText, row.transportText, qsTr("disk")].filter(s => s.length > 0).join(" ")
                            font.family: Theme.family
                            font.pixelSize: Theme.smallSize
                            color: Theme.muted
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: row.contents.length > 0 ? qsTr("Holds %1").arg(row.contents.join(", ")) : qsTr("Holds nothing the installer recognizes")
                            font.family: Theme.family
                            font.pixelSize: Theme.smallSize
                            color: Theme.muted
                        }
                        Text {
                            visible: row.canBeside
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: qsTr("Room for joe Linux beside %1: %2 free").arg(row.besideWhat).arg(row.besideSizeText)
                            font.family: Theme.family
                            font.pixelSize: Theme.smallSize
                            font.weight: Font.Medium
                            color: Theme.accent
                        }
                        Text {
                            visible: !row.selectable
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: qsTr("Can't be used: %1").arg(row.reason)
                            font.family: Theme.family
                            font.pixelSize: Theme.smallSize
                            font.weight: Font.Medium
                            color: Theme.ink
                        }
                    }
                }
            }
        }
    }

    // How to install on the chosen disk, when there is a choice.
    Rectangle {
        visible: page.chosen >= 0 && page.disk.canBeside === true
        Layout.fillWidth: true
        Layout.topMargin: 8
        implicitHeight: how.implicitHeight
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.hairline
        clip: true
        Column {
            id: how
            width: parent.width
            Choice {
                checked: page.beside
                enabled: true
                title: qsTr("Install beside %1").arg(page.disk.besideWhat || "")
                detail: qsTr("joe Linux takes the %1 of free space. %2 is kept, and when the computer starts you choose which system to use.")
                            .arg(page.disk.besideSizeText || "").arg(page.disk.besideWhat || "")
                onPicked: page.beside = true
            }
            Choice {
                first: false
                checked: !page.beside
                enabled: page.disk.usable === true
                title: qsTr("Erase the disk")
                detail: page.disk.usable === true ? qsTr("Everything on the disk is deleted, and joe Linux takes all of it.")
                                                  : qsTr("Can't be used: %1").arg(page.disk.reason || "")
                onPicked: page.beside = false
            }
        }
    }
    // Erasing is the only way, but the disk holds something: say how to keep it.
    Text {
        visible: page.chosen >= 0 && page.disk.canBeside !== true && (page.disk.layout || []).length > 0
        Layout.fillWidth: true
        Layout.topMargin: 8
        wrapMode: Text.Wrap
        text: Backend.disks.minimumBesideSizeText
              ? qsTr("To keep what is on this disk, make room for joe Linux first. In Windows, open Disk Management, right-click the Windows partition, choose Shrink Volume and leave at least %1 free; then start this installer again. (%2.)")
                    .arg(Backend.disks.minimumBesideSizeText).arg(page.disk.besideReason || "")
              : qsTr("To keep what is on this disk, make free space and start the installer again. (%1.)").arg(page.disk.besideReason || "")
        font.family: Theme.family
        font.pixelSize: Theme.smallSize
        color: Theme.muted
    }

    actions: [
        ActionButton { text: qsTr("Back"); enabled: Backend.state === Backend.Idle; onClicked: page.back() },
        Item { Layout.fillWidth: true },
        ActionButton {
            text: qsTr("Continue")
            kind: "suggested"
            enabled: Backend.state === Backend.Idle && page.chosen >= 0
            onClicked: page.proceed()
        }
    ]

    // One option of a choice, in the manner of a boxed list's radio rows.
    component Choice: Rectangle {
        id: choice
        property bool first: true
        property bool checked: false
        property string title
        property string detail
        signal picked()
        width: parent ? parent.width : 0
        implicitHeight: words.implicitHeight + 28
        color: "transparent"
        opacity: enabled ? 1 : 0.55
        Rectangle { visible: !choice.first; anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.hairline }
        TapHandler { enabled: choice.enabled; onTapped: choice.picked() }
        activeFocusOnTab: enabled
        Keys.onSpacePressed: if (enabled) picked()
        Rectangle {
            id: dot
            anchors { left: parent.left; leftMargin: 18; top: parent.top; topMargin: 16 }
            width: 20; height: 20; radius: 10
            color: "transparent"
            border.width: choice.checked ? 6 : 2
            border.color: choice.checked ? Theme.accent : Theme.muted
        }
        Column {
            id: words
            anchors { left: dot.right; leftMargin: 14; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 14 }
            spacing: 3
            Text {
                width: parent.width
                text: choice.title
                font.family: Theme.family
                font.pixelSize: Theme.bodySize
                font.weight: Font.Bold
                color: Theme.ink
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: choice.detail
                font.family: Theme.family
                font.pixelSize: Theme.smallSize
                color: Theme.muted
            }
        }
    }
}
