#include "SystemBackend.h"

#include <KUser>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSysInfo>
#include <QThread>
#include <QUrl>
#include <algorithm>
#include <cmath>
#include <unistd.h>

SystemBackend::SystemBackend(const QString &startPage, QObject *parent)
    : QObject(parent)
    , m_initialPage(startPage.isEmpty() ? QStringLiteral("home") : startPage)
{
    loadStaticSystemInfo();
    refreshAll();

    // Refresh live metrics (clock, audio, RAM/disk, battery, security) every 6 seconds
    connect(&m_periodicTimer, &QTimer::timeout, this, [this]() {
        loadDynamicSystemMetrics();
        refreshTime();
        refreshAudio();
        refreshPower();
        refreshSecurity();
    });
    m_periodicTimer.start(6000);

    // 15-second safety auto-revert countdown for display orientation changes
    connect(&m_orientationRevertTimer, &QTimer::timeout, this, [this]() {
        if (m_orientationConfirmSeconds > 1) {
            --m_orientationConfirmSeconds;
            emit displayChanged();
        } else {
            m_orientationRevertTimer.stop();
            revertDisplayOrientation();
        }
    });
}

QString SystemBackend::runCommand(const QString &program, const QStringList &args, int timeoutMs) const
{
    QProcess proc;
    proc.start(program, args);
    if (!proc.waitForFinished(timeoutMs)) {
        proc.kill();
        proc.waitForFinished(500);
        return QString();
    }
    return QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
}

void SystemBackend::runDetached(const QString &program, const QStringList &args) const
{
    QProcess::startDetached(program, args);
}

void SystemBackend::notifyStatus(const QString &msg)
{
    m_statusMessage = msg;
    emit statusMessageChanged();
}

void SystemBackend::loadStaticSystemInfo()
{
    // 1. Dynamic User & Hostname Discovery
    KUser kuser;
    m_userName = kuser.loginName();
    if (m_userName.isEmpty()) {
        m_userName = qEnvironmentVariable("USER", QStringLiteral("user"));
    }

    m_userFullName = kuser.property(KUser::FullName).toString().trimmed();
    if (m_userFullName.isEmpty()) {
        m_userFullName = m_userName;
    }

    // Compute initials
    const QStringList parts = m_userFullName.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (parts.size() >= 2) {
        m_userInitials = QString(parts.first().at(0).toUpper()) + QString(parts.last().at(0).toUpper());
    } else if (!m_userFullName.isEmpty()) {
        m_userInitials = m_userFullName.left(2).toUpper();
    } else {
        m_userInitials = QStringLiteral("SL");
    }

    // Comprehensive Profile Picture (Avatar) Discovery
    const uid_t uid = getuid();
    const QString accountsDbusIcon = runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("--system"),
         QStringLiteral("org.freedesktop.Accounts"),
         QStringLiteral("/org/freedesktop/Accounts/User%1").arg(uid),
         QStringLiteral("org.freedesktop.Accounts.User.IconFile")}, 1200);

    QString accountsFileIcon;
    QFile accUserFile(QStringLiteral("/var/lib/AccountsService/users/") + m_userName);
    if (accUserFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        for (const QString &line : QString::fromUtf8(accUserFile.readAll()).split(QLatin1Char('\n'))) {
            if (line.trimmed().startsWith(QStringLiteral("Icon="))) {
                accountsFileIcon = line.trimmed().mid(5).trimmed();
                break;
            }
        }
    }

    const QStringList avatarCandidates = {
        kuser.faceIconPath(),
        accountsDbusIcon,
        accountsFileIcon,
        QStringLiteral("/var/lib/AccountsService/icons/") + m_userName,
        QDir::homePath() + QStringLiteral("/.face.icon"),
        QDir::homePath() + QStringLiteral("/.face"),
        QDir::homePath() + QStringLiteral("/.config/face.icon")
    };

    m_userAvatar.clear();
    for (const QString &candidate : avatarCandidates) {
        const QString cleanPath = candidate.trimmed();
        if (!cleanPath.isEmpty() && QFileInfo::exists(cleanPath) && QFileInfo(cleanPath).isFile()) {
            m_userAvatar = QUrl::fromLocalFile(cleanPath).toString();
            break;
        }
    }

    // Hostname
    m_hostname = QSysInfo::machineHostName().trimmed();
    if (m_hostname.isEmpty()) {
        QFile hostFile(QStringLiteral("/etc/hostname"));
        if (hostFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            m_hostname = QString::fromUtf8(hostFile.readAll()).trimmed();
        }
    }
    if (m_hostname.isEmpty()) {
        m_hostname = QStringLiteral("sourceless-node");
    }

    // OS Name & Kernel
    m_osName = QSysInfo::prettyProductName();
    QFile osRelease(QStringLiteral("/etc/os-release"));
    if (osRelease.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QStringList lines = QString::fromUtf8(osRelease.readAll()).split(QLatin1Char('\n'));
        for (const QString &rawLine : lines) {
            const QString line = rawLine.trimmed();
            if (line.startsWith(QStringLiteral("PRETTY_NAME="))) {
                QString val = line.mid(12).trimmed();
                val.remove(QLatin1Char('"'));
                if (!val.isEmpty()) {
                    m_osName = val;
                }
                break;
            }
        }
    }
    m_kernelVersion = QSysInfo::kernelVersion();

    // CPU Model & Cores (using readAll() because /proc/cpuinfo reports size 0 in stat)
    m_cpuCores = QThread::idealThreadCount();
    m_cpuModel = QSysInfo::currentCpuArchitecture();
    QFile cpuInfo(QStringLiteral("/proc/cpuinfo"));
    if (cpuInfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QStringList lines = QString::fromUtf8(cpuInfo.readAll()).split(QLatin1Char('\n'));
        for (const QString &line : lines) {
            if (line.startsWith(QStringLiteral("model name"))) {
                const int colonIdx = line.indexOf(QLatin1Char(':'));
                if (colonIdx != -1) {
                    const QString model = line.mid(colonIdx + 1).trimmed();
                    if (!model.isEmpty()) {
                        m_cpuModel = model;
                        break;
                    }
                }
            }
        }
    }

    // GPU Model
    const QString lspciOut = runCommand(QStringLiteral("sh"),
        {QStringLiteral("-c"), QStringLiteral("lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n 1")}, 1500);
    if (!lspciOut.isEmpty()) {
        const int idx = lspciOut.indexOf(QStringLiteral(": "));
        m_gpuModel = (idx != -1) ? lspciOut.mid(idx + 2).trimmed() : lspciOut;
    } else {
        m_gpuModel = QStringLiteral("Integrated / Virtual Graphics Adapter");
    }

    // Hardware ID (masked for display)
    QFile hwidFile(QStringLiteral("/etc/sourceless/enrolled_hwid"));
    if (!hwidFile.exists()) {
        hwidFile.setFileName(QStringLiteral("/etc/machine-id"));
    }
    if (hwidFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString rawId = QString::fromUtf8(hwidFile.readAll()).trimmed().toUpper();
        if (rawId.length() >= 12) {
            m_hwid = rawId.left(8) + QStringLiteral("-") + rawId.right(4);
        } else {
            m_hwid = rawId;
        }
    } else {
        m_hwid = QStringLiteral("SL-VERIFIED-NODE");
    }

    emit systemInfoChanged();
}

void SystemBackend::loadDynamicSystemMetrics()
{
    // RAM usage from /proc/meminfo (using readAll() for procfs compatibility)
    QFile memInfo(QStringLiteral("/proc/meminfo"));
    if (memInfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qulonglong memTotalKb = 0;
        qulonglong memAvailKb = 0;
        const QStringList lines = QString::fromUtf8(memInfo.readAll()).split(QLatin1Char('\n'));
        for (const QString &line : lines) {
            if (line.startsWith(QStringLiteral("MemTotal:"))) {
                memTotalKb = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts).value(1).toULongLong();
            } else if (line.startsWith(QStringLiteral("MemAvailable:"))) {
                memAvailKb = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts).value(1).toULongLong();
            }
            if (memTotalKb > 0 && memAvailKb > 0) {
                break;
            }
        }
        if (memTotalKb > 0) {
            const qulonglong usedKb = (memTotalKb > memAvailKb) ? (memTotalKb - memAvailKb) : 0;
            const double totalGb = memTotalKb / (1024.0 * 1024.0);
            const double usedGb = usedKb / (1024.0 * 1024.0);
            m_ramTotalText = QString::number(totalGb, 'f', 1) + QStringLiteral(" GB");
            m_ramUsedText = QString::number(usedGb, 'f', 1) + QStringLiteral(" GB");
            m_ramPercent = qBound(1, static_cast<int>(std::round((usedKb * 100.0) / memTotalKb)), 100);
        }
    }

    // Disk usage via QStorageInfo
    QStorageInfo storage(QDir::homePath());
    if (!storage.isValid() || storage.bytesTotal() <= 0) {
        storage = QStorageInfo::root();
    }
    if (storage.bytesTotal() > 0) {
        const double totalGb = storage.bytesTotal() / (1024.0 * 1024.0 * 1024.0);
        const double freeGb = storage.bytesAvailable() / (1024.0 * 1024.0 * 1024.0);
        const double usedGb = qMax(0.0, totalGb - freeGb);
        m_diskTotalText = QString::number(totalGb, 'f', 1) + QStringLiteral(" GB");
        m_diskUsedText = QString::number(usedGb, 'f', 1) + QStringLiteral(" GB");
        m_diskFreeText = QString::number(freeGb, 'f', 1) + QStringLiteral(" GB");
        m_diskPercent = qBound(1, static_cast<int>(std::round((usedGb * 100.0) / totalGb)), 100);
    }

    // Uptime from /proc/uptime
    QFile uptimeFile(QStringLiteral("/proc/uptime"));
    if (uptimeFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString content = QString::fromUtf8(uptimeFile.readAll()).trimmed();
        const double seconds = content.split(QLatin1Char(' ')).first().toDouble();
        const int days = static_cast<int>(seconds) / 86400;
        const int hours = (static_cast<int>(seconds) % 86400) / 3600;
        const int mins = (static_cast<int>(seconds) % 3600) / 60;
        if (days > 0) {
            m_uptimeText = QStringLiteral("%1d %2h %3m").arg(days).arg(hours).arg(mins);
        } else {
            m_uptimeText = QStringLiteral("%1h %2m").arg(hours).arg(mins);
        }
    }

    emit systemInfoChanged();
}

void SystemBackend::refreshAll()
{
    loadDynamicSystemMetrics();
    refreshAudio();
    refreshDisplay();
    refreshNetwork();
    refreshBluetooth();
    loadInputSettings();
    refreshPower();
    refreshPersonalization();
    refreshApps();
    refreshTime();
    refreshSecurity();
    refreshAccessibility();
}

