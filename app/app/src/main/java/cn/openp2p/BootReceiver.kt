package cn.openp2p

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED != intent.action) return
        val desired = context.getSharedPreferences(OpenP2PService.PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(OpenP2PService.KEY_DESIRED_RUNNING, false)
        Log.i("BootReceiver", "boot completed, desiredRunning=$desired")
        if (!desired) return
        val service = Intent(context, OpenP2PService::class.java).setAction(OpenP2PService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(service) else context.startService(service)
    }
}
