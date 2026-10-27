package com.github.nyjako.little_bunny

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) -- local_auth's BiometricPrompt
// needs a FragmentActivity to host its dialog fragment (M7.4, app-lock).
class MainActivity : FlutterFragmentActivity() {
    // M57 -- backs AndroidForegroundServiceQueueNotifier (app/lib/services/
    // android_foreground_service_queue_notifier.dart), the only bridge this
    // app has from Dart into DownloadForegroundService.
    private val downloadForegroundServiceChannel = "little_bunny/download_foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadForegroundServiceChannel).setMethodCallHandler { call, result ->
            val intent = Intent(this, DownloadForegroundService::class.java)
            when (call.method) {
                "startQueue" -> {
                    intent.action = DownloadForegroundService.ACTION_START
                    intent.putExtra(DownloadForegroundService.EXTRA_TOTAL, call.argument<Int>("total") ?: 0)
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "updateProgress" -> {
                    intent.action = DownloadForegroundService.ACTION_UPDATE_PROGRESS
                    intent.putExtra(DownloadForegroundService.EXTRA_DONE, call.argument<Int>("done") ?: 0)
                    intent.putExtra(DownloadForegroundService.EXTRA_TOTAL, call.argument<Int>("total") ?: 0)
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "showSummary" -> {
                    intent.action = DownloadForegroundService.ACTION_SHOW_SUMMARY
                    intent.putExtra(DownloadForegroundService.EXTRA_SUCCEEDED, call.argument<Int>("succeeded") ?: 0)
                    intent.putExtra(DownloadForegroundService.EXTRA_MISMATCHED, call.argument<Int>("mismatched") ?: 0)
                    intent.putExtra(DownloadForegroundService.EXTRA_FAILED, call.argument<Int>("failed") ?: 0)
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "clear" -> {
                    intent.action = DownloadForegroundService.ACTION_CLEAR
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
