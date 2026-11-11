#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <KLocalizedContext>

int main(int argc, char *argv[])
{
    // Permitem randarea nativă Wayland/X11 și transparența ferestrelor
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan); // Sau OpenGL, automat de obicei
    QGuiApplication app(argc, argv);
    
    app.setOrganizationName("Sourceless NCH");
    app.setApplicationName("SourcelessControlCenter");

    QQmlApplicationEngine engine;
    
    // Conectăm sistemul la contextul KDE
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));

    const QUrl url(u"qrc:/qt/qml/Sourceless/Settings/src/ControlCenter.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    
    engine.load(url);

    return app.exec();
}