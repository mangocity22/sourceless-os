cmake_minimum_required(VERSION 3.16)
project(SourcelessControlCenter VERSION 1.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

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

qt_add_executable(sourceless-control-center src/main.cpp)

qt_add_qml_module(sourceless-control-center
    URI Sourceless.Settings
    VERSION 1.0
    QML_FILES src/ControlCenter.qml
)

target_link_libraries(sourceless-control-center PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2
    KF6::CoreAddons KF6::I18n KF6::Kirigami KF6::KCMUtils
)

install(TARGETS sourceless-control-center ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})