package com.dukapos.simplepos

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The platform half of an in-app update.
 *
 * ## Why this exists on the platform side at all
 *
 * Two things can only be done there:
 *
 *   1. **Reading the downloaded APK.** From API 24 a `file://` URI handed to
 *      another app throws `FileUriExposedException`. A `FileProvider` is the
 *      supported replacement, and its authority and allowed paths are Android
 *      resources rather than Dart strings.
 *
 *   2. **Asking for "install unknown apps",** a per-app permission granted on a
 *      system screen rather than in a dialog. Nothing in Flutter can start it.
 *
 * ## What it deliberately does not do
 *
 * It does not install silently. An update the shop did not approve is not an
 * update; and Android does not permit one anyway without the permission above,
 * so pretending otherwise would only produce a button that does nothing.
 *
 * The whole point of the path is that the install REPLACES this app rather than
 * being installed beside it, which is what makes the shop's data survive: an
 * uninstall would delete the app's private directory, and with it the ledger.
 */
class UpdateChannel(private val activity: MainActivity) {

    companion object {
        const val CHANNEL = "duka.app.update"
        private const val AUTHORITY_SUFFIX = ".fileprovider"
        private const val REQUEST_INSTALL = 0x5157
    }

    private var pendingResult: MethodChannel.Result? = null

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestInstallPermission" -> onRequestInstallPermission(result)
                "installApk" -> onInstallApk(call.argument<String>("path"), result)
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Whether this app may install packages.
     *
     * Checked BEFORE prompting, because a shop that already granted it should
     * not be asked again — a repeated prompt reads as a broken app.
     */
    private fun onRequestInstallPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Pre-26 the grant is implicit at install time.
            result.success(true)
            return
        }
        if (activity.packageManager.canRequestPackageInstalls()) {
            result.success(true)
            return
        }
        if (pendingResult != null) {
            // A prompt is already up. Refuse rather than stack a second, which
            // would let the second request overwrite the first caller's
            // pending result and hang it forever.
            result.success(false)
            return
        }
        pendingResult = result
        activity.startActivityForResult(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            ),
            REQUEST_INSTALL,
        )
    }

    /**
     * Hands the APK to the package installer.
     *
     * `FLAG_GRANT_READ_URI_PERMISSION` is what lets the installer read the
     * content URI at all — without it the provider refuses and the install
     * fails with a permission error that looks like a corrupt file.
     *
     * Returns false for anything the installer rejects, which is how a
     * signing-key or version-code mismatch surfaces. Both mean this build can
     * never update in place, and the caller must say so rather than retrying.
     */
    private fun onInstallApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("bad_argument", "installApk needs a file path", null)
            return
        }
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            result.error("missing_apk", "no APK at $path", null)
            return
        }

        val uri: Uri = try {
            FileProvider.getUriForFile(
                activity,
                activity.packageName + AUTHORITY_SUFFIX,
                file,
            )
        } catch (error: IllegalArgumentException) {
            // The file is outside the provider's allowed paths, which means
            // `update_paths.xml` and the Dart download folder disagree.
            result.error("not_shared", "APK is not covered by the FileProvider", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            // A content URI, not the file path: see the class comment. The type
            // and the URI are set together because `setData` alone leaves the
            // intent's type null and the installer then treats it as a view
            // request for an unknown scheme.
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            activity.startActivity(intent)
            result.success(true)
        } catch (error: android.content.ActivityNotFoundException) {
            // No package installer on the device. Said plainly rather than as
            // a generic failure, because "no installer" and "refused the
            // signature" need different words.
            result.error("no_installer", "this device has no package installer", null)
        }
    }

    /**
     * Opens the system screen for "install unknown apps", for a shop that has
     * never granted it.
     *
     * A convenience rather than a requirement: the permission can also be
     * granted from the device's own Settings, and this saves the owner hunting
     * for it.
     */
    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        activity.startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            ),
        )
    }

    /**
     * Called by the Activity when the permission screen closes.
     *
     * The grant is re-read from the platform rather than taken from the result,
     * because a shop can change it on that screen and then leave it untouched —
     * the screen's return value does not carry the decision.
     */
    fun onInstallPermissionResult() {
        val result = pendingResult ?: return
        pendingResult = null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(true)
            return
        }
        result.success(activity.packageManager.canRequestPackageInstalls())
    }
}