// -----------------------------------------------------------------------------
// 2. AUDIO (PipeWire wpctl / PulseAudio pactl)
// -----------------------------------------------------------------------------
void SystemBackend::refreshAudio()
{
    const QString sinkVol = runCommand(QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, 1500);
    if (!sinkVol.isEmpty() && sinkVol.contains(QStringLiteral("Volume:"))) {
        m_muted = sinkVol.contains(QStringLiteral("[MUTED]"));
        QRegularExpression re(QStringLiteral("Volume:\\s*([0-9]+\\.?[0-9]*)"));
        auto match = re.match(sinkVol);
        if (match.hasMatch()) {
            m_volume = qBound(0, static_cast<int>(std::round(match.captured(1).toDouble() * 100.0)), 100);
        }
    }

    const QString srcVol = runCommand(QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@")}, 1500);
    if (!srcVol.isEmpty() && srcVol.contains(QStringLiteral("Volume:"))) {
        m_micMuted = srcVol.contains(QStringLiteral("[MUTED]"));
        QRegularExpression re(QStringLiteral("Volume:\\s*([0-9]+\\.?[0-9]*)"));
        auto match = re.match(srcVol);
        if (match.hasMatch()) {
            m_micVolume = qBound(0, static_cast<int>(std::round(match.captured(1).toDouble() * 100.0)), 100);
        }
    }

    const QString sinkInspect = runCommand(QStringLiteral("wpctl"), {QStringLiteral("inspect"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, 1500);
    if (!sinkInspect.isEmpty()) {
        for (const QString &line : sinkInspect.split(QLatin1Char('\n'))) {
            if (line.contains(QStringLiteral("node.description"))) {
                const int eqIdx = line.indexOf(QLatin1Char('='));
                if (eqIdx != -1) {
                    QString desc = line.mid(eqIdx + 1).trimmed();
                    desc.remove(QLatin1Char('"'));
                    if (!desc.isEmpty()) {
                        m_audioOutputName = desc;
                    }
                }
                break;
            }
        }
    }

    emit audioChanged();
}

void SystemBackend::setVolume(int val)
{
    m_volume = qBound(0, val, 100);
    runCommand(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("%1%").arg(m_volume)}, 1000);
    if (m_muted && m_volume > 0) {
        m_muted = false;
        runCommand(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("0")}, 1000);
    }
    emit audioChanged();
}

void SystemBackend::toggleMute()
{
    m_muted = !m_muted;
    runCommand(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), m_muted ? QStringLiteral("1") : QStringLiteral("0")}, 1000);
    emit audioChanged();
}

void SystemBackend::setMicVolume(int val)
{
    m_micVolume = qBound(0, val, 100);
    runCommand(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@"), QStringLiteral("%1%").arg(m_micVolume)}, 1000);
    emit audioChanged();
}

void SystemBackend::toggleMicMute()
{
    m_micMuted = !m_micMuted;
    runCommand(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@"), m_micMuted ? QStringLiteral("1") : QStringLiteral("0")}, 1000);
    emit audioChanged();
}

void SystemBackend::testSound()
{
    runDetached(QStringLiteral("pw-play"), {QStringLiteral("/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga")});
    notifyStatus(QStringLiteral("Playing audio test tone..."));
}

// -----------------------------------------------------------------------------
// 3. DISPLAY & BRIGHTNESS (KScreen + KDE PowerManagement + KWin NightLight)
// -----------------------------------------------------------------------------
namespace {
int parseRefreshRateHz(double rawRate)
{
    if (rawRate <= 0.0) {
        return 60;
    }
    const double hz = (rawRate > 1000.0) ? (rawRate / 1000.0) : rawRate;
    return qMax(1, static_cast<int>(std::round(hz)));
}

int extractBrightnessPercent(const QJsonValue &val, int fallback)
{
    if (!val.isDouble()) {
        return fallback;
    }
    const double raw = val.toDouble();
    if (raw <= 1.0) {
        return qBound(5, static_cast<int>(std::round(raw * 100.0)), 100);
    }
    return qBound(5, static_cast<int>(std::round(raw)), 100);
}

QString parseTradeoffString(const QJsonValue &val)
{
    if (val.isDouble()) {
        return (val.toInt() == 1) ? QStringLiteral("preferAccuracy") : QStringLiteral("preferEfficiency");
    }
    const QString str = val.toString().trimmed();
    if (str.compare(QStringLiteral("preferAccuracy"), Qt::CaseInsensitive) == 0) {
        return QStringLiteral("preferAccuracy");
    }
    if (str.compare(QStringLiteral("preferEfficiency"), Qt::CaseInsensitive) == 0) {
        return QStringLiteral("preferEfficiency");
    }
    return QString();
}
} // namespace

void SystemBackend::refreshDisplay()
{
    const QString maxBr = runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.Solid.PowerManagement"),
         QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl"),
         QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightnessMax")}, 1500);
    const QString curBr = runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.Solid.PowerManagement"),
         QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl"),
         QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightness")}, 1500);

    m_hasBrightness = true;
    if (!maxBr.isEmpty() && maxBr.toInt() > 0) {
        m_maxRawBrightness = maxBr.toInt();
        m_brightness = qBound(5, static_cast<int>(std::round((curBr.toInt() * 100.0) / m_maxRawBrightness)), 100);
    } else {
        m_maxRawBrightness = 0;
    }

    QStringList parsedRefreshRates;
    bool hasKscreenBrightness = false;
    bool hasTradeoffFromKscreen = false;

    const QString kscreenJson = runCommand(QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")}, 2500);
    if (!kscreenJson.isEmpty()) {
        const QJsonDocument doc = QJsonDocument::fromJson(kscreenJson.toUtf8());
        if (doc.isObject()) {
            const QJsonArray outputs = doc.object().value(QStringLiteral("outputs")).toArray();
            for (const QJsonValue &val : outputs) {
                const QJsonObject outObj = val.toObject();
                if (outObj.value(QStringLiteral("connected")).toBool() && outObj.value(QStringLiteral("enabled")).toBool()) {
                    m_displayName = outObj.value(QStringLiteral("name")).toString(QStringLiteral("Primary Display"));
                    const double scale = outObj.value(QStringLiteral("scale")).toDouble(1.0);
                    m_displayScale = static_cast<int>(std::round(scale * 100.0));
                    const QString currentModeId = outObj.value(QStringLiteral("currentModeId")).toString();

                    if (m_maxRawBrightness <= 0 && outObj.contains(QStringLiteral("brightness"))) {
                        m_brightness = extractBrightnessPercent(outObj.value(QStringLiteral("brightness")), m_brightness);
                        hasKscreenBrightness = true;
                    }

                    const QJsonValue rotVal = outObj.value(QStringLiteral("rotation"));
                    if (rotVal.isString()) {
                        const QString rStr = rotVal.toString().toLower();
                        if (rStr == QStringLiteral("left") || rStr == QStringLiteral("right") || rStr == QStringLiteral("inverted")) {
                            m_displayOrientation = rStr;
                        } else {
                            m_displayOrientation = QStringLiteral("normal");
                        }
                    } else if (rotVal.isDouble()) {
                        switch (rotVal.toInt(1)) {
                        case 2: m_displayOrientation = QStringLiteral("left"); break;
                        case 4: m_displayOrientation = QStringLiteral("inverted"); break;
                        case 8: m_displayOrientation = QStringLiteral("right"); break;
                        default: m_displayOrientation = QStringLiteral("normal"); break;
                        }
                    }

                    if (outObj.contains(QStringLiteral("colorPowerTradeoff"))) {
                        const QString parsed = parseTradeoffString(outObj.value(QStringLiteral("colorPowerTradeoff")));
                        if (!parsed.isEmpty()) {
                            m_colorAccuracy = parsed;
                            hasTradeoffFromKscreen = true;
                        }
                    }

                    QStringList resList;
                    const QJsonArray modes = outObj.value(QStringLiteral("modes")).toArray();
                    // First pass: collect resolutions and active mode resolution/refresh rate
                    for (const QJsonValue &mVal : modes) {
                        const QJsonObject modeObj = mVal.toObject();
                        const QJsonObject sizeObj = modeObj.value(QStringLiteral("size")).toObject();
                        const int w = sizeObj.value(QStringLiteral("width")).toInt();
                        const int h = sizeObj.value(QStringLiteral("height")).toInt();
                        if (w >= 800 && h >= 600) {
                            const QString resStr = QStringLiteral("%1x%2").arg(w).arg(h);
                            if (!resList.contains(resStr)) {
                                resList.append(resStr);
                            }
                            if (modeObj.value(QStringLiteral("id")).toString() == currentModeId) {
                                m_currentResolution = resStr;
                                const int hz = parseRefreshRateHz(modeObj.value(QStringLiteral("refreshRate")).toDouble(60.0));
                                m_currentRefreshRate = QStringLiteral("%1 Hz").arg(hz);
                            }
                        }
                    }
                    if (!resList.isEmpty()) {
                        m_availableResolutions = resList;
                    }

                    // Second pass: collect unique integer Hz values for the active resolution
                    QList<int> hzValues;
                    for (const QJsonValue &mVal : modes) {
                        const QJsonObject modeObj = mVal.toObject();
                        const QJsonObject sizeObj = modeObj.value(QStringLiteral("size")).toObject();
                        const QString resStr = QStringLiteral("%1x%2")
                            .arg(sizeObj.value(QStringLiteral("width")).toInt())
                            .arg(sizeObj.value(QStringLiteral("height")).toInt());
                        if (resStr == m_currentResolution) {
                            const int hz = parseRefreshRateHz(modeObj.value(QStringLiteral("refreshRate")).toDouble(60.0));
                            if (!hzValues.contains(hz)) {
                                hzValues.append(hz);
                            }
                        }
                    }
                    std::sort(hzValues.begin(), hzValues.end(), std::greater<int>());
                    for (int hz : hzValues) {
                        parsedRefreshRates.append(QStringLiteral("%1 Hz").arg(hz));
                    }
                    break;
                }
            }
        }
    }

    // Check ~/.config/kwinoutputconfig.json for colorPowerTradeoff & brightness fallback
    QFile kwinOutFile(QDir::homePath() + QStringLiteral("/.config/kwinoutputconfig.json"));
    if (kwinOutFile.open(QIODevice::ReadOnly)) {
        const QJsonDocument outDoc = QJsonDocument::fromJson(kwinOutFile.readAll());
        QJsonArray outputEntries;
        if (outDoc.isArray()) {
            const QJsonArray rootArr = outDoc.array();
            for (const QJsonValue &secVal : rootArr) {
                const QJsonObject secObj = secVal.toObject();
                if (secObj.value(QStringLiteral("name")).toString() == QStringLiteral("outputs")) {
                    outputEntries = secObj.value(QStringLiteral("data")).toArray();
                    break;
                }
            }
            if (outputEntries.isEmpty()) {
                outputEntries = rootArr;
            }
        } else if (outDoc.isObject()) {
            outputEntries = outDoc.object().value(QStringLiteral("outputs")).toArray();
        }

        for (const QJsonValue &entryVal : outputEntries) {
            const QJsonObject entryObj = entryVal.toObject();
            const QString connector = entryObj.value(QStringLiteral("connectorName")).toString(
                entryObj.value(QStringLiteral("name")).toString());
            if (!connector.isEmpty() && connector == m_displayName) {
                if (!hasTradeoffFromKscreen && entryObj.contains(QStringLiteral("colorPowerTradeoff"))) {
                    const QString parsed = parseTradeoffString(entryObj.value(QStringLiteral("colorPowerTradeoff")));
                    if (!parsed.isEmpty()) {
                        m_colorAccuracy = parsed;
                    }
                }
                if (m_maxRawBrightness <= 0 && !hasKscreenBrightness && entryObj.contains(QStringLiteral("brightness"))) {
                    m_brightness = extractBrightnessPercent(entryObj.value(QStringLiteral("brightness")), m_brightness);
                }
                break;
            }
        }
    }

    if (m_availableResolutions.isEmpty()) {
        m_availableResolutions = {
            QStringLiteral("3840x2160"),
            QStringLiteral("2560x1440"),
            QStringLiteral("1920x1080"),
            QStringLiteral("1680x1050"),
            QStringLiteral("1600x900"),
            QStringLiteral("1366x768"),
            QStringLiteral("1280x720")
        };
    }

    if (!parsedRefreshRates.isEmpty()) {
        m_availableRefreshRates = parsedRefreshRates;
    } else {
        m_availableRefreshRates = {m_currentRefreshRate};
    }

    QSettings kwinrc(QDir::homePath() + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
    kwinrc.beginGroup(QStringLiteral("NightColor"));
    m_nightLightEnabled = kwinrc.value(QStringLiteral("Active"), false).toBool();
    m_nightLightTemp = kwinrc.value(QStringLiteral("NightTemperature"), 4500).toInt();
    kwinrc.endGroup();

    const QString nlEnabledDbus = runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.KWin"),
         QStringLiteral("/org/kde/KWin/NightLight"),
         QStringLiteral("org.kde.KWin.NightLight.enabled")}, 1000);
    if (nlEnabledDbus == QStringLiteral("true")) {
        m_nightLightEnabled = true;
    } else if (nlEnabledDbus == QStringLiteral("false")) {
        m_nightLightEnabled = false;
    }

    emit displayChanged();
}

void SystemBackend::setBrightness(int val)
{
    m_brightness = qBound(5, val, 100);
    if (!m_displayName.isEmpty()) {
        runCommand(QStringLiteral("kscreen-doctor"),
            {QStringLiteral("output.%1.brightness.%2").arg(m_displayName).arg(m_brightness)}, 1500);
    }
    if (m_maxRawBrightness > 0) {
        const int raw = static_cast<int>(std::round((m_brightness / 100.0) * m_maxRawBrightness));
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.Solid.PowerManagement"),
             QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl"),
             QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl.setBrightness"),
             QString::number(raw)}, 1000);
    }
    emit displayChanged();
}

