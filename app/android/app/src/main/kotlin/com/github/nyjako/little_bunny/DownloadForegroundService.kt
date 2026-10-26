package com.github.nyjako.little_bunny

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

// Keeps the download queue (DownloadQueueService, M43) running through a
// locked screen (M57) -- a foreground Service is the only thing that
// reliably stops Android from killing the process once the Activity goes
// to the background, which a locked screen does immediately. The actual
// download work (HTTP fetch + file write) stays entirely on the Dart side,
// unchanged; this service exists purely to hold the "don't kill me"
// foreground-service notification Android requires in exchange for that.
//
// Reuses the exact same notification channel/id
// FlutterLocalNotificationsQueueNotifier (app/lib/services/
// flutter_local_notifications_queue_notifier.dart) already uses on every
// other platform, so this is the same notification the user already sees,
// not a second, duplicate one.
class DownloadForegroundService : Service() {
    companion object {
        const val ACTION_UPDATE_PROGRESS = "com.github.nyjako.little_bunny.action.UPDATE_PROGRESS"
        const val ACTION_SHOW_SUMMARY = "com.github.nyjako.little_bunny.action.SHOW_SUMMARY"
        const val ACTION_CLEAR = "com.github.nyjako.little_bunny.action.CLEAR"
        const val EXTRA_DONE = "done"
        const val EXTRA_TOTAL = "total"
        const val EXTRA_SUCCEEDED = "succeeded"
        const val EXTRA_MISMATCHED = "mismatched"
        const val EXTRA_FAILED = "failed"

        private const val CHANNEL_ID = "download_queue"
        private const val CHANNEL_NAME = "Downloads"
        private const val NOTIFICATION_ID = 424300
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW))
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UPDATE_PROGRESS -> {
                val done = intent.getIntExtra(EXTRA_DONE, 0)
                val total = intent.getIntExtra(EXTRA_TOTAL, 0)
                startForegroundCompat(progressNotification(done, total))
            }
            ACTION_SHOW_SUMMARY -> {
                val succeeded = intent.getIntExtra(EXTRA_SUCCEEDED, 0)
                val mismatched = intent.getIntExtra(EXTRA_MISMATCHED, 0)
                val failed = intent.getIntExtra(EXTRA_FAILED, 0)
                startForegroundCompat(summaryNotification(succeeded, mismatched, failed))
                // DETACH leaves the notification itself posted (matching every
                // other platform's FlutterLocalNotificationsQueueNotifier.
                // showSummary, which also leaves a dismissible notification up)
                // while ending the foreground-service guarantee, since the
                // queue has fully drained and there's nothing left to protect.
                stopForeground(STOP_FOREGROUND_DETACH)
                stopSelf(startId)
            }
            ACTION_CLEAR -> {
                startForegroundCompat(summaryNotification(0, 0, 0))
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    private fun startForegroundCompat(notification: Notification) {
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0,
        )
    }

    private fun progressNotification(done: Int, total: Int): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Downloading")
            .setContentText("$done of $total")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(total, done, false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun summaryNotification(succeeded: Int, mismatched: Int, failed: Int): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Downloads finished")
            .setContentText("$succeeded downloaded, $mismatched checksum mismatch, $failed failed")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    override fun onBind(intent: Intent?): IBinder? = null
}
