# joe Linux's installer: a Qt Quick front end to `dave install-system`.
cmake_minimum_required(VERSION 3.21)
project(joe-installer VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(joe-installer
    src/main.cpp
    src/backend.cpp src/backend.h
    src/diskmodel.cpp src/diskmodel.h
)

# The pages live in qml/ but belong at the module's root, where they see
# each other and the module's C++ types without an import.
file(GLOB qml_files RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} qml/*.qml)
foreach(file IN LISTS qml_files)
    get_filename_component(name ${file} NAME)
    set_source_files_properties(${file} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(joe-installer
    URI Joe.Installer
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/PageFrame.qml
        qml/ActionButton.qml
        qml/DiskStrip.qml
        qml/WelcomePage.qml
        qml/DiskPage.qml
        qml/ConfirmPage.qml
        qml/CheckOption.qml
        qml/ProgressPage.qml
        qml/DonePage.qml
        qml/FailedPage.qml
)

# Embed any catalogs supplied by translators. English is the source language.
file(GLOB catalogs CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/i18n/joe-installer_*.ts")
if(catalogs)
    find_package(Qt6 REQUIRED COMPONENTS LinguistTools)
    qt_add_translations(joe-installer TS_FILES ${catalogs} RESOURCE_PREFIX "/i18n")
endif()

# The generated QML type registrations include the headers by name.
target_include_directories(joe-installer PRIVATE src)
target_link_libraries(joe-installer PRIVATE Qt6::Quick Qt6::QuickControls2)

include(GNUInstallDirs)
install(TARGETS joe-installer RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/org.joelinux.Installer.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES data/org.joelinux.Installer.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
