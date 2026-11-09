#include "include/bluepulse_ble_windows/bluepulse_ble_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "bluepulse_ble_windows_plugin.h"

void BluepulseBleWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  bluepulse_ble_windows::BluepulseBleWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
