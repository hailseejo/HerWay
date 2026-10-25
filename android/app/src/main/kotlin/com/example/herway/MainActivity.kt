package com.example.herway

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val SMS_CHANNEL = "herway/sms"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SMS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "composeSms") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val arguments = call.arguments as? Map<*, *>
            val recipients = (arguments?.get("recipients") as? List<*>)
                ?.filterIsInstance<String>()
                ?.filter { it.isNotBlank() }
                ?: (arguments?.get("recipient") as? String)?.let(::listOf)
                ?: emptyList()
            val body = arguments?.get("body") as? String

            if (recipients.isEmpty() || body == null) {
                result.error("invalid_sms", "Recipients and message are required.", null)
                return@setMethodCallHandler
            }

            val intent = Intent(
                Intent.ACTION_SENDTO,
                Uri.parse("smsto:${recipients.joinToString(";")}"),
            ).apply {
                putExtra("sms_body", body)
            }
            try {
                startActivity(intent)
                result.success(true)
            } catch (_: ActivityNotFoundException) {
                result.error("sms_unavailable", "SMS is unavailable on this device.", null)
            }
        }
    }
}
