package com.xmo.xmo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object XmoCallNotificationHelper {
    const val CHANNEL_ID = "xmo_call_alerts_v2"
    const val EXTRA_IS_CALL_NOTIFICATION = "xmo_is_call_notification"
    const val EXTRA_ACTION = "xmo_action"
    const val ACTION_OPEN = "com.xmo.xmo.CALL_OPEN"
    const val ACTION_ANSWER = "com.xmo.xmo.CALL_ANSWER"
    const val ACTION_DECLINE = "com.xmo.xmo.CALL_DECLINE"

    private const val CHANNEL_NAME = "XMO calls"
    private const val NOTIFICATION_ID_FALLBACK = 910001

    fun looksLikeCall(data: Map<String, String>, title: String?, body: String?): Boolean {
        if (data["xmo_push_type"] == "call") return true

        val eventType = (data["event_type"] ?: data["type"] ?: "").lowercase()
        if (eventType.startsWith("m.call.") || isGroupCallEventType(eventType)) return true

        val contentType = (data["content_type"] ?: "").lowercase()
        if (contentType.startsWith("m.call.") || isGroupCallEventType(contentType)) return true

        val msgType = (data["msgtype"] ?: data["message_type"] ?: "").lowercase()
        val groupCallType = (data["m.type"] ?: data["call_type"] ?: "").lowercase()
        val groupCallIntent = (data["m.intent"] ?: data["call_intent"] ?: "").lowercase()
        if ((groupCallType == "m.voice" || groupCallType == "m.video") &&
            (groupCallIntent == "m.ring" || groupCallIntent == "m.prompt" || groupCallIntent == "m.room")
        ) {
            return true
        }

        val hasCallId = data.containsKey("call_id") || data.containsKey("m.call.id")
        val hasCallPayload = data.containsKey("offer") || data.containsKey("answer")
        return hasCallId && hasCallPayload && !msgType.startsWith("m.")
    }

    fun showIncomingCall(
        context: Context,
        data: Map<String, String>,
        title: String?,
        body: String?,
    ) {
        createCallChannel(context)

        val notificationId = notificationId(data)
        val isVideo = looksLikeVideoCall(data, title, body)
        val displayTitle = titleFromPayload(data, title)
        val displayBody = body?.takeIf { it.isNotBlank() }
            ?: "Incoming ${if (isVideo) "video" else "voice"} call"

        val openIntent = callIntent(context, ACTION_OPEN, data, notificationId)
        val answerIntent = callIntent(context, ACTION_ANSWER, data, notificationId)
        val declineIntent = callIntent(context, ACTION_DECLINE, data, notificationId)

        val openPendingIntent = PendingIntent.getActivity(
            context,
            notificationId + 1,
            openIntent,
            pendingIntentFlags(),
        )
        val answerPendingIntent = PendingIntent.getActivity(
            context,
            notificationId + 2,
            answerIntent,
            pendingIntentFlags(),
        )
        val declinePendingIntent = PendingIntent.getActivity(
            context,
            notificationId + 3,
            declineIntent,
            pendingIntentFlags(),
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle(displayTitle)
            .setContentText(displayBody)
            .setStyle(NotificationCompat.BigTextStyle().bigText(displayBody))
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(false)
            .setAutoCancel(false)
            .setColor(Color.rgb(34, 197, 94))
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
            .setVibrate(longArrayOf(0, 900, 450, 900, 450, 900))
            .setContentIntent(openPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Decline",
                declinePendingIntent,
            )
            .addAction(
                android.R.drawable.sym_action_call,
                "Answer",
                answerPendingIntent,
            )
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    fun cancelCallNotification(context: Context, data: Map<String, String>) {
        NotificationManagerCompat.from(context).cancel(notificationId(data))
    }

    fun extrasFromIntent(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        if (intent.getBooleanExtra(EXTRA_IS_CALL_NOTIFICATION, false) != true) {
            return null
        }

        val extras = intent.extras ?: return mapOf(EXTRA_ACTION to actionName(intent.action))
        val result = linkedMapOf<String, String>()
        for (key in extras.keySet()) {
            val value = extras.get(key)
            if (value != null) result[key] = value.toString()
        }
        result[EXTRA_ACTION] = actionName(intent.action)
        return result
    }

    private fun callIntent(
        context: Context,
        action: String,
        data: Map<String, String>,
        notificationId: Int,
    ): Intent {
        return Intent(context, MainActivity::class.java).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_IS_CALL_NOTIFICATION, true)
            putExtra(EXTRA_ACTION, actionName(action))
            putExtra("xmo_notification_id", notificationId.toString())
            data.forEach { (key, value) -> putExtra(key, value) }
        }
    }

    private fun createCallChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming voice and video calls from XMO"
            setSound(ringtoneUri, attributes)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 900, 450, 900, 450, 900)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
    }

    private fun isGroupCallEventType(eventType: String): Boolean {
        return eventType == "org.matrix.msc3401.call" ||
            eventType == "org.matrix.msc3401.call.member"
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    private fun notificationId(data: Map<String, String>): Int {
        val seed = data["call_id"]
            ?: data["m.call.id"]
            ?: data["room_id"]
            ?: data["roomId"]
            ?: data["event_id"]
            ?: return NOTIFICATION_ID_FALLBACK
        return seed.hashCode() and Int.MAX_VALUE
    }

    private fun titleFromPayload(data: Map<String, String>, title: String?): String {
        return title?.takeIf { it.isNotBlank() }
            ?: data["room_name"]?.takeIf { it.isNotBlank() }
            ?: data["sender_display_name"]?.takeIf { it.isNotBlank() }
            ?: data["sender"]?.takeIf { it.isNotBlank() }
            ?: "Incoming call"
    }

    private fun looksLikeVideoCall(
        data: Map<String, String>,
        title: String?,
        body: String?,
    ): Boolean {
        val joined = buildString {
            append(title.orEmpty()).append(' ')
            append(body.orEmpty()).append(' ')
            data.forEach { (key, value) ->
                append(key).append(' ').append(value).append(' ')
            }
        }.lowercase()
        return joined.contains("video") || joined.contains("videocall")
    }

    private fun actionName(action: String?): String {
        return when (action) {
            ACTION_ANSWER -> "answer"
            ACTION_DECLINE -> "decline"
            else -> "open"
        }
    }
}
