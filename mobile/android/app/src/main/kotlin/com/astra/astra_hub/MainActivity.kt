package com.astra.astra_hub

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    /**
     * Canaux cités par les push du serveur (android.notification.channel_id) :
     * le membre peut régler chacun séparément dans les paramètres Android.
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannels(
            listOf(
                channel(
                    R.string.notification_channel_messages,
                    R.string.notification_channel_messages_name,
                    R.string.notification_channel_messages_description,
                ),
                channel(
                    R.string.notification_channel_activity,
                    R.string.notification_channel_activity_name,
                    R.string.notification_channel_activity_description,
                ),
            ),
        )
    }

    private fun channel(id: Int, name: Int, description: Int) =
        NotificationChannel(getString(id), getString(name), NotificationManager.IMPORTANCE_HIGH)
            .apply { this.description = getString(description) }
}
