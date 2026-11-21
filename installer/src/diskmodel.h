// The disks `dave install-system --list --json` reports, for the disk page.
#pragma once

#include <QAbstractListModel>
#include <QJsonObject>
#include <QList>
#include <QString>
#include <QtQml/qqmlregistration.h>

struct Disk {
    QString path;       // what is passed as --disk
    QString device;
    qint64 size = 0;
    QString model;
    QString transport;
    bool removable = false;
    bool usable = false;
    QString reason;     // why it cannot be erased
    QStringList contents; // "Windows (ntfs, 512 GB)", ...
    QVariantList segments; // {label, fraction} per file system, for the disk strip
    QVariantList layout;   // {label, start, size} per partition, as fractions of the disk
    // Installing beside what is on the disk, in its largest free space.
    bool canBeside = false;
    QString besideReason;  // why not
    qint64 besideSize = 0;
    double besideStart = 0;    // fractions of the disk
    double besideFraction = 0;
    QString besideWhat;    // "Windows", "Windows and Linux", "another system"
};

class DiskModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("provided by Backend")
    Q_PROPERTY(QString minimumDiskSizeText READ minimumDiskSizeText NOTIFY countChanged)
    Q_PROPERTY(QString minimumBesideSizeText READ minimumBesideSizeText NOTIFY countChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int usableCount READ usableCount NOTIFY countChanged)

public:
    enum Role {
        PathRole = Qt::UserRole + 1,
        DeviceRole,
        NameRole,
        SizeTextRole,
        TransportTextRole,
        RemovableRole,
        UsableRole,
        ReasonRole,
        ContentsRole,
        SegmentsRole,
        LayoutRole,
        SelectableRole,
        CanBesideRole,
        BesideReasonRole,
        BesideSizeTextRole,
        BesideStartRole,
        BesideFractionRole,
        BesideWhatRole,
    };

    using QAbstractListModel::QAbstractListModel;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setDisks(const QJsonObject &listing);
    QString minimumDiskSizeText() const { return m_minimumDiskSizeText; }
    QString minimumBesideSizeText() const { return m_minimumBesideSizeText; }
    int usableCount() const;
    Q_INVOKABLE int indexOfPath(const QString &path) const;
    Q_INVOKABLE QVariantMap get(int row) const;

    static QString transportText(const QString &tran, bool removable);
    static QString sizeText(qint64 bytes);

signals:
    void countChanged();

private:
    QString m_minimumDiskSizeText;
    QString m_minimumBesideSizeText;
    QList<Disk> m_disks;
};
