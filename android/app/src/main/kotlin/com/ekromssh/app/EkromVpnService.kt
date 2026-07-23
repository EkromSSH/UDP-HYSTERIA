package com.ekromssh.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.util.concurrent.atomic.AtomicBoolean

class EkromVpnService : VpnService() {
    companion object {
        const val ACTION_START_HYSTERIA = "com.ekromssh.app.START_HYSTERIA"
        const val ACTION_START_SSH_WS = "com.ekromssh.app.START_SSH_WS"
        const val ACTION_STOP = "com.ekromssh.app.STOP"
        const val NOTIFICATION_CHANNEL_ID = "udp_hysteria_channel"
        const val NOTIFICATION_ID = 1001

        private var instance: EkromVpnService? = null
        fun isRunning(): Boolean = instance?.isRunning?.get() == true

        // Config for current connection
        var currentHost: String = ""
        var currentPort: Int = 0
        var currentPassword: String = ""
        var currentProtocol: String = "hysteria"
        var currentUsername: String = "root"
        var currentWsPath: String = "/"
    }

    private val isRunning = AtomicBoolean(false)
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var tunInterface: ParcelFileDescriptor? = null
    private var job: Job? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_HYSTERIA -> {
                currentHost = intent.getStringExtra("host") ?: ""
                currentPort = intent.getIntExtra("port", 36712)
                currentPassword = intent.getStringExtra("password") ?: ""
                val obfsPassword = intent.getStringExtra("obfsPassword") ?: ""
                val alpn = intent.getStringExtra("alpn") ?: "h3"
                currentProtocol = "hysteria"
                startHysteriaVpn(currentHost, currentPort, currentPassword, obfsPassword, alpn)
            }
            ACTION_START_SSH_WS -> {
                currentHost = intent.getStringExtra("host") ?: ""
                currentPort = intent.getIntExtra("wsPort", 8080)
                currentPassword = intent.getStringExtra("password") ?: ""
                currentUsername = intent.getStringExtra("username") ?: "root"
                currentWsPath = intent.getStringExtra("wsPath") ?: "/"
                currentProtocol = "sshWs"
                startSshWsVpn(currentHost, currentPort, currentUsername, currentPassword, currentWsPath)
            }
            ACTION_STOP -> {
                stopVpn()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        instance = null
        super.onDestroy()
    }

    private fun startHysteriaVpn(
        host: String, port: Int, password: String,
        obfsPassword: String, alpn: String
    ) {
        if (isRunning.get()) return

        val builder = Builder()
        builder.setName("UDP HYSTERIA")
        builder.setMtu(1500)
        builder.addAddress("10.0.0.2", 24)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("8.8.8.8")
        builder.addDnsServer("1.1.1.1")
        builder.setBlocking(true)

        tunInterface = builder.establish()
        if (tunInterface == null) {
            sendStatus("error", "Failed to establish VPN interface")
            return
        }

        isRunning.set(true)
        startForeground(NOTIFICATION_ID, buildNotification("UDP • $host"))

        job = serviceScope.launch {
            try {
                // Read from TUN and forward to Hysteria proxy
                val tunIn = FileInputStream(tunInterface!!.fileDescriptor)
                val tunOut = FileOutputStream(tunInterface!!.fileDescriptor)
                val buffer = ByteArray(32767)

                // Connection to local Hysteria SOCKS5 proxy
                // In production, use Hysteria Go bindings
                // For now, establish a simple UDP tunnel
                val udpChannel = DatagramChannel.open()
                udpChannel.connect(InetSocketAddress(host, port))
                udpChannel.configureBlocking(false)

                val receiveBuffer = ByteBuffer.allocate(65535)
                val sendBuffer = ByteBuffer.allocate(65535)

                while (isActive && isRunning.get()) {
                    // Read from TUN
                    val read = tunIn.read(buffer)
                    if (read <= 0) break

                    // Process packet and forward through tunnel
                    // In production: encrypt and send via Hysteria protocol
                    sendBuffer.clear()
                    sendBuffer.put(buffer, 0, read)
                    sendBuffer.flip()
                    udpChannel.send(sendBuffer, InetSocketAddress(host, port))

                    // Read responses from tunnel
                    receiveBuffer.clear()
                    val source = udpChannel.receive(receiveBuffer)
                    if (source != null) {
                        receiveBuffer.flip()
                        val received = ByteArray(receiveBuffer.remaining())
                        receiveBuffer.get(received)
                        tunOut.write(received)
                        tunOut.flush()
                    }

                    // Traffic update
                    sendTrafficUpdate(read, receiveBuffer.position())
                    delay(100)
                }
            } catch (e: Exception) {
                sendStatus("error", e.message ?: "Connection error")
            } finally {
                stopVpn()
            }
        }
    }

    private fun startSshWsVpn(
        host: String, wsPort: Int,
        username: String, password: String, wsPath: String
    ) {
        if (isRunning.get()) return

        val builder = Builder()
        builder.setName("UDP HYSTERIA SSH WS")
        builder.setMtu(1500)
        builder.addAddress("10.0.0.2", 24)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("8.8.8.8")
        builder.addDnsServer("1.1.1.1")
        builder.setBlocking(true)

        tunInterface = builder.establish()
        if (tunInterface == null) {
            sendStatus("error", "Failed to establish VPN interface")
            return
        }

        isRunning.set(true)
        startForeground(NOTIFICATION_ID, buildNotification("SSH • $host"))

        job = serviceScope.launch {
            try {
                val tunIn = FileInputStream(tunInterface!!.fileDescriptor)
                val tunOut = FileOutputStream(tunInterface!!.fileDescriptor)
                val buffer = ByteArray(32767)

                // Connect via WebSocket then SSH
                // In production: use OkHttp WebSocket + JSch SSH
                val wsUrl = "ws://$host:$wsPort$wsPath"

                while (isActive && isRunning.get()) {
                    val read = tunIn.read(buffer)
                    if (read <= 0) break

                    // Forward TUN traffic through SSH WS tunnel
                    // In production: send via WebSocket which proxies to SSH

                    sendTrafficUpdate(read, 0)
                    delay(100)
                }
            } catch (e: Exception) {
                sendStatus("error", e.message ?: "Connection error")
            } finally {
                stopVpn()
            }
        }
    }

    private fun stopVpn() {
        isRunning.set(false)
        job?.cancel()
        job = null
        tunInterface?.close()
        tunInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        sendStatus("disconnected", "")
    }

    private fun sendStatus(status: String, message: String) {
        val intent = Intent("com.ekromssh.app.VPN_STATUS")
        intent.putExtra("status", status)
        intent.putExtra("errorMessage", message)
        sendBroadcast(intent)
    }

    private fun sendTrafficUpdate(sent: Int, received: Int) {
        val intent = Intent("com.ekromssh.app.TRAFFIC_UPDATE")
        intent.putExtra("bytesSent", sent)
        intent.putExtra("bytesReceived", received)
        sendBroadcast(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "EkromSSH VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN connection status"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(content: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, EkromVpnService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("UDP HYSTERIA")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "Disconnect", stopIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
