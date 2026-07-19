package com.agentstatus.app.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.agentstatus.app.AgentStatusApp
import com.agentstatus.app.data.repo.StatusUiState
import com.agentstatus.app.service.StatusMonitorService
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val repo = (app as AgentStatusApp).repository

    val state: StateFlow<StatusUiState> = repo.state

    init {
        // Ensure monitor process is up whenever UI is created.
        StatusMonitorService.start(app)
    }

    fun saveConfig(url: String, key: String) {
        viewModelScope.launch {
            repo.saveConfig(url, key)
            StatusMonitorService.start(getApplication())
        }
    }

    fun saveNotify(red: Boolean, yellow: Boolean, green: Boolean) {
        viewModelScope.launch { repo.saveNotify(red, yellow, green) }
    }

    fun reconnect() {
        repo.reconnectNow()
        StatusMonitorService.start(getApplication())
    }
}
