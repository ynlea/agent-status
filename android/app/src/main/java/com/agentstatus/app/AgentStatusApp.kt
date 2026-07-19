package com.agentstatus.app

import android.app.Application
import android.util.Log
import com.agentstatus.app.data.api.RestClient
import com.agentstatus.app.data.prefs.Prefs
import com.agentstatus.app.data.repo.StatusRepository
import com.agentstatus.app.data.ws.WsClient
import com.agentstatus.app.notify.Notifier
import com.agentstatus.app.service.StatusMonitorService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class AgentStatusApp : Application() {
    companion object {
        private const val TAG = "AgentStatusApp"
    }

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    lateinit var notifier: Notifier
        private set
    lateinit var repository: StatusRepository
        private set

    override fun onCreate() {
        super.onCreate()
        val process = currentProcessName()
        Log.i(TAG, "onCreate process=$process pid=${android.os.Process.myPid()}")

        // :monitor process hosts StatusMonitorService only.
        if (process.endsWith(":monitor")) {
            return
        }

        notifier = Notifier(this).also { it.ensureChannel() }
        repository = StatusRepository(
            appContext = this,
            prefs = Prefs(this),
            rest = RestClient(),
            ws = WsClient(),
            scope = appScope,
        ).also { it.start() }

        appScope.launch {
            repository.state
                .map { it.configured }
                .distinctUntilChanged()
                .collect { configured ->
                    if (configured) StatusMonitorService.start(this@AgentStatusApp)
                    else StatusMonitorService.stop(this@AgentStatusApp)
                }
        }
    }

    private fun currentProcessName(): String {
        return if (android.os.Build.VERSION.SDK_INT >= 28) {
            getProcessName()
        } else {
            try {
                val activityThread = Class.forName("android.app.ActivityThread")
                val method = activityThread.getDeclaredMethod("currentProcessName")
                method.invoke(null) as? String ?: packageName
            } catch (_: Throwable) {
                packageName
            }
        }
    }
}
