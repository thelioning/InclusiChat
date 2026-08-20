package com.inclusichat.inclusichat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == "ACTION_REJECT_CALL") {
            MainActivity.instance?.stopIncomingRinging()
        }
    }
}
