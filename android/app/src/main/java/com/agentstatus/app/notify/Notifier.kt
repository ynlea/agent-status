package com.agentstatus.app.notify

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.agentstatus.app.domain.NotificationPayload
import com.agentstatus.app.domain.SessionState

class Notifier(private val context: Context) {
    companion object {
        // Bump when channel defaults change — Android freezes channel settings after first create.
        const val CHANNEL_ID = "agent_status_v3"
        const val ONGOING_CHANNEL_ID = "agent_status_ongoing_v2"
        private val VIBRATE_PATTERN = longArrayOf(0, 220, 120, 220)
    }

    fun ensureChannel() {
        val mgr = context.getSystemService(NotificationManager::class.java)
        // Drop stale channels that had no vibration / wrong defaults.
        listOf("agent_status", "agent_status_v2", "agent_status_ongoing").forEach { id ->
            runCatching { mgr.deleteNotificationChannel(id) }
        }

        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audio = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val alert = NotificationChannel(
            CHANNEL_ID,
            context.getString(com.agentstatus.app.R.string.channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(com.agentstatus.app.R.string.channel_desc)
            enableVibration(true)
            vibrationPattern = VIBRATE_PATTERN
            enableLights(true)
            setShowBadge(true)
            setSound(sound, audio)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        mgr.createNotificationChannel(alert)

        val ongoing = NotificationChannel(
            ONGOING_CHANNEL_ID,
            context.getString(com.agentstatus.app.R.string.ongoing_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(com.agentstatus.app.R.string.ongoing_channel_desc)
            enableVibration(false)
            setSound(null, null)
            setShowBadge(false)
        }
        mgr.createNotificationChannel(ongoing)
    }

    fun notifyState(payload: NotificationPayload) {
        ensureChannel()
        val st = SessionState.parse(payload.state)
        val title = when (st) {
            SessionState.Confirm -> "需确认"
            SessionState.Working -> "工作中"
            SessionState.Done -> "完成"
            SessionState.Idle -> return
        }
        val dir = payload.displayName.ifBlank { payload.sessionId }
        val text = buildString {
            append(payload.machineName.ifBlank { payload.machineId })
            append(" · ")
            append(payload.agent)
            append(" · ")
            append(dir)
            if (payload.message.isNotBlank()) {
                append(" — ")
                append(payload.message)
            }
        }
        val id = (payload.machineId + payload.sessionId).hashCode()
        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVibrate(VIBRATE_PATTERN)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .build()
        runCatching {
            NotificationManagerCompat.from(context).notify(id, n)
        }
        // OEM fallback: force vibrator even if channel vibration is muted by ROM quirks.
        vibrate()
    }

    fun buildOngoing(connected: Boolean, configured: Boolean): Notification {
        ensureChannel()
        val text = when {
            !configured -> "尚未配置服务"
            connected -> "WebSocket 已连接，后台监听中"
            else -> "正在重连…"
        }
        return NotificationCompat.Builder(context, ONGOING_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle(context.getString(com.agentstatus.app.R.string.ongoing_title))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
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
