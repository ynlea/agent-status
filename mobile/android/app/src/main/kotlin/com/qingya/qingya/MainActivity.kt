package com.qingya.qingya

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.qingya.qingya.monitor.MonitorConfigStore
import com.qingya.qingya.monitor.Notifier
import com.qingya.qingya.monitor.StatusMonitorService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "qingya/monitor"
        private const val TAG = "QingyaMain"
        private const val REQ_POST_NOTIFICATIONS = 1001
    }

    private var pendingStartAfterPermission = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
