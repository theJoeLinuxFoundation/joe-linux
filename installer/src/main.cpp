// joe Linux's installer. See README.md in this directory.
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>

#include "backend.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("joe-installer"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Install joe Linux"));
    QGuiApplication::setDesktopFileName(QStringLiteral("org.joelinux.Installer"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Installs joe Linux onto a disk of this computer."));
    parser.addHelpOption();
    QCommandLineOption autotest(QStringLiteral("autotest"),
        QStringLiteral("Install onto DISK without waiting for anyone, through the same pages and "
                       "actions a person would use, then exit with the result. For automated tests."),
        QStringLiteral("DISK"));
    parser.addOption(autotest);
    QCommandLineOption beside(QStringLiteral("beside"),
        QStringLiteral("With --autotest, install beside what is on DISK, in its free space."));
    parser.addOption(beside);
    QCommandLineOption enforce(QStringLiteral("enforce"),
        QStringLiteral("With --autotest, make the installed system enforce the security module."));
    parser.addOption(enforce);
    QCommandLineOption importOption(QStringLiteral("import"),
        QStringLiteral("With --autotest, bring over the accounts of the system mounted at ROOT."), QStringLiteral("ROOT"));
    parser.addOption(importOption);
    QCommandLineOption screenshots(QStringLiteral("screenshots"),
        QStringLiteral("With --autotest, save a picture of each page in DIR."), QStringLiteral("DIR"));
    parser.addOption(screenshots);
    parser.process(app);

    // The pages are drawn by the installer itself, in the Basic style,
    // following the desktop's light or dark appearance.
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QQmlApplicationEngine engine;
    auto *backend = engine.singletonInstance<Backend *>("Joe.Installer", "Backend");
    if (backend && parser.isSet(autotest))
        backend->setAutotestDisk(parser.value(autotest));
    if (backend && parser.isSet(beside))
        backend->setAutotestBeside(true);
    if (backend && parser.isSet(enforce))
        backend->setAutotestEnforce(true);
    if (backend && parser.isSet(importOption))
        backend->setAutotestImport(parser.value(importOption));
    if (backend && parser.isSet(screenshots))
        backend->setScreenshotDir(parser.value(screenshots));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app, [](QObject *root) {
        if (auto *window = qobject_cast<QQuickWindow *>(root))
            QObject::connect(window, &QQuickWindow::frameSwapped, window,
                             [] { qInfo("Installer window is ready"); }, Qt::SingleShotConnection);
    });
    engine.loadFromModule("Joe.Installer", "Main");
    return app.exec();
}
