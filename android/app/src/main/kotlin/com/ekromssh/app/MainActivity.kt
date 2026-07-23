package com.ekromssh.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ekromssh.app/vpn"
    private var methodChannel: MethodChannel? = null
    private var statusReceiver: VpnStatusReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSshWs" -> {
                    val host = call.argument<String>("host") ?: ""
                    val sshPort = call.argument<Int>("sshPort") ?: 22
                    val username = call.argument<String>("username") ?: "root"
                    val password = call.argument<String>("password") ?: ""
                    val wsPort = call.argument<Int>("wsPort") ?: 8080
                    val wsPath = call.argument<String>("wsPath") ?: "/"

                    // Request VPN permission
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                        // For now, proceed anyway
                    }

                    val serviceIntent = Intent(this, EkromVpnService::class.java).apply {
                        action = EkromVpnService.ACTION_CONNECT
                        putExtra("host", host)
                        putExtra("sshPort", sshPort)
                        putExtra("username", username)
                        putExtra("password", password)
                        putExtra("wsPort", wsPort)
                        putExtra("wsPath", wsPath)
                    }
                    startForegroundServiceCompat(serviceIntent)
                    result.success(true)
                }
                "startHysteria" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<String>("port") ?: "36712"
                    val auth = call.argument<String>("auth") ?: ""
                    val obfsPassword = call.argument<String>("obfsPassword") ?: ""
                    val upSpeed = call.argument<Int>("upSpeed") ?: 10
                    val downSpeed = call.argument<Int>("downSpeed") ?: 18
                    val udpWindow = call.argument<Int>("udpWindow") ?: 196608

                    // Hysteria via Go binding - placeholder for future
                    result.success(false)
                }
                "stopVpn" -> {
                    val serviceIntent = Intent(this, EkromVpnService::class.java).apply {
                        action = EkromVpnService.ACTION_DISCONNECT
                    }
                    startService(serviceIntent)
                    result.success(true)
                }
                "isRunning" -> {
                    result.success(EkromVpnService.isRunning())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        statusReceiver = VpnStatusReceiver()
        registerReceiver(
            statusReceiver,
            IntentFilter("com.ekromssh.app.VPN_STATUS"),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                RECEIVER_NOT_EXPORTED else 0
        )
    }

    override fun onDestroy() {
        statusReceiver?.let { unregisterReceiver(it) }
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            // VPN permission granted (or denied)
        }
    }

    private fun startForegroundServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private inner class VpnStatusReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getStringExtra("status") ?: return
            val errorMessage = intent.getStringExtra("errorMessage") ?: ""

            when (status) {
                "connected" -> methodChannel?.invokeMethod("onStatusChanged", mapOf(
                    "status" to "connected",
                    "bytesSent" to 0,
                    "bytesReceived" to 0
                ))
                "disconnected" -> methodChannel?.invokeMethod("onStatusChanged", mapOf(
                    "status" to "disconnected",
                    "bytesSent" to 0,
                    "bytesReceived" to 0
                ))
                "error" -> methodChannel?.invokeMethod("onStatusChanged", mapOf(
                    "status" to "error",
                    "errorMessage" to errorMessage
                ))
                "connecting" -> methodChannel?.invokeMethod("onStatusChanged", mapOf(
                    "status" to "connecting"
                ))
            }
        }
    }

    companion object {
        private const val VPN_REQUEST_CODE = 1000
    }
}
