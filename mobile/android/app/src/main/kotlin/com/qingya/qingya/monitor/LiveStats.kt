package com.qingya.qingya.monitor

import android.util.Log
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import kotlin.math.roundToLong

/** 常驻通知：在线设备 / 工作中会话 / 今日 token。 */
data class LiveStats(
    val onlineMachines: Int = 0,
    /** 仅 state=working。 */
    val workingSessions: Int = 0,
    /** 今日 real_usage；null 表示尚未拉到。 */
    val todayTokens: Long? = null,
) {
    fun summaryLine(): String {
        val usage = formatTokens(todayTokens)
        return "${onlineMachines} 台在线 · ${workingSessions} 个工作中 · $usage"
    }

    companion object {
        /** 与 App formatSessionTokens 一致：原样 / xk / xM。 */
        fun formatTokens(realUsage: Long?): String {
            if (realUsage == null) return "—"
            if (realUsage <= 0L) return "0"
            if (realUsage < 1_000L) return realUsage.toString()
            if (realUsage < 1_000_000L) {
                val v = realUsage / 1000.0
                return "${trimOne(v)}k"
            }
            val v = realUsage / 1_000_000.0
            return "${trimOne(v)}M"
        }

        private fun trimOne(v: Double): String {
            val rounded = if (v >= 100) v.roundToLong().toString()
            else {
                val s = String.format("%.1f", v)
                if (s.endsWith(".0")) s.dropLast(2) else s
            }
            return rounded
        }
    }
}

/**
 * REST 汇总在线设备、工作中会话、今日用量。
 * 「工作中」只计 SessionState.Working。
 */
class LiveStatsFetcher(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(12, TimeUnit.SECONDS)
        .build(),
) {
    companion object {
        private const val TAG = "QingyaLiveStats"
    }

    fun fetch(baseUrl: String, key: String): LiveStats? {
        if (baseUrl.isBlank() || key.isBlank()) return null
        return runCatching {
            val root = baseUrl.trimEnd('/')
            val machines = getJson(root, "/api/v1/machines", key) ?: return@runCatching null
            val list = machines.optJSONArray("machines") ?: return@runCatching LiveStats()
            var online = 0
            var working = 0
            for (i in 0 until list.length()) {
                val m = list.optJSONObject(i) ?: continue
                if (m.optBoolean("online", false)) online++
                val mid = m.optString("machine_id").trim()
                if (mid.isEmpty()) continue
                val path = "/api/v1/machines/${URLEncoder.encode(mid, "UTF-8")}/sessions"
                val sessRoot = getJson(root, path, key) ?: continue
                val sessions = sessRoot.optJSONArray("sessions") ?: continue
                for (j in 0 until sessions.length()) {
                    val s = sessions.optJSONObject(j) ?: continue
                    if (SessionState.parse(s.optString("state")) == SessionState.Working) {
                        working++
                    }
                }
            }
            val today = fetchTodayTokens(root, key)
            LiveStats(
                onlineMachines = online,
                workingSessions = working,
                todayTokens = today,
            )
        }.onFailure {
            Log.w(TAG, "fetch failed: ${it.message}")
        }.getOrNull()
    }

    private fun fetchTodayTokens(root: String, key: String): Long? {
        val zone = ZoneId.systemDefault()
        val start = LocalDate.now(zone).atStartOfDay(zone).toInstant()
        val end = Instant.now()
        val from = DateTimeFormatter.ISO_INSTANT.format(start)
        val to = DateTimeFormatter.ISO_INSTANT.format(end)
        // ISO_INSTANT is like 2026-07-21T00:00:00Z — server accepts RFC3339
        val path = "/api/v1/usage/summary?from=${URLEncoder.encode(from, "UTF-8")}" +
            "&to=${URLEncoder.encode(to, "UTF-8")}"
        val json = getJson(root, path, key) ?: return null
        // UsageMetrics embedded: real_usage
        return when {
            json.has("real_usage") && !json.isNull("real_usage") -> json.optLong("real_usage", 0L)
            else -> 0L
        }
    }

    private fun getJson(base: String, path: String, key: String): JSONObject? {
        val full = if (path.startsWith("http")) path else base + path
        val url = full.toHttpUrlOrNull()
            ?: return null.also { Log.w(TAG, "bad url $full") }
        val req = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $key")
            .header("Accept", "application/json")
            .get()
            .build()
        client.newCall(req).execute().use { res ->
            if (!res.isSuccessful) {
                Log.w(TAG, "HTTP ${res.code} $path")
                return null
            }
            val body = res.body?.string().orEmpty()
            if (body.isBlank()) return null
            return JSONObject(body)
        }
    }
}
