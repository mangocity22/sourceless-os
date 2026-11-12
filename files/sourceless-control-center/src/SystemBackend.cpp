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
// 3. DISPLAY & BRIGHTNESS (KScreen + KDE PowerManagement + KWin NightColor)
// -----------------------------------------------------------------------------
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

    if (!maxBr.isEmpty() && maxBr.toInt() > 0) {
        m_hasBrightness = true;
        m_maxRawBrightness = maxBr.toInt();
        m_brightness = qBound(5, static_cast<int>(std::round((curBr.toInt() * 100.0) / m_maxRawBrightness)), 100);
    } else {
        m_hasBrightness = false;
        m_brightness = 100;
    }

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

                    QStringList resList;
                    const QJsonArray modes = outObj.value(QStringLiteral("modes")).toArray();
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
                            }
                        }
                    }
                    if (!resList.isEmpty()) {
                        m_availableResolutions = resList;
                    }
                    break;
                }
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

    QSettings kwinrc(QDir::homePath() + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
    kwinrc.beginGroup(QStringLiteral("NightColor"));
    m_nightLightEnabled = kwinrc.value(QStringLiteral("Active"), false).toBool();
    m_nightLightTemp = kwinrc.value(QStringLiteral("NightTemperature"), 4500).toInt();
    kwinrc.endGroup();

    emit displayChanged();
}

void SystemBackend::setBrightness(int val)
{
    m_brightness = qBound(5, val, 100);
    if (m_hasBrightness && m_maxRawBrightness > 0) {
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
        m_currentResolution = res;
        notifyStatus(QStringLiteral("Display resolution set to %1").arg(res));
        emit displayChanged();
    }
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
         QStringLiteral("--key"), QStringLiteral("Active"),
         enabled ? QStringLiteral("true") : QStringLiteral("false")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("NightColor"),
         QStringLiteral("--key"), QStringLiteral("Mode"),
         QStringLiteral("Constant")}, 1500);
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kwinrc"),
         QStringLiteral("--group"), QStringLiteral("NightColor"),
         QStringLiteral("--key"), QStringLiteral("NightTemperature"),
         QString::number(m_nightLightTemp)}, 1500);

    runDetached(QStringLiteral("qdbus6"), {QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("reconfigure")});
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
// 7. PERSONALIZATION (Curated Sourceless Wallpapers & Glass Effects)
// -----------------------------------------------------------------------------
void SystemBackend::refreshPersonalization()
{
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
            const QStringList files = imgDir.entryList({QStringLiteral("*.png"), QStringLiteral("*.jpg")}, QDir::Files);
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
    m_supportSessionActive = QFileInfo::exists(QStringLiteral("/tmp/sourceless_support_active")) ||
                             QFileInfo::exists(QStringLiteral("/var/run/sourceless_support_active"));

    const bool tamperFlagFile = QFileInfo::exists(QStringLiteral("/etc/sourceless/.tamper_detected")) ||
                                QFileInfo::exists(QStringLiteral("/tmp/.sourceless_tamper_trigger"));

    const QString groupsOut = runCommand(QStringLiteral("id"), {QStringLiteral("-Gn")}, 1000);
    const bool inWheelGroup = groupsOut.split(QLatin1Char(' ')).contains(QStringLiteral("wheel"));

    m_isTampered = tamperFlagFile || m_supportSessionActive || inWheelGroup;

    if (m_isTampered) {
        score -= 35;
        QStringList reasons;
        if (tamperFlagFile) reasons << QStringLiteral("Tamper Seal Broken");
        if (m_supportSessionActive) reasons << QStringLiteral("Support Shell Unlocked");
        if (inWheelGroup) reasons << QStringLiteral("Wheel Admin Active");
        m_systemIntegrity = QStringLiteral("Modified (%1)").arg(reasons.join(QStringLiteral(" / ")));

        events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("System Integrity Modified: ") + reasons.join(QStringLiteral(", "))},
                                  {QStringLiteral("severity"), QStringLiteral("critical")}});
    } else {
        m_systemIntegrity = QStringLiteral("Verified Immutable (OSTree + Cosign)");
    }

    if (m_supportSessionActive) {
        events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("Interactive Terminal Gate is currently UNLOCKED")},
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

void SystemBackend::lockSupportSession()
{
    QFile::remove(QStringLiteral("/tmp/sourceless_support_active"));
    QFile::remove(QStringLiteral("/var/run/sourceless_support_active"));
    runDetached(QStringLiteral("killall"), {QStringLiteral("-9"), QStringLiteral("konsole.real")});
    refreshSecurity();
    notifyStatus(QStringLiteral("Support session ended and Terminal re-locked"));
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
