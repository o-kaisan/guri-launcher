package io.github.okaisan.gurilauncher

import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isCurrentHome" -> result.success(isCurrentHome())
                "requestHomeRole" -> result.success(requestHomeRole())
                else -> result.notImplemented()
            }
        }
    }

    private fun isCurrentHome(): Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        getSystemService(RoleManager::class.java).isRoleHeld(RoleManager.ROLE_HOME)
    } else {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        packageManager.resolveActivity(intent, 0)?.activityInfo?.packageName == packageName
    }

    private fun requestHomeRole(): String {
        if (isCurrentHome()) return "alreadyHome"
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val manager = getSystemService(RoleManager::class.java)
                if (!manager.isRoleAvailable(RoleManager.ROLE_HOME)) return "unavailable"
                startActivityForResult(manager.createRequestRoleIntent(RoleManager.ROLE_HOME), REQUEST_CODE)
                "requestStarted"
            } else {
                startActivityForResult(Intent(Settings.ACTION_HOME_SETTINGS), REQUEST_CODE)
                "settingsOpened"
            }
        } catch (_: ActivityNotFoundException) {
            "failed"
        }
    }

    private companion object {
        const val CHANNEL = "guri_launcher/home_role"
        const val REQUEST_CODE = 20
    }
}
