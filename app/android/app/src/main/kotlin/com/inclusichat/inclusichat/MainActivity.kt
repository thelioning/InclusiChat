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
    }

    private val CHANNEL = "com.inclusichat/ringtone"
    private val NOTIFICATION_CHANNEL_ID = "inclusichat_calls_channel"
    private val NOTIFICATION_ID = 9991

    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var toneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Llamadas de InclusiChat"
            val descriptionText = "Notificaciones prioritarias de llamadas entrantes"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 1000)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
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

            // 1. PendingIntent para Responder
            val answerIntent = Intent(applicationContext, MainActivity::class.java).apply {
                action = "ACTION_ANSWER_CALL"
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
            val answerPendingIntent = PendingIntent.getActivity(
                applicationContext,
                101,
                answerIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
            )

            // 2. PendingIntent para Rechazar
            val rejectIntent = Intent(applicationContext, CallActionReceiver::class.java).apply {
                action = "ACTION_REJECT_CALL"
            }
            val rejectPendingIntent = PendingIntent.getBroadcast(
                applicationContext,
                102,
                rejectIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
            )

            // 3. Crear Persona para CallStyle
            val callerPerson = Person.Builder()
                .setName(callerName)
                .setImportant(true)
                .build()

            // 4. Construir Notificación estilo Llamada Entrante (Heads-Up Banner idéntico a WhatsApp)
            val notificationBuilder = NotificationCompat.Builder(applicationContext, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(callerName)
                .setContentText("Llamada entrante")
                .setStyle(
                    NotificationCompat.CallStyle.forIncomingCall(
                        callerPerson,
                        rejectPendingIntent,
                        answerPendingIntent
                    )
                )
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setFullScreenIntent(answerPendingIntent, true)
                .setContentIntent(answerPendingIntent)
                .setAutoCancel(true)
                .setOngoing(true)

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, notificationBuilder.build())

            // 5. Vibrador real de hardware de Android en bucle
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

            // 6. Timbre oficial de llamadas de Android con volumen del sistema
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
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(NOTIFICATION_ID)
            ringtone?.stop()
            ringtone = null
            vibrator?.cancel()
            vibrator = null
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
