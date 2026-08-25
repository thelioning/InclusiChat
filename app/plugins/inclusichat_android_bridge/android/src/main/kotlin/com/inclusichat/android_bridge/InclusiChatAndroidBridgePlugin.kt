package com.inclusichat.android_bridge

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class InclusiChatAndroidBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "finishIncomingCallUi" -> {
                try {
                    val action =
                        "${context.packageName}.com.hiennv.flutter_callkit_incoming.ACTION_ENDED_CALL_INCOMING"
                    val intent = Intent(action).apply {
                        setPackage(context.packageName)
                        putExtra("ACCEPTED", false)
                    }
                    context.sendBroadcast(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("finish_call_ui_failed", error.message, null)
                }
            }
            "isDeviceLocked" -> {
                try {
                    val keyguardManager =
                        context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    result.success(keyguardManager.isKeyguardLocked)
                } catch (error: Exception) {
                    result.error("keyguard_state_failed", error.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val CHANNEL = "com.inclusichat/android_bridge"
    }
}
