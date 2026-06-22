package com.xmo.xmo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.net.URL

object XmoMessageNotificationHelper {
    private const val CHANNEL_ID = "xmo_messages_v2"
    private const val CHANNEL_NAME = "XMO messages"
    private const val NOTIFICATION_ID_FALLBACK = 920001
    private const val AVATAR_SIZE = 192

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
        val displayBody = bodyFromPayload(data, body)
        val largeIcon = avatarBitmap(data) ?: fallbackAvatarBitmap(displayTitle)

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
            .apply {
                if (largeIcon != null) {
                    setLargeIcon(largeIcon)
                }
            }
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    private fun createMessageChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Message notifications from XMO chats"
            lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
    }

    private fun bodyFromPayload(data: Map<String, String>, rawBody: String?): String {
        val explicitPreview = data["preview_label"]?.takeIf { it.isDisplayableText() }
        val previewKind = (data["preview_kind"] ?: "").lowercase()
        if (explicitPreview != null && previewKind.isNotBlank()) {
            return previewPrefix(previewKind) + explicitPreview
        }

        val msgType = (data["msgtype"] ?: data["message_type"] ?: data["event_type"] ?: "")
            .lowercase()
        return when {
            msgType.startsWith("m.call.") -> "☎ Incoming call"
            msgType.startsWith("m.room.") -> "Room updated"
            msgType.contains("m.image") || msgType.contains("image") -> "\uD83D\uDDBC\uFE0F Photo"
            msgType.contains("m.video") || msgType.contains("video") -> "▶ Video"
            msgType.contains("m.audio") || msgType.contains("audio") -> {
                val fileName = data["filename"] ?: data["content"] ?: data["body"]
                if (fileName?.lowercase()?.startsWith("voice_") == true) {
                    "🎙 Voice message"
                } else {
                    "🎧 " + (fileName?.takeIf { it.isDisplayableText() } ?: "Audio")
                }
            }
            msgType.contains("m.file") || msgType.contains("file") ->
                previewPrefix(fileKind(data)) + (data["filename"]?.takeIf { it.isDisplayableText() }
                    ?: data["content"]?.takeIf { it.isDisplayableText() }
                    ?: data["body"]?.takeIf { it.isDisplayableText() }
                    ?: "File")
            msgType.contains("m.location") || msgType.contains("location") -> "📍 Location"
            msgType.contains("m.room.encrypted") || msgType.contains("encrypted") ->
                "🔒 New encrypted message"
            else -> data["content"]?.takeIf { it.isDisplayableText() }
                ?: data["body"]?.takeIf { it.isDisplayableText() }
                ?: rawBody?.takeIf { it.isDisplayableText() }
                ?: "Open XMO to view this message"
        }
    }

    private fun previewPrefix(kind: String): String {
        return when (kind.lowercase()) {
            "image" -> "\uD83D\uDDBC\uFE0F "
            "video" -> "▶ "
            "voice" -> "🎙 "
            "audio" -> "🎧 "
            "pdf" -> "\uD83D\uDCC4 "
            "word" -> "\uD83D\uDCDD "
            "spreadsheet" -> "\uD83D\uDCCA "
            "presentation" -> "\uD83D\uDCCA "
            "apk" -> "\uD83D\uDCE6 "
            "archive" -> "\uD83D\uDCE6 "
            "text_file" -> "\uD83D\uDCC4 "
            "code" -> "\uD83D\uDCBB "
            "app" -> "\uD83D\uDCE6 "
            "file" -> "\uD83D\uDCC4 "
            "location" -> "📍 "
            "encrypted" -> "🔒 "
            else -> ""
        }
    }

    private fun fileKind(data: Map<String, String>): String {
        val explicitKind = data["preview_kind"]?.lowercase()
        if (!explicitKind.isNullOrBlank()) return explicitKind

        val mimeType = data["mimetype"]?.lowercase() ?: ""
        val filename = (data["filename"] ?: data["content"] ?: data["body"] ?: "").lowercase()
        val extension = filename.substringAfterLast('.', "")

        if (mimeType.startsWith("image/") ||
            setOf("jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif", "svg")
                .contains(extension)
        ) return "image"
        if (mimeType.startsWith("video/") ||
            setOf("mp4", "mkv", "mov", "avi", "webm", "3gp", "m4v").contains(extension)
        ) return "video"
        if (mimeType.startsWith("audio/") ||
            setOf("mp3", "m4a", "aac", "wav", "ogg", "opus", "flac", "amr").contains(extension)
        ) return "audio"

        return when (extension) {
            "pdf" -> "pdf"
            "doc", "docx" -> "word"
            "xls", "xlsx", "csv" -> "spreadsheet"
            "ppt", "pptx" -> "presentation"
            "apk", "aab" -> "apk"
            "zip", "rar", "7z", "tar", "gz" -> "archive"
            "txt", "rtf", "md" -> "text_file"
            "json", "xml", "html", "css", "js", "ts", "dart", "java", "kt",
            "py", "c", "cpp", "cs", "php", "sh" -> "code"
            "exe", "msi", "dmg", "pkg", "deb", "rpm" -> "app"
            else -> {
                when {
                    mimeType.contains("pdf") -> "pdf"
                    mimeType.contains("word") ||
                        mimeType.contains("officedocument.wordprocessingml") -> "word"
                    mimeType.contains("spreadsheet") || mimeType.contains("excel") -> "spreadsheet"
                    mimeType.contains("presentation") || mimeType.contains("powerpoint") ->
                        "presentation"
                    mimeType == "application/vnd.android.package-archive" -> "apk"
                    mimeType.startsWith("text/") -> "text_file"
                    else -> "file"
                }
            }
        }
    }

    private fun avatarBitmap(data: Map<String, String>): Bitmap? {
        val url = data["avatar_url"]
            ?: data["sender_avatar_url"]
            ?: data["room_avatar_url"]
            ?: data["icon_url"]
            ?: return null
        if (!url.startsWith("http://") && !url.startsWith("https://")) return null

        return try {
            URL(url).openStream().use { stream ->
                BitmapFactory.decodeStream(stream)?.let { circularBitmap(it) }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun fallbackAvatarBitmap(title: String): Bitmap {
        val size = AVATAR_SIZE
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(44, 44, 46)
        }
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, background)

        val letter = title.trim().firstOrNull()?.uppercaseChar()?.toString() ?: "X"
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(150, 243, 42)
            textAlign = Paint.Align.CENTER
            textSize = 88f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val y = size / 2f - (textPaint.descent() + textPaint.ascent()) / 2f
        canvas.drawText(letter, size / 2f, y, textPaint)
        return bitmap
    }

    private fun circularBitmap(source: Bitmap): Bitmap {
        val size = AVATAR_SIZE
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val scale = maxOf(
            size.toFloat() / source.width.toFloat(),
            size.toFloat() / source.height.toFloat(),
        )
        val matrix = android.graphics.Matrix().apply {
            setScale(scale, scale)
            postTranslate(
                (size - source.width * scale) / 2f,
                (size - source.height * scale) / 2f,
            )
        }

        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.xfermode = android.graphics.PorterDuffXfermode(
            android.graphics.PorterDuff.Mode.SRC_IN,
        )
        canvas.drawBitmap(source, matrix, paint)
        return output
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
