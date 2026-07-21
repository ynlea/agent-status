package com.qingya.qingya.monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.qingya.qingya.MainActivity
import com.qingya.qingya.R

class Notifier(private val context: Context) {
    companion object {
        // Bump when channel defaults change — Android freezes channel settings after first create.
        const val CHANNEL_ID = "qingya_alert_v2"
        const val ONGOING_CHANNEL_ID = "qingya_ongoing_v2"
        private val VIBRATE_PATTERN = longArrayOf(0, 220, 120, 220)
    }

    fun ensureChannel() {
        val mgr = context.getSystemService(NotificationManager::class.java) ?: return
        // Drop older channel ids so users pick up new defaults.
        listOf("qingya_alert_v1", "qingya_ongoing_v1").forEach { id ->
            runCatching { mgr.deleteNotificationChannel(id) }
        }

        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audio = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val alert = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.qingya_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.qingya_channel_desc)
            enableVibration(true)
            vibrationPattern = VIBRATE_PATTERN
            enableLights(true)
            lightColor = ContextCompat.getColor(context, R.color.qingya_brand)
            setShowBadge(true)
            setSound(sound, audio)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        mgr.createNotificationChannel(alert)

        val ongoing = NotificationChannel(
            ONGOING_CHANNEL_ID,
            context.getString(R.string.qingya_ongoing_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.qingya_ongoing_channel_desc)
            enableVibration(false)
            setSound(null, null)
            setShowBadge(false)
        }
        mgr.createNotificationChannel(ongoing)
    }

    fun notifyState(payload: NotificationPayload) {
        ensureChannel()
        val st = SessionState.parse(payload.state)
        if (st == SessionState.Idle) return

        val stateLabel = when (st) {
            SessionState.Confirm -> "需确认"
            SessionState.Working -> "工作中"
            SessionState.Done -> "已完成"
            SessionState.Idle -> return
        }
        val accent = when (st) {
            SessionState.Confirm -> R.color.qingya_confirm
            SessionState.Working -> R.color.qingya_working
            SessionState.Done -> R.color.qingya_done
            SessionState.Idle -> R.color.qingya_brand
        }
        val emoji = when (st) {
            SessionState.Confirm -> "🔴"
            SessionState.Working -> "🟡"
            SessionState.Done -> "🟢"
            SessionState.Idle -> ""
        }

        val machine = payload.machineName.ifBlank { payload.machineId }.ifBlank { "未知设备" }
        val agent = payload.agent.ifBlank { "agent" }
        val task = payload.message.trim().ifBlank {
            payload.displayName.ifBlank { payload.sessionId }.ifBlank { "会话更新" }
        }
        val project = payload.displayName.ifBlank { payload.sessionId }

        val title = "$emoji 轻芽 · $stateLabel"
        val summary = "$machine · $agent"
        val detail = buildString {
            append(task)
            if (project.isNotBlank() && project != task) {
                append('\n')
                append(project)
            }
            append('\n')
            append(summary)
        }

        val notifId = (payload.machineId + "|" + payload.sessionId + "|" + payload.state).hashCode()
        val openApp = openAppIntent(
            requestCode = notifId,
            machineId = payload.machineId,
            sessionId = payload.sessionId,
            state = payload.state,
        )
        val largeIcon = runCatching {
            BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
        }.getOrNull()

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_qingya)
            .setContentTitle(title)
            .setContentText(task)
            .setSubText(summary)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .setBigContentTitle(title)
                    .bigText(detail)
                    .setSummaryText(summary),
            )
            .setColor(ContextCompat.getColor(context, accent))
            .setColorized(false)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVibrate(VIBRATE_PATTERN)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setContentIntent(openApp)
            .setTicker("$stateLabel · $machine")
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setNumber(1)

        if (largeIcon != null) {
            builder.setLargeIcon(largeIcon)
        }

        runCatching {
            NotificationManagerCompat.from(context).notify(notifId, builder.build())
        }
        vibrate()
    }

    fun buildOngoing(isConnected: Boolean, detail: String): Notification {
        ensureChannel()
        val title = if (isConnected) "轻芽 · 监听中" else "轻芽 · 重连中"
        val text = detail.ifBlank {
            if (isConnected) "统计刷新中…" else "正在恢复连接…"
        }
        val openApp = openAppIntent(requestCode = 1)

        // 只保留左侧 smallIcon，不设 largeIcon（右侧大图标）。
        return NotificationCompat.Builder(context, ONGOING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_qingya)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setColor(ContextCompat.getColor(context, R.color.qingya_ongoing))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openApp)
            .setShowWhen(false)
            .build()
    }

    private fun openAppIntent(
        requestCode: Int,
        machineId: String = "",
        sessionId: String = "",
        state: String = "",
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "com.qingya.qingya.OPEN_FROM_NOTIFICATION"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("from_notification", true)
            if (machineId.isNotBlank()) putExtra("machine_id", machineId)
            if (sessionId.isNotBlank()) putExtra("session_id", sessionId)
            if (state.isNotBlank()) putExtra("state", state)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun vibrate() {
        runCatching {
            val vibrator = if (Build.VERSION.SDK_INT >= 31) {
                val vm = context.getSystemService(VibratorManager::class.java)
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            } ?: return
            if (!vibrator.hasVibrator()) return
            if (Build.VERSION.SDK_INT >= 26) {
                vibrator.vibrate(
                    VibrationEffect.createWaveform(VIBRATE_PATTERN, -1),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(VIBRATE_PATTERN, -1)
            }
        }
    }
}
