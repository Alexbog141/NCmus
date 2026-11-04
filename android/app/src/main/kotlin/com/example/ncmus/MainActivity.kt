package com.example.ncmus

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the audio service and exposes the few Android-only operations that
 * have no cross-platform Flutter plugin in this project:
 *
 * - POST_NOTIFICATIONS runtime permission for the media notification;
 * - launching the system package installer for a downloaded APK update.
 */
class MainActivity : AudioServiceActivity() {

    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        requestNotificationPermission(result)
                    }

                    "canInstallPackages" -> {
                        result.success(canInstallPackages())
                    }

                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "APK path is empty.", null)
                        } else {
                            installApk(path, result)
                        }
                    }

                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("invalid_url", "URL is empty.", null)
                        } else {
                            openUrl(url, result)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }

        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST
        )
    }

    private fun canInstallPackages(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }
    }

    private fun openUrl(url: String, result: MethodChannel.Result) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            result.success(true)
        } catch (error: Exception) {
            result.error(
                "open_url_failed",
                error.message ?: "Unable to open the release page.",
                null
            )
        }
    }

    /**
     * Returns true/false when both signatures can be read, or null when the
     * platform cannot inspect them. A null result lets the system installer
     * make the final decision instead of blocking a potentially valid update.
     */
    private fun signaturesMatch(apkFile: File): Boolean? {
        return try {
            val pm = packageManager
            val installed: Array<Signature>?
            val archive: Array<Signature>?

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                installed = pm.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                ).signingInfo?.apkContentsSigners
                archive = pm.getPackageArchiveInfo(
                    apkFile.absolutePath,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )?.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                installed = pm.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                ).signatures
                @Suppress("DEPRECATION")
                archive = pm.getPackageArchiveInfo(
                    apkFile.absolutePath,
                    PackageManager.GET_SIGNATURES
                )?.signatures
            }

            if (installed == null || archive == null) {
                null
            } else {
                installed.any { current ->
                    archive.any { candidate ->
                        current.toByteArray().contentEquals(candidate.toByteArray())
                    }
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        if (!canInstallPackages()) {
            openInstallSettings()
            result.success("permission_required")
            return
        }

        try {
            val apkFile = File(path)
            if (!apkFile.exists() || apkFile.length() <= 0L) {
                result.error("apk_not_found", "Downloaded APK was not found.", null)
                return
            }

            if (signaturesMatch(apkFile) == false) {
                result.success("signature_mismatch")
                return
            }

            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                clipData = ClipData.newRawUri("NCmus update", apkUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            startActivity(intent)
            result.success("started")
        } catch (error: Exception) {
            result.error(
                "install_failed",
                error.message ?: "Unable to start the package installer.",
                null
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingNotificationPermissionResult?.success(granted)
        pendingNotificationPermissionResult = null
    }

    companion object {
        private const val CHANNEL_NAME = "com.example.ncmus/system"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4711
    }
}
