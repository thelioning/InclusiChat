package com.inclusichat.inclusichat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class InclusiChatCallService : Service() {

    companion object {
        const val FOREGROUND_CHANNEL_ID = "inclusichat_service_channel"
        const val CALL_CHANNEL_ID = "inclusichat_calls_channel"
        const val SERVICE_NOTIFICATION_ID = 9001
        const val CALL_NOTIFICATION_ID = 9991

        const val ACTION_START_SERVICE = "ACTION_START_SERVICE"
        const val ACTION_STOP_SERVICE = "ACTION_STOP_SERVICE"
        const val ACTION_REJECT_CALL = "ACTION_REJECT_CALL"
        const val ACTION_CALL_HANDLED = "ACTION_CALL_HANDLED"

        var isRunning = false
        var activeIncomingCallId: String? = null
    }

    private var isPolling = false
    private var pollThread: Thread? = null

    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var userId: String? = null
    private var authToken: String? = null
    private var supabaseUrl: String? = null
    private var apiKey: String? = null

    private val handledCallIds = mutableSetOf<String>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (action == ACTION_STOP_SERVICE) {
            stopPolling()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        if (action == ACTION_REJECT_CALL) {
            val callId = intent.getStringExtra("call_id")
            val convId = intent.getStringExtra("conv_id")
            if (callId != null) {
                handledCallIds.add(callId)
            }
            stopIncomingRinging()
            if (convId != null && callId != null) {
                sendRejectSignalAsync(convId, callId)
            }
            return START_STICKY
        }

        if (action == ACTION_CALL_HANDLED) {
            val callId = intent.getStringExtra("call_id")
            if (callId != null) {
                handledCallIds.add(callId)
            }
            stopIncomingRinging()
            return START_STICKY
        }

        // Cargar credenciales desde el Intent o SharedPreferences
        val newUserId = intent?.getStringExtra("userId")
        val newAuthToken = intent?.getStringExtra("authToken")
        val newSupabaseUrl = intent?.getStringExtra("supabaseUrl")
        val newApiKey = intent?.getStringExtra("apiKey")

        val prefs = getSharedPreferences("InclusiChatServicePrefs", Context.MODE_PRIVATE)

        if (newUserId != null) {
            userId = newUserId
            authToken = newAuthToken
            supabaseUrl = newSupabaseUrl
            apiKey = newApiKey

            prefs.edit()
                .putString("userId", userId)
                .putString("authToken", authToken)
                .putString("supabaseUrl", supabaseUrl)
                .putString("apiKey", apiKey)
                .apply()
        } else {
            userId = prefs.getString("userId", null)
            authToken = prefs.getString("authToken", null)
            supabaseUrl = prefs.getString("supabaseUrl", "https://wzkcuvwsbbhrkgkrsrgm.supabase.co")
            apiKey = prefs.getString("apiKey", "sb_publishable_P-yNCVxR9rtpt8Ye6bK_Ig_ve0uRStf")
        }

        startForegroundServiceNotification()
        startPolling()

        isRunning = true
        return START_STICKY
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Canal 1: Servicio en segundo plano (Discreto)
            val serviceChannel = NotificationChannel(
                FOREGROUND_CHANNEL_ID,
                "InclusiChat Servicio Activo",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Mantiene InclusiChat conectado para llamadas"
                setShowBadge(false)
            }
            manager.createNotificationChannel(serviceChannel)

            // Canal 2: Llamadas de alta prioridad
            val callChannel = NotificationChannel(
                CALL_CHANNEL_ID,
                "Llamadas de InclusiChat",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alertas de llamadas entrantes prioritarias"
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 1000)
            }
            manager.createNotificationChannel(callChannel)
        }
    }

    private fun startForegroundServiceNotification() {
        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            0,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, FOREGROUND_CHANNEL_ID)
            .setContentTitle("InclusiChat")
            .setContentText("Listo para recibir llamadas privadas")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        startForeground(SERVICE_NOTIFICATION_ID, notification)
    }

    private fun startPolling() {
        if (isPolling) return
        isPolling = true

        pollThread = Thread {
            while (isPolling) {
                try {
                    checkIncomingCallsFromSupabase()
                } catch (e: Exception) {
                    e.printStackTrace()
                }

                try {
                    Thread.sleep(2000)
                } catch (e: InterruptedException) {
                    break
                }
            }
        }.apply {
            isDaemon = true
            start()
        }
    }

    private fun stopPolling() {
        isPolling = false
        pollThread?.interrupt()
        pollThread = null
    }

    private fun checkIncomingCallsFromSupabase() {
        val uid = userId ?: return
        val urlBase = supabaseUrl ?: return
        val key = apiKey ?: return
        val token = authToken ?: key

        try {
            // Consultar mensajes recientes tipo system donde sender_id != uid
            val endpoint = "$urlBase/rest/v1/messages?select=id,conversation_id,sender_id,metadata,created_at&type=eq.system&sender_id=neq.$uid&order=created_at.desc&limit=10"
            val url = URL(endpoint)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("apikey", key)
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 4000
            conn.readTimeout = 4000

            val responseCode = conn.responseCode
            if (responseCode == 200) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                val sb = StringBuilder()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    sb.append(line)
                }
                reader.close()

                val jsonArray = JSONArray(sb.toString())
                val now = System.currentTimeMillis()

                for (i in 0 until jsonArray.length()) {
                    val row = jsonArray.getJSONObject(i)
                    val metadataStr = row.optString("metadata", null)
                    if (metadataStr != null && metadataStr.isNotEmpty()) {
                        val meta = if (metadataStr.startsWith("{")) JSONObject(metadataStr) else null
                        if (meta != null && meta.optBoolean("call_signal", false)) {
                            val action = meta.optString("action")
                            val callId = meta.optString("call_id")
                            val callerName = meta.optString("caller_name", "Contacto")
                            val callerId = row.optString("sender_id")
                            val conversationId = row.optString("conversation_id")
                            val createdAtStr = row.optString("created_at")

                            if (action == "start" && callId.isNotEmpty() && !handledCallIds.contains(callId)) {
                                val callTime = parseIsoTimestamp(createdAtStr)
                                val diffSeconds = (now - callTime) / 1000

                                if (diffSeconds in 0..40) {
                                    // Verificar que no haya sido cancelada ni atendida
                                    if (activeIncomingCallId != callId) {
                                        triggerIncomingCallAlert(callerName, callId, conversationId, callerId)
                                    }
                                    break
                                }
                            } else if ((action == "reject" || action == "end" || action == "accept") && callId == activeIncomingCallId) {
                                stopIncomingRinging()
                            }
                        }
                    }
                }
            }
            conn.disconnect()
        } catch (e: Exception) {
            // Error de conexión temporal
        }
    }

    private fun parseIsoTimestamp(isoString: String): Long {
        return try {
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            sdf.timeZone = TimeZone.getTimeZone("UTC")
            val clean = if (isoString.contains(".")) isoString.substring(0, isoString.indexOf('.')) else isoString.replace("Z", "")
            sdf.parse(clean)?.time ?: System.currentTimeMillis()
        } catch (_) {
            System.currentTimeMillis()
        }
    }

    private fun triggerIncomingCallAlert(callerName: String, callId: String, conversationId: String, callerId: String) {
        activeIncomingCallId = callId

        try {
            // 1. Encender la pantalla del teléfono con WakeLock
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "InclusiChat:IncomingCallWakeLock"
            )
            wakeLock?.acquire(30000)

            // 2. PendingIntent para Responder (Abre la app directamente)
            val answerIntent = Intent(applicationContext, MainActivity::class.java).apply {
                action = "ACTION_ANSWER_CALL"
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                putExtra("call_id", callId)
                putExtra("conversation_id", conversationId)
                putExtra("caller_name", callerName)
                putExtra("caller_id", callerId)
            }
            val answerPendingIntent = PendingIntent.getActivity(
                applicationContext,
                101,
                answerIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
            )

            // 3. PendingIntent para Rechazar (Se ejecuta en segundo plano)
            val rejectIntent = Intent(applicationContext, CallActionReceiver::class.java).apply {
                action = "ACTION_REJECT_CALL"
                putExtra("call_id", callId)
                putExtra("conv_id", conversationId)
            }
            val rejectPendingIntent = PendingIntent.getBroadcast(
                applicationContext,
                102,
                rejectIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
            )

            // 4. Crear Notificación CallStyle Heads-Up idéntica a WhatsApp
            val callerPerson = Person.Builder()
                .setName(callerName)
                .setImportant(true)
                .build()

            val notification = NotificationCompat.Builder(applicationContext, CALL_CHANNEL_ID)
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
                .build()

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(CALL_NOTIFICATION_ID, notification)

            // 5. Iniciar Timbre y Vibración Nativa
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val ringerMode = audioManager.ringerMode

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

            if (ringerMode == AudioManager.RINGER_MODE_NORMAL) {
                val notificationUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
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
        activeIncomingCallId = null
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(CALL_NOTIFICATION_ID)
            ringtone?.stop()
            ringtone = null
            vibrator?.cancel()
            vibrator = null
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            wakeLock = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun sendRejectSignalAsync(conversationId: String, callId: String) {
        Thread {
            try {
                val urlBase = supabaseUrl ?: return@Thread
                val key = apiKey ?: return@Thread
                val token = authToken ?: key
                val uid = userId ?: return@Thread

                val endpoint = "$urlBase/rest/v1/messages"
                val url = URL(endpoint)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("apikey", key)
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Prefer", "return=minimal")
                conn.doOutput = true

                val payload = JSONObject().apply {
                    put("conversation_id", conversationId)
                    put("sender_id", uid)
                    put("type", "system")
                    put("content", "📞 Llamada rechazada")
                    put("metadata", JSONObject().apply {
                        put("call_signal", true)
                        put("action", "reject")
                        put("call_id", callId)
                        put("timestamp", System.currentTimeMillis())
                    })
                }

                conn.outputStream.use { os ->
                    os.write(payload.toString().toByteArray())
                }
                conn.responseCode
                conn.disconnect()
            } catch (_) {}
        }.start()
    }

    override fun onDestroy() {
        stopPolling()
        stopIncomingRinging()
        isRunning = false
        super.onDestroy()
    }
}
