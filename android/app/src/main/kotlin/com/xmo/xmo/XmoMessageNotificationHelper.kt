package com.xmo.xmo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object XmoMessageNotificationHelper {
    private const val CHANNEL_ID = "xmo_messages"
    private const val CHANNEL_NAME = "XMO messages"
    private const val NOTIFICATION_ID_FALLBACK = 920001

    fun showMessage(
        context: Context,
        data: Map<String, String>,
        title: String?,
        body: String?,
    ) {
        createMessageChannel(context)

        val displayTitle = title?.takeIf { it.isNotBlank() }
            ?: data["room_name"]?.takeIf { it.isNotBlank() }
            ?: data["sender_display_name"]?.takeIf { it.isNotBlank() }
            ?: data["sender"]?.takeIf { it.isNotBlank() }
            ?: "New message"
        val displayBody = body?.takeIf { it.isNotBlank() }
            ?: bodyFromPayload(data)

        val notificationId = notificationId(data)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            data.forEach { (key, value) -> putExtra(key, value) }
            putExtra("xmo_notification_id", notificationId.toString())
        }
        val openPendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openIntent,
            pendingIntentFlags(),
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle(displayTitle)
            .setContentText(displayBody)
            .setStyle(NotificationCompat.BigTextStyle().bigText(displayBody))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setColor(Color.rgb(47, 128, 237))
            .setContentIntent(openPendingIntent)
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    private fun createMessageChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Message notifications from XMO chats"
            lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
    }

    private fun bodyFromPayload(data: Map<String, String>): String {
        data["content"]?.takeIf { it.isDisplayableText() }?.let { return it }
        data["body"]?.takeIf { it.isDisplayableText() }?.let { return it }

        val msgType = (data["msgtype"] ?: data["message_type"] ?: data["event_type"] ?: "")
            .lowercase()
        return when {
            msgType.startsWith("m.call.") -> "Incoming call"
            msgType.startsWith("m.room.") -> "Room updated"
            msgType.contains("m.image") || msgType.contains("image") -> "Photo"
            msgType.contains("m.video") || msgType.contains("video") -> "Video"
            msgType.contains("m.audio") || msgType.contains("audio") -> "Audio"
            msgType.contains("m.file") || msgType.contains("file") -> "File"
            msgType.contains("m.location") || msgType.contains("location") -> "Location"
            msgType.contains("m.room.encrypted") || msgType.contains("encrypted") ->
                "New encrypted message"
            else -> "Open XMO to view this message"
        }
    }

    private fun String.isDisplayableText(): Boolean {
        val value = trim()
        if (value.isBlank()) return false
        if (value.startsWith("m.call.") || value.startsWith("m.room.")) return false
        return true
    }

    private fun notificationId(data: Map<String, String>): Int {
        val seed = data["event_id"]
            ?: data["room_id"]
            ?: data["roomId"]
            ?: return NOTIFICATION_ID_FALLBACK
        return seed.hashCode() and Int.MAX_VALUE
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }
}