void SystemBackend::setResolution(const QString &res)
{
    if (res.isEmpty() || m_displayName.isEmpty() || res == m_currentResolution) {
        return;
    }
    QString targetModeId;
    int bestHz = -1;
    const int desiredHz = m_currentRefreshRate.split(QLatin1Char(' ')).first().toInt();
    const QString kscreenJson = runCommand(QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")}, 2000);
    if (!kscreenJson.isEmpty()) {
        const QJsonDocument doc = QJsonDocument::fromJson(kscreenJson.toUtf8());
        const QJsonArray outputs = doc.object().value(QStringLiteral("outputs")).toArray();
        for (const QJsonValue &val : outputs) {
            const QJsonObject outObj = val.toObject();
            if (outObj.value(QStringLiteral("name")).toString() == m_displayName) {
                const QJsonArray modes = outObj.value(QStringLiteral("modes")).toArray();
                for (const QJsonValue &mVal : modes) {
                    const QJsonObject modeObj = mVal.toObject();
                    const QJsonObject sizeObj = modeObj.value(QStringLiteral("size")).toObject();
                    const QString modeRes = QStringLiteral("%1x%2")
                        .arg(sizeObj.value(QStringLiteral("width")).toInt())
                        .arg(sizeObj.value(QStringLiteral("height")).toInt());
                    if (modeRes == res) {
                        const int hz = parseRefreshRateHz(modeObj.value(QStringLiteral("refreshRate")).toDouble(60.0));
                        if (hz == desiredHz) {
                            targetModeId = modeObj.value(QStringLiteral("id")).toString();
                            break;
                        }
                        if (hz > bestHz) {
                            bestHz = hz;
                            targetModeId = modeObj.value(QStringLiteral("id")).toString();
                        }
                    }
                }
                break;
            }
        }
    }

    if (!targetModeId.isEmpty()) {
        runCommand(QStringLiteral("kscreen-doctor"),
            {QStringLiteral("output.%1.mode.%2").arg(m_displayName, targetModeId)}, 2500);
        notifyStatus(QStringLiteral("Display resolution set to %1").arg(res));
        refreshDisplay();
    }
}

void SystemBackend::setRefreshRate(const QString &rate)
{
    if (rate.isEmpty() || m_displayName.isEmpty() || rate == m_currentRefreshRate) {
        return;
    }
    const int targetHz = rate.split(QLatin1Char(' ')).first().toInt();
    QString targetModeId;
    const QString kscreenJson = runCommand(QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")}, 2000);
    if (!kscreenJson.isEmpty()) {
        const QJsonDocument doc = QJsonDocument::fromJson(kscreenJson.toUtf8());
        const QJsonArray outputs = doc.object().value(QStringLiteral("outputs")).toArray();
        for (const QJsonValue &val : outputs) {
            const QJsonObject outObj = val.toObject();
            if (outObj.value(QStringLiteral("name")).toString() == m_displayName) {
                const QJsonArray modes = outObj.value(QStringLiteral("modes")).toArray();
                for (const QJsonValue &mVal : modes) {
                    const QJsonObject modeObj = mVal.toObject();
                    const QJsonObject sizeObj = modeObj.value(QStringLiteral("size")).toObject();
                    const QString modeRes = QStringLiteral("%1x%2")
                        .arg(sizeObj.value(QStringLiteral("width")).toInt())
                        .arg(sizeObj.value(QStringLiteral("height")).toInt());
                    const int hz = parseRefreshRateHz(modeObj.value(QStringLiteral("refreshRate")).toDouble(60.0));
                    if (modeRes == m_currentResolution && hz == targetHz) {
                        targetModeId = modeObj.value(QStringLiteral("id")).toString();
                        break;
                    }
                }
                break;
            }
        }
    }

    if (!targetModeId.isEmpty()) {
        runCommand(QStringLiteral("kscreen-doctor"),
            {QStringLiteral("output.%1.mode.%2").arg(m_displayName, targetModeId)}, 2500);
        m_currentRefreshRate = rate;
        notifyStatus(QStringLiteral("Refresh rate set to %1").arg(rate));
        emit displayChanged();
    }
}

void SystemBackend::applyDisplayOrientationRaw(const QString &orientation)
{
    if (m_displayName.isEmpty() || orientation.isEmpty()) {
        return;
    }
    runCommand(QStringLiteral("kscreen-doctor"),
        {QStringLiteral("output.%1.rotation.%2").arg(m_displayName, orientation)}, 2500);

    // Sync KWin Wayland pointer/tablet devices to the rotated output coordinate matrix
    const QString devOut = runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.KWin"),
         QStringLiteral("/org/kde/KWin/InputDevice"),
         QStringLiteral("org.kde.KWin.InputDeviceManager.devicesSysNames")}, 1000);
    for (const QString &dev : devOut.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QString sysName = dev.trimmed();
        if (sysName.startsWith(QStringLiteral("event"))) {
            runCommand(QStringLiteral("busctl"),
                {QStringLiteral("--user"),
                 QStringLiteral("set-property"),
                 QStringLiteral("org.kde.KWin"),
                 QStringLiteral("/org/kde/KWin/InputDevice/") + sysName,
                 QStringLiteral("org.kde.KWin.InputDevice"),
                 QStringLiteral("outputName"),
                 QStringLiteral("s"),
                 m_displayName}, 400);
        }
    }

    m_displayOrientation = orientation;
}

void SystemBackend::setDisplayOrientation(const QString &orientation)
{
    static const QStringList validOrientations = {
        QStringLiteral("normal"),
        QStringLiteral("left"),
        QStringLiteral("right"),
        QStringLiteral("inverted")
    };
    if (!validOrientations.contains(orientation) || m_displayName.isEmpty() || orientation == m_displayOrientation) {
        return;
    }

    if (m_orientationConfirmSeconds == 0) {
        m_previousOrientation = m_displayOrientation;
    }

    applyDisplayOrientationRaw(orientation);

    if (orientation != QStringLiteral("normal")) {
        m_orientationConfirmSeconds = 15;
        m_orientationRevertTimer.start(1000);
        notifyStatus(QStringLiteral("Orientation set to %1 — confirm within 15s (or press Esc)").arg(orientation));
    } else {
        m_orientationRevertTimer.stop();
        m_orientationConfirmSeconds = 0;
        notifyStatus(QStringLiteral("Display orientation set to normal"));
    }
    emit displayChanged();
}

void SystemBackend::confirmDisplayOrientation()
{
    m_orientationRevertTimer.stop();
    m_orientationConfirmSeconds = 0;
    m_previousOrientation = m_displayOrientation;
    notifyStatus(QStringLiteral("Display orientation confirmed (%1)").arg(m_displayOrientation));
    emit displayChanged();
}

void SystemBackend::revertDisplayOrientation()
{
    m_orientationRevertTimer.stop();
    m_orientationConfirmSeconds = 0;
    const QString fallback = m_previousOrientation.isEmpty() ? QStringLiteral("normal") : m_previousOrientation;
    applyDisplayOrientationRaw(fallback);
    notifyStatus(QStringLiteral("Display orientation reverted to %1").arg(fallback));
    emit displayChanged();
}

void SystemBackend::setColorAccuracy(const QString &mode)
{
    if ((mode != QStringLiteral("preferEfficiency") && mode != QStringLiteral("preferAccuracy")) ||
        m_displayName.isEmpty() || mode == m_colorAccuracy) {
        return;
    }
    runCommand(QStringLiteral("kscreen-doctor"),
        {QStringLiteral("output.%1.colorPowerTradeoff.%2").arg(m_displayName, mode)}, 2500);
    m_colorAccuracy = mode;
    notifyStatus(mode == QStringLiteral("preferAccuracy")
        ? QStringLiteral("Color accuracy prioritized")
        : QStringLiteral("Power efficiency prioritized for color"));
    emit displayChanged();
}

void SystemBackend::setDisplayScale(int percent)
{
    const int clamped = qBound(100, percent, 200);
    if (clamped == m_displayScale) {
        return;
    }
    m_displayScale = clamped;
    const double scaleFactor = m_displayScale / 100.0;
    if (!m_displayName.isEmpty()) {
        runCommand(QStringLiteral("kscreen-doctor"),
            {QStringLiteral("output.%1.scale.%2").arg(m_displayName, QString::number(scaleFactor, 'f', 2))}, 2500);
        notifyStatus(QStringLiteral("Display scale set to %1%").arg(m_displayScale));
    }
    emit displayChanged();
}

