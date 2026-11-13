package com.example.ironmusic420ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Experimental background listener. START_NOT_STICKY and stopWithTask=true
 * so a kill cannot restart-storm the phone.
 */
class HeyIronForegroundService : Service(), HeyIronEngine.Listener {
    companion object {
        private const val CHANNEL_ID = "hey_iron_v2_bg"
        private const val NOTIFICATION_ID = 2421
    }

    private var engine: HeyIronEngine? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        if (engine == null) {
            engine = HeyIronEngine(this, this)
        }
        if (engine?.isRunning() != true) {
            if (engine?.start() != true) {
                stopSelf()
                return START_NOT_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        engine?.stop()
        engine = null
        super.onDestroy()
    }

    override fun onHeartbeat() {}

    override fun onDetected(keyword: String) {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launch?.putExtra("hey_iron_detected", keyword)
        if (launch != null) startActivity(launch)
        stopSelf()
    }

    override fun onError(message: String) {
        stopSelf()
    }

    override fun onListeningChanged(listening: Boolean) {}

    private fun startAsForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Хей Айрън (експериментален фон)",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Хей Айрън")
            .setContentText("Експериментално слушане на заден план")
            .setContentIntent(pending)
            .setOngoing(true)
            .setSilent(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
