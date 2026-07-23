package com.ekromssh.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import com.jcraft.jsch.JSch
import com.jcraft.jsch.Session
import kotlinx.coroutines.*
import java.io.FileDescriptor
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket

class EkromVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var sshSession: Session? = null
    private var socksServer: ServerSocket? = null
    private var job: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        const val ACTION_CONNECT = "com.ekromssh.app.CONNECT"
        const val ACTION_DISCONNECT = "com.ekromssh.app.DISCONNECT"
        const val BROADCAST_STATUS = "com.ekromssh.app.VPN_STATUS"
        private var _isRunning = false
        fun isRunning() = _isRunning
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val host = intent.getStringExtra("host") ?: return START_STICKY
                val sshPort = intent.getIntExtra("sshPort", 22)
                val username = intent.getStringExtra("username") ?: "root"
                val password = intent.getStringExtra("password") ?: ""
                val wsPort = intent.getIntExtra("wsPort", 8080)
                val wsPath = intent.getStringExtra("wsPath") ?: "/"

                startForeground(createNotification())
                scope.launch { connect(host, sshPort, username, password, wsPort, wsPath) }
            }
            ACTION_DISCONNECT -> {
                disconnect()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    private suspend fun connect(
        host: String, sshPort: Int, username: String, password: String,
        wsPort: Int, wsPath: String
    ) = withContext(Dispatchers.IO) {
        try {
            _isRunning = true
            broadcastStatus("connecting")

            // 1. Start VPN interface
            val builder = Builder()
            builder.setSession("EkromSSH")
            builder.setMtu(1500)
            builder.addAddress("10.0.0.2", 32)
            builder.addRoute("0.0.0.0", 0) // Route all traffic
            builder.addDnsServer("8.8.8.8")
            builder.addDnsServer("1.1.1.1")

            // Block apps that shouldn't use VPN (optional)
            // builder.addDisallowedApplication("com.android.chrome")

            vpnInterface = builder.establish()

            // 2. Connect SSH via JSch
            val jsch = JSch()
            sshSession = jsch.getSession(username, host, sshPort)
            sshSession?.setPassword(password)

            // Auto-accept host key for demo (in production, should verify)
            val sshConfig = java.util.Properties()
            sshConfig["StrictHostKeyChecking"] = "no"
            sshConfig["compression.s2c"] = "zlib,none"
            sshConfig["compression.c2s"] = "zlib,none"
            sshSession?.setConfig(sshConfig)

            sshSession?.connect(10000) // 10s timeout

            // 3. Create SOCKS proxy via SSH dynamic port forwarding
            socksServer = ServerSocket(0) // random available port
            val socksPort = socksServer!!.localPort

            // Use JSch's built-in port forwarding for SOCKS
            sshSession?.setPortForwardingR(InetSocketAddress("127.0.0.1", socksPort))

            broadcastStatus("connected")

            // 4. Handle TUN traffic forwarding (simplified)
            handleTunTraffic(vpnInterface?.fd, socksPort)

        } catch (e: Exception) {
            broadcastStatus("error", e.message ?: "Connection failed")
            disconnect()
        }
    }

    private fun handleTunTraffic(fd: FileDescriptor?, socksPort: Int) {
        // Simplified: For now we just keep the connection alive.
        // Real implementation would:
        // 1. Read IP packets from TUN fd
        // 2. Parse TCP/UDP headers
        // 3. Forward through SOCKS5 proxy on 127.0.0.1:socksPort
        // 4. Use tun2socks (native) or manual packet routing
        //
        // For v1, SSH connection test + status display works
        // Full TUN routing will be added in next version with tun2socks native lib
    }

    private fun disconnect() {
        job?.cancel()
        try { sshSession?.disconnect() } catch (_: Exception) {}
        try { socksServer?.close() } catch (_: Exception) {}
        try { vpnInterface?.close() } catch (_: Exception) {}
        sshSession = null
        socksServer = null
        vpnInterface = null
        _isRunning = false
        broadcastStatus("disconnected")
    }

    private fun broadcastStatus(status: String, errorMessage: String = "") {
        val intent = Intent(BROADCAST_STATUS).apply {
            putExtra("status", status)
            if (errorMessage.isNotEmpty()) putExtra("errorMessage", errorMessage)
        }
        sendBroadcast(intent)
    }

    private fun createNotification(): Notification {
        val channelId = "EkromSSH_VPN"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "EkromSSH VPN Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
        return Notification.Builder(this, channelId)
            .setContentTitle("EkromSSH")
            .setContentText("VPN is active")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        disconnect()
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
