package com.mapmyindia.bluepulse.bluepulse_ble_android;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/**
 * Keeps a BluePulse scan running when the app is not on screen: a foreground service with a
 * notification ("BluePulse is scanning"), so Android treats the scan as work the person asked for
 * rather than a background app's. The scan itself stays in the app; this service only holds the
 * process in the foreground. Started from Start scan (the app is on screen then), stopped by Stop
 * scan or when the app closes.
 */
public class ScanKeepAliveService extends Service {
  static final String CHANNEL = "bluepulse_scan";
  static final int NOTIFICATION_ID = 0xB1E5;
  static final String EXTRA_TEXT = "text";

  static void start(Context context, String text) {
    Intent i = new Intent(context, ScanKeepAliveService.class).putExtra(EXTRA_TEXT, text);
    if (Build.VERSION.SDK_INT >= 26) {
      context.startForegroundService(i);
    } else {
      context.startService(i);
    }
  }

  static void stop(Context context) {
    context.stopService(new Intent(context, ScanKeepAliveService.class));
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    String text = intent == null ? null : intent.getStringExtra(EXTRA_TEXT);
    Notification n = notification(text == null ? "Scanning for EYE devices and beacons" : text);
    if (Build.VERSION.SDK_INT >= 29) {
      startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
    } else {
      startForeground(NOTIFICATION_ID, n);
    }
    // Not restarted if Android stops it: a scan restarted without the app would have nowhere to go.
    return START_NOT_STICKY;
  }

  private Notification notification(String text) {
    NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
    Notification.Builder b;
    if (Build.VERSION.SDK_INT >= 26) {
      if (nm != null && nm.getNotificationChannel(CHANNEL) == null) {
        NotificationChannel ch = new NotificationChannel(CHANNEL, "Scanning", NotificationManager.IMPORTANCE_LOW);
        ch.setDescription("Shown while BluePulse scans, so the scan carries on with the screen off");
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);
      }
      b = new Notification.Builder(this, CHANNEL);
    } else {
      b = new Notification.Builder(this);
    }
    Intent open = getPackageManager().getLaunchIntentForPackage(getPackageName());
    if (open != null) {
      open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
      b.setContentIntent(PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE));
    }
    return b.setSmallIcon(getApplicationInfo().icon)
        .setContentTitle("BluePulse is scanning")
        .setContentText(text)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .build();
  }

  @Override
  public IBinder onBind(Intent intent) {
    return null;
  }
}
