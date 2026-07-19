package com.qingya.qingya.monitor

import android.util.Log
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

sealed class WsEvent {
    data class Notification(val payload: NotificationPayload) : WsEvent()
    data class Connected(val ok: Boolean) : WsEvent()
    data class Failure(val message: String) : WsEvent()
}

class WsClient(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .pingInterval(12, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .build(),
) {
    companion object {
        private const val TAG = "QingyaWS"
    }

    private val socket = AtomicReference<WebSocket?>(null)
    private val desired = AtomicBoolean(false)
    private val opening = AtomicBoolean(false)
    @Volatile private var baseUrl: String = ""
    @Volatile private var key: String = ""
    @Volatile private var openedOnce = false

    private val _events = MutableSharedFlow<WsEvent>(
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val events: SharedFlow<WsEvent> = _events

    fun connect(baseUrl: String, key: String) {
        val sameTarget = this.baseUrl == baseUrl && this.key == key
        this.baseUrl = baseUrl
        this.key = key
        desired.set(true)
        if (sameTarget && socket.get() != null && openedOnce) {
            _events.tryEmit(WsEvent.Connected(true))
            return
        }
        openSocket("connect")
    }

    fun ensureConnected() {
        if (!desired.get()) return
        if (baseUrl.isBlank() || key.isBlank()) return
        if (socket.get() != null && openedOnce) return
        openSocket("ensure")
    }

    fun close() {
        desired.set(false)
        opening.set(false)
        openedOnce = false
        socket.getAndSet(null)?.close(1000, "bye")
        _events.tryEmit(WsEvent.Connected(false))
    }

    private fun openSocket(reason: String) {
        if (!desired.get()) return
        if (!opening.compareAndSet(false, true)) return
        val url = baseUrl
        val secret = key
        if (url.isBlank() || secret.isBlank()) {
            opening.set(false)
            return
        }

        val old = socket.getAndSet(null)
        if (old != null) {
            openedOnce = false
            old.cancel()
        }

        val wsUrl = url.trimEnd('/')
            .replace("https://", "wss://")
            .replace("http://", "ws://") + "/api/v1/ws"
        Log.i(TAG, "open ($reason) $wsUrl")
        val req = Request.Builder()
            .url(wsUrl)
            .header("Authorization", "Bearer $secret")
            .build()

        val ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                opening.set(false)
                openedOnce = true
                socket.set(webSocket)
                Log.i(TAG, "opened")
                _events.tryEmit(WsEvent.Connected(true))
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching {
                    val root = JSONObject(text)
                    val type = root.optString("type")
                    val payload = root.optJSONObject("payload") ?: return@runCatching
                    if (type == "notification") {
                        val n = NotificationPayload(
                            machineId = payload.optString("machine_id"),
                            machineName = payload.optString("machine_name"),
                            agent = payload.optString("agent"),
                            sessionId = payload.optString("session_id"),
                            displayName = payload.optString("display_name"),
                            state = payload.optString("state", "idle"),
                            color = payload.optString("color", "empty"),
                            message = payload.optString("message"),
                            at = payload.optString("at"),
                        )
                        _events.tryEmit(WsEvent.Notification(n))
                    }
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.w(TAG, "failure: ${t.message}")
                opening.set(false)
                openedOnce = false
                socket.compareAndSet(webSocket, null)
                _events.tryEmit(WsEvent.Failure(t.message ?: "ws failure"))
                _events.tryEmit(WsEvent.Connected(false))
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "closed code=$code reason=$reason")
                opening.set(false)
                openedOnce = false
                socket.compareAndSet(webSocket, null)
                _events.tryEmit(WsEvent.Connected(false))
            }
        })
        socket.set(ws)
    }
}
