package com.example.frontend

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Minimal DNS message codec for A/AAAA queries over UDP.
 */
object DnsMessageCodec {
    data class Query(
        val transactionId: Int,
        val qname: String,
        val qtype: Int,
    )

    fun parseQuery(payload: ByteArray, length: Int): Query? {
        if (length < 12) return null
        val id = ((payload[0].toInt() and 0xFF) shl 8) or (payload[1].toInt() and 0xFF)
        val flags = ((payload[2].toInt() and 0xFF) shl 8) or (payload[3].toInt() and 0xFF)
        if ((flags shr 15) and 1 != 0) return null // response
        val qdCount = ((payload[4].toInt() and 0xFF) shl 8) or (payload[5].toInt() and 0xFF)
        if (qdCount != 1) return null
        var offset = 12
        val nameParts = mutableListOf<String>()
        while (offset < length) {
            val len = payload[offset].toInt() and 0xFF
            offset++
            if (len == 0) break
            if (len >= 0xC0) return null // compression not expected in question
            if (offset + len > length) return null
            nameParts.add(String(payload, offset, len, Charsets.US_ASCII).lowercase())
            offset += len
        }
        if (offset + 4 > length) return null
        val qtype = ((payload[offset].toInt() and 0xFF) shl 8) or (payload[offset + 1].toInt() and 0xFF)
        return Query(id, nameParts.joinToString("."), qtype)
    }

    fun safeSearchOverride(host: String): ByteArray? = null

    fun buildQuery(transactionId: Int, qname: String, qtype: Int): ByteArray {
        val qnameBytes = encodeName(qname)
        val buf = ByteBuffer.allocate(12 + qnameBytes.size + 4).order(ByteOrder.BIG_ENDIAN)
        buf.putShort(transactionId.toShort())
        buf.putShort(0x0100.toShort())
        buf.putShort(1)
        buf.putShort(0)
        buf.putShort(0)
        buf.putShort(0)
        buf.put(qnameBytes)
        buf.putShort(qtype.toShort())
        buf.putShort(1)
        return buf.array()
    }

    fun buildNxDomain(query: Query): ByteArray = buildAnswer(query, rcode = 3, ip = null)

    fun buildARecord(query: Query, ip: ByteArray): ByteArray = buildAnswer(query, rcode = 0, ip = ip)

    private fun buildAnswer(query: Query, rcode: Int, ip: ByteArray?): ByteArray {
        val qnameBytes = encodeName(query.qname)
        val answerSize = if (ip != null) 16 else 0
        val buf = ByteBuffer.allocate(12 + qnameBytes.size + 4 + answerSize)
            .order(ByteOrder.BIG_ENDIAN)
        buf.putShort(query.transactionId.toShort())
        val flags = 0x8180 or (rcode and 0xF) // QR=1, AA=1
        buf.putShort(flags.toShort())
        buf.putShort(1) // QDCOUNT
        buf.putShort(if (ip != null) 1 else 0) // ANCOUNT
        buf.putShort(0)
        buf.putShort(0)
        buf.put(qnameBytes)
        buf.putShort(query.qtype.toShort())
        buf.putShort(1) // IN
        if (ip != null) {
            buf.putShort(0xC00C.toShort()) // pointer to question name
            buf.putShort(1) // A
            buf.putShort(1) // IN
            buf.putInt(300) // TTL
            buf.putShort(4)
            buf.put(ip)
        }
        return buf.array().copyOf(buf.position())
    }

    private fun encodeName(host: String): ByteArray {
        val out = ArrayList<Byte>()
        for (label in host.split('.')) {
            if (label.isEmpty()) continue
            out.add(label.length.toByte())
            label.toByteArray(Charsets.US_ASCII).forEach { out.add(it) }
        }
        out.add(0)
        return out.toByteArray()
    }

    fun forwardQuery(
        queryPayload: ByteArray,
        length: Int,
        upstreamHost: String,
        protect: ((DatagramSocket) -> Unit)? = null,
    ): ByteArray? {
        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            protect?.invoke(socket)
            socket.soTimeout = 4000
            val upstream = InetAddress.getByName(upstreamHost)
            val send = DatagramPacket(queryPayload, length, upstream, 53)
            socket.send(send)
            val recvBuf = ByteArray(4096)
            val recv = DatagramPacket(recvBuf, recvBuf.size)
            socket.receive(recv)
            recv.data.copyOf(recv.length)
        } catch (_: Exception) {
            null
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
        }
    }
}
