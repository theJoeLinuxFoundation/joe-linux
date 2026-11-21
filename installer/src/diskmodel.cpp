#include "diskmodel.h"

#include <algorithm>

#include <QJsonArray>

int DiskModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_disks.size());
}

// Sizes as disks are sold: decimal units.
QString DiskModel::sizeText(qint64 bytes)
{
    const double gb = double(bytes) / 1e9;
    if (gb >= 1000)
        return tr("%1 TB").arg(gb / 1000, 0, 'f', gb >= 10000 ? 0 : 1);
    if (gb >= 10)
        return tr("%1 GB").arg(qRound(gb));
    return tr("%1 GB").arg(gb, 0, 'f', 1);
}

QString DiskModel::transportText(const QString &tran, bool removable)
{
    if (tran == QLatin1String("nvme"))
        return tr("NVMe");
    if (tran == QLatin1String("sata") || tran == QLatin1String("ata"))
        return tr("SATA");
    if (tran == QLatin1String("usb"))
        return tr("USB");
    if (tran == QLatin1String("mmc"))
        return tr("Memory card");
    if (tran.isEmpty())
        return removable ? tr("removable") : QString();
    return tran.toUpper();
}

static QString displayName(const Disk &d)
{
    if (!d.model.isEmpty())
        return d.model;
    return d.device.section(QLatin1Char('/'), -1);
}

QVariant DiskModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_disks.size())
        return {};
    const Disk &d = m_disks.at(index.row());
    switch (role) {
    case PathRole: return d.path;
    case DeviceRole: return d.device;
    case NameRole: return displayName(d);
    case SizeTextRole: return sizeText(d.size);
    case TransportTextRole: return transportText(d.transport, d.removable);
    case RemovableRole: return d.removable;
    case UsableRole: return d.usable;
    case ReasonRole: return d.reason;
    case ContentsRole: return d.contents;
    case SegmentsRole: return d.segments;
    case LayoutRole: return d.layout;
    case SelectableRole: return d.usable || d.canBeside;
    case CanBesideRole: return d.canBeside;
    case BesideReasonRole: return d.besideReason;
    case BesideSizeTextRole: return sizeText(d.besideSize);
    case BesideStartRole: return d.besideStart;
    case BesideFractionRole: return d.besideFraction;
    case BesideWhatRole: return d.besideWhat;
    }
    return {};
}

QHash<int, QByteArray> DiskModel::roleNames() const
{
    return {
        {PathRole, "path"},
        {DeviceRole, "device"},
        {NameRole, "name"},
        {SizeTextRole, "sizeText"},
        {TransportTextRole, "transportText"},
        {RemovableRole, "removable"},
        {UsableRole, "usable"},
        {ReasonRole, "reason"},
        {ContentsRole, "contents"},
        {SegmentsRole, "segments"},
        {LayoutRole, "layout"},
        {SelectableRole, "selectable"},
        {CanBesideRole, "canBeside"},
        {BesideReasonRole, "besideReason"},
        {BesideSizeTextRole, "besideSizeText"},
        {BesideStartRole, "besideStart"},
        {BesideFractionRole, "besideFraction"},
        {BesideWhatRole, "besideWhat"},
    };
}

