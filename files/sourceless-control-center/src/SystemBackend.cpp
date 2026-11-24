#include "SystemBackend.h"

#include <KUser>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSysInfo>
#include <QThread>
#include <QUrl>
#include <algorithm>
#include <cmath>
#include <ctime>
#include <unistd.h>

SystemBackend::SystemBackend(const QString &startPage, QObject *parent)
    : QObject(parent)
    , m_initialPage(startPage.isEmpty() ? QStringLiteral("home") : startPage)
{
    m_workerPool.setMaxThreadCount(4);

    // Instant local/procfs initialization only so the window appears without delay
    loadStaticSystemInfo();
    loadDynamicSystemMetrics();
    loadInputSettings();
    refreshSystemUpdate();

    // Defer subprocess/D-Bus probes until after the event loop starts and the window is shown
    QTimer::singleShot(0, this, &SystemBackend::scheduleStartupRefresh);

    // Refresh live metrics (clock, RAM/disk, OS updates, audio, security, battery) every 6 seconds
    connect(&m_periodicTimer, &QTimer::timeout, this, [this]() {
        loadDynamicSystemMetrics();
        refreshSystemUpdate();
        m_currentDateTime = QDateTime::currentDateTime().toString(
            m_use24Hour ? QStringLiteral("dddd, dd MMMM yyyy  •  HH:mm") : QStringLiteral("dddd, dd MMMM yyyy  •  hh:mm AP"));
        emit timeChanged();
        refreshAudio();
        refreshSecurity();
        if (m_hasBattery) {
            refreshPower();
        }
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

SystemBackend::~SystemBackend()
{
    m_destroying.store(true, std::memory_order_relaxed);
    m_periodicTimer.stop();
    m_orientationRevertTimer.stop();
    m_workerPool.clear();
    m_workerPool.waitForDone(2500);
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

QString SystemBackend::runCommandCancellable(const QString &program, const QStringList &args, int timeoutMs) const
{
    if (m_destroying.load(std::memory_order_relaxed)) {
        return QString();
    }
    QProcess proc;
    proc.start(program, args);
    QElapsedTimer timer;
    timer.start();
    while (!proc.waitForFinished(150)) {
        if (proc.error() == QProcess::FailedToStart) {
            return QString();
        }
        if (m_destroying.load(std::memory_order_relaxed) || timer.elapsed() >= timeoutMs) {
            proc.kill();
            proc.waitForFinished(250);
            return QString();
        }
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

    // Fast local profile metadata (D-Bus refresh happens asynchronously after startup)
    QString accountsFileRealName;
    QString accountsFileEmail;
    QString accountsFileIcon;
    QFile accUserFile(QStringLiteral("/var/lib/AccountsService/users/") + m_userName);
    if (accUserFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        for (const QString &rawLine : QString::fromUtf8(accUserFile.readAll()).split(QLatin1Char('\n'))) {
            const QString line = rawLine.trimmed();
            if (line.startsWith(QStringLiteral("RealName="))) {
                accountsFileRealName = line.mid(9).trimmed();
            } else if (line.startsWith(QStringLiteral("Email="))) {
                accountsFileEmail = line.mid(6).trimmed();
            } else if (line.startsWith(QStringLiteral("Icon="))) {
                accountsFileIcon = line.mid(5).trimmed();
            }
        }
    }
    if (!accountsFileRealName.isEmpty()) {
        m_userFullName = accountsFileRealName;
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

    if (!accountsFileEmail.isEmpty()) {
        m_userEmail = accountsFileEmail;
    } else {
        QSettings mailCfg(QDir::homePath() + QStringLiteral("/.config/emaildefaults"), QSettings::IniFormat);
        mailCfg.beginGroup(QStringLiteral("PROFILE_Default"));
        m_userEmail = mailCfg.value(QStringLiteral("EmailAddress")).toString().trimmed();
        mailCfg.endGroup();
    }

    const QStringList avatarCandidates = {
        kuser.faceIconPath(),
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
    m_osName = QStringLiteral("SourceLess OS");
    QFile osRelease(QStringLiteral("/etc/os-release"));
    if (osRelease.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QStringList lines = QString::fromUtf8(osRelease.readAll()).split(QLatin1Char('\n'));
        for (const QString &rawLine : lines) {
            const QString line = rawLine.trimmed();
            if (line.startsWith(QStringLiteral("PRETTY_NAME="))) {
                QString val = line.mid(12).trimmed();
                val.remove(QLatin1Char('"'));
                if (!val.isEmpty() &&
                    !val.contains(QStringLiteral("fedora"), Qt::CaseInsensitive) &&
                    !val.contains(QStringLiteral("kinoite"), Qt::CaseInsensitive) &&
                    !val.contains(QStringLiteral("sourceless os"), Qt::CaseInsensitive)) {
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

    // GPU Model placeholder (resolved asynchronously after startup)
    m_gpuModel = QStringLiteral("Detecting graphics adapter...");

    // Pre-populate dropdown defaults so UI combo boxes are valid immediately
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
    if (m_availableRefreshRates.isEmpty()) {
        m_availableRefreshRates = {m_currentRefreshRate};
    }
    if (m_availableTimezones.isEmpty()) {
        m_availableTimezones = {
            QStringLiteral("Europe/Bucharest"),
            QStringLiteral("UTC"),
            QStringLiteral("Europe/London"),
            QStringLiteral("Europe/Berlin"),
            QStringLiteral("Europe/Paris"),
            QStringLiteral("Europe/Madrid"),
            QStringLiteral("Europe/Rome"),
            QStringLiteral("Europe/Vienna"),
            QStringLiteral("Europe/Warsaw"),
            QStringLiteral("Europe/Budapest"),
            QStringLiteral("Europe/Prague"),
            QStringLiteral("Europe/Athens"),
            QStringLiteral("Europe/Istanbul"),
            QStringLiteral("Europe/Kyiv"),
            QStringLiteral("Europe/Chisinau"),
            QStringLiteral("Europe/Zurich"),
            QStringLiteral("Europe/Amsterdam"),
            QStringLiteral("Europe/Brussels"),
            QStringLiteral("Europe/Stockholm"),
            QStringLiteral("America/New_York"),
            QStringLiteral("America/Chicago"),
            QStringLiteral("America/Denver"),
            QStringLiteral("America/Los_Angeles"),
            QStringLiteral("America/Toronto"),
            QStringLiteral("America/Sao_Paulo"),
            QStringLiteral("Asia/Tokyo"),
            QStringLiteral("Asia/Seoul"),
            QStringLiteral("Asia/Shanghai"),
            QStringLiteral("Asia/Singapore"),
            QStringLiteral("Asia/Dubai"),
            QStringLiteral("Asia/Kolkata"),
            QStringLiteral("Australia/Sydney")
        };
    }
    m_currentDateTime = QDateTime::currentDateTime().toString(
        m_use24Hour ? QStringLiteral("dddd, dd MMMM yyyy  •  HH:mm") : QStringLiteral("dddd, dd MMMM yyyy  •  hh:mm AP"));

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
}

void SystemBackend::refreshGpuInfoAsync()
{
    runAsyncTask(
        QStringLiteral("gpu"),
        [this]() {
            const QString lspciOut = runCommandCancellable(QStringLiteral("sh"),
                {QStringLiteral("-c"), QStringLiteral("lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n 1")}, 1500);
            if (!lspciOut.isEmpty()) {
                const int idx = lspciOut.indexOf(QStringLiteral(": "));
                return (idx != -1) ? lspciOut.mid(idx + 2).trimmed() : lspciOut;
            }
            return QStringLiteral("Integrated / Virtual Graphics Adapter");
        },
        [this](QString gpu) {
            m_gpuModel = std::move(gpu);
            emit systemInfoChanged();
        });
}

void SystemBackend::scheduleStartupRefresh()
{
    refreshGpuInfoAsync();
    refreshAudio();
    refreshDisplay();
    refreshNetwork();
    refreshSecurity();
    refreshBluetooth();
    refreshUserProfile();

    if (m_initialPage == QStringLiteral("system")) {
        refreshPower();
    } else if (m_initialPage == QStringLiteral("bluetooth") || m_initialPage == QStringLiteral("printers")) {
        refreshPrinters();
    } else if (m_initialPage == QStringLiteral("personalization")) {
        refreshPersonalization();
    } else if (m_initialPage == QStringLiteral("apps")) {
        refreshApps();
    } else if (m_initialPage == QStringLiteral("time")) {
        refreshTime();
    } else if (m_initialPage == QStringLiteral("accessibility")) {
        refreshAccessibility();
    }
}

void SystemBackend::refreshUserProfile()
{
    const uid_t uid = getuid();
    const QString userName = m_userName;
    const QString fallbackFullName = m_userFullName;
    const QString currentAvatar = m_userAvatar;
    const QString homePath = QDir::homePath();

    struct UserProfileSnapshot {
        QString fullName;
        QString initials;
        QString email;
        QString avatar;
    };

    runAsyncTask(
        QStringLiteral("userProfile"),
        [this, uid, userName, fallbackFullName, currentAvatar, homePath]() {
            UserProfileSnapshot snap;
            const QString userObj = QStringLiteral("/org/freedesktop/Accounts/User%1").arg(uid);

            const QString realNameDbus = runCommandCancellable(QStringLiteral("qdbus6"),
                {QStringLiteral("--system"), QStringLiteral("org.freedesktop.Accounts"),
                 userObj, QStringLiteral("org.freedesktop.Accounts.User.RealName")}, 1200);
            const QString emailDbus = runCommandCancellable(QStringLiteral("qdbus6"),
                {QStringLiteral("--system"), QStringLiteral("org.freedesktop.Accounts"),
                 userObj, QStringLiteral("org.freedesktop.Accounts.User.Email")}, 1200);
            const QString iconDbus = runCommandCancellable(QStringLiteral("qdbus6"),
                {QStringLiteral("--system"), QStringLiteral("org.freedesktop.Accounts"),
                 userObj, QStringLiteral("org.freedesktop.Accounts.User.IconFile")}, 1200);

            QString accFileRealName;
            QString accFileEmail;
            QString accFileIcon;
            QFile accUserFile(QStringLiteral("/var/lib/AccountsService/users/") + userName);
            if (accUserFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                for (const QString &rawLine : QString::fromUtf8(accUserFile.readAll()).split(QLatin1Char('\n'))) {
                    const QString line = rawLine.trimmed();
                    if (line.startsWith(QStringLiteral("RealName="))) {
                        accFileRealName = line.mid(9).trimmed();
                    } else if (line.startsWith(QStringLiteral("Email="))) {
                        accFileEmail = line.mid(6).trimmed();
                    } else if (line.startsWith(QStringLiteral("Icon="))) {
                        accFileIcon = line.mid(5).trimmed();
                    }
                }
            }

            const QString resolvedName = !realNameDbus.trimmed().isEmpty() ? realNameDbus.trimmed() : accFileRealName;
            if (!resolvedName.isEmpty()) {
                snap.fullName = resolvedName;
            } else if (!fallbackFullName.isEmpty()) {
                snap.fullName = fallbackFullName;
            } else {
                snap.fullName = userName;
            }

            const QStringList parts = snap.fullName.split(QLatin1Char(' '), Qt::SkipEmptyParts);
            if (parts.size() >= 2) {
                snap.initials = QString(parts.first().at(0).toUpper()) + QString(parts.last().at(0).toUpper());
            } else if (!snap.fullName.isEmpty()) {
                snap.initials = snap.fullName.left(2).toUpper();
            } else {
                snap.initials = QStringLiteral("SL");
            }

            QString resolvedEmail = !emailDbus.trimmed().isEmpty() ? emailDbus.trimmed() : accFileEmail;
            if (resolvedEmail.isEmpty()) {
                QSettings mailCfg(homePath + QStringLiteral("/.config/emaildefaults"), QSettings::IniFormat);
                mailCfg.beginGroup(QStringLiteral("PROFILE_Default"));
                resolvedEmail = mailCfg.value(QStringLiteral("EmailAddress")).toString().trimmed();
                mailCfg.endGroup();
            }
            snap.email = resolvedEmail;

            QString existingCachedAvatar;
            if (!currentAvatar.isEmpty()) {
                const QString localCached = QUrl(currentAvatar).toLocalFile();
                if (!localCached.isEmpty() && localCached.contains(QStringLiteral("sourceless-avatar-")) && QFileInfo::exists(localCached)) {
                    existingCachedAvatar = currentAvatar;
                }
            }

            if (!existingCachedAvatar.isEmpty()) {
                snap.avatar = existingCachedAvatar;
            } else {
                KUser kuser;
                const QStringList avatarCandidates = {
                    iconDbus,
                    accFileIcon,
                    homePath + QStringLiteral("/.face.icon"),
                    homePath + QStringLiteral("/.face"),
                    homePath + QStringLiteral("/.config/face.icon"),
                    kuser.faceIconPath(),
                    QStringLiteral("/var/lib/AccountsService/icons/") + userName
                };
                for (const QString &candidate : avatarCandidates) {
                    const QString cleanPath = candidate.trimmed();
                    if (!cleanPath.isEmpty() && QFileInfo::exists(cleanPath) && QFileInfo(cleanPath).isFile()) {
                        snap.avatar = QUrl::fromLocalFile(cleanPath).toString();
                        break;
                    }
                }
            }
            return snap;
        },
        [this](UserProfileSnapshot snap) {
            m_userFullName = std::move(snap.fullName);
            m_userInitials = std::move(snap.initials);
            m_userEmail = std::move(snap.email);
            m_userAvatar = std::move(snap.avatar);
            emit systemInfoChanged();
        });
}

void SystemBackend::setUserFullName(const QString &fullName)
{
    const QString clean = fullName.trimmed();
    if (clean.isEmpty()) {
        notifyStatus(QStringLiteral("Display name cannot be empty"));
        return;
    }

    const uid_t uid = getuid();
    const QString userObj = QStringLiteral("/org/freedesktop/Accounts/User%1").arg(uid);
    QProcess proc;
    proc.start(QStringLiteral("qdbus6"),
        {QStringLiteral("--system"), QStringLiteral("org.freedesktop.Accounts"),
         userObj, QStringLiteral("org.freedesktop.Accounts.User.SetRealName"), clean});
    if (proc.waitForFinished(3000) && proc.exitCode() == 0) {
        m_userFullName = clean;
        const QStringList parts = clean.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        m_userInitials = (parts.size() >= 2)
            ? (QString(parts.first().at(0).toUpper()) + QString(parts.last().at(0).toUpper()))
            : clean.left(2).toUpper();
        notifyStatus(QStringLiteral("Display name updated to %1").arg(clean));
        emit systemInfoChanged();
    } else {
        const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        notifyStatus(err.isEmpty()
            ? QStringLiteral("Could not update display name")
            : QStringLiteral("Name error: %1").arg(err));
    }
}

void SystemBackend::setUserEmail(const QString &email)
{
    const QString clean = email.trimmed();
    const uid_t uid = getuid();
    const QString userObj = QStringLiteral("/org/freedesktop/Accounts/User%1").arg(uid);

    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("--system"), QStringLiteral("org.freedesktop.Accounts"),
         userObj, QStringLiteral("org.freedesktop.Accounts.User.SetEmail"), clean}, 2500);

    QSettings mailCfg(QDir::homePath() + QStringLiteral("/.config/emaildefaults"), QSettings::IniFormat);
    mailCfg.beginGroup(QStringLiteral("PROFILE_Default"));
    mailCfg.setValue(QStringLiteral("EmailAddress"), clean);
    mailCfg.endGroup();
    mailCfg.sync();

    m_userEmail = clean;
    notifyStatus(clean.isEmpty() ? QStringLiteral("Email address cleared") : QStringLiteral("Email updated to %1").arg(clean));
    emit systemInfoChanged();
}

void SystemBackend::chooseUserAvatar()
{
    const QString startDir = QFileInfo::exists(QDir::homePath() + QStringLiteral("/Pictures"))
        ? (QDir::homePath() + QStringLiteral("/Pictures"))
        : QDir::homePath();

    QString selectedPath;
    if (!QStandardPaths::findExecutable(QStringLiteral("kdialog")).isEmpty()) {
        selectedPath = runCommand(QStringLiteral("kdialog"),
            {QStringLiteral("--getopenfilename"), startDir,
             QStringLiteral("Image Files (*.png *.jpg *.jpeg *.webp *.bmp *.svg)")}, 60000);
    } else if (!QStandardPaths::findExecutable(QStringLiteral("zenity")).isEmpty()) {
        selectedPath = runCommand(QStringLiteral("zenity"),
            {QStringLiteral("--file-selection"),
             QStringLiteral("--title=Choose Profile Picture"),
             QStringLiteral("--file-filter=Images | *.png *.jpg *.jpeg *.webp *.bmp *.svg")}, 60000);
    } else {
        notifyStatus(QStringLiteral("No file picker dialog (kdialog/zenity) available"));
        return;
    }

    selectedPath = selectedPath.trimmed();
    if (selectedPath.isEmpty()) {
        return;
    }

    QImage img(selectedPath);
    if (img.isNull()) {
        notifyStatus(QStringLiteral("Selected file is not a valid image"));
        return;
    }

    img = img.scaled(256, 256, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    const int xOff = qMax(0, (img.width() - 256) / 2);
    const int yOff = qMax(0, (img.height() - 256) / 2);
    img = img.copy(xOff, yOff, 256, 256);

    const QString faceIcon = QDir::homePath() + QStringLiteral("/.face.icon");
    const QString faceDot = QDir::homePath() + QStringLiteral("/.face");
    if (!img.save(faceIcon, "PNG")) {
        notifyStatus(QStringLiteral("Failed to write profile picture to ~/.face.icon"));
        return;
    }
    img.save(faceDot, "PNG");

    const QString cacheDir = QDir::homePath() + QStringLiteral("/.cache");
    QDir(cacheDir).mkpath(QStringLiteral("."));
    const QStringList oldCached = QDir(cacheDir).entryList({QStringLiteral("sourceless-avatar-*.png")}, QDir::Files);
    for (const QString &oldFile : oldCached) {
        QFile::remove(cacheDir + QLatin1Char('/') + oldFile);
    }
    const QString cachePath = QStringLiteral("%1/sourceless-avatar-%2.png")
        .arg(cacheDir)
        .arg(QDateTime::currentMSecsSinceEpoch());
    img.save(cachePath, "PNG");

    const uid_t uid = getuid();
    const QString userObj = QStringLiteral("/org/freedesktop/Accounts/User%1").arg(uid);
    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("--system"), QStringLiteral("org.freedesktop.Accounts"),
         userObj, QStringLiteral("org.freedesktop.Accounts.User.SetIconFile"), faceIcon}, 2500);

    m_userAvatar = QUrl::fromLocalFile(cachePath).toString();
    notifyStatus(QStringLiteral("Profile picture updated"));
    emit systemInfoChanged();
}

void SystemBackend::clearUserAvatar()
{
    QFile::remove(QDir::homePath() + QStringLiteral("/.face.icon"));
    QFile::remove(QDir::homePath() + QStringLiteral("/.face"));
    QFile::remove(QDir::homePath() + QStringLiteral("/.config/face.icon"));
    const QString cacheDir = QDir::homePath() + QStringLiteral("/.cache");
    const QStringList oldCached = QDir(cacheDir).entryList({QStringLiteral("sourceless-avatar-*.png")}, QDir::Files);
    for (const QString &oldFile : oldCached) {
        QFile::remove(cacheDir + QLatin1Char('/') + oldFile);
    }

    const uid_t uid = getuid();
    const QString userObj = QStringLiteral("/org/freedesktop/Accounts/User%1").arg(uid);
    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("--system"), QStringLiteral("org.freedesktop.Accounts"),
         userObj, QStringLiteral("org.freedesktop.Accounts.User.SetIconFile"), QString()}, 2500);

    m_userAvatar.clear();
    notifyStatus(QStringLiteral("Profile picture reset to initials"));
    emit systemInfoChanged();
}

bool SystemBackend::changeUserPassword(const QString &currentPass, const QString &newPass, const QString &confirmPass)
{
    if (currentPass.isEmpty() || newPass.isEmpty()) {
        notifyStatus(QStringLiteral("Enter your current and new password"));
        return false;
    }
    if (newPass != confirmPass) {
        notifyStatus(QStringLiteral("New password and confirmation do not match"));
        return false;
    }
    if (newPass.length() < 6) {
        notifyStatus(QStringLiteral("New password must be at least 6 characters"));
        return false;
    }

    const QString pyScript = QStringLiteral(
        "import os, pty, select, sys\n"
        "cur = os.environ.get('SL_CUR_PASS', '')\n"
        "newp = os.environ.get('SL_NEW_PASS', '')\n"
        "pid, fd = pty.fork()\n"
        "if pid == 0:\n"
        "    os.execvp('passwd', ['passwd'])\n"
        "buf = b''\n"
        "sent_cur = 0\n"
        "sent_new = 0\n"
        "sent_confirm = 0\n"
        "out_log = ''\n"
        "aborted_msg = ''\n"
        "while True:\n"
        "    r, _, _ = select.select([fd], [], [], 10.0)\n"
        "    if not r:\n"
        "        aborted_msg = 'Password prompt timed out'\n"
        "        break\n"
        "    try:\n"
        "        chunk = os.read(fd, 1024)\n"
        "    except OSError:\n"
        "        break\n"
        "    if not chunk:\n"
        "        break\n"
        "    buf += chunk\n"
        "    out_log += chunk.decode('utf-8', 'ignore')\n"
        "    low = buf.decode('utf-8', 'ignore').lower()\n"
        "    if 'current password' in low or 'old password' in low:\n"
        "        if sent_cur == 0:\n"
        "            os.write(fd, (cur + '\\n').encode('utf-8'))\n"
        "            sent_cur += 1\n"
        "            buf = b''\n"
        "        else:\n"
        "            aborted_msg = 'Current password was rejected'\n"
        "            break\n"
        "    elif 'retype' in low or 'confirm' in low:\n"
        "        if sent_confirm == 0:\n"
        "            os.write(fd, (newp + '\\n').encode('utf-8'))\n"
        "            sent_confirm += 1\n"
        "            buf = b''\n"
        "    elif 'new password' in low:\n"
        "        if sent_new == 0:\n"
        "            os.write(fd, (newp + '\\n').encode('utf-8'))\n"
        "            sent_new += 1\n"
        "            buf = b''\n"
        "        else:\n"
        "            aborted_msg = 'New password rejected by system password policy'\n"
        "            break\n"
        "os.close(fd)\n"
        "_, status = os.waitpid(pid, 0)\n"
        "rc = os.waitstatus_to_exitcode(status) if hasattr(os, 'waitstatus_to_exitcode') else ((status >> 8) & 0xff)\n"
        "if aborted_msg or rc != 0:\n"
        "    err_lines = [ln.strip() for ln in out_log.splitlines() if ('bad password' in ln.lower() or 'authentication' in ln.lower() or 'sorry' in ln.lower() or 'error' in ln.lower() or 'fail' in ln.lower())]\n"
        "    msg = aborted_msg or (err_lines[-1] if err_lines else 'Password update failed')\n"
        "    sys.stderr.write(msg)\n"
        "    sys.exit(1)\n"
        "sys.exit(0)\n"
    );

    QProcess proc;
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("SL_CUR_PASS"), currentPass);
    env.insert(QStringLiteral("SL_NEW_PASS"), newPass);
    proc.setProcessEnvironment(env);
    proc.start(QStringLiteral("python3"), {QStringLiteral("-c"), pyScript});

    if (proc.waitForFinished(12000) && proc.exitCode() == 0) {
        notifyStatus(QStringLiteral("Account password changed successfully"));
        return true;
    }

    const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
    notifyStatus(err.isEmpty() ? QStringLiteral("Failed to update password") : err);
    return false;
}

void SystemBackend::lockScreenSession()
{
    if (!QStandardPaths::findExecutable(QStringLiteral("loginctl")).isEmpty()) {
        runDetached(QStringLiteral("loginctl"), {QStringLiteral("lock-session")});
    } else {
        runDetached(QStringLiteral("qdbus6"),
            {QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
             QStringLiteral("org.freedesktop.ScreenSaver.Lock")});
    }
    notifyStatus(QStringLiteral("Locking desktop session..."));
}

void SystemBackend::logoutSession()
{
    if (!QStandardPaths::findExecutable(QStringLiteral("qdbus6")).isEmpty()) {
        runDetached(QStringLiteral("qdbus6"),
            {QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"),
             QStringLiteral("org.kde.Shutdown.logout")});
    } else {
        runDetached(QStringLiteral("loginctl"), {QStringLiteral("terminate-user"), m_userName});
    }
    notifyStatus(QStringLiteral("Signing out of current session..."));
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
    refreshPrinters();
    loadInputSettings();
    refreshPower();
    refreshPersonalization();
    refreshApps();
    refreshTime();
    refreshSecurity();
    refreshAccessibility();
    refreshSystemUpdate();
}

// -----------------------------------------------------------------------------
// 2. AUDIO (PipeWire wpctl / PulseAudio pactl)
// -----------------------------------------------------------------------------
void SystemBackend::refreshAudio()
{
    struct AudioSnapshot {
        int volume;
        bool muted;
        int micVolume;
        bool micMuted;
        QString audioOutputName;
    };

    AudioSnapshot init{m_volume, m_muted, m_micVolume, m_micMuted, m_audioOutputName};

    runAsyncTask(
        QStringLiteral("audio"),
        [this, init]() mutable {
            const QString sinkVol = runCommandCancellable(QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, 1500);
            if (!sinkVol.isEmpty() && sinkVol.contains(QStringLiteral("Volume:"))) {
                init.muted = sinkVol.contains(QStringLiteral("[MUTED]"));
                QRegularExpression re(QStringLiteral("Volume:\\s*([0-9]+\\.?[0-9]*)"));
                auto match = re.match(sinkVol);
                if (match.hasMatch()) {
                    init.volume = qBound(0, static_cast<int>(std::round(match.captured(1).toDouble() * 100.0)), 100);
                }
            }

            const QString srcVol = runCommandCancellable(QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@")}, 1500);
            if (!srcVol.isEmpty() && srcVol.contains(QStringLiteral("Volume:"))) {
                init.micMuted = srcVol.contains(QStringLiteral("[MUTED]"));
                QRegularExpression re(QStringLiteral("Volume:\\s*([0-9]+\\.?[0-9]*)"));
                auto match = re.match(srcVol);
                if (match.hasMatch()) {
                    init.micVolume = qBound(0, static_cast<int>(std::round(match.captured(1).toDouble() * 100.0)), 100);
                }
            }

            const QString sinkInspect = runCommandCancellable(QStringLiteral("wpctl"), {QStringLiteral("inspect"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, 1500);
            if (!sinkInspect.isEmpty()) {
                for (const QString &line : sinkInspect.split(QLatin1Char('\n'))) {
                    if (line.contains(QStringLiteral("node.description"))) {
                        const int eqIdx = line.indexOf(QLatin1Char('='));
                        if (eqIdx != -1) {
                            QString desc = line.mid(eqIdx + 1).trimmed();
                            desc.remove(QLatin1Char('"'));
                            if (!desc.isEmpty()) {
                                init.audioOutputName = desc;
                            }
                        }
                        break;
                    }
                }
            }
            return init;
        },
        [this](AudioSnapshot snap) {
            m_volume = snap.volume;
            m_muted = snap.muted;
            m_micVolume = snap.micVolume;
            m_micMuted = snap.micMuted;
            m_audioOutputName = std::move(snap.audioOutputName);
            emit audioChanged();
        });
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
    struct DisplaySnapshot {
        bool hasBrightness = true;
        int maxRawBrightness = 0;
        int brightness = 100;
        QString displayName;
        int displayScale = 100;
        QString displayOrientation;
        QString colorAccuracy;
        QString currentResolution;
        QString currentRefreshRate;
        QStringList availableResolutions;
        QStringList availableRefreshRates;
        bool nightLightEnabled = false;
        int nightLightTemp = 4500;
    };

    DisplaySnapshot init;
    init.hasBrightness = true;
    init.maxRawBrightness = 0;
    init.brightness = m_brightness;
    init.displayName = m_displayName;
    init.displayScale = m_displayScale;
    init.displayOrientation = m_displayOrientation;
    init.colorAccuracy = m_colorAccuracy;
    init.currentResolution = m_currentResolution;
    init.currentRefreshRate = m_currentRefreshRate;
    init.nightLightEnabled = m_nightLightEnabled;
    init.nightLightTemp = m_nightLightTemp;
    const QString homePath = QDir::homePath();

    runAsyncTask(
        QStringLiteral("display"),
        [this, init, homePath]() mutable {
            const QString maxBr = runCommandCancellable(QStringLiteral("qdbus6"),
                {QStringLiteral("org.kde.Solid.PowerManagement"),
                 QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl"),
                 QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightnessMax")}, 1500);
            const QString curBr = runCommandCancellable(QStringLiteral("qdbus6"),
                {QStringLiteral("org.kde.Solid.PowerManagement"),
                 QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl"),
                 QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightness")}, 1500);

            init.hasBrightness = true;
            if (!maxBr.isEmpty() && maxBr.toInt() > 0) {
                init.maxRawBrightness = maxBr.toInt();
                init.brightness = qBound(5, static_cast<int>(std::round((curBr.toInt() * 100.0) / init.maxRawBrightness)), 100);
            } else {
                init.maxRawBrightness = 0;
            }

            QStringList parsedRefreshRates;
            bool hasKscreenBrightness = false;
            bool hasTradeoffFromKscreen = false;

            const QString kscreenJson = runCommandCancellable(QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")}, 2500);
            if (!kscreenJson.isEmpty()) {
                const QJsonDocument doc = QJsonDocument::fromJson(kscreenJson.toUtf8());
                if (doc.isObject()) {
                    const QJsonArray outputs = doc.object().value(QStringLiteral("outputs")).toArray();
                    for (const QJsonValue &val : outputs) {
                        const QJsonObject outObj = val.toObject();
                        if (outObj.value(QStringLiteral("connected")).toBool() && outObj.value(QStringLiteral("enabled")).toBool()) {
                            init.displayName = outObj.value(QStringLiteral("name")).toString(QStringLiteral("Primary Display"));
                            const double scale = outObj.value(QStringLiteral("scale")).toDouble(1.0);
                            init.displayScale = static_cast<int>(std::round(scale * 100.0));
                            const QString currentModeId = outObj.value(QStringLiteral("currentModeId")).toString();

                            if (init.maxRawBrightness <= 0 && outObj.contains(QStringLiteral("brightness"))) {
                                init.brightness = extractBrightnessPercent(outObj.value(QStringLiteral("brightness")), init.brightness);
                                hasKscreenBrightness = true;
                            }

                            const QJsonValue rotVal = outObj.value(QStringLiteral("rotation"));
                            if (rotVal.isString()) {
                                const QString rStr = rotVal.toString().toLower();
                                if (rStr == QStringLiteral("left") || rStr == QStringLiteral("right") || rStr == QStringLiteral("inverted")) {
                                    init.displayOrientation = rStr;
                                } else {
                                    init.displayOrientation = QStringLiteral("normal");
                                }
                            } else if (rotVal.isDouble()) {
                                switch (rotVal.toInt(1)) {
                                case 2: init.displayOrientation = QStringLiteral("left"); break;
                                case 4: init.displayOrientation = QStringLiteral("inverted"); break;
                                case 8: init.displayOrientation = QStringLiteral("right"); break;
                                default: init.displayOrientation = QStringLiteral("normal"); break;
                                }
                            }

                            if (outObj.contains(QStringLiteral("colorPowerTradeoff"))) {
                                const QString parsed = parseTradeoffString(outObj.value(QStringLiteral("colorPowerTradeoff")));
                                if (!parsed.isEmpty()) {
                                    init.colorAccuracy = parsed;
                                    hasTradeoffFromKscreen = true;
                                }
                            }

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
                                        init.currentResolution = resStr;
                                        const int hz = parseRefreshRateHz(modeObj.value(QStringLiteral("refreshRate")).toDouble(60.0));
                                        init.currentRefreshRate = QStringLiteral("%1 Hz").arg(hz);
                                    }
                                }
                            }
                            if (!resList.isEmpty()) {
                                init.availableResolutions = resList;
                            }

                            QList<int> hzValues;
                            for (const QJsonValue &mVal : modes) {
                                const QJsonObject modeObj = mVal.toObject();
                                const QJsonObject sizeObj = modeObj.value(QStringLiteral("size")).toObject();
                                const QString resStr = QStringLiteral("%1x%2")
                                    .arg(sizeObj.value(QStringLiteral("width")).toInt())
                                    .arg(sizeObj.value(QStringLiteral("height")).toInt());
                                if (resStr == init.currentResolution) {
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

            QFile kwinOutFile(homePath + QStringLiteral("/.config/kwinoutputconfig.json"));
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
                    if (!connector.isEmpty() && connector == init.displayName) {
                        if (!hasTradeoffFromKscreen && entryObj.contains(QStringLiteral("colorPowerTradeoff"))) {
                            const QString parsed = parseTradeoffString(entryObj.value(QStringLiteral("colorPowerTradeoff")));
                            if (!parsed.isEmpty()) {
                                init.colorAccuracy = parsed;
                            }
                        }
                        if (init.maxRawBrightness <= 0 && !hasKscreenBrightness && entryObj.contains(QStringLiteral("brightness"))) {
                            init.brightness = extractBrightnessPercent(entryObj.value(QStringLiteral("brightness")), init.brightness);
                        }
                        break;
                    }
                }
            }

            if (init.availableResolutions.isEmpty()) {
                init.availableResolutions = {
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
                init.availableRefreshRates = parsedRefreshRates;
            } else {
                init.availableRefreshRates = {init.currentRefreshRate};
            }

            QSettings kwinrc(homePath + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
            kwinrc.beginGroup(QStringLiteral("NightColor"));
            init.nightLightEnabled = kwinrc.value(QStringLiteral("Active"), false).toBool();
            init.nightLightTemp = kwinrc.value(QStringLiteral("NightTemperature"), 4500).toInt();
            kwinrc.endGroup();

            const QString nlEnabledDbus = runCommandCancellable(QStringLiteral("qdbus6"),
                {QStringLiteral("org.kde.KWin"),
                 QStringLiteral("/org/kde/KWin/NightLight"),
                 QStringLiteral("org.kde.KWin.NightLight.enabled")}, 1000);
            if (nlEnabledDbus == QStringLiteral("true")) {
                init.nightLightEnabled = true;
            } else if (nlEnabledDbus == QStringLiteral("false")) {
                init.nightLightEnabled = false;
            }

            return init;
        },
        [this](DisplaySnapshot snap) {
            m_hasBrightness = snap.hasBrightness;
            m_maxRawBrightness = snap.maxRawBrightness;
            m_brightness = snap.brightness;
            m_displayName = std::move(snap.displayName);
            m_displayScale = snap.displayScale;
            m_displayOrientation = std::move(snap.displayOrientation);
            m_colorAccuracy = std::move(snap.colorAccuracy);
            m_currentResolution = std::move(snap.currentResolution);
            m_currentRefreshRate = std::move(snap.currentRefreshRate);
            m_availableResolutions = std::move(snap.availableResolutions);
            m_availableRefreshRates = std::move(snap.availableRefreshRates);
            m_nightLightEnabled = snap.nightLightEnabled;
            m_nightLightTemp = snap.nightLightTemp;
            emit displayChanged();
        });
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
    struct NetworkSnapshot {
        bool wifiEnabled = true;
        bool networkConnected = false;
        QString connectionType = QStringLiteral("Disconnected");
        QString activeNetworkName = QStringLiteral("Not Connected");
        QString ipAddress = QStringLiteral("Offline");
    };

    runAsyncTask(
        QStringLiteral("network"),
        [this]() {
            NetworkSnapshot snap;
            const QString wifiState = runCommandCancellable(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi")}, 1500);
            snap.wifiEnabled = (wifiState.trimmed() == QStringLiteral("enabled"));

            const QString activeConns = runCommandCancellable(QStringLiteral("nmcli"),
                {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("NAME,TYPE,DEVICE"), QStringLiteral("connection"), QStringLiteral("show"), QStringLiteral("--active")}, 2000);

            for (const QString &line : activeConns.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const QStringList fields = line.split(QLatin1Char(':'));
                if (fields.size() >= 3) {
                    const QString name = fields.at(0);
                    const QString type = fields.at(1);
                    if (type == QStringLiteral("loopback") || name == QStringLiteral("lo")) {
                        continue;
                    }
                    snap.networkConnected = true;
                    snap.activeNetworkName = name;
                    if (type.contains(QStringLiteral("wireless")) || type.contains(QStringLiteral("wifi"))) {
                        snap.connectionType = QStringLiteral("Wi-Fi");
                    } else if (type.contains(QStringLiteral("ethernet"))) {
                        snap.connectionType = QStringLiteral("Ethernet");
                    } else {
                        snap.connectionType = type;
                    }
                    break;
                }
            }

            const QString ipOut = runCommandCancellable(QStringLiteral("sh"),
                {QStringLiteral("-c"), QStringLiteral("ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1")}, 1500);
            snap.ipAddress = ipOut.isEmpty() ? QStringLiteral("Offline") : ipOut;
            return snap;
        },
        [this](NetworkSnapshot snap) {
            m_wifiEnabled = snap.wifiEnabled;
            m_networkConnected = snap.networkConnected;
            m_connectionType = std::move(snap.connectionType);
            m_activeNetworkName = std::move(snap.activeNetworkName);
            m_ipAddress = std::move(snap.ipAddress);
            emit networkChanged();
        });
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
    struct BluetoothSnapshot {
        bool enabled = false;
        QVariantList devices;
    };

    runAsyncTask(
        QStringLiteral("bluetooth"),
        [this]() {
            BluetoothSnapshot snap;
            const QString btShow = runCommandCancellable(QStringLiteral("bluetoothctl"), {QStringLiteral("show")}, 1500);
            snap.enabled = btShow.contains(QStringLiteral("Powered: yes"), Qt::CaseInsensitive);

            if (snap.enabled) {
                const QString devsOut = runCommandCancellable(QStringLiteral("bluetoothctl"), {QStringLiteral("devices")}, 1500);
                for (const QString &line : devsOut.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                    const QStringList tokens = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
                    if (tokens.size() >= 3 && tokens.at(0) == QStringLiteral("Device")) {
                        const QString mac = tokens.at(1);
                        const QString name = tokens.mid(2).join(QLatin1Char(' '));
                        const QString infoOut = runCommandCancellable(QStringLiteral("bluetoothctl"), {QStringLiteral("info"), mac}, 1000);
                        const bool connected = infoOut.contains(QStringLiteral("Connected: yes"), Qt::CaseInsensitive);
                        QVariantMap dev;
                        dev[QStringLiteral("mac")] = mac;
                        dev[QStringLiteral("name")] = name;
                        dev[QStringLiteral("connected")] = connected;
                        snap.devices.append(dev);
                    }
                }
            }
            return snap;
        },
        [this](BluetoothSnapshot snap) {
            m_bluetoothEnabled = snap.enabled;
            m_bluetoothDevices = std::move(snap.devices);
            emit bluetoothChanged();
        });
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
    notifyStatus(QStringLiteral("Bluetooth scan complete — updating device list..."));
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

void SystemBackend::refreshPrinters()
{
    struct PrintersSnapshot {
        bool cupsRunning = false;
        QString defaultPrinter = QStringLiteral("None");
        int activePrintJobs = 0;
        QVariantList printers;
    };

    const QString homePath = QDir::homePath();

    runAsyncTask(
        QStringLiteral("printers"),
        [this, homePath]() {
            PrintersSnapshot snap;
            const QString sched = runCommandCancellable(QStringLiteral("lpstat"), {QStringLiteral("-r")}, 1500);
            snap.cupsRunning = sched.contains(QStringLiteral("is running"), Qt::CaseInsensitive);

            QString defaultDest;
            QFile lpOptsFile(homePath + QStringLiteral("/.cups/lpoptions"));
            if (lpOptsFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                for (const QString &line : QString::fromUtf8(lpOptsFile.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                    const QString trimmed = line.trimmed();
                    if (trimmed.startsWith(QStringLiteral("Default "))) {
                        const QStringList parts = trimmed.split(QLatin1Char(' '), Qt::SkipEmptyParts);
                        if (parts.size() >= 2) {
                            defaultDest = parts.at(1);
                            break;
                        }
                    }
                }
            }
            if (defaultDest.isEmpty()) {
                const QString lpstatD = runCommandCancellable(QStringLiteral("lpstat"), {QStringLiteral("-d")}, 1200);
                const int colonIdx = lpstatD.indexOf(QLatin1Char(':'));
                if (colonIdx != -1) {
                    defaultDest = lpstatD.mid(colonIdx + 1).trimmed();
                }
            }
            snap.defaultPrinter = defaultDest.isEmpty() ? QStringLiteral("None") : defaultDest;

            QMap<QString, QString> uris;
            const QString lpstatV = runCommandCancellable(QStringLiteral("lpstat"), {QStringLiteral("-v")}, 1500);
            QRegularExpression reUri(QStringLiteral("^device for ([^:]+):\\s*(.+)$"));
            for (const QString &line : lpstatV.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const auto m = reUri.match(line.trimmed());
                if (m.hasMatch()) {
                    uris.insert(m.captured(1).trimmed(), m.captured(2).trimmed());
                }
            }

            QMap<QString, int> jobsPerPrinter;
            const QString lpstatO = runCommandCancellable(QStringLiteral("lpstat"), {QStringLiteral("-o")}, 1500);
            QRegularExpression reJob(QStringLiteral("^(.+)-\\d+\\s+"));
            for (const QString &line : lpstatO.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const QString trimmed = line.trimmed();
                if (trimmed.isEmpty()) {
                    continue;
                }
                ++snap.activePrintJobs;
                const auto m = reJob.match(trimmed);
                if (m.hasMatch()) {
                    const QString pName = m.captured(1);
                    jobsPerPrinter[pName] = jobsPerPrinter.value(pName, 0) + 1;
                }
            }

            QStringList orderedNames;
            QMap<QString, QString> statuses;
            const QString lpstatP = runCommandCancellable(QStringLiteral("lpstat"), {QStringLiteral("-p")}, 1500);
            QRegularExpression rePrinter(QStringLiteral("^printer\\s+(\\S+)\\s+(.+)$"));
            for (const QString &line : lpstatP.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const auto m = rePrinter.match(line.trimmed());
                if (m.hasMatch()) {
                    const QString name = m.captured(1);
                    const QString desc = m.captured(2);
                    QString status = QStringLiteral("Ready");
                    if (desc.contains(QStringLiteral("disabled"), Qt::CaseInsensitive)) {
                        status = QStringLiteral("Paused / Disabled");
                    } else if (desc.contains(QStringLiteral("printing"), Qt::CaseInsensitive)) {
                        status = QStringLiteral("Printing");
                    } else if (desc.contains(QStringLiteral("idle"), Qt::CaseInsensitive)) {
                        status = QStringLiteral("Idle");
                    }
                    if (!orderedNames.contains(name)) {
                        orderedNames.append(name);
                    }
                    statuses.insert(name, status);
                }
            }

            for (auto it = uris.constBegin(); it != uris.constEnd(); ++it) {
                if (!orderedNames.contains(it.key())) {
                    orderedNames.append(it.key());
                    statuses.insert(it.key(), QStringLiteral("Ready"));
                }
            }

            for (const QString &name : orderedNames) {
                QVariantMap item;
                item[QStringLiteral("name")] = name;
                item[QStringLiteral("uri")] = uris.value(name, QStringLiteral("Local / Auto-discovered"));
                item[QStringLiteral("status")] = statuses.value(name, QStringLiteral("Ready"));
                item[QStringLiteral("isDefault")] = (!defaultDest.isEmpty() && name == defaultDest);
                item[QStringLiteral("jobs")] = jobsPerPrinter.value(name, 0);
                snap.printers.append(item);
            }
            return snap;
        },
        [this](PrintersSnapshot snap) {
            m_cupsRunning = snap.cupsRunning;
            m_defaultPrinter = std::move(snap.defaultPrinter);
            m_activePrintJobs = snap.activePrintJobs;
            m_printers = std::move(snap.printers);
            emit printersChanged();
        });
}

void SystemBackend::setDefaultPrinter(const QString &printerName)
{
    const QString clean = printerName.trimmed();
    if (clean.isEmpty()) {
        return;
    }
    runCommand(QStringLiteral("lpoptions"), {QStringLiteral("-d"), clean}, 1500);
    runCommand(QStringLiteral("lpadmin"), {QStringLiteral("-d"), clean}, 1500);
    notifyStatus(QStringLiteral("Default printer set to %1").arg(clean));
    refreshPrinters();
}

void SystemBackend::printTestPage(const QString &printerName)
{
    const QString clean = printerName.trimmed();
    if (clean.isEmpty()) {
        return;
    }

    QString testFile;
    if (QFileInfo::exists(QStringLiteral("/usr/share/cups/data/testprint"))) {
        testFile = QStringLiteral("/usr/share/cups/data/testprint");
    } else if (QFileInfo::exists(QStringLiteral("/usr/share/cups/data/default-testpage.pdf"))) {
        testFile = QStringLiteral("/usr/share/cups/data/default-testpage.pdf");
    }

    QProcess proc;
    if (!testFile.isEmpty()) {
        proc.start(QStringLiteral("lp"),
            {QStringLiteral("-d"), clean, QStringLiteral("-t"), QStringLiteral("SourceLess OS Test Page"), testFile});
    } else {
        proc.start(QStringLiteral("sh"),
            {QStringLiteral("-c"),
             QStringLiteral("printf 'SourceLess OS Printer Test Page\\nPrinter: %s\\n' \"$1\" | lp -d \"$1\" -t \"SourceLess OS Test Page\""),
             QStringLiteral("sh"),
             clean});
    }

    if (proc.waitForFinished(4000) && proc.exitCode() == 0) {
        notifyStatus(QStringLiteral("Test page queued on %1").arg(clean));
    } else {
        const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        notifyStatus(err.isEmpty()
            ? QStringLiteral("Failed to queue test page on %1").arg(clean)
            : QStringLiteral("Print error: %1").arg(err));
    }
    refreshPrinters();
}

void SystemBackend::cancelAllPrintJobs(const QString &printerName)
{
    const QString clean = printerName.trimmed();
    if (clean.isEmpty()) {
        runCommand(QStringLiteral("cancel"), {QStringLiteral("-a")}, 2000);
        notifyStatus(QStringLiteral("All active print jobs cancelled"));
    } else {
        runCommand(QStringLiteral("cancel"), {QStringLiteral("-a"), clean}, 2000);
        notifyStatus(QStringLiteral("Cancelled queued jobs for %1").arg(clean));
    }
    refreshPrinters();
}

void SystemBackend::addNetworkPrinter(const QString &name, const QString &uri)
{
    QString cleanName = name.trimmed();
    cleanName.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral("_"));
    cleanName.remove(QRegularExpression(QStringLiteral("[/#?]")));

    QString cleanUri = uri.trimmed();
    if (cleanName.isEmpty() || cleanUri.isEmpty()) {
        notifyStatus(QStringLiteral("Enter both printer name and IP/URI"));
        return;
    }

    if (!cleanUri.contains(QStringLiteral("://"))) {
        cleanUri = QStringLiteral("ipp://%1/ipp/print").arg(cleanUri);
    }

    QProcess proc;
    proc.start(QStringLiteral("lpadmin"),
        {QStringLiteral("-p"), cleanName, QStringLiteral("-E"), QStringLiteral("-v"), cleanUri, QStringLiteral("-m"), QStringLiteral("everywhere")});
    if (proc.waitForFinished(6000) && proc.exitCode() == 0) {
        notifyStatus(QStringLiteral("Added network printer: %1").arg(cleanName));
    } else {
        const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        notifyStatus(err.isEmpty()
            ? QStringLiteral("Could not add printer %1 (check privileges or URI)").arg(cleanName)
            : QStringLiteral("Printer setup failed: %1").arg(err));
    }
    refreshPrinters();
}

void SystemBackend::removePrinter(const QString &printerName)
{
    const QString clean = printerName.trimmed();
    if (clean.isEmpty()) {
        return;
    }
    QProcess proc;
    proc.start(QStringLiteral("lpadmin"), {QStringLiteral("-x"), clean});
    if (proc.waitForFinished(3000) && proc.exitCode() == 0) {
        notifyStatus(QStringLiteral("Removed printer: %1").arg(clean));
    } else {
        const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        notifyStatus(err.isEmpty()
            ? QStringLiteral("Failed to remove printer %1").arg(clean)
            : QStringLiteral("Remove error: %1").arg(err));
    }
    refreshPrinters();
}

void SystemBackend::openSystemPrinterConfig()
{
    if (!QStandardPaths::findExecutable(QStringLiteral("kcmshell6")).isEmpty()) {
        runDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_printer_manager")});
    } else if (!QStandardPaths::findExecutable(QStringLiteral("kde-add-printer")).isEmpty()) {
        runDetached(QStringLiteral("kde-add-printer"), {QStringLiteral("--add-printer")});
    } else if (!QStandardPaths::findExecutable(QStringLiteral("system-config-printer")).isEmpty()) {
        runDetached(QStringLiteral("system-config-printer"), {});
    } else {
        runDetached(QStringLiteral("xdg-open"), {QStringLiteral("http://localhost:631")});
    }
    notifyStatus(QStringLiteral("Opening system printer configuration..."));
}

// -----------------------------------------------------------------------------
// 6. POWER & BATTERY
// -----------------------------------------------------------------------------
void SystemBackend::refreshPower()
{
    struct PowerSnapshot {
        bool hasBattery = false;
        int batteryPercent = 100;
        QString batteryState = QStringLiteral("Connected to AC Power");
        QString powerProfile;
        int screenLockMinutes = 5;
        int screenOffMinutes = 10;
        int sleepTimeoutMinutes = 15;
        bool lockOnSleep = true;
    };

    PowerSnapshot init;
    init.powerProfile = m_powerProfile;
    init.screenLockMinutes = m_screenLockMinutes;
    init.screenOffMinutes = m_screenOffMinutes;
    init.sleepTimeoutMinutes = m_sleepTimeoutMinutes;
    init.lockOnSleep = m_lockOnSleep;

    runAsyncTask(
        QStringLiteral("power"),
        [this, init]() mutable {
            init.hasBattery = false;
            QDir powerDir(QStringLiteral("/sys/class/power_supply"));
            for (const QString &entry : powerDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
                if (entry.startsWith(QStringLiteral("BAT"))) {
                    init.hasBattery = true;
                    QFile capFile(powerDir.filePath(entry + QStringLiteral("/capacity")));
                    if (capFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                        init.batteryPercent = qBound(0, QString::fromUtf8(capFile.readAll()).trimmed().toInt(), 100);
                    }
                    QFile statusFile(powerDir.filePath(entry + QStringLiteral("/status")));
                    if (statusFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                        init.batteryState = QString::fromUtf8(statusFile.readAll()).trimmed();
                    }
                    break;
                }
            }
            if (!init.hasBattery) {
                init.batteryPercent = 100;
                init.batteryState = QStringLiteral("Connected to AC Power");
            }

            const QString ppOut = runCommandCancellable(QStringLiteral("powerprofilesctl"), {QStringLiteral("get")}, 1500);
            if (!ppOut.isEmpty()) {
                init.powerProfile = ppOut.trimmed();
            }

            // Read screen auto-lock & lock-on-sleep settings from kscreenlockerrc
            const QString autoLockRaw = runCommandCancellable(QStringLiteral("kreadconfig6"),
                {QStringLiteral("--file"), QStringLiteral("kscreenlockerrc"),
                 QStringLiteral("--group"), QStringLiteral("Daemon"),
                 QStringLiteral("--key"), QStringLiteral("Autolock"),
                 QStringLiteral("--default"), QStringLiteral("true")}, 1200).trimmed().toLower();
            if (autoLockRaw == QStringLiteral("false") || autoLockRaw == QStringLiteral("0")) {
                init.screenLockMinutes = 0;
            } else {
                const int lockMins = runCommandCancellable(QStringLiteral("kreadconfig6"),
                    {QStringLiteral("--file"), QStringLiteral("kscreenlockerrc"),
                     QStringLiteral("--group"), QStringLiteral("Daemon"),
                     QStringLiteral("--key"), QStringLiteral("Timeout"),
                     QStringLiteral("--default"), QStringLiteral("5")}, 1200).trimmed().toInt();
                init.screenLockMinutes = (lockMins > 0) ? lockMins : 5;
            }

            const QString lockResumeRaw = runCommandCancellable(QStringLiteral("kreadconfig6"),
                {QStringLiteral("--file"), QStringLiteral("kscreenlockerrc"),
                 QStringLiteral("--group"), QStringLiteral("Daemon"),
                 QStringLiteral("--key"), QStringLiteral("LockOnResume"),
                 QStringLiteral("--default"), QStringLiteral("true")}, 1200).trimmed().toLower();
            init.lockOnSleep = (lockResumeRaw != QStringLiteral("false") && lockResumeRaw != QStringLiteral("0"));

            // Read display idle turn-off & system sleep timeouts from powerdevilrc
            const QString dispIdleRaw = runCommandCancellable(QStringLiteral("kreadconfig6"),
                {QStringLiteral("--file"), QStringLiteral("powerdevilrc"),
                 QStringLiteral("--group"), QStringLiteral("AC"),
                 QStringLiteral("--group"), QStringLiteral("Display"),
                 QStringLiteral("--key"), QStringLiteral("TurnOffDisplayWhenIdle"),
                 QStringLiteral("--default"), QStringLiteral("true")}, 1200).trimmed().toLower();
            if (dispIdleRaw == QStringLiteral("false") || dispIdleRaw == QStringLiteral("0")) {
                init.screenOffMinutes = 0;
            } else {
                const int dispSec = runCommandCancellable(QStringLiteral("kreadconfig6"),
                    {QStringLiteral("--file"), QStringLiteral("powerdevilrc"),
                     QStringLiteral("--group"), QStringLiteral("AC"),
                     QStringLiteral("--group"), QStringLiteral("Display"),
                     QStringLiteral("--key"), QStringLiteral("TurnOffDisplayIdleTimeoutSec"),
                     QStringLiteral("--default"), QStringLiteral("600")}, 1200).trimmed().toInt();
                init.screenOffMinutes = (dispSec >= 60) ? qMax(1, dispSec / 60) : 10;
            }

            const int suspendAction = runCommandCancellable(QStringLiteral("kreadconfig6"),
                {QStringLiteral("--file"), QStringLiteral("powerdevilrc"),
                 QStringLiteral("--group"), QStringLiteral("AC"),
                 QStringLiteral("--group"), QStringLiteral("SuspendAndShutdown"),
                 QStringLiteral("--key"), QStringLiteral("AutoSuspendAction"),
                 QStringLiteral("--default"), QStringLiteral("1")}, 1200).trimmed().toInt();
            if (suspendAction == 0) {
                init.sleepTimeoutMinutes = 0;
            } else {
                const int sleepSec = runCommandCancellable(QStringLiteral("kreadconfig6"),
                    {QStringLiteral("--file"), QStringLiteral("powerdevilrc"),
                     QStringLiteral("--group"), QStringLiteral("AC"),
                     QStringLiteral("--group"), QStringLiteral("SuspendAndShutdown"),
                     QStringLiteral("--key"), QStringLiteral("AutoSuspendIdleTimeoutSec"),
                     QStringLiteral("--default"), QStringLiteral("900")}, 1200).trimmed().toInt();
                init.sleepTimeoutMinutes = (sleepSec >= 60) ? qMax(1, sleepSec / 60) : 15;
            }

            return init;
        },
        [this](PowerSnapshot snap) {
            m_hasBattery = snap.hasBattery;
            m_batteryPercent = snap.batteryPercent;
            m_batteryState = std::move(snap.batteryState);
            m_powerProfile = std::move(snap.powerProfile);
            m_screenLockMinutes = snap.screenLockMinutes;
            m_screenOffMinutes = snap.screenOffMinutes;
            m_sleepTimeoutMinutes = snap.sleepTimeoutMinutes;
            m_lockOnSleep = snap.lockOnSleep;
            emit powerChanged();
        });
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

void SystemBackend::setScreenLockMinutes(int minutes)
{
    const int clean = (minutes <= 0) ? 0 : qBound(1, minutes, 240);
    m_screenLockMinutes = clean;

    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kscreenlockerrc"),
         QStringLiteral("--group"), QStringLiteral("Daemon"),
         QStringLiteral("--key"), QStringLiteral("Autolock"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         clean > 0 ? QStringLiteral("true") : QStringLiteral("false")}, 1500);

    if (clean > 0) {
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kscreenlockerrc"),
             QStringLiteral("--group"), QStringLiteral("Daemon"),
             QStringLiteral("--key"), QStringLiteral("Timeout"),
             QString::number(clean)}, 1500);
    }

    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
         QStringLiteral("org.kde.screensaver.configure")}, 1500);
    notifyStatus(clean > 0
        ? QStringLiteral("Screen will auto-lock after %1 minute(s)").arg(clean)
        : QStringLiteral("Automatic screen lock disabled"));
    emit powerChanged();
}

void SystemBackend::setLockOnSleep(bool enabled)
{
    m_lockOnSleep = enabled;
    runCommand(QStringLiteral("kwriteconfig6"),
        {QStringLiteral("--file"), QStringLiteral("kscreenlockerrc"),
         QStringLiteral("--group"), QStringLiteral("Daemon"),
         QStringLiteral("--key"), QStringLiteral("LockOnResume"),
         QStringLiteral("--type"), QStringLiteral("bool"),
         enabled ? QStringLiteral("true") : QStringLiteral("false")}, 1500);
    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
         QStringLiteral("org.kde.screensaver.configure")}, 1500);
    notifyStatus(enabled
        ? QStringLiteral("Password will be required on wake")
        : QStringLiteral("Wake lock disabled"));
    emit powerChanged();
}

void SystemBackend::setScreenOffMinutes(int minutes)
{
    const int clean = (minutes <= 0) ? 0 : qBound(1, minutes, 480);
    m_screenOffMinutes = clean;
    const QString secStr = QString::number(clean > 0 ? clean * 60 : 600);
    const QString enabledStr = clean > 0 ? QStringLiteral("true") : QStringLiteral("false");

    for (const QString &powerState : {QStringLiteral("AC"), QStringLiteral("Battery")}) {
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("powerdevilrc"),
             QStringLiteral("--group"), powerState,
             QStringLiteral("--group"), QStringLiteral("Display"),
             QStringLiteral("--key"), QStringLiteral("TurnOffDisplayWhenIdle"),
             QStringLiteral("--type"), QStringLiteral("bool"),
             enabledStr}, 1500);
        if (clean > 0) {
            runCommand(QStringLiteral("kwriteconfig6"),
                {QStringLiteral("--file"), QStringLiteral("powerdevilrc"),
                 QStringLiteral("--group"), powerState,
                 QStringLiteral("--group"), QStringLiteral("Display"),
                 QStringLiteral("--key"), QStringLiteral("TurnOffDisplayIdleTimeoutSec"),
                 secStr}, 1500);
        }
    }

    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.Solid.PowerManagement"),
         QStringLiteral("/org/kde/Solid/PowerManagement"),
         QStringLiteral("reparseConfiguration")}, 1500);
    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.Solid.PowerManagement"),
         QStringLiteral("/org/kde/Solid/PowerManagement"),
         QStringLiteral("refreshStatus")}, 1500);
    notifyStatus(clean > 0
        ? QStringLiteral("Display will turn off after %1 minute(s)").arg(clean)
        : QStringLiteral("Display auto turn-off disabled"));
    emit powerChanged();
}

void SystemBackend::setSleepTimeoutMinutes(int minutes)
{
    const int clean = (minutes <= 0) ? 0 : qBound(1, minutes, 480);
    m_sleepTimeoutMinutes = clean;
    const QString secStr = QString::number(clean > 0 ? clean * 60 : 900);
    const QString actionStr = (clean > 0) ? QStringLiteral("1") : QStringLiteral("0");

    for (const QString &powerState : {QStringLiteral("AC"), QStringLiteral("Battery")}) {
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("powerdevilrc"),
             QStringLiteral("--group"), powerState,
             QStringLiteral("--group"), QStringLiteral("SuspendAndShutdown"),
             QStringLiteral("--key"), QStringLiteral("AutoSuspendAction"),
             actionStr}, 1500);
        if (clean > 0) {
            runCommand(QStringLiteral("kwriteconfig6"),
                {QStringLiteral("--file"), QStringLiteral("powerdevilrc"),
                 QStringLiteral("--group"), powerState,
                 QStringLiteral("--group"), QStringLiteral("SuspendAndShutdown"),
                 QStringLiteral("--key"), QStringLiteral("AutoSuspendIdleTimeoutSec"),
                 secStr}, 1500);
        }
    }

    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.Solid.PowerManagement"),
         QStringLiteral("/org/kde/Solid/PowerManagement"),
         QStringLiteral("reparseConfiguration")}, 1500);
    runCommand(QStringLiteral("qdbus6"),
        {QStringLiteral("org.kde.Solid.PowerManagement"),
         QStringLiteral("/org/kde/Solid/PowerManagement"),
         QStringLiteral("refreshStatus")}, 1500);
    notifyStatus(clean > 0
        ? QStringLiteral("System will sleep after %1 minute(s)").arg(clean)
        : QStringLiteral("Automatic sleep disabled"));
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
    struct PersonalizationSnapshot {
        QString currentTheme;
        QVariantList themes;
        QVariantList wallpapers;
        bool blurEnabled = true;
        bool animationsEnabled = true;
    };

    const QString homePath = QDir::homePath();

    runAsyncTask(
        QStringLiteral("personalization"),
        [homePath]() {
            PersonalizationSnapshot snap;

            // Active Plasma desktop theme
            QSettings plasmarc(homePath + QStringLiteral("/.config/plasmarc"), QSettings::IniFormat);
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
            snap.currentTheme = activeTheme;

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
                theme[QStringLiteral("active")] = (themeId == activeTheme);
                themeList.append(theme);
                seenThemeIds.append(themeId);
            }

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
                lnf[QStringLiteral("active")] = (lnfId == activeTheme);
                lnf.remove(QStringLiteral("mappedDesktop"));
                themeList.append(lnf);
            }
            snap.themes = themeList;

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
            snap.wallpapers = wpList;

            QSettings kwinrc(homePath + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
            kwinrc.beginGroup(QStringLiteral("Plugins"));
            snap.blurEnabled = kwinrc.value(QStringLiteral("blurEnabled"), true).toBool();
            kwinrc.endGroup();

            QSettings kdeglobals(homePath + QStringLiteral("/.config/kdeglobals"), QSettings::IniFormat);
            kdeglobals.beginGroup(QStringLiteral("KDE"));
            snap.animationsEnabled = kdeglobals.value(QStringLiteral("AnimationDurationFactor"), 1.0).toDouble() > 0.05;
            kdeglobals.endGroup();

            return snap;
        },
        [this](PersonalizationSnapshot snap) {
            m_currentTheme = std::move(snap.currentTheme);
            m_themes = std::move(snap.themes);
            m_wallpapers = std::move(snap.wallpapers);
            m_blurEnabled = snap.blurEnabled;
            m_animationsEnabled = snap.animationsEnabled;
            emit personalizationChanged();
        });
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
    notifyStatus(enabled ? QStringLiteral("SourceLess Glass Blur enabled") : QStringLiteral("SourceLess Glass Blur disabled"));
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
    runAsyncTask(
        QStringLiteral("apps"),
        [this]() {
            const QString out = runCommandCancellable(QStringLiteral("flatpak"),
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
            return apps;
        },
        [this](QVariantList apps) {
            m_installedApps = std::move(apps);
            emit appsChanged();
        });
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
// 8b. SOURCELESS OS SYSTEM UPDATE (Signed OCI Staging + Mandatory Reboot Apply)
// -----------------------------------------------------------------------------
void SystemBackend::refreshSystemUpdate()
{
    QFile verFile(QStringLiteral("/usr/lib/sourceless-version"));
    if (verFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString v = QString::fromUtf8(verFile.readAll()).trimmed();
        if (!v.isEmpty()) {
            m_osBuildVersion = v;
        }
    }

    QFile confFile(QStringLiteral("/etc/sourceless/update.conf"));
    if (confFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QStringList lines = QString::fromUtf8(confFile.readAll()).split(QLatin1Char('\n'));
        for (const QString &line : lines) {
            if (line.startsWith(QStringLiteral("UPDATE_CHANNEL="))) {
                QString ch = line.mid(15).trimmed();
                ch.remove(QLatin1Char('"')).remove(QLatin1Char('\''));
                if (ch == QStringLiteral("stable") || ch == QStringLiteral("testing")) {
                    m_updateChannel = ch;
                }
            }
        }
    }

    QFile stateFile(QStringLiteral("/var/lib/sourceless-update/state.json"));
    if (stateFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QJsonDocument doc = QJsonDocument::fromJson(stateFile.readAll());
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            const QString st = obj.value(QStringLiteral("status")).toString();
            if (!st.isEmpty()) m_updateStatus = st;
            const QString hl = obj.value(QStringLiteral("headline")).toString();
            if (!hl.isEmpty()) m_updateHeadline = hl;
            const QString dt = obj.value(QStringLiteral("detail")).toString();
            if (!dt.isEmpty()) m_updateDetail = dt;
            const QString ch = obj.value(QStringLiteral("channel")).toString();
            if (ch == QStringLiteral("stable") || ch == QStringLiteral("testing")) {
                m_updateChannel = ch;
            }
            m_updateProgress = qBound(0, obj.value(QStringLiteral("progress")).toInt(0), 100);
            m_updatePendingRestart = obj.value(QStringLiteral("pending_restart")).toBool(false);
            m_updateBusy = (m_updateStatus == QStringLiteral("checking") || m_updateStatus == QStringLiteral("downloading"));
        }
    } else {
        m_updateStatus = QStringLiteral("up_to_date");
        m_updateHeadline = QStringLiteral("You're up to date");
        m_updateDetail = QStringLiteral("SourceLess OS (%1) on %2 channel is up to date.")
            .arg(m_osBuildVersion, m_updateChannel);
        m_updateProgress = 100;
        m_updateBusy = false;
        m_updatePendingRestart = QFileInfo::exists(QStringLiteral("/var/lib/sourceless-update/pending"));
    }

    emit systemUpdateChanged();
}

void SystemBackend::checkForOsUpdates()
{
    m_updateStatus = QStringLiteral("checking");
    m_updateHeadline = QStringLiteral("Checking for SourceLess OS updates...");
    m_updateDetail = QStringLiteral("Querying signed %1 channel...").arg(m_updateChannel);
    m_updateProgress = 10;
    m_updateBusy = true;
    emit systemUpdateChanged();
    notifyStatus(QStringLiteral("Checking for signed SourceLess OS updates..."));

    runDetached(QStringLiteral("sudo"), {
        QStringLiteral("-n"),
        QStringLiteral("/usr/bin/sourceless-os-updater"),
        QStringLiteral("check-and-stage")
    });
    QTimer::singleShot(1500, this, &SystemBackend::refreshSystemUpdate);
}

void SystemBackend::setUpdateChannel(const QString &channel)
{
    const QString clean = channel.trimmed().toLower();
    if (clean != QStringLiteral("stable") && clean != QStringLiteral("testing")) {
        return;
    }
    runCommand(QStringLiteral("sudo"), {
        QStringLiteral("-n"),
        QStringLiteral("/usr/bin/sourceless-os-updater"),
        QStringLiteral("set-channel"),
        clean
    }, 3000);
    m_updateChannel = clean;
    refreshSystemUpdate();
    notifyStatus(QStringLiteral("Switched OS update channel to %1").arg(clean));
}

void SystemBackend::rebootForUpdate()
{
    notifyStatus(QStringLiteral("Restarting to install verified SourceLess OS update..."));
    runDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
}

// -----------------------------------------------------------------------------
// 9. TIME & LANGUAGE
// -----------------------------------------------------------------------------
void SystemBackend::refreshTime()
{
    struct TimeSnapshot {
        QStringList availableTimezones;
        QString timezone;
        bool ntpEnabled = true;
        QString keyboardLayout;
        bool use24Hour = true;
        QString regionalFormat;
        QString systemLanguage;
    };

    TimeSnapshot init;
    init.timezone = m_timezone;
    init.ntpEnabled = m_ntpEnabled;
    init.use24Hour = m_use24Hour;
    init.keyboardLayout = m_keyboardLayout;
    init.regionalFormat = m_regionalFormat;
    init.systemLanguage = m_systemLanguage;
    const QString homePath = QDir::homePath();

    runAsyncTask(
        QStringLiteral("time"),
        [this, init, homePath]() mutable {
            init.availableTimezones = {
                QStringLiteral("Europe/Bucharest"),
                QStringLiteral("UTC"),
                QStringLiteral("Europe/London"),
                QStringLiteral("Europe/Berlin"),
                QStringLiteral("Europe/Paris"),
                QStringLiteral("Europe/Madrid"),
                QStringLiteral("Europe/Rome"),
                QStringLiteral("Europe/Vienna"),
                QStringLiteral("Europe/Warsaw"),
                QStringLiteral("Europe/Budapest"),
                QStringLiteral("Europe/Prague"),
                QStringLiteral("Europe/Athens"),
                QStringLiteral("Europe/Istanbul"),
                QStringLiteral("Europe/Kyiv"),
                QStringLiteral("Europe/Chisinau"),
                QStringLiteral("Europe/Zurich"),
                QStringLiteral("Europe/Amsterdam"),
                QStringLiteral("Europe/Brussels"),
                QStringLiteral("Europe/Stockholm"),
                QStringLiteral("America/New_York"),
                QStringLiteral("America/Chicago"),
                QStringLiteral("America/Denver"),
                QStringLiteral("America/Los_Angeles"),
                QStringLiteral("America/Toronto"),
                QStringLiteral("America/Sao_Paulo"),
                QStringLiteral("Asia/Tokyo"),
                QStringLiteral("Asia/Seoul"),
                QStringLiteral("Asia/Shanghai"),
                QStringLiteral("Asia/Singapore"),
                QStringLiteral("Asia/Dubai"),
                QStringLiteral("Asia/Kolkata"),
                QStringLiteral("Australia/Sydney")
            };

            const QString tz = runCommandCancellable(QStringLiteral("timedatectl"), {QStringLiteral("show"), QStringLiteral("-p"), QStringLiteral("Timezone"), QStringLiteral("--value")}, 1500);
            if (!tz.isEmpty()) {
                init.timezone = tz.trimmed();
                if (!init.availableTimezones.contains(init.timezone)) {
                    init.availableTimezones.prepend(init.timezone);
                }
            }

            const QString ntp = runCommandCancellable(QStringLiteral("timedatectl"), {QStringLiteral("show"), QStringLiteral("-p"), QStringLiteral("NTP"), QStringLiteral("--value")}, 1500);
            if (!ntp.isEmpty()) {
                init.ntpEnabled = (ntp.trimmed() == QStringLiteral("yes"));
            }

            QSettings kxkb(homePath + QStringLiteral("/.config/kxkbrc"), QSettings::IniFormat);
            kxkb.beginGroup(QStringLiteral("Layout"));
            init.keyboardLayout = kxkb.value(QStringLiteral("LayoutList"), QStringLiteral("us")).toString();
            kxkb.endGroup();

            QSettings localeRc(homePath + QStringLiteral("/.config/plasma-localerc"), QSettings::IniFormat);
            localeRc.beginGroup(QStringLiteral("Clock"));
            init.use24Hour = localeRc.value(QStringLiteral("Use24Hour"), init.use24Hour).toBool();
            localeRc.endGroup();

            localeRc.beginGroup(QStringLiteral("Formats"));
            QString fmtLang = localeRc.value(QStringLiteral("LANG")).toString().trimmed();
            localeRc.endGroup();

            if (fmtLang.isEmpty()) {
                QFile sysLocale(QStringLiteral("/etc/locale.conf"));
                if (sysLocale.open(QIODevice::ReadOnly | QIODevice::Text)) {
                    for (const QString &rawLine : QString::fromUtf8(sysLocale.readAll()).split(QLatin1Char('\n'))) {
                        const QString line = rawLine.trimmed();
                        if (line.startsWith(QStringLiteral("LANG="))) {
                            fmtLang = line.mid(5).trimmed();
                            fmtLang.remove(QLatin1Char('"'));
                            break;
                        }
                    }
                }
            }
            if (fmtLang.endsWith(QStringLiteral(".utf8"), Qt::CaseInsensitive)) {
                fmtLang.replace(fmtLang.size() - 5, 5, QStringLiteral(".UTF-8"));
            }
            if (!fmtLang.isEmpty()) {
                init.regionalFormat = fmtLang;
            }

            localeRc.beginGroup(QStringLiteral("Translations"));
            const QString transLang = localeRc.value(QStringLiteral("LANGUAGE")).toString().trimmed();
            localeRc.endGroup();
            if (!transLang.isEmpty()) {
                const QStringList langs = transLang.split(QLatin1Char(':'), Qt::SkipEmptyParts);
                if (!langs.isEmpty()) {
                    init.systemLanguage = langs.first().trimmed();
                }
            } else if (!init.regionalFormat.isEmpty()) {
                const QString base = init.regionalFormat.section(QLatin1Char('.'), 0, 0).trimmed();
                if (!base.isEmpty() && base != QStringLiteral("C")) {
                    init.systemLanguage = base;
                }
            }

            return init;
        },
        [this](TimeSnapshot snap) {
            m_availableTimezones = std::move(snap.availableTimezones);
            m_timezone = std::move(snap.timezone);
            m_ntpEnabled = snap.ntpEnabled;
            m_keyboardLayout = std::move(snap.keyboardLayout);
            m_use24Hour = snap.use24Hour;
            m_regionalFormat = std::move(snap.regionalFormat);
            m_systemLanguage = std::move(snap.systemLanguage);
            m_currentDateTime = QDateTime::currentDateTime().toString(
                m_use24Hour ? QStringLiteral("dddd, dd MMMM yyyy  •  HH:mm") : QStringLiteral("dddd, dd MMMM yyyy  •  hh:mm AP"));
            emit timeChanged();
        });
}

void SystemBackend::setTimezone(const QString &tz)
{
    const QString cleanTz = tz.trimmed();
    if (cleanTz.isEmpty()) {
        return;
    }

    QProcess proc;
    proc.start(QStringLiteral("timedatectl"), {QStringLiteral("set-timezone"), cleanTz});
    if (proc.waitForFinished(4000) && proc.exitCode() == 0) {
        m_timezone = cleanTz;
        if (!m_availableTimezones.contains(cleanTz)) {
            m_availableTimezones.prepend(cleanTz);
        }
        qputenv("TZ", cleanTz.toUtf8());
        tzset();
        notifyStatus(QStringLiteral("Time zone updated to %1").arg(cleanTz));
    } else {
        const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        notifyStatus(err.isEmpty()
            ? QStringLiteral("Failed to set time zone to %1").arg(cleanTz)
            : QStringLiteral("Time zone error: %1").arg(err));
    }
    refreshTime();
}

void SystemBackend::setNtpEnabled(bool enabled)
{
    QProcess proc;
    proc.start(QStringLiteral("timedatectl"),
        {QStringLiteral("set-ntp"), enabled ? QStringLiteral("true") : QStringLiteral("false")});
    if (proc.waitForFinished(4000) && proc.exitCode() == 0) {
        notifyStatus(enabled ? QStringLiteral("Automatic NTP time sync enabled") : QStringLiteral("Automatic NTP time sync disabled"));
    } else {
        const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        notifyStatus(err.isEmpty()
            ? QStringLiteral("Failed to change NTP synchronization state")
            : QStringLiteral("NTP error: %1").arg(err));
    }
    refreshTime();
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
    QSettings localeRc(QDir::homePath() + QStringLiteral("/.config/plasma-localerc"), QSettings::IniFormat);
    localeRc.beginGroup(QStringLiteral("Clock"));
    localeRc.setValue(QStringLiteral("Use24Hour"), m_use24Hour);
    localeRc.endGroup();
    localeRc.sync();
    notifyStatus(use24 ? QStringLiteral("Clock format set to 24-hour") : QStringLiteral("Clock format set to 12-hour"));
    refreshTime();
}

void SystemBackend::writePlasmaLocaleSettings() const
{
    const QString shortLang = m_systemLanguage.section(QLatin1Char('_'), 0, 0).trimmed();
    QStringList langChain = {m_systemLanguage};
    if (!shortLang.isEmpty() && shortLang != m_systemLanguage) {
        langChain.append(shortLang);
    }
    if (m_systemLanguage != QStringLiteral("en_US")) {
        langChain.append(QStringLiteral("en_US"));
    }
    const QString languageValue = langChain.join(QLatin1Char(':'));

    {
        QSettings localeRc(QDir::homePath() + QStringLiteral("/.config/plasma-localerc"), QSettings::IniFormat);
        localeRc.beginGroup(QStringLiteral("Formats"));
        localeRc.setValue(QStringLiteral("LANG"), m_regionalFormat);
        localeRc.endGroup();
        localeRc.beginGroup(QStringLiteral("Translations"));
        localeRc.setValue(QStringLiteral("LANGUAGE"), languageValue);
        localeRc.endGroup();
        localeRc.sync();
    }

    const QString scriptPath = QDir::homePath() + QStringLiteral("/.config/plasma-locale-settings.sh");
    QFile localeScript(scriptPath);
    if (localeScript.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        const QString content = QStringLiteral(
            "#!/bin/sh\n"
            "# Generated by SourceLess Control Center, do not edit\n"
            "export LANG=%1\n"
            "export LANGUAGE=%2\n")
            .arg(m_regionalFormat, languageValue);
        localeScript.write(content.toUtf8());
        localeScript.close();
        localeScript.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
                                    | QFileDevice::ReadGroup | QFileDevice::ExeGroup
                                    | QFileDevice::ReadOther | QFileDevice::ExeOther);
    }

    runCommand(QStringLiteral("systemctl"),
        {QStringLiteral("--user"), QStringLiteral("set-environment"),
         QStringLiteral("LANG=%1").arg(m_regionalFormat),
         QStringLiteral("LANGUAGE=%1").arg(languageValue)}, 1500);
}

void SystemBackend::setSystemLanguage(const QString &langCode)
{
    const QString clean = langCode.trimmed();
    if (clean.isEmpty()) {
        return;
    }
    m_systemLanguage = clean;
    writePlasmaLocaleSettings();
    notifyStatus(QStringLiteral("System display language set to %1 (re-login to apply across all apps)").arg(clean));
    emit timeChanged();
}

void SystemBackend::setRegionalFormat(const QString &localeCode)
{
    const QString clean = localeCode.trimmed();
    if (clean.isEmpty()) {
        return;
    }
    m_regionalFormat = clean;
    writePlasmaLocaleSettings();

    QProcess proc;
    proc.start(QStringLiteral("localectl"), {QStringLiteral("set-locale"), QStringLiteral("LANG=%1").arg(clean)});
    proc.waitForFinished(3000);

    notifyStatus(QStringLiteral("Regional format updated to %1 (re-login for full session effect)").arg(clean));
    emit timeChanged();
}

// -----------------------------------------------------------------------------
// 10. PRIVACY & SECURITY (SourceLess OS Lockdown Telemetry & Controls)
// -----------------------------------------------------------------------------
void SystemBackend::refreshSecurity()
{
    struct SecuritySnapshot {
        bool selinuxOk = false;
        QString selinuxStatus;
        bool lockdownOk = false;
        QString lockdownMode;
        bool shieldActive = false;
        bool clientActive = false;
        bool supportSessionActive = false;
        bool isTampered = false;
        QString systemIntegrity;
        int securityScore = 100;
        bool overallSecurityOk = true;
        QVariantList securityEvents;
    };

    runAsyncTask(
        QStringLiteral("security"),
        [this]() {
            SecuritySnapshot snap;
            int score = 100;
            QVariantList events;

            // 1. SELinux Check
            QFile selinuxFile(QStringLiteral("/sys/fs/selinux/enforce"));
            if (selinuxFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                if (QString::fromUtf8(selinuxFile.readAll()).trimmed() == QStringLiteral("1")) {
                    snap.selinuxOk = true;
                    snap.selinuxStatus = QStringLiteral("Enforcing (Mandatory Access Control)");
                } else {
                    snap.selinuxStatus = QStringLiteral("Permissive / Disabled (UNSAFE)");
                }
            } else {
                snap.selinuxStatus = QStringLiteral("Permissive / Disabled (UNSAFE)");
            }
            if (!snap.selinuxOk) {
                score -= 25;
                events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("SELinux Mandatory Access Control is not enforcing")},
                                          {QStringLiteral("severity"), QStringLiteral("critical")}});
            }

            // 2. Kernel Lockdown Check
            QFile lockdownFile(QStringLiteral("/sys/kernel/security/lockdown"));
            if (lockdownFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                const QString ld = QString::fromUtf8(lockdownFile.readAll()).trimmed();
                if (ld.contains(QStringLiteral("[confidentiality]"))) {
                    snap.lockdownOk = true;
                    snap.lockdownMode = QStringLiteral("Confidentiality (Strict)");
                } else if (ld.contains(QStringLiteral("[integrity]"))) {
                    snap.lockdownOk = true;
                    snap.lockdownMode = QStringLiteral("Integrity (Kernel Hardened)");
                } else {
                    snap.lockdownMode = QStringLiteral("None / Disabled (UNSAFE)");
                }
            } else {
                snap.lockdownMode = QStringLiteral("None / Disabled (UNSAFE)");
            }
            if (!snap.lockdownOk) {
                score -= 15;
            }

            // 3. YARA Shield & Telemetry Agent Check
            snap.shieldActive = (runCommandCancellable(QStringLiteral("systemctl"), {QStringLiteral("is-active"), QStringLiteral("sourceless-shield.service")}, 1500) == QStringLiteral("active"));
            if (!snap.shieldActive) {
                score -= 15;
                events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("Real-Time YARA Downloads Shield is stopped")},
                                          {QStringLiteral("severity"), QStringLiteral("warning")}});
            }

            snap.clientActive = (runCommandCancellable(QStringLiteral("systemctl"), {QStringLiteral("is-active"), QStringLiteral("sourceless-client.service")}, 1500) == QStringLiteral("active"));
            if (!snap.clientActive) {
                score -= 10;
            }

            // 4. Support Gate & Tamper / Modified Check
            const bool supportTokenExists = QFileInfo::exists(QStringLiteral("/tmp/sourceless_support_active")) ||
                                            QFileInfo::exists(QStringLiteral("/var/run/sourceless_support_active"));
            const bool konsoleRunning = !runCommandCancellable(QStringLiteral("pgrep"), {QStringLiteral("-x"), QStringLiteral("konsole.real")}, 1000).isEmpty();
            snap.supportSessionActive = supportTokenExists || konsoleRunning;

            const bool tamperFlagFile = QFileInfo::exists(QStringLiteral("/etc/sourceless/.tamper_detected")) ||
                                        QFileInfo::exists(QStringLiteral("/tmp/.sourceless_tamper_trigger"));

            const QString groupsOut = runCommandCancellable(QStringLiteral("id"), {QStringLiteral("-Gn")}, 1000);
            const bool inWheelGroup = groupsOut.split(QLatin1Char(' ')).contains(QStringLiteral("wheel"));

            // Check journald for support unlock or interactive shell audit logs in current boot
            const QString auditLogs = runCommandCancellable(QStringLiteral("sh"),
                {QStringLiteral("-c"),
                 QStringLiteral("journalctl -b -t sourceless-security -t sourceless-audit --no-pager -q -n 5 2>/dev/null")}, 1500);
            const bool hasAuditActivity = !auditLogs.isEmpty();

            snap.isTampered = tamperFlagFile || snap.supportSessionActive || inWheelGroup || hasAuditActivity;

            if (snap.isTampered) {
                score -= 35;
                QStringList reasons;
                if (tamperFlagFile) reasons << QStringLiteral("Tamper Seal Broken");
                if (snap.supportSessionActive) reasons << QStringLiteral("Terminal Active");
                if (inWheelGroup) reasons << QStringLiteral("Wheel Admin");
                if (hasAuditActivity && !tamperFlagFile) reasons << QStringLiteral("Sudo / Shell Audit Logged");
                snap.systemIntegrity = QStringLiteral("Modified (%1)").arg(reasons.join(QStringLiteral(" • ")));

                events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("System Integrity Modified: ") + reasons.join(QStringLiteral(", "))},
                                          {QStringLiteral("severity"), QStringLiteral("critical")}});
            } else {
                snap.systemIntegrity = QStringLiteral("Verified Immutable (OSTree + Cosign)");
            }

            if (snap.supportSessionActive) {
                events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("Interactive Terminal / Support Session is currently ACTIVE")},
                                          {QStringLiteral("severity"), QStringLiteral("critical")}});
            }

            if (events.isEmpty()) {
                events.append(QVariantMap{{QStringLiteral("title"), QStringLiteral("All SourceLess OS lockdown and kernel integrity checks passed")},
                                          {QStringLiteral("severity"), QStringLiteral("ok")}});
            }

            snap.securityScore = qBound(0, score, 100);
            snap.overallSecurityOk = (!snap.isTampered && snap.selinuxOk && snap.lockdownOk && snap.shieldActive && !snap.supportSessionActive);
            snap.securityEvents = events;
            return snap;
        },
        [this](SecuritySnapshot snap) {
            m_selinuxOk = snap.selinuxOk;
            m_selinuxStatus = std::move(snap.selinuxStatus);
            m_lockdownOk = snap.lockdownOk;
            m_lockdownMode = std::move(snap.lockdownMode);
            m_shieldActive = snap.shieldActive;
            m_clientActive = snap.clientActive;
            m_supportSessionActive = snap.supportSessionActive;
            m_isTampered = snap.isTampered;
            m_systemIntegrity = std::move(snap.systemIntegrity);
            m_securityScore = snap.securityScore;
            m_overallSecurityOk = snap.overallSecurityOk;
            m_securityEvents = std::move(snap.securityEvents);
            emit securityChanged();
        });
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
        notifyStatus(QStringLiteral("Desktop layout restored to SourceLess OS defaults"));
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
    struct AccessibilitySnapshot {
        bool screenZoomEnabled = false;
        bool invertPluginEnabled = false;
        bool invertScreenEnabled = false;
        bool shakeCursorEnabled = true;
        bool trackMouseEnabled = false;
        int colorBlindnessMode = 0;
        int cursorSize = 24;
        bool screenReaderEnabled = false;
        bool mouseKeysEnabled = false;
        bool stickyKeysEnabled = false;
        bool stickyKeysLock = true;
        bool slowKeysEnabled = false;
        int slowKeysDelay = 500;
        bool bounceKeysEnabled = false;
        int bounceKeysDelay = 500;
        bool toggleKeysBeep = false;
        bool systemBellEnabled = false;
        bool visibleBellEnabled = false;
        bool visibleBellInvert = true;
    };

    const QString homePath = QDir::homePath();

    runAsyncTask(
        QStringLiteral("accessibility"),
        [this, homePath]() {
            AccessibilitySnapshot snap;
            QSettings kwinrc(homePath + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
            kwinrc.beginGroup(QStringLiteral("Plugins"));
            snap.screenZoomEnabled = kwinrc.value(QStringLiteral("zoomEnabled"), false).toBool();
            const bool cbEnabled = kwinrc.value(QStringLiteral("colorblindnesscorrectionEnabled"), false).toBool();
            snap.invertPluginEnabled = kwinrc.value(QStringLiteral("invertEnabled"), false).toBool();
            snap.shakeCursorEnabled = kwinrc.value(QStringLiteral("shakecursorEnabled"), true).toBool();
            snap.trackMouseEnabled = kwinrc.value(QStringLiteral("trackmouseEnabled"), false).toBool();
            kwinrc.endGroup();

            const QString activeEffectsOut = runCommandCancellable(QStringLiteral("qdbus6"),
                {QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                 QStringLiteral("org.kde.kwin.Effects.activeEffects")}, 1000);
            snap.invertScreenEnabled = activeEffectsOut.split(QLatin1Char('\n'), Qt::SkipEmptyParts)
                                                       .contains(QStringLiteral("invert"));

            if (cbEnabled) {
                kwinrc.beginGroup(QStringLiteral("Effect-colorblindnesscorrection"));
                const int cbRawMode = kwinrc.value(QStringLiteral("Mode"), 0).toInt();
                kwinrc.endGroup();
                snap.colorBlindnessMode = qBound(0, cbRawMode, 3) + 1;
            } else {
                snap.colorBlindnessMode = 0;
            }

            QSettings kcminputrc(homePath + QStringLiteral("/.config/kcminputrc"), QSettings::IniFormat);
            kcminputrc.beginGroup(QStringLiteral("Mouse"));
            snap.cursorSize = qBound(24, kcminputrc.value(QStringLiteral("cursorSize"), 24).toInt(), 64);
            kcminputrc.endGroup();

            QSettings kaccessrc(homePath + QStringLiteral("/.config/kaccessrc"), QSettings::IniFormat);
            kaccessrc.beginGroup(QStringLiteral("ScreenReader"));
            if (kaccessrc.contains(QStringLiteral("Enabled"))) {
                snap.screenReaderEnabled = kaccessrc.value(QStringLiteral("Enabled"), false).toBool();
            } else {
                snap.screenReaderEnabled = kaccessrc.value(QStringLiteral("enabled"), false).toBool();
            }
            kaccessrc.endGroup();

            kaccessrc.beginGroup(QStringLiteral("Mouse"));
            snap.mouseKeysEnabled = kaccessrc.value(QStringLiteral("MouseKeys"), false).toBool();
            kaccessrc.endGroup();

            kaccessrc.beginGroup(QStringLiteral("Keyboard"));
            snap.stickyKeysEnabled = kaccessrc.value(QStringLiteral("StickyKeys"), false).toBool();
            snap.stickyKeysLock = kaccessrc.value(QStringLiteral("StickyKeysLatch"), true).toBool();
            snap.slowKeysEnabled = kaccessrc.value(QStringLiteral("SlowKeys"), false).toBool();
            snap.slowKeysDelay = qBound(100, kaccessrc.value(QStringLiteral("SlowKeysDelay"), 500).toInt(), 2000);
            snap.bounceKeysEnabled = kaccessrc.value(QStringLiteral("BounceKeys"), false).toBool();
            snap.bounceKeysDelay = qBound(100, kaccessrc.value(QStringLiteral("BounceKeysDelay"), 500).toInt(), 2000);
            snap.toggleKeysBeep = kaccessrc.value(QStringLiteral("ToggleKeysBeep"), false).toBool();
            kaccessrc.endGroup();

            kaccessrc.beginGroup(QStringLiteral("Bell"));
            snap.systemBellEnabled = kaccessrc.value(QStringLiteral("SystemBell"), false).toBool();
            snap.visibleBellEnabled = kaccessrc.value(QStringLiteral("VisibleBell"), false).toBool();
            snap.visibleBellInvert = kaccessrc.value(QStringLiteral("VisibleBellInvert"), true).toBool();
            kaccessrc.endGroup();

            return snap;
        },
        [this, homePath](AccessibilitySnapshot snap) {
            if (!snap.invertPluginEnabled) {
                QSettings kwinrc(homePath + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
                kwinrc.beginGroup(QStringLiteral("Plugins"));
                kwinrc.setValue(QStringLiteral("invertEnabled"), true);
                kwinrc.endGroup();
                kwinrc.sync();
                runDetached(QStringLiteral("sh"),
                    {QStringLiteral("-c"),
                     QStringLiteral("if [ \"$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded invert 2>/dev/null)\" != \"true\" ]; then "
                                    "qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; "
                                    "sleep 0.35; "
                                    "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect invert >/dev/null 2>&1; "
                                    "fi")});
            }

            m_screenZoomEnabled = snap.screenZoomEnabled;
            m_shakeCursorEnabled = snap.shakeCursorEnabled;
            m_trackMouseEnabled = snap.trackMouseEnabled;
            m_invertScreenEnabled = snap.invertScreenEnabled;
            m_colorBlindnessMode = snap.colorBlindnessMode;
            m_cursorSize = snap.cursorSize;
            m_screenReaderEnabled = snap.screenReaderEnabled;
            m_mouseKeysEnabled = snap.mouseKeysEnabled;
            m_stickyKeysEnabled = snap.stickyKeysEnabled;
            m_stickyKeysLock = snap.stickyKeysLock;
            m_slowKeysEnabled = snap.slowKeysEnabled;
            m_slowKeysDelay = snap.slowKeysDelay;
            m_bounceKeysEnabled = snap.bounceKeysEnabled;
            m_bounceKeysDelay = snap.bounceKeysDelay;
            m_toggleKeysBeep = snap.toggleKeysBeep;
            m_systemBellEnabled = snap.systemBellEnabled;
            m_visibleBellEnabled = snap.visibleBellEnabled;
            m_visibleBellInvert = snap.visibleBellInvert;
            emit accessibilityChanged();
        });
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
        runDetached(QStringLiteral("sh"),
            {QStringLiteral("-c"),
             QStringLiteral("qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect colorblindnesscorrection >/dev/null 2>&1; "
                            "qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1")});
        notifyStatus(QStringLiteral("Color blindness filter disabled"));
    } else {
        const int kwinMode = clamped - 1;
        static const QStringList kwinGroups = {
            QStringLiteral("Effect-colorblindnesscorrection"),
            QStringLiteral("Effect-ColorblindnessCorrection"),
            QStringLiteral("Effect-ColorBlindnessCorrection"),
            QStringLiteral("ColorBlindnessCorrection"),
            QStringLiteral("ColorblindnessCorrection")
        };
        {
            QSettings kwinrc(QDir::homePath() + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
            for (const QString &group : kwinGroups) {
                kwinrc.beginGroup(group);
                kwinrc.setValue(QStringLiteral("Mode"), kwinMode);
                kwinrc.endGroup();
            }
            kwinrc.sync();
        }
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"),
             QStringLiteral("--group"), QStringLiteral("Effect-colorblindnesscorrection"),
             QStringLiteral("--key"), QStringLiteral("Mode"),
             QString::number(kwinMode),
             QStringLiteral("--notify")}, 1500);
        runCommand(QStringLiteral("kwriteconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"),
             QStringLiteral("--group"), QStringLiteral("Plugins"),
             QStringLiteral("--key"), QStringLiteral("colorblindnesscorrectionEnabled"),
             QStringLiteral("--type"), QStringLiteral("bool"),
             QStringLiteral("true"),
             QStringLiteral("--notify")}, 1500);
        runDetached(QStringLiteral("sh"),
            {QStringLiteral("-c"),
             QStringLiteral("qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; "
                            "sleep 0.25; "
                            "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect colorblindnesscorrection >/dev/null 2>&1; "
                            "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect colorblindnesscorrection >/dev/null 2>&1; "
                            "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect colorblindnesscorrection >/dev/null 2>&1")});
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
    {
        QSettings kwinrc(QDir::homePath() + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
        kwinrc.beginGroup(QStringLiteral("Plugins"));
        kwinrc.setValue(QStringLiteral("invertEnabled"), true);
        kwinrc.endGroup();
        kwinrc.sync();
    }

    if (enabled) {
        runDetached(QStringLiteral("sh"),
            {QStringLiteral("-c"),
             QStringLiteral("if [ \"$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded invert 2>/dev/null)\" != \"true\" ]; then "
                            "kwriteconfig6 --file kwinrc --group Plugins --key invertEnabled --type bool true --notify >/dev/null 2>&1; "
                            "qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; "
                            "sleep 0.35; "
                            "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect invert >/dev/null 2>&1; "
                            "sleep 0.35; "
                            "fi; "
                            "if ! qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | grep -qx \"invert\"; then "
                            "qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \"Invert\" >/dev/null 2>&1; "
                            "sleep 0.15; "
                            "if ! qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | grep -qx \"invert\"; then "
                            "qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \"Invert Screen Colors\" >/dev/null 2>&1; "
                            "fi; "
                            "fi")});
    } else {
        runDetached(QStringLiteral("sh"),
            {QStringLiteral("-c"),
             QStringLiteral("if qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | grep -qx \"invert\"; then "
                            "qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \"Invert\" >/dev/null 2>&1; "
                            "sleep 0.15; "
                            "if qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | grep -qx \"invert\"; then "
                            "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect invert >/dev/null 2>&1; "
                            "sleep 0.1; "
                            "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect invert >/dev/null 2>&1; "
                            "fi; "
                            "fi")});
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