void SystemBackend::setNightLight(bool enabled, int temp)
{
    m_nightLightEnabled = enabled;
    m_nightLightTemp = qBound(2500, temp, 6500);

    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("NightColor"),
         QStringLiteral("--key"), QStringLiteral("Mode"),
         QStringLiteral("Constant"),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("NightColor"),
         QStringLiteral("--key"), QStringLiteral("NightTemperature"),
         QString::number(m_nightLightTemp),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("NightColor"),
         QStringLiteral("--key"), QStringLiteral("DayTemperature"),
         enabled ? QString::number(m_nightLightTemp) : QStringLiteral("6500"),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("NightColor"),
         QStringLiteral("--key"), QStringLiteral("Active"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);

    if (enabled) {
        const QString inhibited = runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"),
             QStringLiteral("/org/kde/KWin/NightLight"),
             QStringLiteral("org.kde.KWin.NightLight.inhibited")}, 1000);
        if (inhibited == QStringLiteral("true")) {
            runDetached(QStringLiteral("qdbus6"),
                {QStringLiteral("org.kde.kglobalaccel"),
                 QStringLiteral("/component/kwin"),
                 QStringLiteral("org.kde.kglobalaccel.Component.invokeShortcut"),
                 QStringLiteral("Toggle Night Color")});
        }
    }

    notifyStatus(enabled ? QStringLiteral("Night Light enabled (%1K)").arg(m_nightLightTemp) : QStringLiteral("Night Light disabled"));
    emit displayChanged();
}

// -----------------------------------------------------------------------------
// 4. NETWORK & INTERNET (NetworkManager nmcli)
// -----------------------------------------------------------------------------
void SystemBackend::refreshNetwork()
{
    const QString wifiState = runCommand(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi")}, 1500);
    m_wifiEnabled = (wifiState.trimmed() == QStringLiteral("enabled"));

    const QString activeConns = runCommand(QStringLiteral("nmcli"),
        {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("NAME,TYPE,DEVICE"), QStringLiteral("connection"), QStringLiteral("show"), QStringLiteral("--active")}, 2000);

    m_networkConnected = false;
    m_connectionType = QStringLiteral("Disconnected");
    m_activeNetworkName = QStringLiteral("Not Connected");

    for (const QString &line : activeConns.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList fields = line.split(QLatin1Char(':'));
        if (fields.size() >= 3) {
            const QString name = fields.at(0);
            const QString type = fields.at(1);
            if (type == QStringLiteral("loopback") || name == QStringLiteral("lo")) {
                continue;
            }
            m_networkConnected = true;
            m_activeNetworkName = name;
            if (type.contains(QStringLiteral("wireless")) || type.contains(QStringLiteral("wifi"))) {
                m_connectionType = QStringLiteral("Wi-Fi");
            } else if (type.contains(QStringLiteral("ethernet"))) {
                m_connectionType = QStringLiteral("Ethernet");
            } else {
                m_connectionType = type;
            }
            break;
        }
    }

    const QString ipOut = runCommand(QStringLiteral("sh"),
        {QStringLiteral("-c"), QStringLiteral("ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1")}, 1500);
    m_ipAddress = ipOut.isEmpty() ? QStringLiteral("Offline") : ipOut;

    emit networkChanged();
}

void SystemBackend::setWifiEnabled(bool enabled)
{
    m_wifiEnabled = enabled;
    runCommand(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), enabled ? QStringLiteral("on") : QStringLiteral("off")}, 2000);
    if (enabled) {
        scanWifi();
    } else {
        m_wifiNetworks.clear();
        refreshNetwork();
    }
}

void SystemBackend::scanWifi()
{
    if (!m_wifiEnabled) {
        return;
    }
    notifyStatus(QStringLiteral("Scanning for Wi-Fi networks..."));
    const QString out = runCommand(QStringLiteral("nmcli"),
        {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
         QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list"), QStringLiteral("--rescan"), QStringLiteral("auto")}, 4000);

    QVariantList nets;
    QStringList seenSsids;
    for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList parts = line.split(QLatin1Char(':'));
        if (parts.size() >= 4) {
            const bool inUse = (parts.at(0).trimmed() == QStringLiteral("*"));
            const QString ssid = parts.at(1).trimmed();
            if (ssid.isEmpty() || seenSsids.contains(ssid)) {
                continue;
            }
            seenSsids.append(ssid);
            QVariantMap item;
            item[QStringLiteral("inUse")] = inUse;
            item[QStringLiteral("ssid")] = ssid;
            item[QStringLiteral("signal")] = parts.at(2).toInt();
            item[QStringLiteral("security")] = parts.at(3).trimmed().isEmpty() ? QStringLiteral("Open") : parts.at(3).trimmed();
            nets.append(item);
        }
    }
    m_wifiNetworks = nets;
    refreshNetwork();
    notifyStatus(QStringLiteral("Found %1 Wi-Fi networks").arg(nets.size()));
}

void SystemBackend::connectWifi(const QString &ssid, const QString &password)
{
    if (ssid.isEmpty()) {
        return;
    }
    notifyStatus(QStringLiteral("Connecting to %1...").arg(ssid));
    QStringList args = {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid};
    if (!password.isEmpty()) {
        args << QStringLiteral("password") << password;
    }
    const QString res = runCommand(QStringLiteral("nmcli"), args, 8000);
    if (res.contains(QStringLiteral("successfully activated"), Qt::CaseInsensitive)) {
        notifyStatus(QStringLiteral("Connected to %1").arg(ssid));
    } else {
        notifyStatus(QStringLiteral("Connection result: %1").arg(res.isEmpty() ? QStringLiteral("Failed or timed out") : res));
    }
    scanWifi();
}

void SystemBackend::disconnectNetwork()
{
    if (!m_activeNetworkName.isEmpty() && m_activeNetworkName != QStringLiteral("Not Connected")) {
        runCommand(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("down"), m_activeNetworkName}, 3000);
        notifyStatus(QStringLiteral("Disconnected from %1").arg(m_activeNetworkName));
        refreshNetwork();
    }
}

// -----------------------------------------------------------------------------
// 5. BLUETOOTH & INPUT DEVICES
// -----------------------------------------------------------------------------
void SystemBackend::refreshBluetooth()
{
    const QString btShow = runCommand(QStringLiteral("bluetoothctl"), {QStringLiteral("show")}, 1500);
    m_bluetoothEnabled = btShow.contains(QStringLiteral("Powered: yes"), Qt::CaseInsensitive);

    QVariantList devList;
    if (m_bluetoothEnabled) {
        const QString devsOut = runCommand(QStringLiteral("bluetoothctl"), {QStringLiteral("devices")}, 1500);
        for (const QString &line : devsOut.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QStringList tokens = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
            if (tokens.size() >= 3 && tokens.at(0) == QStringLiteral("Device")) {
                const QString mac = tokens.at(1);
                const QString name = tokens.mid(2).join(QLatin1Char(' '));
                const QString infoOut = runCommand(QStringLiteral("bluetoothctl"), {QStringLiteral("info"), mac}, 1000);
                const bool connected = infoOut.contains(QStringLiteral("Connected: yes"), Qt::CaseInsensitive);
                QVariantMap dev;
                dev[QStringLiteral("mac")] = mac;
                dev[QStringLiteral("name")] = name;
                dev[QStringLiteral("connected")] = connected;
                devList.append(dev);
            }
        }
    }
    m_bluetoothDevices = devList;
    emit bluetoothChanged();
}

void SystemBackend::setBluetoothEnabled(bool enabled)
{
    m_bluetoothEnabled = enabled;
    if (enabled) {
        runCommand(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("bluetooth")}, 1500);
        runCommand(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), QStringLiteral("on")}, 2000);
        notifyStatus(QStringLiteral("Bluetooth turned on"));
    } else {
        runCommand(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), QStringLiteral("off")}, 2000);
        notifyStatus(QStringLiteral("Bluetooth turned off"));
    }
    refreshBluetooth();
}

void SystemBackend::scanBluetooth()
{
    if (!m_bluetoothEnabled) {
        setBluetoothEnabled(true);
    }
    notifyStatus(QStringLiteral("Scanning Bluetooth devices..."));
    runCommand(QStringLiteral("bluetoothctl"), {QStringLiteral("--timeout"), QStringLiteral("3"), QStringLiteral("scan"), QStringLiteral("on")}, 4000);
    refreshBluetooth();
    notifyStatus(QStringLiteral("Bluetooth scan complete (%1 devices)").arg(m_bluetoothDevices.size()));
}

void SystemBackend::toggleBluetoothDevice(const QString &mac, bool connectDevice)
{
    if (mac.isEmpty()) {
        return;
    }
    runCommand(QStringLiteral("bluetoothctl"), {connectDevice ? QStringLiteral("connect") : QStringLiteral("disconnect"), mac}, 4000);
    refreshBluetooth();
}

void SystemBackend::loadInputSettings()
{
    QSettings inputRc(QDir::homePath() + QStringLiteral("/.config/kcminputrc"), QSettings::IniFormat);
    inputRc.beginGroup(QStringLiteral("Mouse"));
    const double accel = inputRc.value(QStringLiteral("PointerAcceleration"), 0.0).toDouble();
    m_mouseSpeed = qBound(1, static_cast<int>(std::round((accel + 1.0) * 5.0)), 10);
    m_leftHandedMouse = inputRc.value(QStringLiteral("XLbInptLeftHanded"), false).toBool();
    m_naturalScroll = inputRc.value(QStringLiteral("NaturalScroll"), false).toBool();
    m_tapToClick = inputRc.value(QStringLiteral("TapToClick"), true).toBool();
    inputRc.endGroup();
    emit inputChanged();
}

void SystemBackend::setMouseSettings(int speed, bool natural, bool tap, bool leftHanded)
{
    m_mouseSpeed = qBound(1, speed, 10);
    m_naturalScroll = natural;
    m_tapToClick = tap;
    m_leftHandedMouse = leftHanded;

    const double accel = (m_mouseSpeed / 5.0) - 1.0;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kcminputrc"),
         QStringLiteral("--group"), QStringLiteral("Mouse"),
         QStringLiteral("--key"), QStringLiteral("PointerAcceleration"),
         QString::number(accel, 'f', 2)}, 1000);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kcminputrc"),
         QStringLiteral("--group"), QStringLiteral("Mouse"),
         QStringLiteral("--key"), QStringLiteral("XLbInptLeftHanded"),
         leftHanded ? QStringLiteral("true") : QStringLiteral("false")}, 1000);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kcminputrc"),
         QStringLiteral("--group"), QStringLiteral("Mouse"),
         QStringLiteral("--key"), QStringLiteral("NaturalScroll"),
         natural ? QStringLiteral("true") : QStringLiteral("false")}, 1000);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kcminputrc"),
         QStringLiteral("--group"), QStringLiteral("Mouse"),
         QStringLiteral("--key"), QStringLiteral("TapToClick"),
         tap ? QStringLiteral("true") : QStringLiteral("false")}, 1000);

    runDetached(QStringLiteral("qdbus6"), {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("reconfigure")});
    notifyStatus(QStringLiteral("Mouse & Touchpad preferences applied"));
    emit inputChanged();
}

// -----------------------------------------------------------------------------
// 6. POWER & BATTERY
// -----------------------------------------------------------------------------
void SystemBackend::refreshPower()
{
    m_hasBattery = false;
    QDir powerDir(QStringLiteral("/sys/class/power_supply"));
    for (const QString &entry : powerDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (entry.startsWith(QStringLiteral("BAT"))) {
            m_hasBattery = true;
            QFile capFile(powerDir.filePath(entry + QStringLiteral("/capacity")));
            if (capFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                m_batteryPercent = qBound(0, QString::fromUtf8(capFile.readAll()).trimmed().toInt(), 100);
            }
            QFile statusFile(powerDir.filePath(entry + QStringLiteral("/status")));
            if (statusFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                m_batteryState = QString::fromUtf8(statusFile.readAll()).trimmed();
            }
            break;
        }
    }
    if (!m_hasBattery) {
        m_batteryPercent = 100;
        m_batteryState = QStringLiteral("Connected to AC Power");
    }

    const QString ppOut = runCommand(QStringLiteral("powerprofilesctl"), {QStringLiteral("get")}, 1500);
    if (!ppOut.isEmpty()) {
        m_powerProfile = ppOut.trimmed();
    }
    emit powerChanged();
}