void DiskModel::setDisks(const QJsonObject &listing)
{
    beginResetModel();
    const auto limitText = [&listing](QLatin1String key) {
        const qint64 bytes = listing.value(key).toInteger();
        return bytes > 0 ? sizeText(bytes) : QString();
    };
    m_minimumDiskSizeText = limitText(QLatin1String("min_disk_size"));
    m_minimumBesideSizeText = limitText(QLatin1String("min_beside_size"));
    const QJsonArray disks = listing.value(QLatin1String("disks")).toArray();
    m_disks.clear();
    for (const QJsonValue &v : disks) {
        const QJsonObject o = v.toObject();
        Disk d;
        d.path = o.value(QLatin1String("path")).toString();
        d.device = o.value(QLatin1String("device")).toString();
        d.size = qint64(o.value(QLatin1String("size")).toDouble());
        d.model = o.value(QLatin1String("model")).toString();
        d.transport = o.value(QLatin1String("transport")).toString();
        d.removable = o.value(QLatin1String("removable")).toBool();
        d.usable = o.value(QLatin1String("usable")).toBool();
        d.reason = o.value(QLatin1String("reason")).toString();
        const double size = double(d.size);
        for (const QJsonValue &p : o.value(QLatin1String("partitions")).toArray()) {
            const QJsonObject po = p.toObject();
            const QString kind = po.value(QLatin1String("kind")).toString();
            QString label = po.value(QLatin1String("label")).toString();
            if (label.isEmpty())
                label = kind == QLatin1String("windows") ? tr("Windows")
                      : kind == QLatin1String("esp")     ? tr("EFI")
                                                         : po.value(QLatin1String("fstype")).toString();
            if (size > 0) {
                d.layout << QVariantMap{
                    {QStringLiteral("label"), label},
                    {QStringLiteral("start"), po.value(QLatin1String("start")).toDouble() / size},
                    {QStringLiteral("size"), po.value(QLatin1String("size")).toDouble() / size},
                };
            }
        }
        const QJsonObject beside = o.value(QLatin1String("beside")).toObject();
        d.canBeside = beside.value(QLatin1String("possible")).toBool();
        d.besideReason = beside.value(QLatin1String("reason")).toString();
        d.besideSize = qint64(beside.value(QLatin1String("size")).toDouble());
        if (size > 0) {
            d.besideStart = beside.value(QLatin1String("start")).toDouble() / size;
            d.besideFraction = beside.value(QLatin1String("size")).toDouble() / size;
        }
        QStringList systems;
        for (const QJsonValue &s : beside.value(QLatin1String("systems")).toArray())
            systems << s.toString();
        d.besideWhat = systems.isEmpty() ? tr("another system")
                     : systems.size() == 1 ? systems.first()
                                           : tr("%1 and %2").arg(systems.mid(0, systems.size() - 1).join(QStringLiteral(", ")), systems.last());
        for (const QJsonValue &c : o.value(QLatin1String("contents")).toArray()) {
            const QJsonObject co = c.toObject();
            const QString label = co.value(QLatin1String("label")).toString();
            const QString fstype = co.value(QLatin1String("fstype")).toString();
            const QString size = sizeText(qint64(co.value(QLatin1String("size")).toDouble()));
            d.contents << (label.isEmpty() ? tr("an unnamed %1 partition (%2)").arg(fstype, size)
                                           : tr("%1 (%2, %3)").arg(label, fstype, size));
            if (d.size > 0) {
                d.segments << QVariantMap{
                    {QStringLiteral("label"), label.isEmpty() ? fstype : label},
                    {QStringLiteral("fraction"), co.value(QLatin1String("size")).toDouble() / double(d.size)},
                };
            }
        }
        m_disks << d;
    }
    // Disks that can be used first, those joe can share with another
    // system before them, then the largest: the likely choice is at the top.
    std::stable_sort(m_disks.begin(), m_disks.end(), [](const Disk &a, const Disk &b) {
        const bool ua = a.usable || a.canBeside, ub = b.usable || b.canBeside;
        if (ua != ub)
            return ua;
        if (a.canBeside != b.canBeside)
            return a.canBeside;
        return a.size > b.size;
    });
    endResetModel();
    emit countChanged();
}

int DiskModel::usableCount() const
{
    return int(std::count_if(m_disks.begin(), m_disks.end(), [](const Disk &d) { return d.usable || d.canBeside; }));
}

int DiskModel::indexOfPath(const QString &path) const
{
    for (int i = 0; i < m_disks.size(); ++i) {
        if (m_disks.at(i).path == path || m_disks.at(i).device == path)
            return i;
    }
    return -1;
}

QVariantMap DiskModel::get(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= m_disks.size())
        return map;
    const QModelIndex i = index(row);
    const auto roles = roleNames();
    for (auto it = roles.begin(); it != roles.end(); ++it)
        map.insert(QString::fromLatin1(it.value()), data(i, it.key()));
    return map;
}
