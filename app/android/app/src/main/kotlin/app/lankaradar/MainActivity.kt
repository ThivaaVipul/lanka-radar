package app.lankaradar

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The Alerts screen opens the app's pages in Android's settings.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.lankaradar/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "app" -> {
                        open(appInfo())
                        result.success(null)
                    }
                    "notifications" -> {
                        open(notificationSettings())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun appInfo() =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))

    private fun notificationSettings() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            appInfo()
        }

    // Some phones lack a settings page; app info is always there.
    private fun open(intent: Intent) {
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            startActivity(appInfo())
        }
    }
}