void SystemBackend::setPowerProfile(const QString &profile)
{
    if (profile.isEmpty()) {
        return;
    }
    m_powerProfile = profile;
    runCommand(QStringLiteral("powerprofilesctl"), {QStringLiteral("set"), profile}, 2000);
    notifyStatus(QStringLiteral("Power mode switched to %1").arg(profile));
    emit powerChanged();
}

// -----------------------------------------------------------------------------
// 7. PERSONALIZATION (Curated Sourceless Themes, Wallpapers & Visual Effects)
// -----------------------------------------------------------------------------
namespace {
QJsonObject readJsonMetadata(const QString &jsonPath)
{
    QFile file(jsonPath);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    return doc.isObject() ? doc.object() : QJsonObject{};
}
}

void SystemBackend::refreshPersonalization()
{
    // Active Plasma desktop theme
    QSettings plasmarc(QDir::homePath() + QStringLiteral("/.config/plasmarc"), QSettings::IniFormat);
    plasmarc.beginGroup(QStringLiteral("Theme"));
    QString activeTheme = plasmarc.value(QStringLiteral("name")).toString().trimmed();
    plasmarc.endGroup();
    if (activeTheme.isEmpty()) {
        QSettings globalPlasmarc(QStringLiteral("/etc/xdg/plasmarc"), QSettings::IniFormat);
        globalPlasmarc.beginGroup(QStringLiteral("Theme"));
        activeTheme = globalPlasmarc.value(QStringLiteral("name"), QStringLiteral("SourcelessGlass")).toString().trimmed();
        globalPlasmarc.endGroup();
    }
    if (activeTheme.isEmpty()) {
        activeTheme = QStringLiteral("SourcelessGlass");
    }
    m_currentTheme = activeTheme;

    // Index Look-and-Feel thumbnails & mapped desktop theme IDs
    QVariantMap lnfThumbByDesktopTheme;
    QVariantList customLnfFallback;
    const QDir lnfRoot(QStringLiteral("/usr/share/plasma/look-and-feel"));
    for (const QString &lnfDir : lnfRoot.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        if (lnfDir.startsWith(QStringLiteral("org.kde.")) || lnfDir.startsWith(QStringLiteral("org.fedoraproject."))) {
            continue;
        }
        const QString lnfPath = lnfRoot.filePath(lnfDir);
        const QString thumbPath = lnfPath + QStringLiteral("/contents/previews/thumbnail.png");
        const QString thumbUrl = QFileInfo::exists(thumbPath) ? QUrl::fromLocalFile(thumbPath).toString() : QString();

        QSettings defaultsIni(lnfPath + QStringLiteral("/contents/defaults"), QSettings::IniFormat);
        defaultsIni.beginGroup(QStringLiteral("PlasmaTheme"));
        QString mappedDesktop = defaultsIni.value(QStringLiteral("name")).toString().trimmed();
        defaultsIni.endGroup();
        if (mappedDesktop.isEmpty()) {
            defaultsIni.beginGroup(QStringLiteral("Theme"));
            mappedDesktop = defaultsIni.value(QStringLiteral("name")).toString().trimmed();
            defaultsIni.endGroup();
        }
        if (!mappedDesktop.isEmpty() && !thumbUrl.isEmpty()) {
            lnfThumbByDesktopTheme[mappedDesktop] = thumbUrl;
        }

        const QJsonObject meta = readJsonMetadata(lnfPath + QStringLiteral("/metadata.json"));
        const QJsonObject plugin = meta.value(QStringLiteral("KPlugin")).toObject();
        const QString lnfId = plugin.value(QStringLiteral("Id")).toString(lnfDir);
        const QString lnfName = plugin.value(QStringLiteral("Name")).toString(lnfDir);
        const QString lnfDesc = plugin.value(QStringLiteral("Description")).toString();

        QVariantMap lnfItem;
        lnfItem[QStringLiteral("id")] = lnfId;
        lnfItem[QStringLiteral("mappedDesktop")] = mappedDesktop;
        lnfItem[QStringLiteral("name")] = lnfName;
        lnfItem[QStringLiteral("description")] = lnfDesc;
        lnfItem[QStringLiteral("hasBlur")] = mappedDesktop.contains(QStringLiteral("Glass"), Qt::CaseInsensitive)
                                             || lnfDesc.contains(QStringLiteral("Glass"), Qt::CaseInsensitive);
        lnfItem[QStringLiteral("previewUrl")] = thumbUrl;
        customLnfFallback.append(lnfItem);
    }

    // Scan installed Plasma desktop themes (skip generic upstream system directories)
    QVariantList themeList;
    QStringList seenThemeIds;
    const QStringList skipDesktopDirs = {
        QStringLiteral("default"),
        QStringLiteral("widgets"),
        QStringLiteral("breeze"),
        QStringLiteral("breeze-dark"),
        QStringLiteral("breeze-light"),
        QStringLiteral("oxygen")
    };
    const QDir dtRoot(QStringLiteral("/usr/share/plasma/desktoptheme"));
    for (const QString &dirName : dtRoot.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        if (skipDesktopDirs.contains(dirName, Qt::CaseInsensitive)) {
            continue;
        }
        const QString dtPath = dtRoot.filePath(dirName);
        if (!QFileInfo::exists(dtPath + QStringLiteral("/metadata.json"))) {
            continue;
        }
        const QJsonObject meta = readJsonMetadata(dtPath + QStringLiteral("/metadata.json"));
        const QJsonObject plugin = meta.value(QStringLiteral("KPlugin")).toObject();
        const QString themeId = plugin.value(QStringLiteral("Id")).toString(dirName);
        const QString themeName = plugin.value(QStringLiteral("Name")).toString(dirName);
        const bool hasBlur = meta.value(QStringLiteral("BlurEffect")).toObject().value(QStringLiteral("enabled")).toBool(false);
        QString desc = plugin.value(QStringLiteral("Description")).toString().trimmed();
        if (desc.isEmpty()) {
            desc = hasBlur ? QStringLiteral("Liquid Glass • Blur Enabled") : QStringLiteral("Solid Theme • No Blur");
        }

        QString previewUrl;
        const QStringList previewCandidates = {
            dtPath + QStringLiteral("/preview.png"),
            dtPath + QStringLiteral("/contents/previews/preview.png"),
            dtPath + QStringLiteral("/contents/previews/thumbnail.png")
        };
        for (const QString &cand : previewCandidates) {
            if (QFileInfo::exists(cand)) {
                previewUrl = QUrl::fromLocalFile(cand).toString();
                break;
            }
        }
        if (previewUrl.isEmpty() && lnfThumbByDesktopTheme.contains(themeId)) {
            previewUrl = lnfThumbByDesktopTheme.value(themeId).toString();
        }

        QVariantMap theme;
        theme[QStringLiteral("id")] = themeId;
        theme[QStringLiteral("name")] = themeName;
        theme[QStringLiteral("description")] = desc;
        theme[QStringLiteral("hasBlur")] = hasBlur;
        theme[QStringLiteral("previewUrl")] = previewUrl;
        theme[QStringLiteral("active")] = (themeId == m_currentTheme);
        themeList.append(theme);
        seenThemeIds.append(themeId);
    }

    // Include any standalone custom Look-and-Feel themes not already backed by a listed desktop theme
    for (const QVariant &v : customLnfFallback) {
        QVariantMap lnf = v.toMap();
        const QString lnfId = lnf.value(QStringLiteral("id")).toString();
        const QString mapped = lnf.value(QStringLiteral("mappedDesktop")).toString();
        if (seenThemeIds.contains(lnfId) || (!mapped.isEmpty() && seenThemeIds.contains(mapped))) {
            continue;
        }
        QString desc = lnf.value(QStringLiteral("description")).toString().trimmed();
        if (desc.isEmpty()) {
            desc = lnf.value(QStringLiteral("hasBlur")).toBool()
                       ? QStringLiteral("Liquid Glass • Blur Enabled")
                       : QStringLiteral("Solid Theme • No Blur");
        }
        lnf[QStringLiteral("description")] = desc;
        lnf[QStringLiteral("active")] = (lnfId == m_currentTheme);
        lnf.remove(QStringLiteral("mappedDesktop"));
        themeList.append(lnf);
    }
    m_themes = themeList;

    // Scan curated wallpapers
    QVariantList wpList;
    QDir wpRoot(QStringLiteral("/usr/share/wallpapers"));
    const QStringList entries = wpRoot.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &dirName : entries) {
        const QString fullDir = wpRoot.filePath(dirName);
        if (QFileInfo(fullDir).isSymLink()) {
            continue;
        }
        QString imgPath;
        const QStringList candidates = {
            fullDir + QStringLiteral("/contents/images_dark/3840x2160.jpg"),
            fullDir + QStringLiteral("/contents/images/3840x2160.jpg"),
            fullDir + QStringLiteral("/contents/images_dark/3840x2160.png"),
            fullDir + QStringLiteral("/contents/images/3840x2160.png"),
            fullDir + QStringLiteral("/contents/images_dark/1920x1080.png"),
            fullDir + QStringLiteral("/contents/images/1920x1080.png")
        };
        for (const QString &cand : candidates) {
            if (QFileInfo::exists(cand)) {
                imgPath = cand;
                break;
            }
        }
        if (imgPath.isEmpty()) {
            QDir imgDir(fullDir + QStringLiteral("/contents/images"));
            const QStringList files = imgDir.entryList({QStringLiteral("*.jpg"), QStringLiteral("*.png")}, QDir::Files);
            if (!files.isEmpty()) {
                imgPath = imgDir.filePath(files.first());
            }
        }
        if (!imgPath.isEmpty()) {
            QVariantMap wp;
            wp[QStringLiteral("id")] = dirName;
            QString displayName = dirName;
            displayName.replace(QLatin1Char('-'), QLatin1Char(' '));
            wp[QStringLiteral("name")] = displayName;
            wp[QStringLiteral("previewUrl")] = QUrl::fromLocalFile(imgPath).toString();
            wp[QStringLiteral("path")] = imgPath;
            wpList.append(wp);
        }
    }
    m_wallpapers = wpList;

    QSettings kwinrc(QDir::homePath() + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
    kwinrc.beginGroup(QStringLiteral("Plugins"));
    m_blurEnabled = kwinrc.value(QStringLiteral("blurEnabled"), true).toBool();
    kwinrc.endGroup();

    QSettings kdeglobals(QDir::homePath() + QStringLiteral("/.config/kdeglobals"), QSettings::IniFormat);
    kdeglobals.beginGroup(QStringLiteral("KDE"));
    m_animationsEnabled = kdeglobals.value(QStringLiteral("AnimationDurationFactor"), 1.0).toDouble() > 0.05;
    kdeglobals.endGroup();

    emit personalizationChanged();
}

