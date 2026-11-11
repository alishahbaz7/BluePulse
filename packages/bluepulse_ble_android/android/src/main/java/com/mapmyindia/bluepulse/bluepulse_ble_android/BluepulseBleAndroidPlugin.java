package com.mapmyindia.bluepulse.bluepulse_ble_android;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.AdvertiseData;
import android.bluetooth.le.AdvertisingSet;
import android.bluetooth.le.AdvertisingSetCallback;
import android.bluetooth.le.AdvertisingSetParameters;
import android.bluetooth.le.BluetoothLeAdvertiser;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

/**
 * BluePulse's BLE transmitter on Android: advertises a simulated EYE device or beacon with an
 * exact interval and transmit power (AdvertisingSet, Android 8+), updates its data while it runs,
 * and can advertise a chosen name by renaming the phone's Bluetooth for as long as it transmits.
 * The original name is saved before renaming and put back on stop — also at the next start of the
 * app if it was closed while transmitting.
 */
public class BluepulseBleAndroidPlugin
    implements FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

  private static final String PREFS = "bluepulse_ble_tx";
  private static final String KEY_ORIGINAL_NAME = "originalName";
  private static final int PERMISSION_REQUEST = 0xB1E7;
  private static final int NOTIFICATION_REQUEST = 0xB1E8;

  private MethodChannel channel;
  private Context context;
  private ActivityPluginBinding activity;
  private final Handler main = new Handler(Looper.getMainLooper());

  private Result pendingPermission;
  private Result pendingStart;
  private AdvertisingSet set;
  private AdvertisingSetCallback callback;

  /** The name just given back to the phone, until Android reports it (renaming takes a moment). */
  private String restoring;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    channel = new MethodChannel(binding.getBinaryMessenger(), "bluepulse_ble_android");
    channel.setMethodCallHandler(this);
    restoreNameIfLeftChanged();
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    stopAdvertising(true);
    ScanKeepAliveService.stop(context);
    channel.setMethodCallHandler(null);
  }

  // ActivityAware: permissions are asked through the activity.
  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activity = binding;
    binding.addRequestPermissionsResultListener(this);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    if (activity != null) activity.removeRequestPermissionsResultListener(this);
    activity = null;
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    try {
      switch (call.method) {
        case "capabilities":
          result.success(capabilities());
          break;
        case "requestPermissions":
          requestPermissions(result);
          break;
        case "start":
          start(call, result);
          break;
        case "update":
          update(call, result);
          break;
        case "stop":
          stopAdvertising(true);
          result.success(null);
          break;
        case "keepAliveStart":
          keepAliveStart(call.argument("text"));
          result.success(null);
          break;
        case "keepAliveStop":
          ScanKeepAliveService.stop(context);
          result.success(null);
          break;
        default:
          result.notImplemented();
      }
    } catch (SecurityException e) {
      result.error("permission", "Bluetooth permission was refused: " + e.getMessage(), null);
    } catch (Exception e) {
      result.error("failed", e.getClass().getSimpleName() + ": " + e.getMessage(), null);
    }
  }

  /**
   * Holds the app in the foreground while it scans (see ScanKeepAliveService). Android 13+ shows
   * the notification only with permission, asked once here; without it the service still runs.
   */
  private void keepAliveStart(String text) {
    if (Build.VERSION.SDK_INT >= 33
        && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        && activity != null) {
      activity.getActivity().requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, NOTIFICATION_REQUEST);
    }
    ScanKeepAliveService.start(context, text);
  }

  private BluetoothAdapter adapter() {
    BluetoothManager m = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
    return m == null ? null : m.getAdapter();
  }

  private String[] neededPermissions() {
    if (Build.VERSION.SDK_INT >= 31) {
      return new String[] {Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT};
    }
    return new String[0]; // BLUETOOTH / BLUETOOTH_ADMIN are granted at install before Android 12
  }

  private boolean permitted() {
    for (String p : neededPermissions()) {
      if (context.checkSelfPermission(p) != PackageManager.PERMISSION_GRANTED) return false;
    }
    return true;
  }

  @SuppressLint("MissingPermission")
  private Map<String, Object> capabilities() {
    Map<String, Object> m = new HashMap<>();
    BluetoothAdapter a = adapter();
    String reason = null;
    if (a == null) {
      reason = "This phone has no Bluetooth";
    } else if (Build.VERSION.SDK_INT < 26) {
      reason = "Transmitting needs Android 8 or later";
    }
    boolean on = a != null && a.isEnabled();
    m.put("bluetoothOn", on);
    m.put("permitted", permitted());
    if (reason == null && on && !a.isMultipleAdvertisementSupported()) {
      reason = "This phone's Bluetooth cannot advertise";
    }
    m.put("supported", reason == null);
    m.put("reason", reason);
    if (a != null && Build.VERSION.SDK_INT >= 26 && on) {
      m.put("extended", a.isLeExtendedAdvertisingSupported());
      m.put("maxDataLength", a.getLeMaximumAdvertisingDataLength());
    }
    m.put("sdk", Build.VERSION.SDK_INT);
    return m;
  }

  private void requestPermissions(Result result) {
    if (permitted()) {
      result.success(true);
      return;
    }
    Activity a = activity == null ? null : activity.getActivity();
    if (a == null) {
      result.error("no_activity", "Permissions can only be asked while the app is open", null);
      return;
    }
    pendingPermission = result;
    a.requestPermissions(neededPermissions(), PERMISSION_REQUEST);
  }

  @Override
  public boolean onRequestPermissionsResult(int code, @NonNull String[] permissions, @NonNull int[] results) {
    if (code != PERMISSION_REQUEST || pendingPermission == null) return false;
    boolean all = results.length > 0;
    for (int r : results) all &= r == PackageManager.PERMISSION_GRANTED;
    pendingPermission.success(all);
    pendingPermission = null;
    return true;
  }

  @SuppressLint("MissingPermission")
  private void start(MethodCall call, Result result) {
    BluetoothAdapter a = adapter();
    if (a == null) {
      result.error("unsupported", "This phone has no Bluetooth", null);
      return;
    }
    if (Build.VERSION.SDK_INT < 26) {
      result.error("unsupported", "Transmitting needs Android 8 or later", null);
      return;
    }
    if (!a.isEnabled()) {
      result.error("bluetooth_off", "Bluetooth is off", null);
      return;
    }
    if (!permitted()) {
      result.error("permission", "Bluetooth advertise permission is needed", null);
      return;
    }
    final BluetoothLeAdvertiser advertiser = a.getBluetoothLeAdvertiser();
    if (advertiser == null || !a.isMultipleAdvertisementSupported()) {
      result.error("unsupported", "This phone's Bluetooth cannot advertise", null);
      return;
    }
    // A new start replaces the running set without giving the phone its name back first: restoring
    // and renaming again at once raced, and could save the simulated name as the phone's own.
    stopAdvertising(false);

    final Map<String, Object> adv = call.argument("adv");
    final Map<String, Object> sr = call.argument("scanResponse");
    final Integer intervalMs = call.argument("intervalMs");
    final Integer txPower = call.argument("txPowerDbm");
    final String name = call.argument("name");

    final AdvertisingSetParameters params = new AdvertisingSetParameters.Builder()
        .setLegacyMode(true)
        .setConnectable(false)
        .setScannable(sr != null)
        .setInterval(intervalUnits(intervalMs == null ? 1000 : intervalMs))
        .setTxPowerLevel(clamp(txPower == null ? AdvertisingSetParameters.TX_POWER_MEDIUM : txPower, -127, 1))
        .build();

    pendingStart = result;
    callback = new AdvertisingSetCallback() {
      @Override
      public void onAdvertisingSetStarted(AdvertisingSet s, int txPowerDbm, int status) {
        Result r = pendingStart;
        pendingStart = null;
        if (status == AdvertisingSetCallback.ADVERTISE_SUCCESS) {
          set = s;
          if (r != null) {
            Map<String, Object> m = new HashMap<>();
            m.put("txPowerDbm", txPowerDbm);
            m.put("name", currentName());
            r.success(m);
          }
        } else {
          callback = null;
          restoreName();
          if (r != null) r.error(statusCode(status), statusText(status), null);
        }
      }

      @Override
      public void onAdvertisingDataSet(AdvertisingSet s, int status) {
        if (status != AdvertisingSetCallback.ADVERTISE_SUCCESS) report(statusText(status));
      }

      @Override
      public void onScanResponseDataSet(AdvertisingSet s, int status) {
        if (status != AdvertisingSetCallback.ADVERTISE_SUCCESS) report(statusText(status));
      }

      @Override
      public void onAdvertisingSetStopped(AdvertisingSet s) {
        if (set == s) set = null;
      }
    };

    final boolean wantsName = name != null && !name.isEmpty();
    final AdvertisingSetCallback cb = callback;
    if (!wantsName) restoreName();
    if (wantsName && !name.equals(a.getName())) {
      saveOriginalName(a.getName());
      a.setName(name);
      // The new name takes a moment to apply; advertising before it does would send the old one.
      waitForName(a, name, 20, () -> begin(advertiser, params, adv, sr, cb));
    } else {
      begin(advertiser, params, adv, sr, cb);
    }
  }

  @SuppressLint("MissingPermission")
  private void begin(BluetoothLeAdvertiser advertiser, AdvertisingSetParameters params, Map<String, Object> adv,
      Map<String, Object> sr, AdvertisingSetCallback cb) {
    if (cb != callback) return; // stopped while the name was applying
    try {
      advertiser.startAdvertisingSet(params, data(adv), sr == null ? null : data(sr), null, null, cb);
    } catch (Exception e) {
      Result r = pendingStart;
      pendingStart = null;
      callback = null;
      restoreName();
      if (r != null) r.error("failed", e.getClass().getSimpleName() + ": " + e.getMessage(), null);
    }
  }

  @SuppressLint("MissingPermission")
  private void waitForName(BluetoothAdapter a, String name, int triesLeft, Runnable then) {
    if (triesLeft <= 0 || name.equals(a.getName())) {
      then.run();
      return;
    }
    main.postDelayed(() -> waitForName(a, name, triesLeft - 1, then), 100);
  }

  @SuppressLint("MissingPermission")
  private void update(MethodCall call, Result result) {
    if (set == null) {
      result.error("not_started", "Not transmitting", null);
      return;
    }
    Map<String, Object> adv = call.argument("adv");
    Map<String, Object> sr = call.argument("scanResponse");
    if (adv != null) set.setAdvertisingData(data(adv));
    if (sr != null) set.setScanResponseData(data(sr));
    result.success(null);
  }

  /** Stops the running set; {@code restore} gives the phone its own name back (not when a new start follows). */
  @SuppressLint("MissingPermission")
  private void stopAdvertising(boolean restore) {
    BluetoothAdapter a = adapter();
    if (callback != null && a != null && a.getBluetoothLeAdvertiser() != null) {
      try {
        a.getBluetoothLeAdvertiser().stopAdvertisingSet(callback);
      } catch (Exception ignored) {
        // Bluetooth already off: nothing is transmitting.
      }
    }
    callback = null;
    set = null;
    if (pendingStart != null) {
      pendingStart.error("stopped", "Stopped before it started", null);
      pendingStart = null;
    }
    if (restore) restoreName();
  }

  /** One packet's fields as Android advertising data. Flags are added by Android only when connectable. */
  @SuppressWarnings("unchecked")
  private static AdvertiseData data(Map<String, Object> m) {
    AdvertiseData.Builder b = new AdvertiseData.Builder();
    b.setIncludeTxPowerLevel(false);
    b.setIncludeDeviceName(Boolean.TRUE.equals(m.get("includeName")));
    List<Object> uuids = (List<Object>) m.get("uuids16");
    if (uuids != null) for (Object u : uuids) b.addServiceUuid(uuid16(((Number) u).intValue()));
    List<Object> svc = (List<Object>) m.get("serviceData16");
    if (svc != null) {
      for (Object e : svc) {
        List<Object> pair = (List<Object>) e;
        b.addServiceData(uuid16(((Number) pair.get(0)).intValue()), (byte[]) pair.get(1));
      }
    }
    List<Object> mfr = (List<Object>) m.get("manufacturer");
    if (mfr != null) {
      for (Object e : mfr) {
        List<Object> pair = (List<Object>) e;
        b.addManufacturerData(((Number) pair.get(0)).intValue(), (byte[]) pair.get(1));
      }
    }
    return b.build();
  }

  private static ParcelUuid uuid16(int u) {
    return ParcelUuid.fromString(String.format(Locale.ROOT, "0000%04x-0000-1000-8000-00805f9b34fb", u & 0xFFFF));
  }

  /** Milliseconds to the 0.625 ms units Android takes: 100 ms up to about 10.5 s and beyond. */
  private static int intervalUnits(int ms) {
    return clamp((int) Math.round(ms / 0.625), AdvertisingSetParameters.INTERVAL_MIN, 16777215);
  }

  private static int clamp(int v, int lo, int hi) {
    return Math.max(lo, Math.min(hi, v));
  }

  private void report(String message) {
    main.post(() -> {
      if (channel != null) channel.invokeMethod("error", message);
    });
  }

  @SuppressLint("MissingPermission")
  private String currentName() {
    BluetoothAdapter a = adapter();
    try {
      return a == null ? null : a.getName();
    } catch (SecurityException e) {
      return null;
    }
  }

  private SharedPreferences prefs() {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
  }

  private void saveOriginalName(String current) {
    // Keep the first original: renaming twice must not save the simulated name as the original.
    if (prefs().contains(KEY_ORIGINAL_NAME)) return;
    // Stop then Start again quickly: Android may still report the simulated name while the phone's
    // own is being put back, so the name being put back is the original.
    if (restoring != null && restoring.equals(current)) restoring = null;
    String original = restoring != null ? restoring : current;
    if (original != null) prefs().edit().putString(KEY_ORIGINAL_NAME, original).apply();
  }

  @SuppressLint("MissingPermission")
  private void restoreName() {
    String original = prefs().getString(KEY_ORIGINAL_NAME, null);
    if (original == null) return;
    BluetoothAdapter a = adapter();
    try {
      if (a != null && a.isEnabled()) {
        a.setName(original);
        restoring = original;
        prefs().edit().remove(KEY_ORIGINAL_NAME).apply();
      }
    } catch (SecurityException ignored) {
      // Without the permission the name stays saved and is put back next time.
    }
  }

  private void restoreNameIfLeftChanged() {
    if (Build.VERSION.SDK_INT >= 31
        && context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
      return;
    }
    restoreName();
  }

  private static String statusCode(int status) {
    switch (status) {
      case AdvertisingSetCallback.ADVERTISE_FAILED_DATA_TOO_LARGE:
        return "too_large";
      case AdvertisingSetCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS:
        return "busy";
      case AdvertisingSetCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED:
        return "unsupported";
      default:
        return "failed";
    }
  }

  private static String statusText(int status) {
    switch (status) {
      case AdvertisingSetCallback.ADVERTISE_FAILED_DATA_TOO_LARGE:
        return "The packet is larger than 31 bytes; shorten the name";
      case AdvertisingSetCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS:
        return "Bluetooth has no free advertiser; another app is advertising";
      case AdvertisingSetCallback.ADVERTISE_FAILED_ALREADY_STARTED:
        return "Already transmitting";
      case AdvertisingSetCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED:
        return "This phone's Bluetooth does not support this advertising";
      default:
        return "Bluetooth refused to transmit (internal error " + status + ")";
    }
  }
}
