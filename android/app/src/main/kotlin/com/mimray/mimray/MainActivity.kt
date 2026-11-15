package com.mimray.mimray

import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import com.google.zxing.integration.android.IntentIntegrator
import java.io.File

/**
 * Bridge to the Dart side:
 *  - method channel "mimray/vpn": filesDir, start(config) (asks for VPN permission
 *    the first time), stop, status, installApk(path), openUrl(url),
 *    scanQr() -> text|null (camera), pickFile(mime) -> cached path|null
 *  - event channel "mimray/vpn/events": {status: starting|started|stopped, error}
 */
class MainActivity : FlutterActivity() {
    private var pendingConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var events: EventChannel.EventSink? = null
    private var pendingScan: MethodChannel.Result? = null
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "mimray/vpn").setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.path)
                "status" -> result.success(MimrayVpnService.status)
                "start" -> {
                    val config = call.argument<String>("config")
                        ?: return@setMethodCallHandler result.error("args", "config missing", null)
                    val consent = VpnService.prepare(this)
                    if (consent != null) {
                        pendingConfig = config
                        pendingResult = result
                        startActivityForResult(consent, REQUEST_VPN)
                    } else {
                        startVpn(config)
                        result.success(true)
                    }
                }
                "installApk" -> {
                    // hand the downloaded, sha256-verified APK to Android's installer
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.error("args", "path missing", null)
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                "scanQr" -> {
                    // ZXing scanner: on-device, no Play Services, asks for camera permission itself
                    pendingScan = result
                    IntentIntegrator(this)
                        .setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
                        .setPrompt("Point the camera at a server or subscription QR code")
                        .setBeepEnabled(false)
                        .setOrientationLocked(false)
                        .initiateScan()
                }
                "pickFile" -> {
                    // system document picker: no storage permission needed
                    pendingPick = result
                    startActivityForResult(
                        Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(call.argument<String>("mime") ?: "*/*"),
                        REQUEST_PICK,
                    )
                }
                "openUrl" -> {
                    // "Share your server": open the GitHub issue form in the browser
                    val url = call.argument<String>("url")
                    if (url == null || !url.startsWith("https://")) {
                        return@setMethodCallHandler result.error("args", "https url required", null)
                    }
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "stop" -> {
                    startService(Intent(this, MimrayVpnService::class.java).setAction(MimrayVpnService.ACTION_STOP))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "mimray/vpn/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                events = sink
                MimrayVpnService.listener = { status, error ->
                    runOnUiThread { events?.success(mapOf("status" to status, "error" to error)) }
                }
            }

            override fun onCancel(arguments: Any?) {
                events = null
                MimrayVpnService.listener = null
            }
        })
    }

    private fun startVpn(config: String) {
        val i = Intent(this, MimrayVpnService::class.java)
            .setAction(MimrayVpnService.ACTION_START)
            .putExtra(MimrayVpnService.EXTRA_CONFIG, config)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
    }

    @Deprecated("Activity result API is overkill for one request")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        IntentIntegrator.parseActivityResult(requestCode, resultCode, data)?.let {
            pendingScan?.success(it.contents) // null when cancelled
            pendingScan = null
            return
        }
        if (requestCode == REQUEST_PICK) {
            val result = pendingPick
            pendingPick = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) return result?.success(null) ?: Unit
            Thread {
                val path = runCatching { copyToCache(uri) }.getOrNull()
                runOnUiThread { result?.success(path) }
            }.start()
            return
        }
        if (requestCode != REQUEST_VPN) return
        val config = pendingConfig
        val result = pendingResult
        pendingConfig = null
        pendingResult = null
        if (resultCode == RESULT_OK && config != null) {
            startVpn(config)
            result?.success(true)
        } else {
            result?.success(false) // user declined the VPN permission
        }
    }

    /** Copies a picked document into the cache (max 10 MB) so Dart can read it by path. */
    private fun copyToCache(uri: Uri): String {
        val out = File(cacheDir, "picked").apply { mkdirs() }.resolve("import")
        contentResolver.openInputStream(uri)!!.use { input ->
            out.outputStream().use { output ->
                val buf = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > 10L * 1024 * 1024) error("file too large")
                    output.write(buf, 0, n)
                }
            }
        }
        return out.path
    }

    companion object {
        private const val REQUEST_VPN = 1
        private const val REQUEST_PICK = 2
    }
}
