#include "backend.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

// JOE_INSTALLER_DAVE replaces dave, for trying the pages outside a live
// system with a stand-in that prints what dave would.
static QString dave()
{
    const QString override = qEnvironmentVariable("JOE_INSTALLER_DAVE");
    return override.isEmpty() ? QStringLiteral("/usr/bin/dave") : override;
}

// JOE_INSTALLER_POUR likewise replaces pour.
static QString pour()
{
    const QString override = qEnvironmentVariable("JOE_INSTALLER_POUR");
    return override.isEmpty() ? QStringLiteral("/usr/bin/pour") : override;
}

Backend::Backend(QObject *parent)
    : QObject(parent)
{
}

// The PRETTY_NAME of the system on the medium.
QString Backend::systemName() const
{
    QFile file(QStringLiteral("/usr/lib/os-release"));
    if (file.open(QIODevice::ReadOnly)) {
        const QList<QByteArray> lines = file.readAll().split('\n');
        for (const QByteArray &line : lines) {
            if (line.startsWith("PRETTY_NAME="))
                return QString::fromUtf8(line.mid(12)).remove(QLatin1Char('"'));
        }
    }
    return QStringLiteral("joe Linux");
}

void Backend::setState(State state, const QString &error)
{
    if (state == State::Failed)
        m_failedDuring = m_state;
    m_state = state;
    m_error = error;
    emit stateChanged();
}

void Backend::appendLog(const QString &text)
{
    m_log += text;
    if (!m_log.endsWith(QLatin1Char('\n')))
        m_log += QLatin1Char('\n');
    emit logChanged();
}

// FailedToStart has no matching finished signal. Other errors (including
// a crash) are handled by the process's finished handler.
QProcess *Backend::newProcess()
{
    auto *process = new QProcess(this);
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        if (m_install == process)
            m_install = nullptr;
        process->deleteLater();
        setState(State::Failed, tr("Could not start %1. %2").arg(process->program(), process->errorString()));
    });
    return process;
}

void Backend::refreshDisks()
{
    if (m_state != State::Idle && m_state != State::Failed)
        return;
    setState(State::Listing);
    auto *process = newProcess();
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        const QByteArray out = process->readAllStandardOutput();
        const QByteArray err = process->readAllStandardError();
        if (status != QProcess::NormalExit || code != 0) {
            setState(State::Failed, tr("The disks of this computer could not be listed.\n%1")
                                        .arg(QString::fromUtf8(err).trimmed()));
            return;
        }
        const QJsonObject listing = QJsonDocument::fromJson(out).object();
        if (!listing.value(QLatin1String("disks")).isArray()) {
            setState(State::Failed, tr("dave returned an invalid disk list."));
            return;
        }
        m_disks.setDisks(listing);
        setState(State::Idle);
        emit disksListed();
    });
    process->start(dave(), {QStringLiteral("install-system"), QStringLiteral("--list"), QStringLiteral("--json")});
}

// The Linux systems mounted on this computer, as pour finds them: one
// {"event":"system",...} line each. The live system and the medium's own
// root image are not other systems. Nothing found is not an error: the list
// is simply empty, and the page says how to have one listed.
void Backend::findSystems()
{
    if (m_state != State::Idle && m_state != State::Failed)
        return;
    setState(State::Scanning);
    auto *process = newProcess();
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        // pour scan exits 1 when it finds no mounted system.
        if (status != QProcess::NormalExit || (code != 0 && code != 1)) {
            setState(State::Failed, tr("pour could not scan for accounts. %1")
                                        .arg(QString::fromUtf8(process->readAllStandardError()).trimmed()));
            return;
        }
        QVariantList found;
        const QList<QByteArray> lines = process->readAllStandardOutput().split('\n');
        for (const QByteArray &line : lines) {
            const QJsonObject event = QJsonDocument::fromJson(line).object();
            if (event.value(QLatin1String("event")).toString() != QLatin1String("system"))
                continue;
            const QString root = event.value(QLatin1String("root")).toString();
            if (root.isEmpty() || root == QLatin1String("/") || root.startsWith(QLatin1String("/run/live")))
                continue;
            found.append(QVariantMap{
                {QStringLiteral("root"), root},
                {QStringLiteral("name"), event.value(QLatin1String("name")).toString()},
                {QStringLiteral("device"), event.value(QLatin1String("device")).toString()},
            });
        }
        m_systems = found;
        emit systemsChanged();
        setState(State::Idle);
    });
    process->start(pour(), {QStringLiteral("scan"), QStringLiteral("--json")});
}

