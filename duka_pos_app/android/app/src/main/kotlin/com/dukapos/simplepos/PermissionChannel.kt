package com.dukapos.simplepos

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The camera runtime permission, over a method channel.
 *
 * WHY THIS IS OWNED OUTRIGHT
 *
 * The alternative is the `permission_handler` pub package. This app already
 * owns its Bluetooth channel outright for the same reason — the package it
 * wanted was discontinued, and a till should not carry a dependency graph for
 * one question. The camera permission is three calls: is it held, ask for it,
 * and has the owner said "don't ask again".
 *
 * WHY IT IS A SEPARATE CHANNEL FROM THE PRINTER'S
 *
 * The printer's channel already owns the BLUETOOTH_CONNECT permission, and
 * asking for the same permission from two channels is two code paths that can
 * disagree about whether it is held. The camera permission belongs to nobody
 * else, so it gets its own channel rather than a shared one.
 *
 * THE CALLBACK, NOT A ROUTED RESULT
 *
 * A permission dialog is a platform result. Routing it back through the Dart
 * channel would let a second request overwrite the first caller's pending
 * result and hang it forever — the same reasoning as the printer's bridge, and
 * the same shape.
 */
class PermissionChannel(private val activity: android.app.Activity) {
    companion object {
        private const val CHANNEL = "duka_pos/permissions"
        private const val REQUEST_CODE_CAMERA = 4712
    }

    /** The pending camera-permission result, if one is waiting. */
    private var permissionCallback: ((Boolean) -> Unit)? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasCameraPermission" -> reply(result) { hasCameraPermission() }
                "requestCameraPermission" -> requestCameraPermission(result)
                "isCameraPermissionPermanentlyDenied" ->
                    reply(result) { isCameraPermissionPermanentlyDenied() }
                else -> result.notImplemented()
            }
        }
    }

    /** Runs [block] and answers with its result, or with false if it throws. */
    private fun reply(result: MethodChannel.Result, block: () -> Boolean) {
        try {
            result.success(block())
        } catch (e: Exception) {
            result.success(false)
        }
    }

    /**
     * Whether the camera permission is held.
     *
     * Below API 23 the permission is granted at install time, so it is always
     * held and there is no dialog to raise.
     */
    private fun hasCameraPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return activity.checkSelfPermission(Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * Whether the owner said "don't ask again".
     *
     * True only when the permission is NOT held AND the system says it will not
     * show a rationale — which is the state only the system Settings screen can
     * undo. It is the difference between "ask again" and "send them to
     * Settings", and the app must not send somebody to Settings for a
     * permission they have not refused.
     */
    private fun isCameraPermissionPermanentlyDenied(): Boolean {
        if (hasCameraPermission()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return !activity.shouldShowRequestPermissionRationale(
            Manifest.permission.CAMERA
        )
    }

    /**
     * Raises the system prompt, if there is one to raise.
     *
     * The result is delivered through the activity's own callback rather than
     * through the method channel, so a second request cannot overwrite a
     * pending one.
     */
    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (hasCameraPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            // Below API 23 there is no runtime prompt: the manifest grant is
            // all there is.
            result.success(true)
            return
        }
        if (permissionCallback != null) {
            // A prompt is already up. Refuse rather than stack a second.
            result.success(false)
            return
        }
        permissionCallback = { granted -> result.success(granted) }
        activity.requestPermissions(
            arrayOf(Manifest.permission.CAMERA),
            REQUEST_CODE_CAMERA,
        )
    }

    /**
     * Called by the activity when the prompt is answered.
     *
     * Returns whether the request was one of ours, so the activity can pass it
     * on to the printer's own handler.
     */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE_CAMERA) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val callback = permissionCallback
        permissionCallback = null
        callback?.invoke(granted)
        return true
    }
}