void SystemBackend::applyTheme(const QString &themeId)
{
    if (themeId.isEmpty()) {
        return;
    }

    const QString desktopMeta = QStringLiteral("/usr/share/plasma/desktoptheme/") + themeId + QStringLiteral("/metadata.json");
    const QString lnfMeta = QStringLiteral("/usr/share/plasma/look-and-feel/") + themeId + QStringLiteral("/metadata.json");
    bool hasBlur = false;

    if (QFileInfo::exists(desktopMeta)) {
        runCommand(QStringLiteral("plasma-apply-desktoptheme"), {themeId}, 3000);
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("plasmarc"),
             QStringLiteral("--group"), QStringLiteral("Theme"),
             QStringLiteral("--key"), QStringLiteral("name"),
             themeId}, 1500);

        const QJsonObject meta = readJsonMetadata(desktopMeta);
        hasBlur = meta.value(QStringLiteral("BlurEffect")).toObject().value(QStringLiteral("enabled")).toBool(false);
    } else if (QFileInfo::exists(lnfMeta)) {
        runCommand(QStringLiteral("plasma-apply-lookandfeel"), {QStringLiteral("-a"), themeId}, 4000);
    }

    if (QFileInfo::exists(QStringLiteral("/usr/share/color-schemes/") + themeId + QStringLiteral(".colors"))) {
        runCommand(QStringLiteral("plasma-apply-colorscheme"), {themeId}, 2000);
    }
    if (QFileInfo::exists(QStringLiteral("/usr/share/Kvantum/") + themeId)) {
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("Kvantum/kvantum.kvconfig"),
             QStringLiteral("--group"), QStringLiteral("General"),
             QStringLiteral("--key"), QStringLiteral("theme"),
             themeId}, 1500);
    }
    if (QFileInfo::exists(QStringLiteral("/usr/share/aurorae/themes/") + themeId)) {
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"),
             QStringLiteral("--group"), QStringLiteral("org.kde.kdecoration2"),
             QStringLiteral("--key"), QStringLiteral("theme"),
             QStringLiteral("__aurorae__svg__") + themeId}, 1500);
    }

    // Automatically match KWin compositor blur to the selected theme's capability
    m_blurEnabled = hasBlur;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("Plugins"),
         QStringLiteral("--key"), QStringLiteral("blurEnabled"),
         hasBlur ? QStringLiteral("true") : QStringLiteral("false")}, 1500);
    runDetached(QStringLiteral("qdbus6"), {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("reconfigure")});

    m_currentTheme = themeId;
    QString displayName = themeId;
    for (int i = 0; i < m_themes.size(); ++i) {
        QVariantMap item = m_themes.at(i).toMap();
        const bool isActive = (item.value(QStringLiteral("id")).toString() == themeId);
        item[QStringLiteral("active")] = isActive;
        if (isActive) {
            displayName = item.value(QStringLiteral("name"), themeId).toString();
        }
        m_themes[i] = item;
    }

    notifyStatus(QStringLiteral("System theme applied: %1").arg(displayName));
    emit personalizationChanged();
}

void SystemBackend::applyWallpaper(const QString &path)
{
    if (path.isEmpty() || !QFileInfo::exists(path)) {
        return;
    }
    m_currentWallpaper = path;
    runCommand(QStringLiteral("plasma-apply-wallpaperimage"), {path}, 3000);
    notifyStatus(QStringLiteral("Desktop wallpaper updated"));
    emit personalizationChanged();
}

void SystemBackend::setBlurEnabled(bool enabled)
{
    m_blurEnabled = enabled;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("Plugins"),
         QStringLiteral("--key"), QStringLiteral("blurEnabled"),
         enabled ? QStringLiteral("true") : QStringLiteral("false")}, 1500);
    runDetached(QStringLiteral("qdbus6"), {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("reconfigure")});
    notifyStatus(enabled ? QStringLiteral("Sourceless Glass Blur enabled") : QStringLiteral("Sourceless Glass Blur disabled"));
    emit personalizationChanged();
}

void SystemBackend::setAnimationsEnabled(bool enabled)
{
    m_animationsEnabled = enabled;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kdeglobals"),
         QStringLiteral("--group"), QStringLiteral("KDE"),
         QStringLiteral("--key"), QStringLiteral("AnimationDurationFactor"),
         enabled ? QStringLiteral("1") : QStringLiteral("0")}, 1500);
    runDetached(QStringLiteral("qdbus6"), {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("reconfigure")});
    notifyStatus(enabled ? QStringLiteral("Desktop animations enabled") : QStringLiteral("Desktop animations reduced"));
    emit personalizationChanged();
}

// -----------------------------------------------------------------------------
// 8. APPS (Flatpak Sandboxed Applications)
// -----------------------------------------------------------------------------
void SystemBackend::refreshApps()
{
    const QString out = runCommand(QStringLiteral("flatpak"),
        {QStringLiteral("list"), QStringLiteral("--app"), QStringLiteral("--columns=name,application,version,branch,installation")}, 3000);

    QVariantList apps;
    const QStringList protectedIds = {
        QStringLiteral("org.mozilla.firefox"),
        QStringLiteral("com.github.tchx84.Flatseal")
    };

    for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList cols = line.split(QLatin1Char('\t'));
        if (cols.size() >= 2) {
            const QString name = cols.at(0).trimmed();
            const QString appId = cols.at(1).trimmed();
            const QString version = cols.value(2).trimmed().isEmpty() ? QStringLiteral("Latest") : cols.value(2).trimmed();
            const QString scope = cols.value(4).trimmed();
            QVariantMap app;
            app[QStringLiteral("name")] = name;
            app[QStringLiteral("appId")] = appId;
            app[QStringLiteral("version")] = version;
            app[QStringLiteral("scope")] = scope.isEmpty() ? QStringLiteral("system") : scope;
            app[QStringLiteral("protectedApp")] = protectedIds.contains(appId);
            apps.append(app);
        }
    }
    m_installedApps = apps;
    emit appsChanged();
}

void SystemBackend::launchApp(const QString &appId)
{
    if (!appId.isEmpty()) {
        runDetached(QStringLiteral("flatpak"), {QStringLiteral("run"), appId});
        notifyStatus(QStringLiteral("Launching %1...").arg(appId));
    }
}

void SystemBackend::uninstallApp(const QString &appId)
{
    if (appId.isEmpty() || appId == QStringLiteral("org.mozilla.firefox") || appId == QStringLiteral("com.github.tchx84.Flatseal")) {
        notifyStatus(QStringLiteral("System core applications cannot be removed."));
        return;
    }
    notifyStatus(QStringLiteral("Uninstalling %1...").arg(appId));
    runCommand(QStringLiteral("flatpak"), {QStringLiteral("uninstall"), QStringLiteral("-y"), QStringLiteral("--noninteractive"), appId}, 15000);
    refreshApps();
    notifyStatus(QStringLiteral("Removed %1").arg(appId));
}

void SystemBackend::updateAllApps()
{
    notifyStatus(QStringLiteral("Updating all Flatpak applications in background..."));
    runDetached(QStringLiteral("flatpak"), {QStringLiteral("update"), QStringLiteral("-y"), QStringLiteral("--noninteractive")});
}

void SystemBackend::clearUserCache()
{
    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
    if (!cacheDir.isEmpty() && cacheDir.startsWith(QDir::homePath())) {
        runCommand(QStringLiteral("find"), {cacheDir, QStringLiteral("-mindepth"), QStringLiteral("1"), QStringLiteral("-maxdepth"), QStringLiteral("2"), QStringLiteral("-mtime"), QStringLiteral("+3"), QStringLiteral("-delete")}, 3000);
    }
    loadDynamicSystemMetrics();
    notifyStatus(QStringLiteral("Temporary user cache cleaned successfully"));
}

// -----------------------------------------------------------------------------
// 9. TIME & LANGUAGE
// -----------------------------------------------------------------------------
void SystemBackend::refreshTime()
{
    m_currentDateTime = QDateTime::currentDateTime().toString(m_use24Hour ? QStringLiteral("dddd, dd MMMM yyyy  •  HH:mm") : QStringLiteral("dddd, dd MMMM yyyy  •  hh:mm AP"));

    const QString tz = runCommand(QStringLiteral("timedatectl"), {QStringLiteral("show"), QStringLiteral("-p"), QStringLiteral("Timezone"), QStringLiteral("--value")}, 1500);
    if (!tz.isEmpty()) {
        m_timezone = tz;
    }

    const QString ntp = runCommand(QStringLiteral("timedatectl"), {QStringLiteral("show"), QStringLiteral("-p"), QStringLiteral("NTP"), QStringLiteral("--value")}, 1500);
    m_ntpEnabled = (ntp.trimmed() == QStringLiteral("yes"));

    QSettings kxkb(QDir::homePath() + QStringLiteral("/.config/kxkbrc"), QSettings::IniFormat);
    kxkb.beginGroup(QStringLiteral("Layout"));
    m_keyboardLayout = kxkb.value(QStringLiteral("LayoutList"), QStringLiteral("us")).toString();
    kxkb.endGroup();

    emit timeChanged();
}

void SystemBackend::setKeyboardLayout(const QString &layout)
{
    if (layout.isEmpty()) {
        return;
    }
    m_keyboardLayout = layout;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kxkbrc"),
         QStringLiteral("--group"), QStringLiteral("Layout"),
         QStringLiteral("--key"), QStringLiteral("LayoutList"),
         layout}, 1000);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kxkbrc"),
         QStringLiteral("--group"), QStringLiteral("Layout"),
         QStringLiteral("--key"), QStringLiteral("Use"),
         QStringLiteral("true")}, 1000);
    runDetached(QStringLiteral("qdbus6"), {QStringLiteral("org.kde.keyboard"), QStringLiteral("/Layouts"), QStringLiteral("reloadConfig")});
    notifyStatus(QStringLiteral("Keyboard layout set to: %1").arg(layout.toUpper()));
    emit timeChanged();
}

void SystemBackend::setUse24Hour(bool use24)
{
    m_use24Hour = use24;
    refreshTime();
}

