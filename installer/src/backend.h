// The installer's connection to dave and pour. Listing disks runs
// `dave install-system --list --json` as the live user; installing runs
// `dave install-system --disk ... --json` as root through pkexec, inside
// systemd-inhibit so that the machine neither sleeps nor powers off while the
// disk is being written. dave reports what it is doing one JSON object per
// line; this turns those lines into properties and signals for the pages.
// Other Linux systems whose accounts could be brought over are those
// `pour scan --json` finds mounted (dave install-system --import ROOT).
#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include "diskmodel.h"

class Backend : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(DiskModel *disks READ disks CONSTANT)
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(State failedDuring READ failedDuring NOTIFY stateChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString step READ step NOTIFY progressChanged)
    Q_PROPERTY(QString log READ log NOTIFY logChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(QString systemName READ systemName CONSTANT)
    Q_PROPERTY(QString autotestDisk READ autotestDisk CONSTANT)
    Q_PROPERTY(bool autotestBeside READ autotestBeside CONSTANT)
    Q_PROPERTY(bool autotestEnforce READ autotestEnforce CONSTANT)
    Q_PROPERTY(QString autotestImport READ autotestImport CONSTANT)
    // [{root, name, device}]: systems mounted from disks, not the medium's.
    Q_PROPERTY(QVariantList systems READ systems NOTIFY systemsChanged)
    Q_PROPERTY(QString screenshotDir READ screenshotDir CONSTANT)

public:
    enum class State { Idle, Listing, Scanning, Installing, Done, Failed };
    Q_ENUM(State)

    explicit Backend(QObject *parent = nullptr);

    DiskModel *disks() { return &m_disks; }
    State state() const { return m_state; }
    State failedDuring() const { return m_failedDuring; }
    double progress() const { return m_progress; }
    QString step() const { return m_step; }
    QString log() const { return m_log; }
    QString error() const { return m_error; }
    QString systemName() const;
    QString autotestDisk() const { return m_autotestDisk; }
    void setAutotestDisk(const QString &disk) { m_autotestDisk = disk; }
    bool autotestBeside() const { return m_autotestBeside; }
    void setAutotestBeside(bool beside) { m_autotestBeside = beside; }
    bool autotestEnforce() const { return m_autotestEnforce; }
    void setAutotestEnforce(bool enforce) { m_autotestEnforce = enforce; }
    QString autotestImport() const { return m_autotestImport; }
    void setAutotestImport(const QString &root) { m_autotestImport = root; }
    QVariantList systems() const { return m_systems; }
    QString screenshotDir() const { return m_screenshotDir; }
    void setScreenshotDir(const QString &dir) { m_screenshotDir = dir; }

    Q_INVOKABLE void refreshDisks();
    Q_INVOKABLE void findSystems();
    // beside: into the disk's free space, keeping what is there.
    // enforce: the installed system boots with the security module enforcing.
    // importRoot: where another system is mounted, to bring its accounts
    // over; empty for none.
    Q_INVOKABLE void install(const QString &diskPath, bool beside, bool enforce, const QString &importRoot);
    Q_INVOKABLE void restart();

signals:
    void stateChanged();
    void progressChanged();
    void logChanged();
    void disksListed();
    void systemsChanged();

private:
    QProcess *newProcess();
    void setState(State state, const QString &error = {});
    void appendLog(const QString &text);
    void handleLine(const QByteArray &line);
    void installFinished(int exitCode, QProcess::ExitStatus status);

    DiskModel m_disks;
    State m_state = State::Idle;
    State m_failedDuring = State::Idle;
    double m_progress = 0;
    QString m_step;
    QString m_log;
    QString m_error;
    QString m_autotestDisk;
    bool m_autotestBeside = false;
    bool m_autotestEnforce = false;
    QString m_autotestImport;
    QVariantList m_systems;
    QString m_screenshotDir;
    QProcess *m_install = nullptr;
    QByteArray m_pending;
};
