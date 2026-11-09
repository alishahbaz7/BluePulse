#include "bluepulse_ble_windows_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.Metadata.h>
#include <winrt/Windows.Storage.Streams.h>

#include <iterator>
#include <string>
#include <utility>

namespace bluepulse_ble_windows {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementReceivedEventArgs;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementScanParameters;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEScanningMode;
using winrt::Windows::Foundation::Metadata::ApiInformation;
using winrt::Windows::Storage::Streams::DataReader;

// Private message that tells the platform thread to send queued advertisements to Dart.
constexpr UINT kDrainMessage = WM_APP + 0x2b7;

// If the platform thread stalls, keep at most this many advertisements; the oldest go first.
constexpr size_t kMaxQueue = 20000;

}  // namespace

void BluepulseBleWindowsPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<BluepulseBleWindowsPlugin>(registrar);
  BluepulseBleWindowsPlugin *self = plugin.get();

  self->methods_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "bluepulse_ble_windows", &flutter::StandardMethodCodec::GetInstance());
  self->methods_->SetMethodCallHandler([self](const auto &call, auto result) {
    self->HandleMethodCall(call, std::move(result));
  });

  self->events_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "bluepulse_ble_windows/advertisements",
      &flutter::StandardMethodCodec::GetInstance());
  self->events_->SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
      [self](const EncodableValue *, std::unique_ptr<flutter::EventSink<EncodableValue>> &&sink)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        self->sink_ = std::move(sink);
        return nullptr;
      },
      [self](const EncodableValue *) -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        self->sink_.reset();
        return nullptr;
      }));

  registrar->AddPlugin(std::move(plugin));
}

BluepulseBleWindowsPlugin::BluepulseBleWindowsPlugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  // The top-level window is learned from its own messages (HandleWindowProc): plugins are registered
  // before the Flutter view is parented to it, so asking the view now would give the wrong window.
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

BluepulseBleWindowsPlugin::~BluepulseBleWindowsPlugin() {
  Stop();
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
}

void BluepulseBleWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string &method = call.method_name();
  if (method == "start") {
    bool low_latency = true;
    if (const auto *args = std::get_if<EncodableMap>(call.arguments())) {
      auto it = args->find(EncodableValue("lowLatency"));
      if (it != args->end()) {
        if (const auto *b = std::get_if<bool>(&it->second)) low_latency = *b;
      }
    }
    Start(low_latency, std::move(result));
  } else if (method == "stop") {
    Stop();
    result->Success();
  } else if (method == "stats") {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("received"), EncodableValue(static_cast<int64_t>(received_.load()))},
        {EncodableValue("dropped"), EncodableValue(static_cast<int64_t>(dropped_.load()))},
        {EncodableValue("scanning"), EncodableValue(static_cast<bool>(watcher_))},
    }));
  } else {
    result->NotImplemented();
  }
}

void BluepulseBleWindowsPlugin::Start(bool low_latency,
                                      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    Stop();
    watcher_ = BluetoothLEAdvertisementWatcher();
    // Active: ask for the scan response too (EYE devices put their name and data there).
    watcher_.ScanningMode(BluetoothLEScanningMode::Active);
    try {
      watcher_.AllowExtendedAdvertisements(true);
    } catch (...) {
      // Windows before 10.0.19041 or a Bluetooth 4 adapter: legacy advertisements only.
    }
    bool low_latency_applied = false;
    if (low_latency &&
        ApiInformation::IsPropertyPresent(
            L"Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementWatcher", L"ScanParameters")) {
      try {
        watcher_.ScanParameters(BluetoothLEAdvertisementScanParameters::LowLatency());
        low_latency_applied = true;
      } catch (...) {
        // The driver or Windows build refuses it; default scanning continues.
      }
    }
    received_token_ = watcher_.Received(
        [this](const BluetoothLEAdvertisementWatcher &, const BluetoothLEAdvertisementReceivedEventArgs &args) {
          OnReceived(args);
        });
    watcher_.Start();
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("lowLatency"), EncodableValue(low_latency_applied)},
    }));
  } catch (const winrt::hresult_error &e) {
    watcher_ = nullptr;
    result->Error("start_failed", winrt::to_string(e.message()));
  } catch (...) {
    watcher_ = nullptr;
    result->Error("start_failed", "Bluetooth scanning could not start");
  }
}

void BluepulseBleWindowsPlugin::Stop() {
  if (!watcher_) return;
  try {
    watcher_.Received(received_token_);
    watcher_.Stop();
  } catch (...) {
    // Stopping a watcher Windows already aborted is not a failure.
  }
  watcher_ = nullptr;
}

void BluepulseBleWindowsPlugin::OnReceived(const BluetoothLEAdvertisementReceivedEventArgs &args) {
  received_++;
  EncodableList sections;
  try {
    for (const auto &section : args.Advertisement().DataSections()) {
      const auto buffer = section.Data();
      std::vector<uint8_t> bytes(buffer.Length());
      if (!bytes.empty()) DataReader::FromBuffer(buffer).ReadBytes(bytes);
      sections.emplace_back(EncodableList{
          EncodableValue(static_cast<int32_t>(section.DataType())),
          EncodableValue(std::move(bytes)),
      });
    }
  } catch (...) {
    return;
  }
  Enqueue(EncodableValue(EncodableMap{
      {EncodableValue("a"), EncodableValue(static_cast<int64_t>(args.BluetoothAddress()))},
      {EncodableValue("r"), EncodableValue(static_cast<int32_t>(args.RawSignalStrengthInDBm()))},
      {EncodableValue("t"), EncodableValue(static_cast<int32_t>(args.AdvertisementType()))},
      {EncodableValue("s"), EncodableValue(std::move(sections))},
  }));
}

void BluepulseBleWindowsPlugin::Enqueue(EncodableValue &&value) {
  bool post = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (queue_.size() >= kMaxQueue) {
      queue_.erase(queue_.begin());
      dropped_++;
    }
    queue_.push_back(std::move(value));
    if (!posted_) {
      posted_ = true;
      post = true;
    }
  }
  if (!post) return;
  const HWND window = hwnd_.load();
  if (window == nullptr || !PostMessage(window, kDrainMessage, 0, reinterpret_cast<LPARAM>(this))) {
    std::lock_guard<std::mutex> lock(mutex_);
    posted_ = false;  // the next window message will learn the handle and drain
  }
}

std::optional<LRESULT> BluepulseBleWindowsPlugin::HandleWindowProc(HWND hwnd, UINT message, WPARAM,
                                                                   LPARAM lparam) {
  hwnd_ = hwnd;  // only the top-level window's messages come here
  if (message == kDrainMessage && lparam == reinterpret_cast<LPARAM>(this)) {
    Drain();
    return 0;
  }
  // Safety net: any other message on the platform thread also delivers what is waiting, so a lost or
  // not-yet-postable drain message can never strand advertisements.
  bool pending = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    pending = !queue_.empty();
  }
  if (pending) Drain();
  return std::nullopt;
}

void BluepulseBleWindowsPlugin::Drain() {
  std::vector<EncodableValue> batch;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    batch.swap(queue_);
    posted_ = false;
  }
  if (sink_ && !batch.empty()) {
    sink_->Success(EncodableValue(
        EncodableList(std::make_move_iterator(batch.begin()), std::make_move_iterator(batch.end()))));
  }
}

}  // namespace bluepulse_ble_windows
