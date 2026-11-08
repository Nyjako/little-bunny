package com.github.nyjako.little_bunny

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) -- local_auth's BiometricPrompt
// needs a FragmentActivity to host its dialog fragment (M7.4, app-lock).
class MainActivity : FlutterFragmentActivity() {
    companion object {
        // M65 -- set on the Intent DownloadForegroundService's notification
        // "Resume" action launches this Activity with. launchMode="singleTop"
        // (AndroidManifest.xml) means this lands in onCreate's own intent when
        // the Activity (and engine) had been killed, or in onNewIntent when
        // it's still alive -- handled identically either way, once the engine/
        // channel are known to be ready.
        const val EXTRA_RESUME_REQUESTED = "resume_downloads"
    }

    // M57 -- backs AndroidForegroundServiceQueueNotifier (app/lib/services/
    // android_foreground_service_queue_notifier.dart), the only bridge this
    // app has from Dart into DownloadForegroundService. A field (not a local
    // val in configureFlutterEngine) so onNewIntent can also use it, for a
    // "Resume" tap (M65) landing while this Activity is already alive.
    private val downloadForegroundServiceChannel = "little_bunny/download_foreground_service"
    private var methodChannel: MethodChannel? = null

    // M65 -- set when a "Resume" notification tap's intent lands before
    // Dart's own handler can be trusted to already be listening (a fresh
    // engine); cleared once Dart actually asks via "checkPendingResumeRequest".
    private var pendingResumeRequest = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadForegroundServiceChannel)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
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
                    intent.putExtra(DownloadForegroundService.EXTRA_FAILED, call.argument<Int>("failed") ?: 0)
                    intent.putExtra(DownloadForegroundService.EXTRA_ETA_TEXT, call.argument<String>("etaText"))
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
                // M65 -- Dart side's own startup pull for the fresh-launch
                // case below; a plain invokeMethod push from Kotlin the
                // moment this engine/channel exist would race Dart's own
                // main() actually getting around to registering its handler
                // (configureFlutterEngine running doesn't guarantee Dart's
                // main() has executed that far yet), so this is asked for,
                // not pushed, whenever the timing can't be trusted.
                "checkPendingResumeRequest" -> {
                    result.success(pendingResumeRequest)
                    pendingResumeRequest = false
                }
                else -> result.notImplemented()
            }
        }
        // Covers a fresh process (engine/channel just configured for the
        // first time) launched directly from the notification action, e.g.
        // after the engine had been killed by swiping the app away -- the
        // intent carrying EXTRA_RESUME_REQUESTED is this Activity's *initial*
        // one in that case. Recorded, not pushed straight to Dart (see
        // "checkPendingResumeRequest" above).
        if (intent.getBooleanExtra(EXTRA_RESUME_REQUESTED, false)) {
            intent.removeExtra(EXTRA_RESUME_REQUESTED)
            pendingResumeRequest = true
        }
    }

    // singleTop launchMode (AndroidManifest.xml) routes a second launch
    // here instead of a fresh configureFlutterEngine call, when the
    // Activity (and its engine) are already alive -- unlike the
    // configureFlutterEngine case above, Dart's own handler is already
    // definitely registered by this point (the app was already running), so
    // pushing directly is safe and more immediate than making Dart wait for
    // its own next poll.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(EXTRA_RESUME_REQUESTED, false)) {
            intent.removeExtra(EXTRA_RESUME_REQUESTED)
            methodChannel?.invokeMethod("resumeRequested", null)
        }
    }
}
