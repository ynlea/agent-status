package com.agentstatus.app.data.repo

import android.content.Context
import com.agentstatus.app.data.api.RestClient
import com.agentstatus.app.data.prefs.MonitorConfigStore
import com.agentstatus.app.data.prefs.Prefs
import com.agentstatus.app.data.ws.WsClient
import com.agentstatus.app.data.ws.WsEvent
import com.agentstatus.app.domain.MachineUi
import com.agentstatus.app.domain.SessionDto
import com.agentstatus.app.domain.SessionUi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class StatusUiState(
    val loading: Boolean = true,
    val configured: Boolean = false,
    val connected: Boolean = false,
    val error: String? = null,
    val machines: List<MachineUi> = emptyList(),
    val notifyRed: Boolean = true,
    val notifyYellow: Boolean = false,
    val notifyGreen: Boolean = false,
)

/**
 * UI-facing repository (main process).
 * Background alert delivery is owned by StatusMonitorService in the `:monitor` process.
 */
class StatusRepository(
    private val appContext: Context,
    private val prefs: Prefs,
    private val rest: RestClient,
    private val ws: WsClient,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow(StatusUiState())
    val state: StateFlow<StatusUiState> = _state

    private val sessions = linkedMapOf<String, SessionDto>()
    private var machineMeta = mapOf<String, MachineUi>()
    private var loopJob: Job? = null
    @Volatile private var lastUrl: String = ""
    @Volatile private var lastKey: String = ""

    fun start() {
        loopJob?.cancel()
        loopJob = scope.launch {
            launch {
                prefs.flow.collect { snap ->
                    mirrorConfig(snap)
                    _state.value = _state.value.copy(
                        configured = snap.configured,
                        notifyRed = snap.notifyRed,
                        notifyYellow = snap.notifyYellow,
                        notifyGreen = snap.notifyGreen,
                    )
                    if (!snap.configured) {
                        lastUrl = ""
                        lastKey = ""
                        ws.close()
                        _state.value = _state.value.copy(
                            loading = false,
                            connected = false,
                            machines = emptyList(),
                        )
                        return@collect
                    }
                    val endpointChanged = snap.serverUrl != lastUrl || snap.key != lastKey
                    lastUrl = snap.serverUrl
                    lastKey = snap.key
                    if (endpointChanged || !_state.value.connected) {
                        refreshSnapshot(snap.serverUrl, snap.key)
                        ws.connect(snap.serverUrl, snap.key)
                    }
                }
            }
            launch {
                ws.events.collect { ev ->
                    when (ev) {
                        is WsEvent.Connected -> _state.value = _state.value.copy(connected = ev.ok)
                        is WsEvent.Failure -> _state.value = _state.value.copy(
                            error = ev.message,
                            connected = false,
                        )
                        is WsEvent.SessionUpsert -> {
                            putSession(ev.session)
                            rebuild()
                        }
                        // Alerts handled in :monitor process to avoid double notify.
                        is WsEvent.Notification -> Unit
                    }
                }
            }
            while (isActive) {
                delay(5_000)
                val snap = prefs.flow.first()
                if (!snap.configured) continue
                mirrorConfig(snap)
                if (!_state.value.connected) {
                    ws.connect(snap.serverUrl, snap.key)
                    refreshSnapshot(snap.serverUrl, snap.key)
                } else {
                    ws.ensureConnected()
                    refreshSnapshot(snap.serverUrl, snap.key)
                }
            }
        }
    }

    private fun mirrorConfig(snap: Prefs.Snapshot) {
        MonitorConfigStore.write(
            appContext,
            MonitorConfigStore.Config(
                serverUrl = snap.serverUrl,
                key = snap.key,
                notifyRed = snap.notifyRed,
                notifyYellow = snap.notifyYellow,
                notifyGreen = snap.notifyGreen,
            ),
        )
    }

    private suspend fun refreshSnapshot(url: String, key: String) {
        _state.value = _state.value.copy(loading = true, error = null)
        val machinesRes = rest.listMachines(url, key)
        machinesRes.onFailure {
            _state.value = _state.value.copy(loading = false, error = it.message)
            return
        }
        val machines = machinesRes.getOrThrow().machines
        sessions.clear()
        val meta = mutableMapOf<String, MachineUi>()
        for (m in machines) {
            meta[m.machineId] = MachineUi(m.machineId, m.machineName, m.platform, m.online, emptyList())
            rest.listSessions(url, key, m.machineId).onSuccess { list ->
                list.forEach { putSession(it) }
            }
        }
        machineMeta = meta
        rebuild(loading = false)
    }

    private fun putSession(s: SessionDto) {
        val key = "${s.machineId}|${s.agent}|${s.sessionId}"
        sessions[key] = s
        if (!machineMeta.containsKey(s.machineId)) {
            machineMeta = machineMeta + (s.machineId to MachineUi(
                id = s.machineId,
                name = s.machineName.ifBlank { s.machineId },
                platform = "",
                online = true,
                sessions = emptyList(),
            ))
        }
    }

    private fun rebuild(loading: Boolean = _state.value.loading) {
        val grouped = sessions.values.groupBy { it.machineId }
        val machines = machineMeta.values.map { m ->
            val list = grouped[m.id].orEmpty().map {
                SessionUi(
                    key = "${it.machineId}|${it.agent}|${it.sessionId}",
                    machineId = it.machineId.ifBlank { m.id },
                    machineName = it.machineName.ifBlank { m.name },
                    agent = it.agent,
                    sessionId = it.sessionId,
                    displayName = it.displayName.ifBlank { it.sessionId },
                    state = it.stateEnum(),
                    message = it.message,
                    updatedAt = it.updatedAt,
                )
            }
            m.copy(sessions = list)
        }.sortedBy { it.name }
        _state.value = _state.value.copy(loading = loading, machines = machines, error = null)
    }

    suspend fun saveConfig(url: String, key: String) = prefs.saveServer(url, key)
    suspend fun saveNotify(red: Boolean, yellow: Boolean, green: Boolean) =
        prefs.saveNotify(red, yellow, green)

    fun reconnectNow() {
        scope.launch {
            val snap = prefs.flow.first()
            if (!snap.configured) return@launch
            mirrorConfig(snap)
            ws.connect(snap.serverUrl, snap.key)
            refreshSnapshot(snap.serverUrl, snap.key)
        }
    }
}
