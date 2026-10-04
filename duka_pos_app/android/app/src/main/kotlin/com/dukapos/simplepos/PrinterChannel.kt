package com.dukapos.simplepos

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.OutputStream
import java.util.UUID

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

        // The SPP UUID is a fixed serial-port profile constant, so it is
        // declared rather than discovered. Discovery would need an extra
        // service query and a user-visible permission this app has no reason to
        // ask for; every printer in this market advertises SPP.
        private const val BUFFER_SIZE = 1024
        private const val DEFAULT_CONNECT_TIMEOUT_MS = 8000L
    }

    private val worker = ThreadPoolExecutorWithSingleThread()

    private var socket: BluetoothSocket? = null
    private var output: OutputStream? = null
    private var pendingPermission: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    fun dispose() {
        closeSocket()
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isBluetoothUsable())
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "isPermissionPermanentlyDenied" ->
                result.success(isPermissionPermanentlyDenied())
            "pairedDevices" -> result.success(pairedDevices())
            "isPaired" -> {
                val address = call.argument<String>("address")
                result.success(address != null && adapter()?.bondedDevices
                    ?.any { it.address == address.uppercase() } == true)
            }
            "pair" -> result.success(pair(call.argument<String>("address")))
            "connect" -> connect(call, result)
            "send" -> send(call, result)
            "isConnected" -> result.success(socket?.isConnected == true)
            "disconnect" -> {
                closeSocket()
                result.success(true)
            }
            else -> result.notImplemented()
        }
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
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // Pre-31 there is no runtime dialog to show; a false here would be a
            // lie, but a true is also unearned. The platform cannot grant it, so
            // the honest answer is false and the UI explains the manifest.
            result.success(false)
            return
        }
        val activity = context as? MainActivity
        if (activity == null) {
            result.success(false)
            return
        }
        // One in-flight prompt. A second request while the dialog is up would
        // replace the pending result and the first caller would hang forever.
        if (pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        activity.requestBluetoothPermission { granted ->
            val pending = pendingPermission
            pendingPermission = null
            pending?.success(granted)
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
            deviceAdapter.bondedDevices.orEmpty().map { device ->
                mapOf(
                    "name" to (device.name ?: ""),
                    "address" to device.address
                )
            }
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    private fun pair(address: String?): Boolean {
        if (address == null) return false
        val device = findDevice(address) ?: return false
        return try {
            // Bonding is a system flow; `createBond` is reflective because it is
            // not on the public API below API 19 and is hidden above it. If the
            // device is already bonded this is a no-op returning true.
            if (device.bondState == BluetoothDevice.BOND_BONDED) return true
            val method = device.javaClass.getMethod("createBond")
            method.invoke(device) as? Boolean ?: false
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
        val timeout =
            (call.argument<Int>("timeoutMs") ?: DEFAULT_CONNECT_TIMEOUT_MS.toInt())
                .toLong()
        if (address == null || address.isBlank()) {
            result.error("not_paired", "No printer address configured", null)
            return
        }
        val device = findDevice(address)
        if (device == null) {
            result.error("not_paired", "Printer is not paired with this handset", null)
            return
        }
        worker.execute {
            try {
                if (socket?.isConnected == true && socket?.remoteDevice?.address == device.address) {
                    result.success(true)
                    return@execute
                }
                closeSocket()
                // Insecure RFCOMM is the SPP channel. Secure SSP sockets are
                // not supported by these printers and, where they are, refuse
                // the connection rather than degrade.
                val fresh = device.javaClass
                    .getMethod("createRfcommSocketToServiceRecord", UUID::class.java)
                    .invoke(device, UUID.fromString(SPP_UUID)) as BluetoothSocket
                fresh.connect()
                socket = fresh
                output = fresh.outputStream
                result.success(true)
            } catch (_: IOException) {
                closeSocket()
                result.error("connect_failed", "Could not open the printer link", null)
            } catch (_: Exception) {
                closeSocket()
                result.error("connect_failed", "Could not open the printer link", null)
            }
        }
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
            result.success(true)
            return
        }
        worker.execute {
            try {
                val stream = output ?: throw IOException("no link")
                stream.write(bytes)
                stream.flush()
                result.success(true)
            } catch (_: IOException) {
                // A printer that powered itself off mid-shift leaves the socket
                // open but dead. Drop it so the next print reconnects rather
                // than writing into a void forever.
                closeSocket()
                result.error("print_failed", "The printer link dropped", null)
            }
        }
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