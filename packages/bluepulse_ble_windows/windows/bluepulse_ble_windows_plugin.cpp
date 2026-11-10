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
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisement;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementDataSection;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementPublisher;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementPublisherStatus;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementPublisherStatusChangedEventArgs;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEManufacturerData;
using winrt::Windows::Foundation::Metadata::ApiInformation;
using winrt::Windows::Storage::Streams::DataReader;
using winrt::Windows::Storage::Streams::DataWriter;
using winrt::Windows::Storage::Streams::IBuffer;

IBuffer ToBuffer(const std::vector<uint8_t> &bytes) {
  DataWriter writer;
  writer.WriteBytes(winrt::array_view<const uint8_t>(bytes));
  return writer.DetachBuffer();
}

const EncodableValue *Find(const EncodableMap &map, const char *key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

int64_t AsInt(const EncodableValue &v) {
  if (const auto *i = std::get_if<int32_t>(&v)) return *i;
  if (const auto *l = std::get_if<int64_t>(&v)) return *l;
  return 0;
}

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
  AdvertiseStop();
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
  } else if (method == "advertiseStart") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "advertiseStart needs a map");
      return;
    }
    AdvertiseStart(*args, std::move(result));
  } else if (method == "advertiseStop") {
    AdvertiseStop();
    result->Success();
  } else if (method == "advertiseStatus") {
    result->Success(AdvertiseStatus());
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

void BluepulseBleWindowsPlugin::AdvertiseStart(const EncodableMap &args,
                                               std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    AdvertiseStop();
    BluetoothLEAdvertisement advertisement;
    // Manufacturer data: [[companyId, bytes], ...]
    if (const auto *v = Find(args, "manufacturer")) {
      if (const auto *list = std::get_if<EncodableList>(v)) {
        for (const auto &e : *list) {
          const auto *pair = std::get_if<EncodableList>(&e);
          if (pair == nullptr || pair->size() != 2) continue;
          const auto *bytes = std::get_if<std::vector<uint8_t>>(&(*pair)[1]);
          if (bytes == nullptr) continue;
          advertisement.ManufacturerData().Append(
              BluetoothLEManufacturerData(static_cast<uint16_t>(AsInt((*pair)[0])), ToBuffer(*bytes)));
        }
      }
    }
    // Complete list of 16-bit service UUIDs (AD type 0x03), little-endian.
    if (const auto *v = Find(args, "uuids16")) {
      if (const auto *list = std::get_if<EncodableList>(v); list != nullptr && !list->empty()) {
        std::vector<uint8_t> bytes;
        for (const auto &u : *list) {
          const auto id = static_cast<uint16_t>(AsInt(u));
          bytes.push_back(static_cast<uint8_t>(id & 0xFF));
          bytes.push_back(static_cast<uint8_t>(id >> 8));
        }
        advertisement.DataSections().Append(BluetoothLEAdvertisementDataSection(0x03, ToBuffer(bytes)));
      }
    }
    // 16-bit service data (AD type 0x16): [[uuid, bytes], ...]
    if (const auto *v = Find(args, "serviceData16")) {
      if (const auto *list = std::get_if<EncodableList>(v)) {
        for (const auto &e : *list) {
          const auto *pair = std::get_if<EncodableList>(&e);
          if (pair == nullptr || pair->size() != 2) continue;
          const auto *data = std::get_if<std::vector<uint8_t>>(&(*pair)[1]);
          if (data == nullptr) continue;
          const auto id = static_cast<uint16_t>(AsInt((*pair)[0]));
          std::vector<uint8_t> bytes{static_cast<uint8_t>(id & 0xFF), static_cast<uint8_t>(id >> 8)};
          bytes.insert(bytes.end(), data->begin(), data->end());
          advertisement.DataSections().Append(BluetoothLEAdvertisementDataSection(0x16, ToBuffer(bytes)));
        }
      }
    }

    publisher_ = BluetoothLEAdvertisementPublisher(advertisement);
    if (const auto *v = Find(args, "txPowerDbm")) {
      if (!v->IsNull() &&
          ApiInformation::IsPropertyPresent(
              L"Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementPublisher",
              L"PreferredTransmitPowerLevelInDBm")) {
        try {
          publisher_.PreferredTransmitPowerLevelInDBm(
              winrt::Windows::Foundation::IReference<int16_t>(static_cast<int16_t>(AsInt(*v))));
        } catch (...) {
          // The adapter does not take a preferred power: Windows picks it.
        }
      }
    }
    publisher_status_ = -1;
    publisher_error_ = 0;
    publisher_token_ = publisher_.StatusChanged(
        [this](const BluetoothLEAdvertisementPublisher &,
               const BluetoothLEAdvertisementPublisherStatusChangedEventArgs &e) {
          publisher_status_ = static_cast<int32_t>(e.Status());
          publisher_error_ = static_cast<int32_t>(e.Error());
        });
    publisher_.Start();
    publisher_starts_++;
    result->Success(AdvertiseStatus());
  } catch (const winrt::hresult_error &e) {
    publisher_ = nullptr;
    result->Error("start_failed", winrt::to_string(e.message()));
  } catch (...) {
    publisher_ = nullptr;
    result->Error("start_failed", "Windows refused to advertise this packet");
  }
}

void BluepulseBleWindowsPlugin::AdvertiseStop() {
  if (!publisher_) return;
  try {
    publisher_.StatusChanged(publisher_token_);
    publisher_.Stop();
  } catch (...) {
    // Already aborted by Windows.
  }
  publisher_ = nullptr;
}

EncodableValue BluepulseBleWindowsPlugin::AdvertiseStatus() {
  int32_t status = publisher_status_.load();
  if (publisher_ && status < 0) {
    try {
      status = static_cast<int32_t>(publisher_.Status());
    } catch (...) {
    }
  }
  // BluetoothLEAdvertisementPublisherStatus: 0 Created, 1 Waiting, 2 Started, 3 Stopping, 4 Stopped,
  // 5 Aborted. Error: BluetoothError (0 Success, 1 RadioNotAvailable, 2 ResourceInUse, 4
  // DisabledByPolicy, 6 NotSupported, 8 DisabledByUser, ...).
  return EncodableValue(EncodableMap{
      {EncodableValue("status"), EncodableValue(status)},
      {EncodableValue("error"), EncodableValue(publisher_error_.load())},
      {EncodableValue("active"), EncodableValue(static_cast<bool>(publisher_))},
      {EncodableValue("starts"), EncodableValue(static_cast<int64_t>(publisher_starts_.load()))},
  });
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
