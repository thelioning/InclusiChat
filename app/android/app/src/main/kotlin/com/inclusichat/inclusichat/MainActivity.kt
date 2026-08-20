package com.inclusichat.inclusichat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        var instance: MainActivity? = null
        const val CHANNEL = "com.inclusichat/ringtone"
    }

    private var methodChannel: MethodChannel? = null
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var toneGenerator: ToneGenerator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val callId = intent?.getStringExtra("call_id")
        if (callId != null) {
            stopIncomingRinging()

            val serviceIntent = Intent(applicationContext, InclusiChatCallService::class.java).apply {
                action = InclusiChatCallService.ACTION_CALL_HANDLED
                putExtra("call_id", callId)
            }
            startService(serviceIntent)

            val conversationId = intent.getStringExtra("conversation_id")
            val callerName = intent.getStringExtra("caller_name") ?: "Contacto"
            val callerId = intent.getStringExtra("caller_id")

            methodChannel?.invokeMethod("onIncomingCallFromNotification", mapOf(
                "call_id" to callId,
                "conversation_id" to conversationId,
                "caller_name" to callerName,
                "caller_id" to callerId
            ))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundCallService" -> {
                    val userId = call.argument<String>("userId")
                    val authToken = call.argument<String>("authToken")
                    val supabaseUrl = call.argument<String>("supabaseUrl")
                    val apiKey = call.argument<String>("apiKey")

                    startBackgroundCallService(userId, authToken, supabaseUrl, apiKey)
                    result.success(true)
                }
                "stopBackgroundCallService" -> {
                    stopBackgroundCallService()
                    result.success(true)
                }
                "startIncomingRinging" -> {
                    val callerName = call.argument<String>("callerName") ?: "Contacto"
                    startIncomingRinging(callerName)
                    result.success(true)
                }
                "stopIncomingRinging" -> {
                    stopIncomingRinging()
                    result.success(true)
                }
                "startOutgoingDialTone" -> {
                    startOutgoingDialTone()
                    result.success(true)
                }
                "stopOutgoingDialTone" -> {
                    stopOutgoingDialTone()
                    result.success(true)
                }
                "bringAppToFront" -> {
                    bringAppToFront()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startBackgroundCallService(userId: String?, authToken: String?, supabaseUrl: String?, apiKey: String?) {
        try {
            val intent = Intent(applicationContext, InclusiChatCallService::class.java).apply {
                action = InclusiChatCallService.ACTION_START_SERVICE
                putExtra("userId", userId)
                putExtra("authToken", authToken)
                putExtra("supabaseUrl", supabaseUrl)
                putExtra("apiKey", apiKey)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopBackgroundCallService() {
        try {
            val intent = Intent(applicationContext, InclusiChatCallService::class.java).apply {
                action = InclusiChatCallService.ACTION_STOP_SERVICE
            }
            startService(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun bringAppToFront() {
        try {
            val intent = Intent(applicationContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun startIncomingRinging(callerName: String) {
        stopIncomingRinging()
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val ringerMode = audioManager.ringerMode

            // 1. Vibrador real de hardware de Android en bucle
            if (ringerMode != AudioManager.RINGER_MODE_SILENT) {
                vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                    vibratorManager.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }

                val pattern = longArrayOf(0, 1000, 1000)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(pattern, 0)
                    vibrator?.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(pattern, 0)
                }
            }

            // 2. Timbre oficial de llamadas de Android con volumen del sistema
            if (ringerMode == AudioManager.RINGER_MODE_NORMAL) {
                val notificationUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

                ringtone = RingtoneManager.getRingtone(applicationContext, notificationUri)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    ringtone?.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ringtone?.isLooping = true
                }
                ringtone?.play()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stopIncomingRinging() {
        try {
            ringtone?.stop()
            ringtone = null
            vibrator?.cancel()
            vibrator = null

            // También notificar al servicio de segundo plano
            val serviceIntent = Intent(applicationContext, InclusiChatCallService::class.java).apply {
                action = InclusiChatCallService.ACTION_CALL_HANDLED
            }
            startService(serviceIntent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startOutgoingDialTone() {
        stopOutgoingDialTone()
        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80)
            toneGenerator?.startTone(ToneGenerator.TONE_SUP_RINGTONE)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopOutgoingDialTone() {
        try {
            toneGenerator?.stopTone()
            toneGenerator?.release()
            toneGenerator = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        if (instance == this) instance = null
        stopIncomingRinging()
        stopOutgoingDialTone()
        super.onDestroy()
    }
}
