package com.qingya.qingya.monitor

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Dedicated `:monitor` process service.
 * Owns WebSocket + alert notifications so UI process freeze/kill cannot drop delivery.
 */
class StatusMonitorService : Service() {
    companion object {
        private const val TAG = "QingyaMonitor"
        private const val ONGOING_ID = 42

        fun start(context: Context) {
            runCatching {
                ContextCompat.startForegroundService(
                    context.applicationContext,
                    Intent(context.applicationContext, StatusMonitorService::class.java),
                )
                Log.i(TAG, "start requested")
            }.onFailure { Log.e(TAG, "start failed: ${it.message}", it) }
        }

        fun stop(context: Context) {
            runCatching {
                context.applicationContext.stopService(
                    Intent(context.applicationContext, StatusMonitorService::class.java),
                )
            }
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var jobs: Job? = null
    private lateinit var notifier: Notifier
    private lateinit var ws: WsClient
    private val statsFetcher = LiveStatsFetcher()
    private var wakeLock: PowerManager.WakeLock? = null
    private val connected = AtomicBoolean(false)
    @Volatile private var lastUrl: String = ""
    @Volatile private var lastKey: String = ""
    @Volatile private var lastStats: LiveStats = LiveStats()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notifier = Notifier(this).also { it.ensureChannel() }
        ws = WsClient()
        promoteForeground(false, "启动中…")
        acquireWakeLock()
        Log.i(TAG, "onCreate pid=${android.os.Process.myPid()}")

        jobs = scope.launch {
            launch {
                ws.events.collect { ev ->
                    when (ev) {
                        is WsEvent.Connected -> {
                            connected.set(ev.ok)
                            if (ev.ok) {
                                refreshStatsIfPossible()
                            }
                            promoteForeground(ev.ok, statsDetail(ev.ok))
                        }
                        is WsEvent.Failure -> {
                            connected.set(false)
                            promoteForeground(false, statsDetail(false))
                        }
                        is WsEvent.Notification -> {
                            val cfg = MonitorConfigStore.read(this@StatusMonitorService)
                            val st = SessionState.parse(ev.payload.state)
                            val allow = when (st) {
                                SessionState.Confirm -> cfg.notifyRed
                                SessionState.Working -> cfg.notifyYellow
                                SessionState.Done -> cfg.notifyGreen
                                SessionState.Idle -> false
                            }
                            if (allow) notifier.notifyState(ev.payload)
                            // 状态变化后尽快刷一次计数
                            refreshStatsIfPossible()
                            promoteForeground(connected.get(), statsDetail(connected.get()))
                        }
                    }
                }
            }
            while (isActive) {
                val cfg = MonitorConfigStore.read(this@StatusMonitorService)
                if (!cfg.configured) {
                    lastStats = LiveStats()
                    promoteForeground(false, "未配置服务（请在 App 内保存地址和密钥）")
                    ws.close()
                    lastUrl = ""
                    lastKey = ""
                } else {
                    val changed = cfg.serverUrl != lastUrl || cfg.key != lastKey
                    lastUrl = cfg.serverUrl
                    lastKey = cfg.key
                    if (changed || !connected.get()) {
                        Log.i(TAG, "ws connect/changed=$changed")
                        ws.connect(cfg.serverUrl, cfg.key)
                    } else {
                        ws.ensureConnected()
                    }
                    // 每轮尝试刷新统计（失败则沿用上次）
                    if (connected.get() || changed) {
                        refreshStatsIfPossible()
                    }
                    promoteForeground(connected.get(), statsDetail(connected.get()))
                }
                delay(4_000)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteForeground(connected.get(), statsDetail(connected.get()))
        scope.launch {
            val cfg = MonitorConfigStore.read(this@StatusMonitorService)
            if (cfg.configured) {
                ws.connect(cfg.serverUrl, cfg.key)
                refreshStatsIfPossible()
                promoteForeground(connected.get(), statsDetail(connected.get()))
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved")
        start(applicationContext)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        jobs?.cancel()
        scope.cancel()
        runCatching { ws.close() }
        releaseWakeLock()
        super.onDestroy()
    }

    private fun refreshStatsIfPossible() {
        val cfg = MonitorConfigStore.read(this)
        if (!cfg.configured) return
        val next = statsFetcher.fetch(cfg.serverUrl, cfg.key) ?: return
        lastStats = next
    }

    private fun statsDetail(isConnected: Boolean): String {
        val line = lastStats.summaryLine()
        return if (isConnected) line else "重连中 · $line"
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(PowerManager::class.java) ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "qingya:monitor").apply {
            setReferenceCounted(false)
            acquire(6 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        runCatching { wakeLock?.let { if (it.isHeld) it.release() } }
        wakeLock = null
    }

    private fun promoteForeground(isConnected: Boolean, detail: String) {
        val notification = buildOngoing(isConnected, detail)
        try {
            val type = if (Build.VERSION.SDK_INT >= 34) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }
            ServiceCompat.startForeground(this, ONGOING_ID, notification, type)
        } catch (t: Throwable) {
            Log.e(TAG, "startForeground typed failed: ${t.message}")
            runCatching { startForeground(ONGOING_ID, notification) }
        }
    }

    private fun buildOngoing(isConnected: Boolean, detail: String): Notification {
        return notifier.buildOngoing(isConnected, detail)
    }
}
