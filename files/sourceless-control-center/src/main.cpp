#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <KLocalizedContext>

#include "SystemBackend.h"

static QString resolveInitialPage(const QStringList &args)
{
    for (int i = 1; i < args.size(); ++i) {
        const QString arg = args.at(i).toLower();
        if (arg == QStringLiteral("--page") && i + 1 < args.size()) {
            return args.at(i + 1).toLower();
        }
        if (arg.contains(QStringLiteral("network")) || arg.contains(QStringLiteral("wifi")) || arg.contains(QStringLiteral("netpref"))) {
            return QStringLiteral("network");
        }
        if (arg.contains(QStringLiteral("bluetooth")) || arg.contains(QStringLiteral("mouse")) || arg.contains(QStringLiteral("touchpad"))) {
            return QStringLiteral("bluetooth");
        }
        if (arg.contains(QStringLiteral("audio")) || arg.contains(QStringLiteral("sound")) || arg.contains(QStringLiteral("pulse")) ||
            arg.contains(QStringLiteral("kscreen")) || arg.contains(QStringLiteral("display")) || arg.contains(QStringLiteral("power")) ||
            arg.contains(QStringLiteral("about"))) {
            return QStringLiteral("system");
        }
        if (arg.contains(QStringLiteral("wallpaper")) || arg.contains(QStringLiteral("lookandfeel")) || arg.contains(QStringLiteral("theme")) ||
            arg.contains(QStringLiteral("style")) || arg.contains(QStringLiteral("colors"))) {
            return QStringLiteral("personalization");
        }
        if (arg.contains(QStringLiteral("clock")) || arg.contains(QStringLiteral("time")) || arg.contains(QStringLiteral("keyboard")) ||
            arg.contains(QStringLiteral("region")) || arg.contains(QStringLiteral("translations"))) {
            return QStringLiteral("time");
        }
        if (arg.contains(QStringLiteral("flatpak")) || arg.contains(QStringLiteral("app"))) {
            return QStringLiteral("apps");
        }
        if (arg.contains(QStringLiteral("security")) || arg.contains(QStringLiteral("firewall"))) {
            return QStringLiteral("security");
        }
    }
    return QStringLiteral("home");
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    app.setOrganizationName(QStringLiteral("Sourceless NCH"));
    app.setApplicationName(QStringLiteral("SourcelessControlCenter"));
    app.setApplicationDisplayName(QStringLiteral("Sourceless Control Center"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("preferences-system")));

    const QString startPage = resolveInitialPage(app.arguments());
    SystemBackend backend(startPage);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);

    engine.loadFromModule("Sourceless.Settings", "ControlCenter");

    return app.exec();
}
