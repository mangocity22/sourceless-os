#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>

class SystemBackend : public QObject
{
    Q_OBJECT

    // 1. Identity & System Info
    Q_PROPERTY(QString userName READ userName NOTIFY systemInfoChanged)
    Q_PROPERTY(QString userFullName READ userFullName NOTIFY systemInfoChanged)
    Q_PROPERTY(QString userInitials READ userInitials NOTIFY systemInfoChanged)
    Q_PROPERTY(QString userAvatar READ userAvatar NOTIFY systemInfoChanged)
    Q_PROPERTY(QString userEmail READ userEmail NOTIFY systemInfoChanged)
    Q_PROPERTY(QString hostname READ hostname NOTIFY systemInfoChanged)
    Q_PROPERTY(QString osName READ osName NOTIFY systemInfoChanged)
    Q_PROPERTY(QString kernelVersion READ kernelVersion NOTIFY systemInfoChanged)
    Q_PROPERTY(QString cpuModel READ cpuModel NOTIFY systemInfoChanged)
    Q_PROPERTY(int cpuCores READ cpuCores NOTIFY systemInfoChanged)
    Q_PROPERTY(QString gpuModel READ gpuModel NOTIFY systemInfoChanged)
    Q_PROPERTY(QString ramTotalText READ ramTotalText NOTIFY systemInfoChanged)
    Q_PROPERTY(QString ramUsedText READ ramUsedText NOTIFY systemInfoChanged)
    Q_PROPERTY(int ramPercent READ ramPercent NOTIFY systemInfoChanged)
    Q_PROPERTY(QString diskTotalText READ diskTotalText NOTIFY systemInfoChanged)
    Q_PROPERTY(QString diskUsedText READ diskUsedText NOTIFY systemInfoChanged)
    Q_PROPERTY(QString diskFreeText READ diskFreeText NOTIFY systemInfoChanged)
    Q_PROPERTY(int diskPercent READ diskPercent NOTIFY systemInfoChanged)
    Q_PROPERTY(QString uptimeText READ uptimeText NOTIFY systemInfoChanged)
    Q_PROPERTY(QString hwid READ hwid NOTIFY systemInfoChanged)
    Q_PROPERTY(QString initialPage READ initialPage CONSTANT)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)

    // 1b. OS Update (Windows-Update-style Staging)
    Q_PROPERTY(QString osBuildVersion READ osBuildVersion NOTIFY systemUpdateChanged)
    Q_PROPERTY(QString updateStatus READ updateStatus NOTIFY systemUpdateChanged)
    Q_PROPERTY(QString updateHeadline READ updateHeadline NOTIFY systemUpdateChanged)
    Q_PROPERTY(QString updateDetail READ updateDetail NOTIFY systemUpdateChanged)
    Q_PROPERTY(QString updateChannel READ updateChannel NOTIFY systemUpdateChanged)
    Q_PROPERTY(int updateProgress READ updateProgress NOTIFY systemUpdateChanged)
    Q_PROPERTY(bool updateBusy READ updateBusy NOTIFY systemUpdateChanged)
    Q_PROPERTY(bool updatePendingRestart READ updatePendingRestart NOTIFY systemUpdateChanged)

    // 2. Audio
    Q_PROPERTY(int volume READ volume NOTIFY audioChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY audioChanged)
    Q_PROPERTY(int micVolume READ micVolume NOTIFY audioChanged)
    Q_PROPERTY(bool micMuted READ micMuted NOTIFY audioChanged)
    Q_PROPERTY(QString audioOutputName READ audioOutputName NOTIFY audioChanged)

    // 3. Display
    Q_PROPERTY(int brightness READ brightness NOTIFY displayChanged)
    Q_PROPERTY(bool hasBrightness READ hasBrightness NOTIFY displayChanged)
    Q_PROPERTY(QString displayName READ displayName NOTIFY displayChanged)
    Q_PROPERTY(QString currentResolution READ currentResolution NOTIFY displayChanged)
    Q_PROPERTY(QStringList availableResolutions READ availableResolutions NOTIFY displayChanged)
    Q_PROPERTY(QString currentRefreshRate READ currentRefreshRate NOTIFY displayChanged)
    Q_PROPERTY(QStringList availableRefreshRates READ availableRefreshRates NOTIFY displayChanged)
    Q_PROPERTY(QString displayOrientation READ displayOrientation NOTIFY displayChanged)
    Q_PROPERTY(int orientationConfirmSeconds READ orientationConfirmSeconds NOTIFY displayChanged)
    Q_PROPERTY(QString colorAccuracy READ colorAccuracy NOTIFY displayChanged)
    Q_PROPERTY(int displayScale READ displayScale NOTIFY displayChanged)
    Q_PROPERTY(bool nightLightEnabled READ nightLightEnabled NOTIFY displayChanged)
    Q_PROPERTY(int nightLightTemp READ nightLightTemp NOTIFY displayChanged)

    // 4. Network
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY networkChanged)
    Q_PROPERTY(bool networkConnected READ networkConnected NOTIFY networkChanged)
    Q_PROPERTY(QString connectionType READ connectionType NOTIFY networkChanged)
    Q_PROPERTY(QString activeNetworkName READ activeNetworkName NOTIFY networkChanged)
    Q_PROPERTY(QString ipAddress READ ipAddress NOTIFY networkChanged)
    Q_PROPERTY(QString dnsStatus READ dnsStatus NOTIFY networkChanged)
    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY networkChanged)

    // 5. Bluetooth & Input
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled NOTIFY bluetoothChanged)
    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY bluetoothChanged)
    Q_PROPERTY(int mouseSpeed READ mouseSpeed NOTIFY inputChanged)
    Q_PROPERTY(bool naturalScroll READ naturalScroll NOTIFY inputChanged)
    Q_PROPERTY(bool tapToClick READ tapToClick NOTIFY inputChanged)
    Q_PROPERTY(bool leftHandedMouse READ leftHandedMouse NOTIFY inputChanged)
    Q_PROPERTY(bool cupsRunning READ cupsRunning NOTIFY printersChanged)
    Q_PROPERTY(QVariantList printers READ printers NOTIFY printersChanged)
    Q_PROPERTY(QString defaultPrinter READ defaultPrinter NOTIFY printersChanged)
    Q_PROPERTY(int activePrintJobs READ activePrintJobs NOTIFY printersChanged)

    // 6. Power & Battery
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY powerChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY powerChanged)
    Q_PROPERTY(QString batteryState READ batteryState NOTIFY powerChanged)
    Q_PROPERTY(QString powerProfile READ powerProfile NOTIFY powerChanged)

    // 7. Personalization
    Q_PROPERTY(QVariantList themes READ themes NOTIFY personalizationChanged)
    Q_PROPERTY(QString currentTheme READ currentTheme NOTIFY personalizationChanged)
    Q_PROPERTY(QVariantList wallpapers READ wallpapers NOTIFY personalizationChanged)
    Q_PROPERTY(QString currentWallpaper READ currentWallpaper NOTIFY personalizationChanged)
    Q_PROPERTY(bool blurEnabled READ blurEnabled NOTIFY personalizationChanged)
    Q_PROPERTY(bool animationsEnabled READ animationsEnabled NOTIFY personalizationChanged)

    // 8. Apps
    Q_PROPERTY(QVariantList installedApps READ installedApps NOTIFY appsChanged)

    // 9. Time & Language
    Q_PROPERTY(QString currentDateTime READ currentDateTime NOTIFY timeChanged)
    Q_PROPERTY(QString timezone READ timezone NOTIFY timeChanged)
    Q_PROPERTY(QStringList availableTimezones READ availableTimezones NOTIFY timeChanged)
    Q_PROPERTY(bool ntpEnabled READ ntpEnabled NOTIFY timeChanged)
    Q_PROPERTY(bool use24Hour READ use24Hour NOTIFY timeChanged)
    Q_PROPERTY(QString keyboardLayout READ keyboardLayout NOTIFY timeChanged)
    Q_PROPERTY(QString systemLanguage READ systemLanguage NOTIFY timeChanged)
    Q_PROPERTY(QString regionalFormat READ regionalFormat NOTIFY timeChanged)

    // 10. Privacy & Security
    Q_PROPERTY(QString selinuxStatus READ selinuxStatus NOTIFY securityChanged)
    Q_PROPERTY(bool selinuxOk READ selinuxOk NOTIFY securityChanged)
    Q_PROPERTY(QString lockdownMode READ lockdownMode NOTIFY securityChanged)
    Q_PROPERTY(bool lockdownOk READ lockdownOk NOTIFY securityChanged)
    Q_PROPERTY(bool shieldActive READ shieldActive NOTIFY securityChanged)
    Q_PROPERTY(bool clientActive READ clientActive NOTIFY securityChanged)
    Q_PROPERTY(QString systemIntegrity READ systemIntegrity NOTIFY securityChanged)
    Q_PROPERTY(bool isTampered READ isTampered NOTIFY securityChanged)
    Q_PROPERTY(bool supportSessionActive READ supportSessionActive NOTIFY securityChanged)
    Q_PROPERTY(bool overallSecurityOk READ overallSecurityOk NOTIFY securityChanged)
    Q_PROPERTY(int securityScore READ securityScore NOTIFY securityChanged)
    Q_PROPERTY(QString lastScanResult READ lastScanResult NOTIFY securityChanged)
    Q_PROPERTY(QVariantList securityEvents READ securityEvents NOTIFY securityChanged)

    // 11. Accessibility
    Q_PROPERTY(bool screenZoomEnabled READ screenZoomEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(int colorBlindnessMode READ colorBlindnessMode NOTIFY accessibilityChanged)
    Q_PROPERTY(bool invertScreenEnabled READ invertScreenEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(bool screenReaderEnabled READ screenReaderEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(int cursorSize READ cursorSize NOTIFY accessibilityChanged)
    Q_PROPERTY(bool shakeCursorEnabled READ shakeCursorEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(bool trackMouseEnabled READ trackMouseEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(bool mouseKeysEnabled READ mouseKeysEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(bool stickyKeysEnabled READ stickyKeysEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(bool stickyKeysLock READ stickyKeysLock NOTIFY accessibilityChanged)
    Q_PROPERTY(bool slowKeysEnabled READ slowKeysEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(int slowKeysDelay READ slowKeysDelay NOTIFY accessibilityChanged)
    Q_PROPERTY(bool bounceKeysEnabled READ bounceKeysEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(int bounceKeysDelay READ bounceKeysDelay NOTIFY accessibilityChanged)
    Q_PROPERTY(bool toggleKeysBeep READ toggleKeysBeep NOTIFY accessibilityChanged)
    Q_PROPERTY(bool systemBellEnabled READ systemBellEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(bool visibleBellEnabled READ visibleBellEnabled NOTIFY accessibilityChanged)
    Q_PROPERTY(bool visibleBellInvert READ visibleBellInvert NOTIFY accessibilityChanged)

public:
    explicit SystemBackend(const QString &startPage = QStringLiteral("home"), QObject *parent = nullptr);

    // Getters
    QString userName() const { return m_userName; }
    QString userFullName() const { return m_userFullName; }
    QString userInitials() const { return m_userInitials; }
    QString userAvatar() const { return m_userAvatar; }
    QString userEmail() const { return m_userEmail; }
    QString hostname() const { return m_hostname; }
    QString osName() const { return m_osName; }
    QString kernelVersion() const { return m_kernelVersion; }
    QString cpuModel() const { return m_cpuModel; }
    int cpuCores() const { return m_cpuCores; }
    QString gpuModel() const { return m_gpuModel; }
    QString ramTotalText() const { return m_ramTotalText; }
    QString ramUsedText() const { return m_ramUsedText; }
    int ramPercent() const { return m_ramPercent; }
    QString diskTotalText() const { return m_diskTotalText; }
    QString diskUsedText() const { return m_diskUsedText; }
    QString diskFreeText() const { return m_diskFreeText; }
    int diskPercent() const { return m_diskPercent; }
    QString uptimeText() const { return m_uptimeText; }
    QString hwid() const { return m_hwid; }
    QString initialPage() const { return m_initialPage; }
    QString statusMessage() const { return m_statusMessage; }

    QString osBuildVersion() const { return m_osBuildVersion; }
    QString updateStatus() const { return m_updateStatus; }
    QString updateHeadline() const { return m_updateHeadline; }
    QString updateDetail() const { return m_updateDetail; }
    QString updateChannel() const { return m_updateChannel; }
    int updateProgress() const { return m_updateProgress; }
    bool updateBusy() const { return m_updateBusy; }
    bool updatePendingRestart() const { return m_updatePendingRestart; }

    int volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    int micVolume() const { return m_micVolume; }
    bool micMuted() const { return m_micMuted; }
    QString audioOutputName() const { return m_audioOutputName; }

    int brightness() const { return m_brightness; }
    bool hasBrightness() const { return m_hasBrightness; }
    QString displayName() const { return m_displayName; }
    QString currentResolution() const { return m_currentResolution; }
    QStringList availableResolutions() const { return m_availableResolutions; }
    QString currentRefreshRate() const { return m_currentRefreshRate; }
    QStringList availableRefreshRates() const { return m_availableRefreshRates; }
    QString displayOrientation() const { return m_displayOrientation; }
    int orientationConfirmSeconds() const { return m_orientationConfirmSeconds; }
    QString colorAccuracy() const { return m_colorAccuracy; }
    int displayScale() const { return m_displayScale; }
    bool nightLightEnabled() const { return m_nightLightEnabled; }
    int nightLightTemp() const { return m_nightLightTemp; }

    bool wifiEnabled() const { return m_wifiEnabled; }
    bool networkConnected() const { return m_networkConnected; }
    QString connectionType() const { return m_connectionType; }
    QString activeNetworkName() const { return m_activeNetworkName; }
    QString ipAddress() const { return m_ipAddress; }
    QString dnsStatus() const { return m_dnsStatus; }
    QVariantList wifiNetworks() const { return m_wifiNetworks; }

    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    QVariantList bluetoothDevices() const { return m_bluetoothDevices; }
    int mouseSpeed() const { return m_mouseSpeed; }
    bool naturalScroll() const { return m_naturalScroll; }
    bool tapToClick() const { return m_tapToClick; }
    bool leftHandedMouse() const { return m_leftHandedMouse; }
    bool cupsRunning() const { return m_cupsRunning; }
    QVariantList printers() const { return m_printers; }
    QString defaultPrinter() const { return m_defaultPrinter; }
    int activePrintJobs() const { return m_activePrintJobs; }

    bool hasBattery() const { return m_hasBattery; }
    int batteryPercent() const { return m_batteryPercent; }
    QString batteryState() const { return m_batteryState; }
    QString powerProfile() const { return m_powerProfile; }

    QVariantList themes() const { return m_themes; }
    QString currentTheme() const { return m_currentTheme; }
    QVariantList wallpapers() const { return m_wallpapers; }
    QString currentWallpaper() const { return m_currentWallpaper; }
    bool blurEnabled() const { return m_blurEnabled; }
    bool animationsEnabled() const { return m_animationsEnabled; }

    QVariantList installedApps() const { return m_installedApps; }

    QString currentDateTime() const { return m_currentDateTime; }
    QString timezone() const { return m_timezone; }
    QStringList availableTimezones() const { return m_availableTimezones; }
    bool ntpEnabled() const { return m_ntpEnabled; }
    bool use24Hour() const { return m_use24Hour; }
    QString keyboardLayout() const { return m_keyboardLayout; }
    QString systemLanguage() const { return m_systemLanguage; }
    QString regionalFormat() const { return m_regionalFormat; }

    QString selinuxStatus() const { return m_selinuxStatus; }
    bool selinuxOk() const { return m_selinuxOk; }
    QString lockdownMode() const { return m_lockdownMode; }
    bool lockdownOk() const { return m_lockdownOk; }
    bool shieldActive() const { return m_shieldActive; }
    bool clientActive() const { return m_clientActive; }
    QString systemIntegrity() const { return m_systemIntegrity; }
    bool isTampered() const { return m_isTampered; }
    bool supportSessionActive() const { return m_supportSessionActive; }
    bool overallSecurityOk() const { return m_overallSecurityOk; }
    int securityScore() const { return m_securityScore; }
    QString lastScanResult() const { return m_lastScanResult; }
    QVariantList securityEvents() const { return m_securityEvents; }

    bool screenZoomEnabled() const { return m_screenZoomEnabled; }
    int colorBlindnessMode() const { return m_colorBlindnessMode; }
    bool invertScreenEnabled() const { return m_invertScreenEnabled; }
    bool screenReaderEnabled() const { return m_screenReaderEnabled; }
    int cursorSize() const { return m_cursorSize; }
    bool shakeCursorEnabled() const { return m_shakeCursorEnabled; }
    bool trackMouseEnabled() const { return m_trackMouseEnabled; }
    bool mouseKeysEnabled() const { return m_mouseKeysEnabled; }
    bool stickyKeysEnabled() const { return m_stickyKeysEnabled; }
    bool stickyKeysLock() const { return m_stickyKeysLock; }
    bool slowKeysEnabled() const { return m_slowKeysEnabled; }
    int slowKeysDelay() const { return m_slowKeysDelay; }
    bool bounceKeysEnabled() const { return m_bounceKeysEnabled; }
    int bounceKeysDelay() const { return m_bounceKeysDelay; }
    bool toggleKeysBeep() const { return m_toggleKeysBeep; }
    bool systemBellEnabled() const { return m_systemBellEnabled; }
    bool visibleBellEnabled() const { return m_visibleBellEnabled; }
    bool visibleBellInvert() const { return m_visibleBellInvert; }

    // Invokable actions for QML
    Q_INVOKABLE void refreshAll();
    Q_INVOKABLE void refreshUserProfile();
    Q_INVOKABLE void refreshAudio();
    Q_INVOKABLE void refreshDisplay();
    Q_INVOKABLE void refreshNetwork();
    Q_INVOKABLE void refreshBluetooth();
    Q_INVOKABLE void refreshPrinters();
    Q_INVOKABLE void refreshPower();
    Q_INVOKABLE void refreshPersonalization();
    Q_INVOKABLE void refreshApps();
    Q_INVOKABLE void refreshTime();
    Q_INVOKABLE void refreshSecurity();
    Q_INVOKABLE void refreshAccessibility();
    Q_INVOKABLE void refreshSystemUpdate();
    Q_INVOKABLE void checkForOsUpdates();
    Q_INVOKABLE void setUpdateChannel(const QString &channel);
    Q_INVOKABLE void rebootForUpdate();

    // Audio controls
    Q_INVOKABLE void setVolume(int val);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void setMicVolume(int val);
    Q_INVOKABLE void toggleMicMute();
    Q_INVOKABLE void testSound();

    // Display controls
    Q_INVOKABLE void setBrightness(int val);
    Q_INVOKABLE void setResolution(const QString &res);
    Q_INVOKABLE void setRefreshRate(const QString &rate);
    Q_INVOKABLE void setDisplayOrientation(const QString &orientation);
    Q_INVOKABLE void confirmDisplayOrientation();
    Q_INVOKABLE void revertDisplayOrientation();
    Q_INVOKABLE void setColorAccuracy(const QString &mode);
    Q_INVOKABLE void setDisplayScale(int percent);
    Q_INVOKABLE void setNightLight(bool enabled, int temp);

    // Network controls
    Q_INVOKABLE void setWifiEnabled(bool enabled);
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password);
    Q_INVOKABLE void disconnectNetwork();

    // Bluetooth & Input controls
    Q_INVOKABLE void setBluetoothEnabled(bool enabled);
    Q_INVOKABLE void scanBluetooth();
    Q_INVOKABLE void toggleBluetoothDevice(const QString &mac, bool connectDevice);
    Q_INVOKABLE void setMouseSettings(int speed, bool natural, bool tap, bool leftHanded);
    Q_INVOKABLE void setDefaultPrinter(const QString &printerName);
    Q_INVOKABLE void printTestPage(const QString &printerName);
    Q_INVOKABLE void cancelAllPrintJobs(const QString &printerName = QString());
    Q_INVOKABLE void addNetworkPrinter(const QString &name, const QString &uri);
    Q_INVOKABLE void removePrinter(const QString &printerName);
    Q_INVOKABLE void openSystemPrinterConfig();

    // Power controls
    Q_INVOKABLE void setPowerProfile(const QString &profile);

    // Personalization controls
    Q_INVOKABLE void applyTheme(const QString &themeId);
    Q_INVOKABLE void applyWallpaper(const QString &path);
    Q_INVOKABLE void setBlurEnabled(bool enabled);
    Q_INVOKABLE void setAnimationsEnabled(bool enabled);

    // App controls
    Q_INVOKABLE void launchApp(const QString &appId);
    Q_INVOKABLE void uninstallApp(const QString &appId);
    Q_INVOKABLE void updateAllApps();
    Q_INVOKABLE void clearUserCache();

    // Time & Language controls
    Q_INVOKABLE void setTimezone(const QString &tz);
    Q_INVOKABLE void setNtpEnabled(bool enabled);
    Q_INVOKABLE void setKeyboardLayout(const QString &layout);
    Q_INVOKABLE void setUse24Hour(bool use24);
    Q_INVOKABLE void setSystemLanguage(const QString &langCode);
    Q_INVOKABLE void setRegionalFormat(const QString &localeCode);

    // Security & Support controls
    Q_INVOKABLE void launchEmergencyTerminal();
    Q_INVOKABLE void runQuickSecurityScan();
    Q_INVOKABLE void resetDesktopLayout();

    // Accessibility controls
    Q_INVOKABLE void setScreenZoomEnabled(bool enabled);
    Q_INVOKABLE void zoomScreen(int direction);
    Q_INVOKABLE void setColorBlindnessMode(int mode);
    Q_INVOKABLE void setInvertScreenEnabled(bool enabled);
    Q_INVOKABLE void setScreenReaderEnabled(bool enabled);
    Q_INVOKABLE void setCursorSize(int size);
    Q_INVOKABLE void setShakeCursorEnabled(bool enabled);
    Q_INVOKABLE void setTrackMouseEnabled(bool enabled);
    Q_INVOKABLE void setMouseKeysEnabled(bool enabled);
    Q_INVOKABLE void setStickyKeys(bool enabled, bool lockKeys);
    Q_INVOKABLE void setSlowKeys(bool enabled, int delayMs);
    Q_INVOKABLE void setBounceKeys(bool enabled, int delayMs);
    Q_INVOKABLE void setToggleKeysBeep(bool enabled);
    Q_INVOKABLE void setBellSettings(bool audibleBell, bool visualBell, bool invertVisual);

    // User Account controls
    Q_INVOKABLE void setUserFullName(const QString &fullName);
    Q_INVOKABLE void setUserEmail(const QString &email);
    Q_INVOKABLE void chooseUserAvatar();
    Q_INVOKABLE void clearUserAvatar();
    Q_INVOKABLE bool changeUserPassword(const QString &currentPass, const QString &newPass, const QString &confirmPass);
    Q_INVOKABLE void lockScreenSession();
    Q_INVOKABLE void logoutSession();

signals:
    void systemInfoChanged();
    void audioChanged();
    void displayChanged();
    void networkChanged();
    void bluetoothChanged();
    void printersChanged();
    void inputChanged();
    void powerChanged();
    void personalizationChanged();
    void appsChanged();
    void timeChanged();
    void securityChanged();
    void accessibilityChanged();
    void statusMessageChanged();
    void systemUpdateChanged();

private:
    QString runCommand(const QString &program, const QStringList &args, int timeoutMs = 3000) const;
    void runDetached(const QString &program, const QStringList &args) const;
    void applyDisplayOrientationRaw(const QString &orientation);
    void setKwinEffectEnabled(const QString &pluginKey, const QString &effectId, bool enabled) const;
    void reloadAccessDaemon() const;
    void writePlasmaLocaleSettings() const;
    void notifyStatus(const QString &msg);
    void loadStaticSystemInfo();
    void loadDynamicSystemMetrics();
    void loadInputSettings();

    QString m_userName;
    QString m_userFullName;
    QString m_userInitials;
    QString m_userAvatar;
    QString m_userEmail;
    QString m_hostname;
    QString m_osName;
    QString m_kernelVersion;
    QString m_cpuModel;
    int m_cpuCores = 1;
    QString m_gpuModel;
    QString m_ramTotalText;
    QString m_ramUsedText;
    int m_ramPercent = 0;
    QString m_diskTotalText;
    QString m_diskUsedText;
    QString m_diskFreeText;
    int m_diskPercent = 0;
    QString m_uptimeText;
    QString m_hwid;
    QString m_initialPage;
    QString m_statusMessage;

    QString m_osBuildVersion = QStringLiteral("2026.11");
    QString m_updateStatus = QStringLiteral("up_to_date");
    QString m_updateHeadline = QStringLiteral("You're up to date");
    QString m_updateDetail = QStringLiteral("SourceLess OS updates are verified with Cosign before staging.");
    QString m_updateChannel = QStringLiteral("stable");
    int m_updateProgress = 100;
    bool m_updateBusy = false;
    bool m_updatePendingRestart = false;

    int m_volume = 70;
    bool m_muted = false;
    int m_micVolume = 80;
    bool m_micMuted = false;
    QString m_audioOutputName = QStringLiteral("Default System Output");

    int m_brightness = 100;
    bool m_hasBrightness = true;
    int m_maxRawBrightness = 0;
    QString m_displayName = QStringLiteral("Primary Display");
    QString m_currentResolution = QStringLiteral("1920x1080");
    QStringList m_availableResolutions;
    QString m_currentRefreshRate = QStringLiteral("60 Hz");
    QStringList m_availableRefreshRates;
    QString m_displayOrientation = QStringLiteral("normal");
    QString m_previousOrientation = QStringLiteral("normal");
    int m_orientationConfirmSeconds = 0;
    QTimer m_orientationRevertTimer;
    QString m_colorAccuracy = QStringLiteral("preferEfficiency");
    int m_displayScale = 100;
    bool m_nightLightEnabled = false;
    int m_nightLightTemp = 4500;

    bool m_wifiEnabled = true;
    bool m_networkConnected = false;
    QString m_connectionType = QStringLiteral("Disconnected");
    QString m_activeNetworkName = QStringLiteral("Not Connected");
    QString m_ipAddress = QStringLiteral("127.0.0.1");
    QString m_dnsStatus = QStringLiteral("Quad9 + Cloudflare DoT (Encrypted)");
    QVariantList m_wifiNetworks;

    bool m_bluetoothEnabled = false;
    QVariantList m_bluetoothDevices;
    int m_mouseSpeed = 5;
    bool m_naturalScroll = false;
    bool m_tapToClick = true;
    bool m_leftHandedMouse = false;
    bool m_cupsRunning = false;
    QVariantList m_printers;
    QString m_defaultPrinter = QStringLiteral("None");
    int m_activePrintJobs = 0;

    bool m_hasBattery = false;
    int m_batteryPercent = 100;
    QString m_batteryState = QStringLiteral("AC Power");
    QString m_powerProfile = QStringLiteral("balanced");

    QVariantList m_themes;
    QString m_currentTheme = QStringLiteral("SourcelessGlass");
    QVariantList m_wallpapers;
    QString m_currentWallpaper;
    bool m_blurEnabled = true;
    bool m_animationsEnabled = true;

    QVariantList m_installedApps;

    QString m_currentDateTime;
    QString m_timezone = QStringLiteral("UTC");
    QStringList m_availableTimezones;
    bool m_ntpEnabled = true;
    bool m_use24Hour = true;
    QString m_keyboardLayout = QStringLiteral("us");
    QString m_systemLanguage = QStringLiteral("en_US");
    QString m_regionalFormat = QStringLiteral("en_US.UTF-8");

    QString m_selinuxStatus = QStringLiteral("Enforcing");
    bool m_selinuxOk = true;
    QString m_lockdownMode = QStringLiteral("Integrity");
    bool m_lockdownOk = true;
    bool m_shieldActive = true;
    bool m_clientActive = true;
    QString m_systemIntegrity = QStringLiteral("Verified Immutable (OSTree)");
    bool m_isTampered = false;
    bool m_supportSessionActive = false;
    bool m_overallSecurityOk = true;
    int m_securityScore = 100;
    QString m_lastScanResult = QStringLiteral("Real-time watcher active on ~/Downloads and ~/.config/autostart");
    QVariantList m_securityEvents;

    bool m_screenZoomEnabled = false;
    int m_colorBlindnessMode = 0;
    bool m_invertScreenEnabled = false;
    bool m_screenReaderEnabled = false;
    int m_cursorSize = 24;
    bool m_shakeCursorEnabled = true;
    bool m_trackMouseEnabled = false;
    bool m_mouseKeysEnabled = false;
    bool m_stickyKeysEnabled = false;
    bool m_stickyKeysLock = true;
    bool m_slowKeysEnabled = false;
    int m_slowKeysDelay = 500;
    bool m_bounceKeysEnabled = false;
    int m_bounceKeysDelay = 500;
    bool m_toggleKeysBeep = false;
    bool m_systemBellEnabled = false;
    bool m_visibleBellEnabled = false;
    bool m_visibleBellInvert = true;

    QTimer m_periodicTimer;
};
