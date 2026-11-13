cmake_minimum_required(VERSION 3.16)
project(SourcelessControlCenter VERSION 1.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
find_package(KF6 REQUIRED COMPONENTS CoreAddons I18n Kirigami KCMUtils)

include(KDEInstallDirs)
include(KDECMakeSettings)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

# Register ControlCenter.qml at the module root (no subdirectory),
# which avoids the QTP0004 warning. Must come before qt_add_qml_module.
set_source_files_properties(src/ControlCenter.qml
    PROPERTIES QT_RESOURCE_ALIAS ControlCenter.qml)

qt_add_executable(sourceless-control-center
    src/main.cpp
    src/SystemBackend.h
    src/SystemBackend.cpp
)

qt_add_qml_module(sourceless-control-center
    URI Sourceless.Settings
    VERSION 1.0
    QML_FILES src/ControlCenter.qml
)

qt_add_resources(sourceless-control-center "cyber_icons"
    PREFIX "/icons"
    BASE "src/icons"
    FILES
        src/icons/sourceless-control-center.svg
        src/icons/search.svg
        src/icons/home.svg
        src/icons/system.svg
        src/icons/bluetooth.svg
        src/icons/network.svg
        src/icons/network-connected.svg
        src/icons/network-offline.svg
        src/icons/personalization.svg
        src/icons/apps.svg
        src/icons/time.svg
        src/icons/security-high.svg
        src/icons/security-scan.svg
        src/icons/security-low.svg
        src/icons/audio-high.svg
        src/icons/audio-muted.svg
        src/icons/audio-speakers.svg
        src/icons/mic.svg
        src/icons/display.svg
        src/icons/scale.svg
        src/icons/night-light.svg
        src/icons/power.svg
        src/icons/storage.svg
        src/icons/mouse.svg
        src/icons/terminal.svg
)

target_link_libraries(sourceless-control-center PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2
    KF6::CoreAddons KF6::I18n KF6::Kirigami KF6::KCMUtils
)

install(TARGETS sourceless-control-center ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
