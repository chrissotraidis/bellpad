cmake_minimum_required(VERSION 3.25)

project(Bellpad LANGUAGES CXX OBJCXX)

if(NOT APPLE)
    message(FATAL_ERROR "Bellpad's product targets currently require an Apple platform.")
endif()

add_library(bellpad_platform_core STATIC
    src/platform/BellpadDiscValidator.cpp
    src/platform/BellpadInput.cpp
)
target_include_directories(bellpad_platform_core PUBLIC src/platform)
target_compile_features(bellpad_platform_core PUBLIC cxx_std_20)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    add_executable(Bellpad MACOSX_BUNDLE
        apple/ios/BellpadIOSApp.mm
    )
    set_target_properties(Bellpad PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/apple/ios/Info.plist"
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "dev.bellpad.app"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    )
    target_link_libraries(Bellpad PRIVATE
        bellpad_platform_core
        "-framework Foundation"
        "-framework CoreGraphics"
        "-framework QuartzCore"
        "-framework UIKit"
        "-framework Metal"
        "-framework MetalKit"
        "-framework GameController"
        "-framework UniformTypeIdentifiers"
    )
else()
    add_executable(Bellpad MACOSX_BUNDLE
        apple/macos/BellpadMacApp.mm
    )
    set_target_properties(Bellpad PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/apple/macos/Info.plist"
        MACOSX_BUNDLE_BUNDLE_NAME "Bellpad"
        MACOSX_BUNDLE_GUI_IDENTIFIER "dev.bellpad.app"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
        MACOSX_BUNDLE_BUNDLE_VERSION "1"
    )
    target_link_libraries(Bellpad PRIVATE
        bellpad_platform_core
        "-framework AppKit"
        "-framework Metal"
        "-framework MetalKit"
        "-framework GameController"
        "-framework UniformTypeIdentifiers"
    )
endif()

target_compile_options(Bellpad PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    include(CTest)
    if(BUILD_TESTING)
        add_executable(bellpad_input_tests tests/BellpadInputTests.cpp)
        target_link_libraries(bellpad_input_tests PRIVATE bellpad_platform_core)
        add_test(NAME bellpad_input_merge COMMAND bellpad_input_tests)
    endif()
endif()
