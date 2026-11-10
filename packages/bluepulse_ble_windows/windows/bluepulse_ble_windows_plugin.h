#ifndef FLUTTER_PLUGIN_BLUEPULSE_BLE_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_BLUEPULSE_BLE_WINDOWS_PLUGIN_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <vector>

namespace bluepulse_ble_windows {

// Scans BLE advertisements with the WinRT watcher in active mode and hands EVERY advertisement and
// scan response to Dart exactly as received (address, RSSI, type, raw AD sections) — no caching, no
// de-duplication, no merging. Events arrive on WinRT thread-pool threads; they are queued and sent
// to Dart in batches on the platform thread.
class BluepulseBleWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit BluepulseBleWindowsPlugin(flutter::PluginRegistrarWindows *registrar);
  virtual ~BluepulseBleWindowsPlugin();

  BluepulseBleWindowsPlugin(const BluepulseBleWindowsPlugin &) = delete;
  BluepulseBleWindowsPlugin &operator=(const BluepulseBleWindowsPlugin &) = delete;

 private:
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue> &call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Start(bool low_latency, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Stop();
  void OnReceived(
      const winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementReceivedEventArgs &args);
  void Enqueue(flutter::EncodableValue &&value);

  // Transmitting: one publisher advertising the payload Dart built (a simulated EYE device or beacon).
  void AdvertiseStart(const flutter::EncodableMap &args,
                      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void AdvertiseStop();
  flutter::EncodableValue AdvertiseStatus();

  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void Drain();

  flutter::PluginRegistrarWindows *registrar_;
  int window_proc_id_ = -1;
  std::atomic<HWND> hwnd_{nullptr};

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> methods_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;

  winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher watcher_{nullptr};
  winrt::event_token received_token_{};

  std::mutex mutex_;
  std::vector<flutter::EncodableValue> queue_;
  bool posted_ = false;
  std::atomic<uint64_t> received_{0};
  std::atomic<uint64_t> dropped_{0};

  winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementPublisher publisher_{nullptr};
  winrt::event_token publisher_token_{};
  std::atomic<int32_t> publisher_status_{-1};
  std::atomic<int32_t> publisher_error_{0};
  std::atomic<uint64_t> publisher_starts_{0};
};

}  // namespace bluepulse_ble_windows

#endif  // FLUTTER_PLUGIN_BLUEPULSE_BLE_WINDOWS_PLUGIN_H_
