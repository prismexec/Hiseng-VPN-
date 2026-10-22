package com.hiseng.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.FileInputStream
import java.io.FileOutputStream

class FluxVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "com.hiseng.vpn.CONNECT"
        const val ACTION_DISCONNECT = "com.hiseng.vpn.DISCONNECT"
        private const val CHANNEL = "vpn"
        private const val NOTIF_ID = 1
    }

    private var tun: ParcelFileDescriptor? = null
    @Volatile private var running = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                stopVpn()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                showNotification("Подключение…")
                if (!running) Thread({ connect() }, "flux-connect").start()
            }
        }
        return START_STICKY
    }

    private fun connect() {
        val link = Prefs.key(this)
        if (link.isNullOrBlank()) {
            fail("Сначала добавьте ключ")
            return
        }
        VpnState.set(Status.CONNECTING, "Подключаемся…")
        try {
            mobile.Mobile.setLowMemory(false)
            val specs = mobile.Mobile.shareSessionSpecs(link)
            val secret = JSONObject(mobile.Mobile.parseShareLink(link)).optString("secret")
            val err = mobile.Mobile.startSession(specs, secret)
            if (err.isNotEmpty()) {
                fail(err)
                return
            }

            val builder = Builder()
                .setSession(getString(R.string.app_name))
                .setMtu(1280)
                .addAddress("10.111.0.2", 32)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
                .setBlocking(true)
            // The app's own sockets (the carriers) go around the tunnel.
            builder.addDisallowedApplication(packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

            val fd = builder.establish()
            if (fd == null) {
                mobile.Mobile.stop()
                fail("Нет разрешения на VPN")
                return
            }
            tun = fd
            running = true
            startPumps(fd)
        } catch (e: Throwable) {
            fail(e.message ?: e.toString())
        }
    }

    private fun startPumps(fd: ParcelFileDescriptor) {
        // Phone -> tunnel.
        Thread({
            val input = FileInputStream(fd.fileDescriptor)
            val buf = ByteArray(32767)
            try {
                while (running) {
                    val n = input.read(buf)
                    if (n > 0) mobile.Mobile.send(buf.copyOf(n))
                }
            } catch (_: Throwable) {
            }
        }, "flux-up").start()

        // Tunnel -> phone.
        Thread({
            val output = FileOutputStream(fd.fileDescriptor)
            try {
                while (running) {
                    val p = mobile.Mobile.readTimeout(500L)
                    if (p != null && p.isNotEmpty()) output.write(p)
                }
            } catch (_: Throwable) {
            }
        }, "flux-down").start()

        // Status and logs.
        Thread({
            var wasOn = false
            while (running) {
                VpnState.addLogs(mobile.Mobile.readLogs())
                val on = mobile.Mobile.isConnected()
                if (on != wasOn || VpnState.status == Status.CONNECTING) {
                    if (on) {
                        VpnState.set(Status.ON, "Защищено")
                        showNotification("Подключено")
                    } else {
                        VpnState.set(Status.CONNECTING, "Ищем канал…")
                        showNotification("Подключение…")
                    }
                    wasOn = on
                }
                try { Thread.sleep(1000) } catch (_: InterruptedException) { break }
            }
        }, "flux-status").start()
    }

    private fun fail(msg: String) {
        try { VpnState.addLogs(mobile.Mobile.readLogs()) } catch (_: Throwable) {}
        VpnState.addLogs("[ERROR] $msg")
        stopVpn()
        VpnState.set(Status.ERROR, msg)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopVpn() {
        val wasRunning = running
        running = false
        try { mobile.Mobile.stop() } catch (_: Throwable) {}
        try { tun?.close() } catch (_: Throwable) {}
        tun = null
        if (wasRunning || VpnState.status != Status.ERROR) VpnState.set(Status.OFF)
    }

    override fun onRevoke() {
        stopVpn()
        stopSelf()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun showNotification(text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW)
        )
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, FluxVpnService::class.java).setAction(ACTION_DISCONNECT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_power)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null as android.graphics.drawable.Icon?, "Отключить", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }
}
