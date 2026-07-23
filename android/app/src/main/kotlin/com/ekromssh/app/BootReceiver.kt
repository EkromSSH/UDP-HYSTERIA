package com.ekromssh.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Auto-start VPN on device boot if user enabled the setting.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val prefs = context.getSharedPreferences("udp_hysteria_settings", Context.MODE_PRIVATE)
            val startOnBoot = prefs.getBoolean("start_on_boot", false)
            val lastServerId = prefs.getString("last_server_id", null)

            if (startOnBoot && lastServerId != null) {
                // Load saved server config and auto-connect
                val serversJson = prefs.getString("ekromssh_servers", "[]")
                // Parse and find the server by ID, then start connection
                // (Simplified: just start the main activity)
                val launchIntent = context.packageManager.getLaunchIntentForPackage(
                    context.packageName
                )
                launchIntent?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    putExtra("auto_connect", true)
                    putExtra("server_id", lastServerId)
                }
                context.startActivity(launchIntent)
            }
        }
    }
}
