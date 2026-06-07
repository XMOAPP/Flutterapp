package com.xmo.xmo

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class XmoFirebaseMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val title = data["title"] ?: message.notification?.title
        val body = data["body"] ?: message.notification?.body

        if (XmoCallNotificationHelper.looksLikeCall(data, title, body)) {
            XmoCallNotificationHelper.showIncomingCall(
                applicationContext,
                data,
                title,
                body,
            )
            return
        }

        if (!XmoAppVisibility.isForeground) {
            XmoMessageNotificationHelper.showMessage(
                applicationContext,
                data,
                title,
                body,
            )
            return
        }

        super.onMessageReceived(message)
    }
}
