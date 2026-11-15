package com.mimray.mimray

import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge to the Dart side:
 *  - method channel "mimray/vpn": filesDir, start(config) (asks for VPN permission
 *    the first time), stop, status
 *  - event channel "mimray/vpn/events": {status: starting|started|stopped, error}
 */
class MainActivity : FlutterActivity() {
    private var pendingConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var events: EventChannel.EventSink? = null

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

    companion object {
        private const val REQUEST_VPN = 1
    }
}
