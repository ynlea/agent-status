package com.agentstatus.app.data.prefs

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * Tiny multi-process config file under the app dataDir (shared by UI and :monitor).
 * DataStore is not multi-process safe, so the monitor process must not rely on it alone.
 */
object MonitorConfigStore {
    data class Config(
        val serverUrl: String = "",
        val key: String = "",
        val notifyRed: Boolean = true,
        val notifyYellow: Boolean = false,
        val notifyGreen: Boolean = false,
    ) {
        val configured: Boolean get() = serverUrl.isNotBlank() && key.isNotBlank()
    }

    private fun file(context: Context): File =
        File(context.applicationInfo.dataDir, "monitor_config.json")

    fun write(context: Context, config: Config) {
        val json = JSONObject()
            .put("server_url", config.serverUrl)
            .put("key", config.key)
            .put("notify_red", config.notifyRed)
            .put("notify_yellow", config.notifyYellow)
            .put("notify_green", config.notifyGreen)
        val target = file(context)
        val tmp = File(target.absolutePath + ".tmp")
        tmp.writeText(json.toString())
        if (!tmp.renameTo(target)) {
            target.writeText(json.toString())
            tmp.delete()
        }
    }

    fun read(context: Context): Config {
        val target = file(context)
        if (!target.exists()) return Config()
        return runCatching {
            val o = JSONObject(target.readText())
            Config(
                serverUrl = o.optString("server_url"),
                key = o.optString("key"),
                notifyRed = o.optBoolean("notify_red", true),
                notifyYellow = o.optBoolean("notify_yellow", false),
                notifyGreen = o.optBoolean("notify_green", false),
            )
        }.getOrElse { Config() }
    }
}
