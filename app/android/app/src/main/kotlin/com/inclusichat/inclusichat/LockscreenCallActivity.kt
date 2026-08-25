package com.inclusichat.inclusichat

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView

/**
 * Minimal native call surface used while Android's keyguard is active.
 *
 * The upstream CallKit activity explicitly requests keyguard dismissal when
 * the user answers. InclusiChat must not unlock the device for a call. This
 * activity stays above the keyguard, forwards call actions to the existing
 * CallKit receiver, and finishes back to the locked screen when the call ends.
 */
class LockscreenCallActivity : Activity() {
    private var callData: Bundle? = null
    private var connected = false
    private var finishReceiverRegistered = false

    private val timeoutHandler = Handler(Looper.getMainLooper())
    private val timeoutRunnable = Runnable {
        if (!connected) finishCallUi()
    }

    private val finishReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == finishIncomingUiAction) {
                finishCallUi()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        connected = savedInstanceState?.getBoolean(STATE_CONNECTED, false) ?: false
        callData = savedInstanceState?.getBundle(STATE_CALL_DATA)
        configureLockscreenWindow()
        registerFinishReceiver()
        handleLaunchIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(STATE_CONNECTED, connected)
        callData?.let { outState.putBundle(STATE_CALL_DATA, it) }
        super.onSaveInstanceState(outState)
    }

    private fun configureLockscreenWindow() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    private fun registerFinishReceiver() {
        val filter = IntentFilter(finishIncomingUiAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(finishReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(finishReceiver, filter)
        }
        finishReceiverRegistered = true
    }

    private fun handleLaunchIntent(launchIntent: Intent) {
        callData = launchIntent.getBundleExtra(EXTRA_INCOMING_DATA)
            ?: launchIntent.getBundleExtra(TRANSPARENT_ACTIVITY_DATA)
            ?: callData

        val data = callData
        if (data == null) {
            finishCallUi()
            return
        }

        when (launchIntent.action) {
            ACTION_ACCEPT,
            "$packageName.$ACTION_ACCEPT" -> acceptCall(data)

            ACTION_CALLBACK,
            "$packageName.$ACTION_CALLBACK" -> {
                sendPluginAction(ACTION_CALLBACK, data)
                openFlutterApp()
                finishCallUi()
            }

            else -> {
                if (connected) {
                    timeoutHandler.removeCallbacks(timeoutRunnable)
                    renderCallUi(data, isConnected = true)
                } else {
                    showIncoming(data)
                }
            }
        }
    }

    private fun showIncoming(data: Bundle) {
        connected = false
        renderCallUi(data, isConnected = false)

        timeoutHandler.removeCallbacks(timeoutRunnable)
        val configuredDuration = data.getLong(EXTRA_DURATION, DEFAULT_RING_DURATION_MS)
        val duration = if (configuredDuration > 0L) configuredDuration else DEFAULT_RING_DURATION_MS
        timeoutHandler.postDelayed(timeoutRunnable, duration)
    }

    private fun acceptCall(data: Bundle) {
        if (connected) return
        connected = true
        timeoutHandler.removeCallbacks(timeoutRunnable)

        sendPluginAction(ACTION_ACCEPT, data)

        if (isKeyguardLocked()) {
            // Keep the call surface above the PIN. The keyguard remains active
            // underneath and becomes visible again as soon as this activity ends.
            renderCallUi(data, isConnected = true)
        } else {
            openFlutterApp()
            finishCallUi()
        }
    }

    private fun rejectCall() {
        if (connected) {
            hangUpCall()
            return
        }

        val data = callData ?: return finishCallUi()
        timeoutHandler.removeCallbacks(timeoutRunnable)
        sendPluginAction(ACTION_DECLINE, data)
        finishCallUi()
    }

    private fun hangUpCall() {
        val data = callData ?: return finishCallUi()
        connected = false
        timeoutHandler.removeCallbacks(timeoutRunnable)
        sendPluginAction(ACTION_ENDED, data)
        finishCallUi()
    }

    private fun sendPluginAction(action: String, data: Bundle) {
        val pluginReceiverIntent = Intent().apply {
            setClassName(
                packageName,
                "com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver",
            )
            this.action = "$packageName.$action"
            putExtra(EXTRA_INCOMING_DATA, data)
            `package` = packageName
        }
        sendBroadcast(pluginReceiverIntent)
    }

    private fun openFlutterApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        startActivity(launchIntent)
    }

    private fun isKeyguardLocked(): Boolean {
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return keyguardManager.isKeyguardLocked
    }

    private fun renderCallUi(data: Bundle, isConnected: Boolean) {
        val callerName = data.getString(EXTRA_CALLER_NAME).orEmpty().ifBlank { "Contacto" }
        val isVideo = data.getInt(EXTRA_CALL_TYPE, 0) > 0

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(56), dp(28), dp(40))
            setBackgroundColor(Color.rgb(15, 20, 26))
        }

        val appName = TextView(this).apply {
            text = "InclusiChat"
            setTextColor(Color.rgb(210, 24, 230))
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        root.addView(
            appName,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )

        root.addView(
            Space(this),
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f),
        )

        val avatar = TextView(this).apply {
            text = callerName.take(1).uppercase()
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.rgb(55, 45, 65))
            textSize = 44f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
        }
        root.addView(avatar, LinearLayout.LayoutParams(dp(112), dp(112)))

        val name = TextView(this).apply {
            text = callerName
            setTextColor(Color.WHITE)
            textSize = 28f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
        }
        root.addView(
            name,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(24)
            },
        )

        val status = TextView(this).apply {
            text = if (isConnected) {
                "Conectado"
            } else if (isVideo) {
                "Videollamada entrante"
            } else {
                "Llamada de voz entrante"
            }
            setTextColor(if (isConnected) Color.rgb(80, 200, 120) else Color.LTGRAY)
            textSize = 17f
            gravity = Gravity.CENTER
        }
        root.addView(
            status,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(10)
            },
        )

        root.addView(
            Space(this),
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 2f),
        )

        if (isConnected) {
            root.addView(
                actionButton("Colgar", Color.rgb(205, 55, 65)) { hangUpCall() },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)),
            )
        } else {
            val actions = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
            }

            actions.addView(
                actionButton("Rechazar", Color.rgb(205, 55, 65)) { rejectCall() },
                LinearLayout.LayoutParams(0, dp(58), 1f).apply { marginEnd = dp(8) },
            )
            actions.addView(
                actionButton("Contestar", Color.rgb(48, 170, 90)) { acceptCall(data) },
                LinearLayout.LayoutParams(0, dp(58), 1f).apply { marginStart = dp(8) },
            )
            root.addView(
                actions,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
            )
        }

        setContentView(root)
    }

    private fun actionButton(label: String, color: Int, onClick: () -> Unit): Button =
        Button(this).apply {
            text = label
            textSize = 16f
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(color)
            isAllCaps = false
            setOnClickListener { onClick() }
        }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun finishCallUi() {
        if (isFinishing) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            finish()
        }
    }

    @Deprecated("The call screen intentionally consumes Back while active")
    override fun onBackPressed() {
        // A call must be explicitly rejected or hung up. Do not expose the PIN
        // screen underneath while the native call surface is active.
    }

    override fun onDestroy() {
        timeoutHandler.removeCallbacks(timeoutRunnable)
        if (finishReceiverRegistered) {
            try {
                unregisterReceiver(finishReceiver)
            } catch (_: Exception) {
            }
        }
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_INCOMING_DATA = "EXTRA_CALLKIT_INCOMING_DATA"
        private const val TRANSPARENT_ACTIVITY_DATA = "data"
        private const val EXTRA_CALLER_NAME = "EXTRA_CALLKIT_NAME_CALLER"
        private const val EXTRA_CALL_TYPE = "EXTRA_CALLKIT_TYPE"
        private const val EXTRA_DURATION = "EXTRA_CALLKIT_DURATION"

        private const val ACTION_ACCEPT =
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
        private const val ACTION_DECLINE =
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
        private const val ACTION_ENDED =
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED"
        private const val ACTION_CALLBACK =
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CALLBACK"
        private const val ACTION_FINISH_INCOMING_UI =
            "com.hiennv.flutter_callkit_incoming.ACTION_ENDED_CALL_INCOMING"

        private const val STATE_CONNECTED = "inclusichat_call_connected"
        private const val STATE_CALL_DATA = "inclusichat_call_data"
        private const val DEFAULT_RING_DURATION_MS = 35_000L
    }

    private val finishIncomingUiAction: String
        get() = "$packageName.$ACTION_FINISH_INCOMING_UI"
}