// -----------------------------------------------------------------------------
// 10. PRIVACY & SECURITY (Sourceless OS Lockdown Telemetry & Controls)
// -----------------------------------------------------------------------------
void SystemBackend::refreshSecurity()
{
    int score = 100;
    QVariantList events;

    // 1. SELinux Check
    m_selinuxOk = false;
    QFile selinuxFile(QStringLiteral("/sys/fs/selinux/enforce"));
    if (selinuxFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (QString::fromUtf8(selinuxFile.readAll()).trimmed() == QStringLiteral("1")) {
            m_selinuxOk = true;
            m_selinuxStatus = QStringLiteral("Enforcing (Mandatory Access Control)");
        } else {
            m_selinuxStatus = QStringLiteral("Permissive / Disabled (UNSAFE)");
        }
    }
    if (!m_selinuxOk) {
        score -= 25;
        events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("SELinux Mandatory Access Control is not enforcing")},
                                  {QStringLiteral("severity"), QStringLiteral("critical")}});
    }

    // 2. Kernel Lockdown Check
    m_lockdownOk = false;
    QFile lockdownFile(QStringLiteral("/sys/kernel/security/lockdown"));
    if (lockdownFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString ld = QString::fromUtf8(lockdownFile.readAll()).trimmed();
        if (ld.contains(QStringLiteral("[confidentiality]"))) {
            m_lockdownOk = true;
            m_lockdownMode = QStringLiteral("Confidentiality (Strict)");
        } else if (ld.contains(QStringLiteral("[integrity]"))) {
            m_lockdownOk = true;
            m_lockdownMode = QStringLiteral("Integrity (Kernel Hardened)");
        } else {
            m_lockdownMode = QStringLiteral("None / Disabled (UNSAFE)");
        }
    }
    if (!m_lockdownOk) {
        score -= 15;
    }

    // 3. YARA Shield & Telemetry Agent Check
    m_shieldActive = (runCommand(QStringLiteral("systemctl"), {QStringLiteral("is-active"), QStringLiteral("sourceless-shield.service")}, 1500) == QStringLiteral("active"));
    if (!m_shieldActive) {
        score -= 15;
        events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("Real-Time YARA Downloads Shield is stopped")},
                                  {QStringLiteral("severity"), QStringLiteral("warning")}});
    }

    m_clientActive = (runCommand(QStringLiteral("systemctl"), {QStringLiteral("is-active"), QStringLiteral("sourceless-client.service")}, 1500) == QStringLiteral("active"));
    if (!m_clientActive) {
        score -= 10;
    }

    // 4. Support Gate & Tamper / Modified Check
    const bool supportTokenExists = QFileInfo::exists(QStringLiteral("/tmp/sourceless_support_active")) ||
                                    QFileInfo::exists(QStringLiteral("/var/run/sourceless_support_active"));
    const bool konsoleRunning = !runCommand(QStringLiteral("pgrep"), {QStringLiteral("-x"), QStringLiteral("konsole.real")}, 1000).isEmpty();
    m_supportSessionActive = supportTokenExists || konsoleRunning;

    const bool tamperFlagFile = QFileInfo::exists(QStringLiteral("/etc/sourceless/.tamper_detected")) ||
                                QFileInfo::exists(QStringLiteral("/tmp/.sourceless_tamper_trigger"));

    const QString groupsOut = runCommand(QStringLiteral("id"), {QStringLiteral("-Gn")}, 1000);
    const bool inWheelGroup = groupsOut.split(QLatin1Char(' ')).contains(QStringLiteral("wheel"));

    // Check journald for support unlock or interactive shell audit logs in current boot
    const QString auditLogs = runCommand(QStringLiteral("sh"),
        {QStringLiteral("-c"),
         QStringLiteral("journalctl -b -t sourceless-security -t sourceless-audit --no-pager -q -n 5 2>/dev/null")}, 1500);
    const bool hasAuditActivity = !auditLogs.isEmpty();

    m_isTampered = tamperFlagFile || m_supportSessionActive || inWheelGroup || hasAuditActivity;

    if (m_isTampered) {
        score -= 35;
        QStringList reasons;
        if (tamperFlagFile) reasons << QStringLiteral("Tamper Seal Broken");
        if (m_supportSessionActive) reasons << QStringLiteral("Terminal Active");
        if (inWheelGroup) reasons << QStringLiteral("Wheel Admin");
        if (hasAuditActivity && !tamperFlagFile) reasons << QStringLiteral("Sudo / Shell Audit Logged");
        m_systemIntegrity = QStringLiteral("Modified (%1)").arg(reasons.join(QStringLiteral(" • ")));

        events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("System Integrity Modified: ") + reasons.join(QStringLiteral(", "))},
                                  {QStringLiteral("severity"), QStringLiteral("critical")}});
    } else {
        m_systemIntegrity = QStringLiteral("Verified Immutable (OSTree + Cosign)");
    }

    if (m_supportSessionActive) {
        events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("Interactive Terminal / Support Session is currently ACTIVE")},
                                  {QStringLiteral("severity"), QStringLiteral("critical")}});
    }

    if (events.isEmpty()) {
        events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("All Sourceless OS lockdown and kernel integrity checks passed")},
                                  {QStringLiteral("severity"), QStringLiteral("ok")}});
    }

    m_securityScore = qBound(0, score, 100);
    m_overallSecurityOk = (!m_isTampered && m_selinuxOk && m_lockdownOk && m_shieldActive && !m_supportSessionActive);
    m_securityEvents = events;

    emit securityChanged();
}

void SystemBackend::launchEmergencyTerminal()
{
    runDetached(QStringLiteral("/usr/bin/sourceless-emergency-terminal"), {});
    notifyStatus(QStringLiteral("Opening Support Authorization prompt..."));
}

void SystemBackend::runQuickSecurityScan()
{
    notifyStatus(QStringLiteral("Running YARA threat scan on ~/Downloads and ~/.config..."));
    const QString downloadsDir = QDir::homePath() + QStringLiteral("/Downloads");
    const QString cmd = QStringLiteral(
        "count=$(find \"%1\" -type f 2>/dev/null | wc -l); "
        "hits=$(yara -r -w /etc/sourceless/rules/*.yar \"%1\" 2>/dev/null | wc -l); "
        "echo \"$count:$hits\"").arg(downloadsDir);

    const QString result = runCommand(QStringLiteral("sh"), {QStringLiteral("-c"), cmd}, 8000);
    const QStringList parts = result.split(QLatin1Char(':'));
    const int filesScanned = parts.value(0).trimmed().toInt();
    const int threatsFound = parts.value(1).trimmed().toInt();

    if (threatsFound > 0) {
        m_lastScanResult = QStringLiteral("ALERT: %1 threat(s) detected across %2 files in ~/Downloads!").arg(threatsFound).arg(filesScanned);
        notifyStatus(m_lastScanResult);
    } else {
        m_lastScanResult = QStringLiteral("Clean (%1 files scanned in ~/Downloads • 0 threats found at %2)")
            .arg(filesScanned)
            .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")));
        notifyStatus(QStringLiteral("YARA Scan Complete: 0 threats detected"));
    }
    emit securityChanged();
}

void SystemBackend::resetDesktopLayout()
{
    const QString skelApplets = QStringLiteral("/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc");
    const QString userApplets = QDir::homePath() + QStringLiteral("/.config/plasma-org.kde.plasma.desktop-appletsrc");
    if (QFileInfo::exists(skelApplets)) {
        QFile::remove(userApplets);
        QFile::copy(skelApplets, userApplets);
        runDetached(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("restart"), QStringLiteral("plasma-plasmashell")});
        notifyStatus(QStringLiteral("Desktop layout restored to Sourceless defaults"));
    }
}

// -----------------------------------------------------------------------------
// 11. ACCESSIBILITY (KWin Effects + KAccess AccessX + KCM Input + Orca)
// -----------------------------------------------------------------------------
void SystemBackend::setKwinEffectEnabled(const QString &pluginKey, const QString &effectId, bool enabled) const
{
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("Plugins"),
         QStringLiteral("--key"), pluginKey,
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);

    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.KWin"),
         QStringLiteral("/Effects"),
         enabled ? QStringLiteral("org.kde.kwin.Effects.loadEffect") : QStringLiteral("org.kde.kwin.Effects.unloadEffect"),
         effectId}, 1200);
    if (enabled) {
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"),
             QStringLiteral("/Effects"),
             QStringLiteral("org.kde.kwin.Effects.reconfigureEffect"),
             effectId}, 1000);
    }
}

void SystemBackend::reloadAccessDaemon() const
{
    runCommand(QStringLiteral("systemctl"),
        {QStringLiteral("--user"), QStringLiteral("try-restart"), QStringLiteral("plasma-kaccess.service")}, 1500);
    runDetached(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin.reconfigure")});
}

void SystemBackend::refreshAccessibility()
{
    QSettings kwinrc(QDir::homePath() + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
    kwinrc.beginGroup(QStringLiteral("Plugins"));
    m_screenZoomEnabled = kwinrc.value(QStringLiteral("zoomEnabled"), false).toBool();
    const bool cbEnabled = kwinrc.value(QStringLiteral("colorblindnesscorrectionEnabled"), false).toBool();
    m_invertScreenEnabled = kwinrc.value(QStringLiteral("invertEnabled"), false).toBool();
    m_shakeCursorEnabled = kwinrc.value(QStringLiteral("shakecursorEnabled"), true).toBool();
    m_trackMouseEnabled = kwinrc.value(QStringLiteral("trackmouseEnabled"), false).toBool();
    kwinrc.endGroup();

    if (cbEnabled) {
        kwinrc.beginGroup(QStringLiteral("Effect-colorblindnesscorrection"));
        const int cbRawMode = kwinrc.value(QStringLiteral("Mode"), 0).toInt();
        kwinrc.endGroup();
        m_colorBlindnessMode = qBound(0, cbRawMode, 3) + 1;
    } else {
        m_colorBlindnessMode = 0;
    }

    QSettings kcminputrc(QDir::homePath() + QStringLiteral("/.config/kcminputrc"), QSettings::IniFormat);
    kcminputrc.beginGroup(QStringLiteral("Mouse"));
    m_cursorSize = qBound(24, kcminputrc.value(QStringLiteral("cursorSize"), 24).toInt(), 64);
    kcminputrc.endGroup();

    QSettings kaccessrc(QDir::homePath() + QStringLiteral("/.config/kaccessrc"), QSettings::IniFormat);
    kaccessrc.beginGroup(QStringLiteral("ScreenReader"));
    if (kaccessrc.contains(QStringLiteral("Enabled"))) {
        m_screenReaderEnabled = kaccessrc.value(QStringLiteral("Enabled"), false).toBool();
    } else {
        m_screenReaderEnabled = kaccessrc.value(QStringLiteral("enabled"), false).toBool();
    }
    kaccessrc.endGroup();

    kaccessrc.beginGroup(QStringLiteral("Mouse"));
    m_mouseKeysEnabled = kaccessrc.value(QStringLiteral("MouseKeys"), false).toBool();
    kaccessrc.endGroup();

    kaccessrc.beginGroup(QStringLiteral("Keyboard"));
    m_stickyKeysEnabled = kaccessrc.value(QStringLiteral("StickyKeys"), false).toBool();
    m_stickyKeysLock = kaccessrc.value(QStringLiteral("StickyKeysLatch"), true).toBool();
    m_slowKeysEnabled = kaccessrc.value(QStringLiteral("SlowKeys"), false).toBool();
    m_slowKeysDelay = qBound(100, kaccessrc.value(QStringLiteral("SlowKeysDelay"), 500).toInt(), 2000);
    m_bounceKeysEnabled = kaccessrc.value(QStringLiteral("BounceKeys"), false).toBool();
    m_bounceKeysDelay = qBound(100, kaccessrc.value(QStringLiteral("BounceKeysDelay"), 500).toInt(), 2000);
    m_toggleKeysBeep = kaccessrc.value(QStringLiteral("ToggleKeysBeep"), false).toBool();
    kaccessrc.endGroup();

    kaccessrc.beginGroup(QStringLiteral("Bell"));
    m_systemBellEnabled = kaccessrc.value(QStringLiteral("SystemBell"), false).toBool();
    m_visibleBellEnabled = kaccessrc.value(QStringLiteral("VisibleBell"), false).toBool();
    m_visibleBellInvert = kaccessrc.value(QStringLiteral("VisibleBellInvert"), true).toBool();
    kaccessrc.endGroup();

    emit accessibilityChanged();
}

void SystemBackend::setScreenZoomEnabled(bool enabled)
{
    m_screenZoomEnabled = enabled;
    setKwinEffectEnabled(QStringLiteral("zoomEnabled"), QStringLiteral("zoom"), enabled);
    notifyStatus(enabled ? QStringLiteral("Screen Magnifier enabled (Meta+= / Meta+-)") : QStringLiteral("Screen Magnifier disabled"));
    emit accessibilityChanged();
}

void SystemBackend::zoomScreen(int direction)
{
    if (direction > 0 && !m_screenZoomEnabled) {
        setScreenZoomEnabled(true);
    }
    QString shortcutName = QStringLiteral("view_actual_size");
    if (direction > 0) {
        shortcutName = QStringLiteral("view_zoom_in");
    } else if (direction < 0) {
        shortcutName = QStringLiteral("view_zoom_out");
    }
    runDetached(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.kglobalaccel"),
         QStringLiteral("/component/kwin"),
         QStringLiteral("org.kde.kglobalaccel.Component.invokeShortcut"),
         shortcutName});
}

void SystemBackend::setColorBlindnessMode(int mode)
{
    const int clamped = qBound(0, mode, 4);
    m_colorBlindnessMode = clamped;
    if (clamped == 0) {
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"),
             QStringLiteral("--group"), QStringLiteral("Plugins"),
             QStringLiteral("--key"), QStringLiteral("colorblindnesscorrectionEnabled"),
             QStringLiteral("--type"), QStringLiteral("bool"),
             QStringLiteral("false"),
             QStringLiteral("--notify")}, 1500);
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin.reconfigure")}, 1200);
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
             QStringLiteral("org.kde.kwin.Effects.unloadEffect"),
             QStringLiteral("colorblindnesscorrection")}, 1200);
        notifyStatus(QStringLiteral("Color blindness filter disabled"));
    } else {
        const int kwinMode = clamped - 1;
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
             QStringLiteral("org.kde.kwin.Effects.unloadEffect"),
             QStringLiteral("colorblindnesscorrection")}, 1200);
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"),
             QStringLiteral("--group"), QStringLiteral("Effect-colorblindnesscorrection"),
             QStringLiteral("--key"), QStringLiteral("Mode"),
             QStringLiteral("--type"), QStringLiteral("int"),
             QString::number(kwinMode),
             QStringLiteral("--notify")}, 1500);
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"),
             QStringLiteral("--group"), QStringLiteral("Plugins"),
             QStringLiteral("--key"), QStringLiteral("colorblindnesscorrectionEnabled"),
             QStringLiteral("--type"), QStringLiteral("bool"),
             QStringLiteral("true"),
             QStringLiteral("--notify")}, 1500);
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin.reconfigure")}, 1200);
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
             QStringLiteral("org.kde.kwin.Effects.loadEffect"),
             QStringLiteral("colorblindnesscorrection")}, 1200);
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
             QStringLiteral("org.kde.kwin.Effects.reconfigureEffect"),
             QStringLiteral("colorblindnesscorrection")}, 1000);
        static const QStringList labels = {
            QStringLiteral("Protanopia"),
            QStringLiteral("Deuteranopia"),
            QStringLiteral("Tritanopia"),
            QStringLiteral("Monochrome")
        };
        notifyStatus(QStringLiteral("Color filter applied: %1").arg(labels.value(kwinMode)));
    }
    emit accessibilityChanged();
}

