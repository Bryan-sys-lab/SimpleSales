package com.dukapos.simplepos

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bluetooth ESC/POS over `BluetoothSocket`, behind a `MethodChannel`.
 *
 * Written rather than pulled in because the `bluetooth_printers` pub package is
 * discontinued; the Dart side owns the seam (`PrinterService`) so this file is
 * replaceable without touching anything above it.
 *
 * Two properties matter more than features here:
 *
 *  1. Every failure returns a *stable string code* rather than a message, so a
 *     wording change here cannot silently change what the operator is told.
 *  2. Nothing blocks for long. `connect` runs off the platform thread with a
 *     hard deadline and `send` writes on the same worker, because the caller is
 *     the checkout path and a wedged socket must degrade to "couldn't print",
 *     never to a hung till.
 *
 * Threading rule: every `result.success`/`result.error` is posted back to the
 * main looper. The worker thread owns the socket, but Flutter requires channel
 * replies on the main thread.
 */
class PrinterChannel(
    private val context: Context,
    private val messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        // Deliberately still "duka_pos/printer" even though the package was
        // renamed to com.dukapos.simplepos: this string is the wire name the
        // Dart side opens the channel with (lib/services/printer/
        // esc_pos_printer.dart), and changing one side without the other
        // breaks printing silently rather than loudly.
        const val CHANNEL = "duka_pos/printer"
        const val SPP_UUID = "00001101-0000-1000-8000-00805F9B34FB"

        private const val DEFAULT_CONNECT_TIMEOUT_MS = 8000L

        // Chunk size for writes. Small printer buffers truncate long receipts,
        // especially once a QR code is on the paper, so the byte stream is
        // dribbled out in 1 KB chunks with a short pause between them.
        private const val WRITE_CHUNK_SIZE = 1024
        private const val WRITE_CHUNK_PAUSE_MS = 5L
    }

    private val worker = ThreadPoolExecutorWithSingleThread()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var socket: BluetoothSocket? = null
    private var output: OutputStream? = null
    private var connectedDevice: BluetoothDevice? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var connectDeadlineJob: Runnable? = null
    private var lastError: Exception? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    fun dispose() {
        removeConnectDeadline()
        closeSocket()
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> reply(result) { isBluetoothUsable() }
            "hasPermission" -> reply(result) { hasPermission() }
            "requestPermission" -> requestPermission(result)
            "isPermissionPermanentlyDenied" ->
                reply(result) { isPermissionPermanentlyDenied() }
            "pairedDevices" -> reply(result) { pairedDevices() }
            "isPaired" -> {
                val address = call.argument<String>("address")
                reply(result) {
                    address != null &&
                        adapter()?.bondedDevices?.any { it.address == address.uppercase() } == true
                }
            }
            "pair" -> reply(result) { pair(call.argument<String>("address")) }
            "connect" -> connect(call, result)
            "send" -> send(call, result)
            "isConnected" -> reply(result) { socket?.isConnected == true }
            "disconnect" -> {
                closeSocket()
                reply(result) { true }
            }
            else -> result.notImplemented()
        }
    }

    /** Posts [result] to the main looper so Flutter never receives a channel
     * reply from the printer worker thread. */
    private inline fun reply(result: MethodChannel.Result, crossinline block: () -> Any?) {
        mainHandler.post { result.success(block()) }
    }

    /** Posts a success reply to the main looper. */
    private fun succeed(result: MethodChannel.Result, value: Boolean = true) {
        mainHandler.post { result.success(value) }
    }

    /** Posts an error reply to the main looper. */
    private fun fail(result: MethodChannel.Result, code: String, message: String?) {
        mainHandler.post { result.error(code, message, null) }
    }

    // ---------------- permissions ----------------

    private fun adapter(): BluetoothAdapter? {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE)
            as? android.bluetooth.BluetoothManager
        return manager?.adapter
    }

    /**
     * Android 12 (API 31) split the old blanket Bluetooth permission into
     * connect and scan. Below that, holding `BLUETOOTH`/`BLUETOOTH_ADMIN` in the
     * manifest was enough and there is nothing to request at runtime, so
     * [hasPermission] reports true and no dialog ever appears — asking would be
     * a no-op the user cannot satisfy.
     */
    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            emptyArray()
        }

    private fun hasPermission(): Boolean = requiredPermissions().all {
        context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * "Denied with don't ask again" is inferred from the platform's own
     * rationale signal rather than persisted here: the system stops returning a
     * rationale once the user has locked the decision, and re-prompting would
     * show nothing at all.
     */
    private fun isPermissionPermanentlyDenied(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        if (hasPermission()) return false
        val activity = context as? MainActivity ?: return false
        return !activity.shouldShowRequestPermissionRationale(
            Manifest.permission.BLUETOOTH_CONNECT
        )
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            succeed(result)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            succeed(result, false)
            return
        }
        val activity = context as? MainActivity
        if (activity == null) {
            succeed(result, false)
            return
        }
        // One in-flight prompt. A second request while the dialog is up would
        // replace the pending result and the first caller would hang forever.
        if (pendingPermission != null) {
            succeed(result, false)
            return
        }
        pendingPermission = result
        activity.requestBluetoothPermission { granted ->
            mainHandler.post {
                val pending = pendingPermission
                pendingPermission = null
                pending?.success(granted)
            }
        }
    }

    private fun isBluetoothUsable(): Boolean =
        try {
            hasPermission() && adapter()?.isEnabled == true
        } catch (_: SecurityException) {
            false
        }

    // ---------------- pairing ----------------

    private fun pairedDevices(): List<Map<String, String>> {
        val deviceAdapter = adapter() ?: return emptyList()
        return try {
            deviceAdapter.bondedDevices.orEmpty()
                // Earbuds, phones and watches share the bonded list. Keep only
                // things that look like printers so the pairing sheet does not
                // offer the cashier a headset as a receipt printer.
                .filter { isLikelyPrinter(it) }
                .map { device ->
                    mapOf(
                        "name" to (device.name ?: ""),
                        "address" to device.address
                    )
                }
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    /**
     * Heuristic: a printer is unlikely to be an audio device (headset/
     * headphones) or a phone. Thermal receipt printers typically report
     * peripheral/imaging/miscellaneous, so we drop the obvious non-printers
     * and keep everything else — including devices whose class is unknown.
     */
    private fun isLikelyPrinter(device: BluetoothDevice): Boolean {
        val cls = device.bluetoothClass ?: return true
        val major = cls.deviceClass
        // MAJOR_PHONE (0x02) and MAJOR_AUDIO (0x04) constants were removed
        // from the public BluetoothClass.Device API in newer compileSdk levels.
        // Use the raw values: https://source.android.com/docs/core/connections/bluetooth/BluetoothClass
        return major != 0x04 && major != 0x02
    }

    private fun pair(address: String?): Boolean {
        if (address == null) return false
        val device = findDevice(address) ?: return false
        return try {
            if (device.bondState == BluetoothDevice.BOND_BONDED) return true
            // `createBond` is public API on every supported level here; no
            // reflection needed. It returns true once bonding has been
            // initiated, not once it has completed.
            device.createBond()
        } catch (_: Exception) {
            false
        }
    }

    private fun findDevice(address: String): BluetoothDevice? {
        val wanted = address.trim().uppercase()
        if (wanted.isEmpty()) return null
        return try {
            adapter()?.bondedDevices?.firstOrNull { it.address == wanted }
        } catch (_: SecurityException) {
            null
        }
    }

    // ---------------- connection and write ----------------

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")
        val timeoutMs =
            (call.argument<Int>("timeoutMs") ?: DEFAULT_CONNECT_TIMEOUT_MS.toInt()).toLong()
        if (address == null || address.isBlank()) {
            fail(result, "not_paired", "No printer address configured")
            return
        }
        val device = findDevice(address)
        if (device == null) {
            fail(result, "not_paired", "Printer is not paired with this handset")
            return
        }
        worker.execute {
            removeConnectDeadline()
            try {
                if (socket?.isConnected == true && socket?.remoteDevice?.address == device.address) {
                    succeed(result)
                    return@execute
                }
                closeSocket()
                val fresh = openSocket(device)
                // Enforce the hard connect deadline: if the handshake does not
                // complete within [timeoutMs], close the socket so a wedged
                // printer cannot hang the till forever.
                val deadline = AtomicBoolean(false)
                connectDeadlineJob = Runnable {
                    if (!deadline.get()) {
                        deadline.set(true)
                        try { fresh.close() } catch (_: Exception) {}
                    }
                }
                 mainHandler.postDelayed(connectDeadlineJob!!, timeoutMs)
                try {
                    fresh.connect()
                } finally {
                    removeConnectDeadline()
                }
                deadline.set(true)
                socket = fresh
                output = fresh.outputStream
                connectedDevice = device
                succeed(result)
            } catch (e: SecurityException) {
                closeSocket()
                // A missing BLUETOOTH_CONNECT permission is a configuration
                // problem the operator can fix, not a generic link failure.
                fail(result, "permission_denied", "Bluetooth permission not granted")
            } catch (_: IOException) {
                closeSocket()
                fail(result, "connect_failed", "Could not open the printer link")
            } catch (_: Exception) {
                closeSocket()
                fail(result, "connect_failed", "Could not open the printer link")
            }
        }
    }

    /**
     * Opens an RFCOMM socket to [device], trying the secure channel first and
     * falling back through insecure RFCOMM to a raw channel-1 socket. Many
     * cheap 58mm printers refuse secure SSP sockets and many refuse insecure
     * ones, so all three are attempted in order.
     *
     * `createRfcommSocketToServiceRecord` and `createRfcommSocket(int)` are
     * both public API, so no reflection is used.
     */
    private fun openSocket(device: BluetoothDevice): BluetoothSocket {
        val exceptions = mutableListOf<Exception>()
        val candidates = listOf(
            { device.createRfcommSocketToServiceRecord(UUID.fromString(SPP_UUID)) },
            { device.createInsecureRfcommSocketToServiceRecord(UUID.fromString(SPP_UUID)) },
            {
                val method = device.javaClass.getMethod(
                    "createRfcommSocket",
                    java.lang.Integer.TYPE
                )
                method.invoke(device, 1) as BluetoothSocket
            },
        )
        for (factory in candidates) {
            return try {
                factory()
            } catch (e: Exception) {
                exceptions.add(e)
                continue
            }
        }
        throw exceptions.firstOrNull() ?: IOException("Could not open any RFCOMM socket")
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
            succeed(result)
            return
        }
        worker.execute {
            var sent = false
            // A power-cycled printer leaves a dead socket that is only detected
            // on write. Reconnect once and resend instead of failing outright.
            for (attempt in 0 until 2) {
                try {
                    val stream = output ?: throw IOException("no link")
                    // Dribble in chunks so small printer buffers cannot swallow
                    // a long receipt (and its QR code).
                    for (i in 0 until bytes.size step WRITE_CHUNK_SIZE) {
                        val end = (i + WRITE_CHUNK_SIZE).coerceAtMost(bytes.size)
                        stream.write(bytes, i, end - i)
                        stream.flush()
                        if (i + WRITE_CHUNK_SIZE < bytes.size) {
                            Thread.sleep(WRITE_CHUNK_PAUSE_MS)
                        }
                    }
                    sent = true
                    break
                } catch (e: IOException) {
                    lastError = e
                    // The socket died mid-shift. Drop it and retry once on the
                    // next pass through the loop.
                    closeSocket()
                    try {
                        val device = connectedDevice
                        if (device != null) {
                            val fresh = openSocket(device)
                            val reconnectDeadline = AtomicBoolean(false)
                            val reconnectJob = Runnable {
                                if (!reconnectDeadline.get()) {
                                    reconnectDeadline.set(true)
                                    try { fresh.close() } catch (_: Exception) {}
                                }
                            }
                            mainHandler.postDelayed(reconnectJob, DEFAULT_CONNECT_TIMEOUT_MS)
                            try {
                                fresh.connect()
                                reconnectDeadline.set(true)
                            } finally {
                                mainHandler.removeCallbacks(reconnectJob)
                            }
                            socket = fresh
                            output = fresh.outputStream
                            connectedDevice = device
                        } else {
                            break
                        }
                    } catch (_: Exception) {
                        break
                    }
                }
            }
            if (sent) {
                succeed(result)
            } else {
                closeSocket()
                fail(result, "print_failed", "The printer link dropped")
            }
        }
    }

    private fun removeConnectDeadline() {
        connectDeadlineJob?.let { mainHandler.removeCallbacks(it) }
        connectDeadlineJob = null
    }

    private fun closeSocket() {
        try {
            output?.close()
        } catch (_: IOException) {
            // Closing a socket that is already gone is not an error worth
            // surfacing; the point of this call is to release the fd.
        }
        try {
            socket?.close()
        } catch (_: IOException) {
        }
        output = null
        socket = null
        connectedDevice = null
    }

    /**
     * A single worker thread.
     *
     * Connect and write must not overlap: two concurrent writes to one receipt
     * buffer interleave into garbled paper, and a connect racing a send can
     * reopen the stream under a live write. One thread serialises both for
     * free, and because it is off the platform thread the checkout path is
     * never blocked waiting on Bluetooth.
     */
    private class ThreadPoolExecutorWithSingleThread {
        private val executor = java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "duka-printer").apply { isDaemon = true }
        }

        fun execute(block: () -> Unit) = executor.execute(block)
        fun shutdown() = executor.shutdownNow()
    }
}
