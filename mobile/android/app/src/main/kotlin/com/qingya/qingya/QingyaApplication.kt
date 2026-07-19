package com.qingya.qingya

import android.app.Application
import android.util.Log
import com.qingya.qingya.monitor.MonitorConfigStore
import com.qingya.qingya.monitor.Notifier
import com.qingya.qingya.monitor.StatusMonitorService

/** Bootstraps the background monitor from disk config before Flutter is ready. */
class QingyaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val proc = currentProcessName()
        if (proc != null && proc.endsWith(":monitor")) {
            Log.i(TAG, "skip Application bootstrap in monitor process")
            return
        }
        runCatching {
            Notifier(this).ensureChannel()
            val cfg = MonitorConfigStore.read(this)
            if (cfg.configured) {
                Log.i(TAG, "bootstrap start monitor from saved config")
                StatusMonitorService.start(this)
            } else {
                Log.i(TAG, "bootstrap skip — not configured")
            }
        }.onFailure {
            Log.e(TAG, "bootstrap failed: ${it.message}", it)
        }
    }

    private fun currentProcessName(): String? {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= 28) {
                getProcessName()
            } else {
                val pid = android.os.Process.myPid()
                val am = getSystemService(ACTIVITY_SERVICE) as? android.app.ActivityManager
                am?.runningAppProcesses?.firstOrNull { it.pid == pid }?.processName
            }
        } catch (_: Throwable) {
            null
        }
    }

    companion object {
        private const val TAG = "QingyaApp"
    }
}
