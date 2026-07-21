package com.qingya.qingya

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.qingya.qingya.monitor.MonitorConfigStore
import com.qingya.qingya.monitor.Notifier
import com.qingya.qingya.monitor.StatusMonitorService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "qingya/monitor"
        private const val UPDATER_CHANNEL = "qingya/updater"
        private const val TAG = "QingyaMain"
        private const val REQ_POST_NOTIFICATIONS = 1001
    }

    private var pendingStartAfterPermission = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installApk" -> {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                            val path = argString(args, "path")
                            if (path.isBlank()) {
                                result.error("bad_args", "path required", null)
                                return@setMethodCallHandler
                            }
                            installApk(path)
                            result.success(mapOf("ok" to true))
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "updater ${call.method} failed: ${t.message}", t)
                    result.error("updater_error", t.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "syncAndStart" -> {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                            val url = argString(args, "serverUrl")
                            val key = argString(args, "apiKey")
                            val notifyRed = argBool(args, "notifyConfirm", true)
                            val notifyYellow = argBool(args, "notifyWorking", true)
                            val notifyGreen = argBool(args, "notifyDone", true)
                            Log.i(TAG, "syncAndStart urlLen=${url.length} keyLen=${key.length}")
                            ensureNotificationPermission(requestIfNeeded = true)
                            Notifier(this).ensureChannel()
                            MonitorConfigStore.write(
                                this,
                                MonitorConfigStore.Config(
                                    serverUrl = url,
                                    key = key,
                                    notifyRed = notifyRed,
                                    notifyYellow = notifyYellow,
                                    notifyGreen = notifyGreen,
                                ),
                            )
                            if (url.isNotBlank() && key.isNotBlank()) {
                                pendingStartAfterPermission = !hasPostNotificationsPermission()
                                StatusMonitorService.start(this)
                                result.success(
                                    mapOf(
                                        "ok" to true,
                                        "started" to true,
                                        "notificationPermission" to hasPostNotificationsPermission(),
                                    ),
                                )
                            } else {
                                pendingStartAfterPermission = false
                                StatusMonitorService.stop(this)
                                result.success(
                                    mapOf(
                                        "ok" to true,
                                        "started" to false,
                                        "notificationPermission" to hasPostNotificationsPermission(),
                                    ),
                                )
                            }
                        }
                        "stop" -> {
                            pendingStartAfterPermission = false
                            StatusMonitorService.stop(this)
                            result.success(mapOf("ok" to true, "started" to false))
                        }
                        "status" -> {
                            val cfg = MonitorConfigStore.read(this)
                            result.success(
                                mapOf(
                                    "configured" to cfg.configured,
                                    "serverUrl" to cfg.serverUrl,
                                    "notificationPermission" to hasPostNotificationsPermission(),
                                ),
                            )
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "channel ${call.method} failed: ${t.message}", t)
                    result.error("monitor_error", t.message, null)
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationPermission(requestIfNeeded = true)
        ensureMonitorFromDisk("onCreate")
    }

    override fun onResume() {
        super.onResume()
        ensureMonitorFromDisk("onResume")
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.i(TAG, "POST_NOTIFICATIONS granted=$granted")
            if (granted || pendingStartAfterPermission) {
                ensureMonitorFromDisk("permissionResult")
            }
            pendingStartAfterPermission = false
        }
    }

    private fun ensureMonitorFromDisk(reason: String) {
        runCatching {
            val cfg = MonitorConfigStore.read(this)
            if (cfg.configured) {
                Log.i(TAG, "ensureMonitor ($reason) start")
                Notifier(this).ensureChannel()
                StatusMonitorService.start(this)
            }
        }.onFailure {
            Log.e(TAG, "ensureMonitor ($reason) failed: ${it.message}", it)
        }
    }

    private fun hasPostNotificationsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensureNotificationPermission(requestIfNeeded: Boolean) {
        if (Build.VERSION.SDK_INT < 33) return
        if (hasPostNotificationsPermission()) return
        if (!requestIfNeeded) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_POST_NOTIFICATIONS,
        )
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists() || !file.canRead()) {
            throw IllegalStateException("安装包不存在或不可读")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!packageManager.canRequestPackageInstalls()) {
                val settings = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
                settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(settings)
                throw IllegalStateException("请允许安装未知应用后重试")
            }
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }

    private fun argString(args: Map<*, *>, key: String): String {
        val v = args[key] ?: return ""
        return v.toString().trim()
    }

    private fun argBool(args: Map<*, *>, key: String, default: Boolean): Boolean {
        return when (val v = args[key]) {
            is Boolean -> v
            is String -> v.equals("true", ignoreCase = true)
            is Number -> v.toInt() != 0
            else -> default
        }
    }
}
