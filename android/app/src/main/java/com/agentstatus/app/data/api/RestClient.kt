package com.agentstatus.app.data.api

import com.agentstatus.app.domain.MachinesResponse
import com.agentstatus.app.domain.SessionDto
import com.agentstatus.app.domain.SessionsResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class RestClient(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build(),
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    suspend fun listMachines(baseUrl: String, key: String): Result<MachinesResponse> =
        get(baseUrl, key, "/api/v1/machines")

    suspend fun listSessions(baseUrl: String, key: String, machineId: String): Result<List<SessionDto>> =
        get<SessionsResponse>(baseUrl, key, "/api/v1/machines/$machineId/sessions")
            .map { it.sessions }

    private suspend inline fun <reified T> get(baseUrl: String, key: String, path: String): Result<T> =
        withContext(Dispatchers.IO) {
            runCatching {
                val req = Request.Builder()
                    .url(baseUrl.trimEnd('/') + path)
                    .header("Authorization", "Bearer $key")
                    .get()
                    .build()
                client.newCall(req).execute().use { res ->
                    val body = res.body?.string().orEmpty()
                    if (!res.isSuccessful) {
                        error("HTTP ${res.code}: ${body.take(200)}")
                    }
                    json.decodeFromString<T>(body)
                }
            }
        }
}
