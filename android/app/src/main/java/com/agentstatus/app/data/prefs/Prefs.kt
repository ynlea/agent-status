package com.agentstatus.app.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore("agent_status_prefs")

class Prefs(private val context: Context) {
    private val keyUrl = stringPreferencesKey("server_url")
    private val keySecret = stringPreferencesKey("server_key")
    private val keyNotifyRed = booleanPreferencesKey("notify_red")
    private val keyNotifyYellow = booleanPreferencesKey("notify_yellow")
    private val keyNotifyGreen = booleanPreferencesKey("notify_green")

    data class Snapshot(
        val serverUrl: String,
        val key: String,
        val notifyRed: Boolean,
        val notifyYellow: Boolean,
        val notifyGreen: Boolean,
    ) {
        val configured: Boolean get() = serverUrl.isNotBlank() && key.isNotBlank()
    }

    val flow: Flow<Snapshot> = context.dataStore.data.map { p ->
        Snapshot(
            serverUrl = p[keyUrl].orEmpty(),
            key = p[keySecret].orEmpty(),
            notifyRed = p[keyNotifyRed] ?: true,
            notifyYellow = p[keyNotifyYellow] ?: false,
            notifyGreen = p[keyNotifyGreen] ?: false,
        )
    }

    suspend fun saveServer(url: String, key: String) {
        context.dataStore.edit {
            it[keyUrl] = url.trim().trimEnd('/')
            it[keySecret] = key.trim()
        }
        syncMonitorFile()
    }

    suspend fun saveNotify(red: Boolean, yellow: Boolean, green: Boolean) {
        context.dataStore.edit {
            it[keyNotifyRed] = red
            it[keyNotifyYellow] = yellow
            it[keyNotifyGreen] = green
        }
        syncMonitorFile()
    }

    /** Mirror latest prefs to a multi-process readable file for :monitor. */
    suspend fun syncMonitorFile() {
        val snap = flow.first()
        MonitorConfigStore.write(
            context,
            MonitorConfigStore.Config(
                serverUrl = snap.serverUrl,
                key = snap.key,
                notifyRed = snap.notifyRed,
                notifyYellow = snap.notifyYellow,
                notifyGreen = snap.notifyGreen,
            ),
        )
    }
}
