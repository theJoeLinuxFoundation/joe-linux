// The installer's window: the pages in order, and an automated run of the
// same pages for the tests (joe-installer --autotest DISK).
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

ApplicationWindow {
    id: window
    width: 960
    height: 700
    minimumWidth: 600
    minimumHeight: 540
    visible: true
    visibility: Window.Maximized
    title: qsTr("Install joe Linux")
    color: Theme.window
    font.family: Theme.family

    onClosing: close => { close.accepted = Backend.state !== Backend.Installing }

    // The disk chosen on the disk page, as the model describes it, and
    // whether joe goes beside what is on it.
    property var disk: ({})
    property bool beside: false
    // Whether the installed system boots with the security module enforcing.
    property bool enforce: false
    // Where another system is mounted whose accounts are brought over; "" for none.
    property string importRoot: ""

    function showDisks() {
        stack.push(diskPage)
        Backend.refreshDisks()
    }
    function confirm(row, beside) {
        window.disk = Backend.disks.get(row)
        window.beside = beside
        stack.push(confirmPage)
        Backend.findSystems()
    }
    function install() {
        stack.replace(null, progressPage)
        Backend.install(window.disk.path, window.beside, window.enforce, window.importRoot)
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: welcomePage
    }

    Component { id: welcomePage; WelcomePage { onProceed: window.showDisks(); onLeave: Qt.quit() } }
    Component { id: diskPage; DiskPage { onBack: stack.pop(); onProceed: window.confirm(chosen, beside) } }
    Component { id: confirmPage; ConfirmPage { disk: window.disk; beside: window.beside; onBack: stack.pop(); onProceed: { window.enforce = enforce; window.importRoot = importRoot; window.install() } } }
    Component { id: progressPage; ProgressPage { disk: window.disk; beside: window.beside } }
    Component { id: donePage; DonePage { importRoot: window.importRoot; onLeave: Qt.quit() } }
    Component {
        id: failedPage
        FailedPage {
            onLeave: Qt.quit()
            onAgain: {
                if (Backend.failedDuring === Backend.Installing) {
                    stack.replace(null, welcomePage)
                    window.showDisks()
                } else {
                    stack.pop()
                    if (Backend.failedDuring === Backend.Listing)
                        Backend.refreshDisks()
                    else
                        Backend.findSystems()
                }
            }
        }
    }

    Connections {
        target: Backend
        function onStateChanged() {
            if (Backend.state === Backend.Done)
                stack.replace(null, donePage)
            else if (Backend.state === Backend.Failed) {
                if (Backend.failedDuring === Backend.Installing)
                    stack.replace(null, failedPage)
                else
                    stack.push(failedPage)
            }
        }
    }

    // --autotest: each page is shown for a moment (so that it can be looked
    // at, and captured), then the action a person would take is taken.
    QtObject {
        id: autotest
        readonly property bool active: Backend.autotestDisk.length > 0
        property int stage: 0

        function report(what) {
            console.log("autotest: " + what)
            if (Backend.screenshotDir.length > 0 && what.startsWith("page ")) {
                const name = what.slice(5).split(":")[0]
                stack.grabToImage(function (shot) {
                    shot.saveToFile(Backend.screenshotDir + "/" + name + ".png")
                })
            }
        }
    }
    Timer {
        running: autotest.active
        interval: 3000
        repeat: true
        onTriggered: {
            const page = stack.currentItem
            if (Backend.state === Backend.Failed && autotest.stage !== 7) {
                autotest.report("page failed: " + page.title + ": " + Backend.error)
                autotest.stage = 7
                return
            }
            switch (autotest.stage) {
            case 0:
                autotest.report("page welcome")
                window.showDisks()
                autotest.stage = 1
                break
            case 1:
                if (Backend.state === Backend.Listing)
                    return
                autotest.report("page disk")
                const row = Backend.disks.indexOfPath(Backend.autotestDisk)
                const found = row >= 0 ? Backend.disks.get(row) : null
                if (!found || !(Backend.autotestBeside ? found.canBeside : found.usable)) {
                    autotest.report("disk " + Backend.autotestDisk + " cannot be used")
                    Qt.exit(2)
                    return
                }
                page.chosen = row
                page.beside = Backend.autotestBeside
                autotest.stage = 2
                break
            case 2:
                window.confirm(page.chosen, page.beside)
                autotest.stage = 3
                break
            case 3:
                if (Backend.state === Backend.Scanning)
                    return
                autotest.report("page confirm")
                if (!window.beside)
                    page.understood = true
                page.enforce = Backend.autotestEnforce
                page.importRoot = Backend.autotestImport
                autotest.stage = 4
                break
            case 4:
                // As the page's button does: what it shows is what is installed.
                page.proceed()
                autotest.report("page progress")
                autotest.stage = 5
                break
            case 5:
                if (Backend.state === Backend.Done) {
                    autotest.report("page done")
                    autotest.stage = 6

                }
                break
            case 6:
                Qt.exit(0)
                break
            case 7:
                Qt.exit(1)
                break
            }
        }
    }
}
