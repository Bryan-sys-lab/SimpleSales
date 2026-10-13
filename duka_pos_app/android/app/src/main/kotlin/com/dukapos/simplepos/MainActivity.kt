package com.dukapos.simplepos

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var printer: PrinterChannel? = null

    /** The platform half of an in-app update. */
    private var updates: UpdateChannel? = null

    /**
     * Bridges the Bluetooth permission prompt.
     *
     * The result is delivered to a callback rather than routed back through
     * Flutter: a permission dialog is a platform result, and routing it through
     * the Dart channel would let a second request overwrite the first caller's
     * pending result and hang it forever.
     */
    private var permissionCallback: ((Boolean) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The Activity is passed rather than `applicationContext` because the
        // channel needs to raise the permission dialog and read the bonding
        // state, and neither is available from the application context.
        printer = PrinterChannel(this, flutterEngine.dartExecutor.binaryMessenger)

        // Same messenger, same Activity. Registered here rather than lazily on
        // first use because a method channel that arrives before its handler is
        // set is answered with `notImplemented`, and a shop tapping "check for
        // updates" on a cold start would see a dead button.
        UpdateChannel(this).also {
            updates = it
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    fun requestBluetoothPermission(callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // Pre-31 there is no runtime dialog; the manifest grant is all
            // there is and it has already been checked by the caller.
            callback(false)
            return
        }
        if (permissionCallback != null) {
            // A prompt is already up. Refuse rather than stack a second: the
            // first caller keeps its own result.
            callback(false)
            return
        }
        permissionCallback = callback
        requestPermissions(
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            REQUEST_CODE_BLUETOOTH,
        )
    }

    /**
     * Called when the "install unknown apps" screen closes.
     *
     * Routed to the update channel rather than handled here, for the same
     * reason the Bluetooth result is: the channel owns its own pending result
     * and the single caller waiting on it.
     */
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: android.content.Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == UpdateChannel.REQUEST_INSTALL) {
            updates?.onInstallPermissionResult()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE_BLUETOOTH) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val callback = permissionCallback
        permissionCallback = null
        callback?.invoke(granted)
    }

    override fun onDestroy() {
        // The Bluetooth socket outlives the Flutter engine, so it is closed
        // explicitly rather than waiting for a GC finaliser that may never run.
        printer?.dispose()
        printer = null
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_CODE_BLUETOOTH = 4711
    }
}