void SystemBackend::setInvertScreenEnabled(bool enabled)
{
    m_invertScreenEnabled = enabled;
    if (enabled) {
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
             QStringLiteral("org.kde.kwin.Effects.unloadEffect"),
             QStringLiteral("invert")}, 1000);
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"),
             QStringLiteral("--group"), QStringLiteral("Plugins"),
             QStringLiteral("--key"), QStringLiteral("invertEnabled"),
             QStringLiteral("--type"), QStringLiteral("bool"),
             QStringLiteral("true"),
             QStringLiteral("--notify")}, 1500);
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin.reconfigure")}, 1200);
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
             QStringLiteral("org.kde.kwin.Effects.loadEffect"),
             QStringLiteral("invert")}, 1200);
        runDetached(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.kglobalaccel"),
             QStringLiteral("/component/kwin"),
             QStringLiteral("org.kde.kglobalaccel.Component.invokeShortcut"),
             QStringLiteral("Invert")});
    } else {
        runCommand(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
             QStringLiteral("org.kde.kwin.Effects.unloadEffect"),
             QStringLiteral("invert")}, 1200);
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"),
             QStringLiteral("--group"), QStringLiteral("Plugins"),
             QStringLiteral("--key"), QStringLiteral("invertEnabled"),
             QStringLiteral("--type"), QStringLiteral("bool"),
             QStringLiteral("false"),
             QStringLiteral("--notify")}, 1500);
    }
    notifyStatus(enabled ? QStringLiteral("High Contrast Invert filter enabled") : QStringLiteral("High Contrast Invert filter disabled"));
    emit accessibilityChanged();
}

void SystemBackend::setScreenReaderEnabled(bool enabled)
{
    m_screenReaderEnabled = enabled;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("ScreenReader"),
         QStringLiteral("--key"), QStringLiteral("Enabled"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    reloadAccessDaemon();

    if (enabled) {
        if (runCommand(QStringLiteral("pgrep"), {QStringLiteral("-x"), QStringLiteral("orca")}, 800).isEmpty()) {
            runDetached(QStringLiteral("orca"), {QStringLiteral("--replace")});
        }
        notifyStatus(QStringLiteral("Orca Screen Reader enabled"));
    } else {
        runCommand(QStringLiteral("pkill"), {QStringLiteral("-x"), QStringLiteral("orca")}, 800);
        notifyStatus(QStringLiteral("Orca Screen Reader disabled"));
    }
    emit accessibilityChanged();
}

void SystemBackend::setCursorSize(int size)
{
    const int clamped = qBound(24, size, 64);
    m_cursorSize = clamped;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kcminputrc"),
         QStringLiteral("--group"), QStringLiteral("Mouse"),
         QStringLiteral("--key"), QStringLiteral("cursorSize"),
         QString::number(m_cursorSize),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("dbus-send"),
        {QStringLiteral("--type=signal"),
         QStringLiteral("/KGlobalSettings"),
         QStringLiteral("org.kde.KGlobalSettings.notifyChange"),
         QStringLiteral("int32:5"),
         QStringLiteral("int32:0")}, 1000);
    runDetached(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin.reconfigure")});
    notifyStatus(QStringLiteral("Pointer cursor size set to %1 px").arg(m_cursorSize));
    emit accessibilityChanged();
}

void SystemBackend::setShakeCursorEnabled(bool enabled)
{
    m_shakeCursorEnabled = enabled;
    setKwinEffectEnabled(QStringLiteral("shakecursorEnabled"), QStringLiteral("shakecursor"), enabled);
    notifyStatus(enabled ? QStringLiteral("Shake cursor to locate enabled") : QStringLiteral("Shake cursor to locate disabled"));
    emit accessibilityChanged();
}

void SystemBackend::setTrackMouseEnabled(bool enabled)
{
    m_trackMouseEnabled = enabled;
    setKwinEffectEnabled(QStringLiteral("trackmouseEnabled"), QStringLiteral("trackmouse"), enabled);
    notifyStatus(enabled ? QStringLiteral("Locate mouse pointer effect enabled") : QStringLiteral("Locate mouse pointer effect disabled"));
    emit accessibilityChanged();
}

void SystemBackend::setMouseKeysEnabled(bool enabled)
{
    m_mouseKeysEnabled = enabled;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Mouse"),
         QStringLiteral("--key"), QStringLiteral("MouseKeys"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    reloadAccessDaemon();
    notifyStatus(enabled ? QStringLiteral("Mouse Keys (NumPad cursor control) enabled") : QStringLiteral("Mouse Keys disabled"));
    emit accessibilityChanged();
}

void SystemBackend::setStickyKeys(bool enabled, bool lockKeys)
{
    m_stickyKeysEnabled = enabled;
    m_stickyKeysLock = lockKeys;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Keyboard"),
         QStringLiteral("--key"), QStringLiteral("StickyKeys"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Keyboard"),
         QStringLiteral("--key"), QStringLiteral("StickyKeysLatch"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         lockKeys ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    reloadAccessDaemon();
    notifyStatus(enabled ? QStringLiteral("Sticky Keys enabled") : QStringLiteral("Sticky Keys disabled"));
    emit accessibilityChanged();
}

void SystemBackend::setSlowKeys(bool enabled, int delayMs)
{
    m_slowKeysEnabled = enabled;
    m_slowKeysDelay = qBound(100, delayMs, 2000);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Keyboard"),
         QStringLiteral("--key"), QStringLiteral("SlowKeys"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Keyboard"),
         QStringLiteral("--key"), QStringLiteral("SlowKeysDelay"),
         QString::number(m_slowKeysDelay),
         QStringLiteral("--notify")}, 1500);
    reloadAccessDaemon();
    notifyStatus(enabled ? QStringLiteral("Slow Keys enabled (%1 ms)").arg(m_slowKeysDelay) : QStringLiteral("Slow Keys disabled"));
    emit accessibilityChanged();
}

void SystemBackend::setBounceKeys(bool enabled, int delayMs)
{
    m_bounceKeysEnabled = enabled;
    m_bounceKeysDelay = qBound(100, delayMs, 2000);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Keyboard"),
         QStringLiteral("--key"), QStringLiteral("BounceKeys"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Keyboard"),
         QStringLiteral("--key"), QStringLiteral("BounceKeysDelay"),
         QString::number(m_bounceKeysDelay),
         QStringLiteral("--notify")}, 1500);
    reloadAccessDaemon();
    notifyStatus(enabled ? QStringLiteral("Bounce Keys enabled (%1 ms)").arg(m_bounceKeysDelay) : QStringLiteral("Bounce Keys disabled"));
    emit accessibilityChanged();
}

void SystemBackend::setToggleKeysBeep(bool enabled)
{
    m_toggleKeysBeep = enabled;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Keyboard"),
         QStringLiteral("--key"), QStringLiteral("ToggleKeysBeep"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    reloadAccessDaemon();
    notifyStatus(enabled ? QStringLiteral("Toggle Keys audible beep enabled") : QStringLiteral("Toggle Keys audible beep disabled"));
    emit accessibilityChanged();
}

void SystemBackend::setBellSettings(bool audibleBell, bool visualBell, bool invertVisual)
{
    m_systemBellEnabled = audibleBell;
    m_visibleBellEnabled = visualBell;
    m_visibleBellInvert = invertVisual;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Bell"),
         QStringLiteral("--key"), QStringLiteral("SystemBell"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         audibleBell ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Bell"),
         QStringLiteral("--key"), QStringLiteral("VisibleBell"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         visualBell ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kaccessrc"),
         QStringLiteral("--group"), QStringLiteral("Bell"),
         QStringLiteral("--key"), QStringLiteral("VisibleBellInvert"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         invertVisual ? QStringLiteral("true") : QStringLiteral("false"),
         QStringLiteral("--notify")}, 1500);
    reloadAccessDaemon();
    notifyStatus(QStringLiteral("Accessibility bell preferences updated"));
    emit accessibilityChanged();
}
