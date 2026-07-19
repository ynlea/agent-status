package com.qingya.qingya.monitor

enum class SessionState {
    Confirm, Working, Done, Idle;

    companion object {
        fun parse(raw: String?): SessionState = when (raw?.trim()?.lowercase()) {
            "confirm" -> Confirm
            "working" -> Working
            "done" -> Done
            "idle" -> Idle
            "stopped", "stop" -> Done
            else -> Idle
        }
    }
}

data class NotificationPayload(
    val machineId: String = "",
    val machineName: String = "",
    val agent: String = "",
    val sessionId: String = "",
    val displayName: String = "",
    val state: String = "idle",
    val color: String = "empty",
    val message: String = "",
    val at: String = "",
)