void Backend::install(const QString &diskPath, bool beside, bool enforce, const QString &importRoot)
{
    if (m_state != State::Idle || m_install)
        return;
    m_log.clear();
    m_pending.clear();
    m_progress = 0;
    m_step = tr("Starting");
    emit progressChanged();
    emit logChanged();
    setState(State::Installing);

    m_install = newProcess();
    connect(m_install, &QProcess::readyReadStandardOutput, this, [this] {
        m_pending += m_install->readAllStandardOutput();
        qsizetype nl;
        while ((nl = m_pending.indexOf('\n')) >= 0) {
            handleLine(m_pending.left(nl));
            m_pending.remove(0, nl + 1);
        }
    });
    // What dave and the programs it runs say for people: the details view.
    connect(m_install, &QProcess::readyReadStandardError, this, [this] {
        appendLog(QString::fromUtf8(m_install->readAllStandardError()));
    });
    connect(m_install, &QProcess::finished, this, &Backend::installFinished);
    QStringList args = {
        QStringLiteral("--what=sleep:idle:shutdown:handle-lid-switch"),
        QStringLiteral("--who=joe Linux installer"),
        QStringLiteral("--why=A disk is being written"),
        QStringLiteral("pkexec"),
        dave(),
        QStringLiteral("install-system"),
        QStringLiteral("--disk"), diskPath,
        QStringLiteral("--json"),
    };
    if (beside)
        args << QStringLiteral("--beside");
    if (enforce)
        args << QStringLiteral("--enforce");
    if (!importRoot.isEmpty())
        args << QStringLiteral("--import") << importRoot;
    m_install->start(QStringLiteral("systemd-inhibit"), args);
}

// One event from dave:
//   {"event":"step","message":"...","fraction":0.1}
//   {"event":"progress","message":"...","fraction":0.4}
//   {"event":"done","fraction":1}
//   {"event":"error","message":"..."}
void Backend::handleLine(const QByteArray &line)
{
    const QJsonObject event = QJsonDocument::fromJson(line).object();
    if (event.isEmpty())
        return;
    const QString kind = event.value(QLatin1String("event")).toString();
    const QString message = event.value(QLatin1String("message")).toString();
    if (event.contains(QLatin1String("fraction")))
        m_progress = event.value(QLatin1String("fraction")).toDouble();
    if (kind == QLatin1String("step") || kind == QLatin1String("progress")) {
        if (!message.isEmpty())
            m_step = message;
        if (kind == QLatin1String("step"))
            appendLog(QStringLiteral("==> ") + message);
    } else if (kind == QLatin1String("error")) {
        m_error = message;
        appendLog(QStringLiteral("error: ") + message);
    } else if (kind == QLatin1String("done")) {
        m_progress = 1;
    }
    emit progressChanged();
}

void Backend::installFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_pending.isEmpty())
        handleLine(m_pending);
    m_pending.clear();
    m_install->deleteLater();
    m_install = nullptr;
    if (status == QProcess::NormalExit && exitCode == 0) {
        setState(State::Done);
        return;
    }
    QString error = m_error;
    if (error.isEmpty()) {
        // pkexec's own exit codes: authorisation refused or dismissed.
        error = (exitCode == 126 || exitCode == 127)
            ? tr("Permission to install was not given.")
            : tr("The installation stopped unexpectedly (exit status %1).").arg(exitCode);
    }
    setState(State::Failed, error);
}

void Backend::restart()
{
    QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
}
