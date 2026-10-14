package com.example.frontend

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import androidx.core.app.NotificationCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * DNS-only VPN: intercepts port-53 traffic on all interfaces (WiFi + mobile),
 * applies category blocklists, and forwards to AdGuard Family or Cloudflare upstream.
 */
class DnsFilterVpnService : VpnService() {
    private var tunFd: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private val running = AtomicBoolean(false)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                stopSelf()
                return START_NOT_STICKY
            }
        }
        if (!DnsFilterPrefs.needsVpn(this)) {
            stopVpn()
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        startVpn()
        return START_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        DnsFilterPrefs.setVpnActive(this, false)
        stopVpn()
        super.onRevoke()
    }

    private fun startVpn() {
        if (running.get()) {
            DnsBlocklist.reload(this)
            return
        }
        DnsBlocklist.reload(this)
        val builder = Builder()
            .setSession("MindSync DNS Filter")
            .setMtu(1500)
            .addAddress(DnsFilterPrefs.VPN_ADDRESS, 32)
            .addDnsServer(DnsFilterPrefs.VPN_ADDRESS)

        // Virtual DNS + LAN router DNS (WiFi) + common public resolvers.
        val dnsRoutes =
            linkedSetOf(
                DnsFilterPrefs.VPN_ADDRESS,
                "192.168.0.0/16",
                "10.0.0.0/8",
                "172.16.0.0/12",
                "1.1.1.1",
                "1.0.0.1",
                "8.8.8.8",
                "8.8.4.4",
                "9.9.9.9",
                "149.112.112.112",
                "208.67.222.222",
                "208.67.220.220",
                DnsFilterPrefs.UPSTREAM_DNS_FAMILY,
                DnsFilterPrefs.UPSTREAM_DNS_FAMILY_ALT,
            )
        for (route in dnsRoutes) {
            try {
                if (route.contains('/')) {
                    val parts = route.split('/')
                    builder.addRoute(parts[0], parts[1].toInt())
                } else {
                    builder.addRoute(route, 32)
                }
            } catch (_: Exception) {
            }
        }

        tunFd = builder.establish()
        if (tunFd == null) {
            DnsFilterPrefs.setVpnActive(this, false)
            stopSelf()
            return
        }
        DnsFilterPrefs.setVpnActive(this, true)
        running.set(true)
        worker = Thread({ runLoop() }, "DnsFilterVpn").also { it.start() }
    }

    private fun stopVpn() {
        running.set(false)
        worker?.interrupt()
        worker = null
        try {
            tunFd?.close()
        } catch (_: Exception) {
        }
        tunFd = null
        DnsFilterPrefs.setVpnActive(this, false)
    }

    private fun runLoop() {
        val fd = tunFd ?: return
        val input = FileInputStream(fd.fileDescriptor)
        val output = FileOutputStream(fd.fileDescriptor)
        val packet = ByteArray(32767)
        while (running.get()) {
            try {
                val length = input.read(packet)
                if (length <= 0) continue
                val response = handlePacket(packet, length)
                if (response != null) {
                    output.write(response)
                }
            } catch (_: InterruptedException) {
                break
            } catch (_: Exception) {
                // keep loop alive
            }
        }
    }

    private fun handlePacket(packet: ByteArray, length: Int): ByteArray? {
        if (length < 20) return null
        val version = (packet[0].toInt() shr 4) and 0xF
        if (version != 4) return null
        val ihl = (packet[0].toInt() and 0xF) * 4
        if (length < ihl + 8) return null
        val protocol = packet[9].toInt() and 0xFF
        if (protocol != OsConstants.IPPROTO_UDP) return null

        val srcIp = packet.copyOfRange(12, 16)
        val dstIp = packet.copyOfRange(16, 20)
        val udpOffset = ihl
        val srcPort = readPort(packet, udpOffset)
        val dstPort = readPort(packet, udpOffset + 2)
        if (dstPort != 53 && srcPort != 53) return null

        val udpLen = readUint16(packet, udpOffset + 4)
        val dnsOffset = udpOffset + 8
        val dnsLen = udpLen - 8
        if (dnsLen <= 0 || dnsOffset + dnsLen > length) return null

        val queryPayload = packet.copyOfRange(dnsOffset, dnsOffset + dnsLen)
        val query = DnsMessageCodec.parseQuery(queryPayload, queryPayload.size) ?: return null

        val responseDns = resolveQuery(query, queryPayload)
        return buildUdpIpResponse(
            srcIp = dstIp,
            dstIp = srcIp,
            srcPort = 53,
            dstPort = srcPort,
            dnsPayload = responseDns,
        )
    }

    private fun resolveQuery(query: DnsMessageCodec.Query, queryPayload: ByteArray): ByteArray {
        if (DnsBlocklist.isBlocked(this, query.qname)) {
            return DnsMessageCodec.buildNxDomain(query)
        }
        val upstream = DnsFilterPrefs.upstreamDns(this)
        return DnsMessageCodec.forwardQuery(
            queryPayload,
            queryPayload.size,
            upstream,
        ) { socket -> protect(socket) }
            ?: DnsMessageCodec.buildNxDomain(query)
    }

    private fun buildUdpIpResponse(
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        dnsPayload: ByteArray,
    ): ByteArray {
        val udpLen = 8 + dnsPayload.size
        val totalLen = 20 + udpLen
        val buf = ByteBuffer.allocate(totalLen).order(ByteOrder.BIG_ENDIAN)
        buf.put(0x45.toByte())
        buf.put(0)
        buf.putShort(totalLen.toShort())
        buf.putShort(0)
        buf.putShort(0x4000.toShort())
        buf.put(64.toByte())
        buf.put(OsConstants.IPPROTO_UDP.toByte())
        buf.putShort(0)
        buf.put(srcIp)
        buf.put(dstIp)
        buf.putShort(srcPort.toShort())
        buf.putShort(dstPort.toShort())
        buf.putShort(udpLen.toShort())
        buf.putShort(0)
        buf.put(dnsPayload)
        val out = buf.array()
        val ipChecksum = ipChecksum(out, 0, 20)
        out[10] = (ipChecksum shr 8).toByte()
        out[11] = ipChecksum.toByte()
        return out
    }

    private fun ipChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        while (i < offset + length) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }
        while (sum shr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return sum.inv() and 0xFFFF
    }

    private fun readPort(data: ByteArray, offset: Int): Int =
        ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)

    private fun readUint16(data: ByteArray, offset: Int): Int =
        ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)

    private fun buildNotification(): android.app.Notification {
        val channelId = "mindsync_dns_filter"
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val mgr = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
            val channel = android.app.NotificationChannel(
                channelId,
                "DNS content filter",
                android.app.NotificationManager.IMPORTANCE_LOW,
            )
            mgr.createNotificationChannel(channel)
        }
        val status = DnsFilterPrefs.filterStatusLabel(this)
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("MindSync DNS filter active")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.example.frontend.dns_filter.STOP"
        private const val NOTIFICATION_ID = 4102

        fun start(context: android.content.Context) {
            val intent = Intent(context, DnsFilterVpnService::class.java)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: android.content.Context) {
            val intent = Intent(context, DnsFilterVpnService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
