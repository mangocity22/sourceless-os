cmake_minimum_required(VERSION 3.16)
project(SourcelessControlCenter VERSION 1.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Găsim Qt6 și componentele necesare
find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick Controls)
find_package(KF6 REQUIRED COMPONENTS CoreAddons I18n Kirigami KCMUtils)

qt_add_executable(sourceless-control-center src/main.cpp)

# Încărcăm resursele QML
qt_add_qml_module(sourceless-control-center
    URI Sourceless.Settings
    VERSION 1.0
    QML_FILES src/ControlCenter.qml
)

target_link_libraries(sourceless-control-center PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Controls
    KF6::CoreAddons KF6::I18n KF6::Kirigami KF6::KCMUtils
)

install(TARGETS sourceless-control-center ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})