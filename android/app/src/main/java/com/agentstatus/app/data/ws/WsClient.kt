package com.agentstatus.app.data.ws

import android.util.Log
import com.agentstatus.app.domain.NotificationPayload
import com.agentstatus.app.domain.SessionDto
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

sealed class WsEvent {
    data class SessionUpsert(val session: SessionDto) : WsEvent()
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
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    companion object {
        private const val TAG = "AgentStatusWS"
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

    fun isOpen(): Boolean = socket.get() != null && openedOnce

    fun connect(baseUrl: String, key: String) {
        val sameTarget = this.baseUrl == baseUrl && this.key == key
        this.baseUrl = baseUrl
        this.key = key
        desired.set(true)
        // Do not tear down a healthy socket just because connect() was called again.
        if (sameTarget && socket.get() != null && openedOnce) {
            Log.d(TAG, "connect skipped — already open")
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
        if (!opening.compareAndSet(false, true)) {
            Log.d(TAG, "open already in progress ($reason)")
            return
        }
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
                    val root = json.parseToJsonElement(text).jsonObject
                    val type = root["type"]?.jsonPrimitive?.content.orEmpty()
                    val payload = root["payload"]
                    when (type) {
                        "session_upsert" -> {
                            if (payload != null) {
                                val s = json.decodeFromJsonElement(SessionDto.serializer(), payload)
                                _events.tryEmit(WsEvent.SessionUpsert(s))
                            }
                        }
                        "notification" -> {
                            if (payload != null) {
                                val n = json.decodeFromJsonElement(NotificationPayload.serializer(), payload)
                                _events.tryEmit(WsEvent.Notification(n))
                            }
                        }
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
