package com.example.ma_ak

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        createCallChannel()
    }

    // Incoming voice calls (send-push uses this channel for kind 'voice_call'):
    // plays the phone's ringtone at ringtone volume, vibrates like a call and
    // shows on the lock screen. Created on first launch of this version; until
    // then calls arrive on the normal Ma'ak channel.
    private fun createCallChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CALL_CHANNEL_ID,
            "Incoming voice calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Rings when someone calls you on Ma'ak"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1000, 1000, 1000, 1000, 1000, 1000, 1000)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            enableLights(true)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    // High importance = the notification pops up on screen, plays the default
    // sound and vibrates. Pushes use this channel (send-push sets channel_id,
    // and AndroidManifest.xml makes it Firebase's default).
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Ma'ak notifications",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Messages, support requests and account updates"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 150, 250)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            enableLights(true)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "maak_alerts"
        const val CALL_CHANNEL_ID = "maak_calls"
    }
}
