package com.agentstatus.app.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.agentstatus.app.data.prefs.MonitorConfigStore

/** Restart the :monitor service after device boot when config already exists. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        val cfg = MonitorConfigStore.read(context)
        if (!cfg.configured) {
            Log.i("AgentStatusBoot", "skip start — not configured")
            return
        }
        Log.i("AgentStatusBoot", "starting monitor after $action")
        StatusMonitorService.start(context)
    }
}
