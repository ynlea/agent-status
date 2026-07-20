package com.agentstatus.app.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class SessionState {
    @SerialName("confirm") Confirm,
    @SerialName("working") Working,
    @SerialName("done") Done,
    @SerialName("idle") Idle;

    val colorName: String
        get() = when (this) {
            Confirm -> "red"
            Working -> "yellow"
            Done -> "green"
            Idle -> "empty"
        }

    /** Product labels: normal turn end is 完成, never 停止. */
    val labelZh: String
        get() = when (this) {
            Confirm -> "需确认"
            Working -> "工作中"
            Done -> "完成"
            Idle -> "空闲"
        }

    companion object {
        fun parse(raw: String?): SessionState = when (raw?.trim()?.lowercase()) {
            "confirm" -> Confirm
            "working" -> Working
            "done" -> Done
            "idle" -> Idle
            // Legacy/mis-mapped labels must not become a fake "停止" state.
            "stopped", "stop" -> Done
            else -> Idle
        }
    }
}

@Serializable
data class MachineDto(
    @SerialName("machine_id") val machineId: String,
    @SerialName("machine_name") val machineName: String = "",
    val platform: String = "",
    val version: String = "",
    val online: Boolean = false,
    @SerialName("last_seen_at") val lastSeenAt: String = "",
)

@Serializable
data class SessionDto(
    @SerialName("machine_id") val machineId: String = "",
    @SerialName("machine_name") val machineName: String = "",
    val agent: String = "",
    @SerialName("session_id") val sessionId: String = "",
    @SerialName("display_name") val displayName: String = "",
    val state: String = "idle",
    val message: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
) {
    fun stateEnum(): SessionState = SessionState.parse(state)
}

@Serializable
data class MachinesResponse(val machines: List<MachineDto> = emptyList())

@Serializable
data class SessionsResponse(
    @SerialName("machine_id") val machineId: String = "",
    val sessions: List<SessionDto> = emptyList(),
)

@Serializable
data class WsEnvelope(
    val type: String,
    // payload is parsed separately
)

@Serializable
data class NotificationPayload(
    @SerialName("machine_id") val machineId: String = "",
    @SerialName("machine_name") val machineName: String = "",
    val agent: String = "",
    @SerialName("session_id") val sessionId: String = "",
    @SerialName("display_name") val displayName: String = "",
    val state: String = "idle",
    val color: String = "empty",
    val message: String = "",
    val at: String = "",
)

data class MachineUi(
    val id: String,
    val name: String,
    val platform: String,
    val online: Boolean,
    val sessions: List<SessionUi>,
    val version: String = "",
)

data class SessionUi(
    val key: String,
    val machineId: String = "",
    val machineName: String = "",
    val agent: String,
    val sessionId: String,
    val displayName: String,
    val state: SessionState,
    val message: String,
    /** RFC3339 timestamp of last state/message update from server. */
    val updatedAt: String = "",
) {
    val title: String
        get() = when {
            message.isBlank() -> displayName
            isGenericStatusMessage(message) -> displayName
            else -> message
        }

    val subtitle: String
        get() = buildString {
            append(displayName)
            if (agent.isNotBlank()) {
                append(" · ")
                append(agent)
            }
            val host = machineName.ifBlank { machineId }
            if (host.isNotBlank()) {
                append(" · ")
                append(host)
            }
        }

    /** Relative time for UI, e.g. 刚刚 / 3分钟前 / 昨天 14:30 */
    val updatedLabel: String
        get() = formatRelativeTime(updatedAt)
}

private fun isGenericStatusMessage(msg: String): Boolean {
    val m = msg.trim().lowercase()
    if (m.isEmpty()) return true
    return m in setOf(
        "stopped", "stop", "permission request", "notification",
        "user_message", "task_started", "task_complete", "turn_aborted",
        "turn_started", "turn_completed", "需要确认", "已停止", "停止",
    ) || (m.all { it.isLetterOrDigit() || it == '_' || it == '-' || it == ':' || it == '.' } &&
        m.any { it.isLetter() } && !m.any { it.code > 127 })
}

fun formatRelativeTime(raw: String): String {
    if (raw.isBlank()) return ""
    val instant = parseInstant(raw) ?: return ""
    val now = java.time.Instant.now()
    val sec = java.time.Duration.between(instant, now).seconds
    return when {
        sec < 0 -> "刚刚"
        sec < 45 -> "刚刚"
        sec < 90 -> "1分钟前"
        sec < 3600 -> "${sec / 60}分钟前"
        sec < 90 * 60 -> "1小时前"
        sec < 24 * 3600 -> "${sec / 3600}小时前"
        sec < 48 * 3600 -> "昨天"
        sec < 7 * 24 * 3600 -> "${sec / (24 * 3600)}天前"
        else -> {
            val z = java.time.ZonedDateTime.ofInstant(instant, java.time.ZoneId.systemDefault())
            "%02d-%02d %02d:%02d".format(z.monthValue, z.dayOfMonth, z.hour, z.minute)
        }
    }
}

private fun parseInstant(raw: String): java.time.Instant? {
    val s = raw.trim()
    return runCatching { java.time.Instant.parse(s) }.getOrNull()
        ?: runCatching {
            // Go often emits fractional seconds with variable precision
            java.time.OffsetDateTime.parse(s).toInstant()
        }.getOrNull()
        ?: runCatching {
            val cleaned = if (s.endsWith("Z")) s else s
            val fmt = java.time.format.DateTimeFormatter.ISO_DATE_TIME
            java.time.ZonedDateTime.parse(cleaned, fmt).toInstant()
        }.getOrNull()
}
