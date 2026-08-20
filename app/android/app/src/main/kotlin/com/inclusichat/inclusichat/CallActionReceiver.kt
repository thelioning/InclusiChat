package com.inclusichat.inclusichat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == "ACTION_REJECT_CALL") {
            val callId = intent.getStringExtra("call_id")
            val convId = intent.getStringExtra("conv_id")

            MainActivity.instance?.stopIncomingRinging()

            val serviceIntent = Intent(context, InclusiChatCallService::class.java).apply {
                this.action = InclusiChatCallService.ACTION_REJECT_CALL
                putExtra("call_id", callId)
                putExtra("conv_id", convId)
            }
            context.startService(serviceIntent)
        }
    }
}
