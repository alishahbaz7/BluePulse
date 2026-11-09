cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "bluepulse_ble_windows")
project(${PROJECT_NAME} LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "bluepulse_ble_windows_plugin")

list(APPEND PLUGIN_SOURCES
  "bluepulse_ble_windows_plugin.cpp"
  "bluepulse_ble_windows_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/bluepulse_ble_windows/bluepulse_ble_windows_plugin_c_api.h"
  "bluepulse_ble_windows_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

# C++/WinRT comes with the Windows SDK; its headers are large.
target_compile_options(${PLUGIN_NAME} PRIVATE /bigobj /utf-8)

set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin windowsapp)

set(bluepulse_ble_windows_bundled_libraries "" PARENT_SCOPE)
