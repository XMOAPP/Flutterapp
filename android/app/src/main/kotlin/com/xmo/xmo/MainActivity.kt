package com.xmo.xmo

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val walletEventsChannel = "com.xmo.xmo/wallet_events"
    private val walletMethodsChannel = "com.xmo.xmo/wallet_methods"
    private val mediaStoreChannel = "com.xmo.xmo/media_store"
    private val callNotificationMethodsChannel = "com.xmo.xmo/call_notifications"
    private val callNotificationEventsChannel = "com.xmo.xmo/call_notification_events"
    private val notificationNavigationMethodsChannel = "com.xmo.xmo/notification_navigation"
    private val notificationNavigationEventsChannel = "com.xmo.xmo/notification_navigation_events"

    private var initialLink: String? = null
    private var linksReceiver: BroadcastReceiver? = null
    private var initialCallAction: Map<String, String>? = null
    private var callNotificationEvents: EventChannel.EventSink? = null
    private var initialNotificationPayload: Map<String, String>? = null
    private var notificationNavigationEvents: EventChannel.EventSink? = null

    override fun onResume() {
        super.onResume()
        XmoAppVisibility.isForeground = true
    }

    override fun onPause() {
        XmoAppVisibility.isForeground = false
        super.onPause()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        initialLink = intent?.data?.toString()
        initialCallAction = XmoCallNotificationHelper.extrasFromIntent(intent)
        initialCallAction?.let {
            XmoCallNotificationHelper.cancelCallNotification(applicationContext, it)
        }
        if (initialCallAction == null) {
            initialNotificationPayload = notificationPayloadFromIntent(intent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, walletEventsChannel)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        linksReceiver = createChangeReceiver(events)
                    }

                    override fun onCancel(arguments: Any?) {
                        linksReceiver = null
                    }
                },
            )

        MethodChannel(messenger, walletMethodsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "initialLink") {
                    result.success(initialLink)
                    initialLink = null
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(messenger, callNotificationMethodsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "initialCallAction") {
                    result.success(initialCallAction)
                    initialCallAction = null
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(messenger, callNotificationEventsChannel)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        callNotificationEvents = events
                        initialCallAction?.let {
                            events.success(it)
                            initialCallAction = null
                        }
                    }

                    override fun onCancel(arguments: Any?) {
                        callNotificationEvents = null
                    }
                },
            )

        MethodChannel(messenger, notificationNavigationMethodsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "initialNotificationPayload") {
                    result.success(initialNotificationPayload)
                    initialNotificationPayload = null
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(messenger, notificationNavigationEventsChannel)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        notificationNavigationEvents = events
                        initialNotificationPayload?.let {
                            events.success(it)
                            initialNotificationPayload = null
                        }
                    }

                    override fun onCancel(arguments: Any?) {
                        notificationNavigationEvents = null
                    }
                },
            )

        MethodChannel(messenger, mediaStoreChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveMediaToGallery" -> {
                        val filePath = call.argument<String>("filePath")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType")

                        if (filePath.isNullOrBlank() || fileName.isNullOrBlank() || mimeType.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "filePath, fileName, and mimeType are required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            result.success(saveMediaToGallery(filePath, fileName, mimeType))
                        } catch (e: Exception) {
                            result.error("MEDIA_STORE_ERROR", e.message, null)
                        }
                    }
                    "shareFile" -> {
                        val filePath = call.argument<String>("filePath")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"

                        if (filePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "filePath and fileName are required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            shareFile(filePath, fileName, mimeType)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHARE_ERROR", e.message, null)
                        }
                    }
                    "openFile" -> {
                        val filePath = call.argument<String>("filePath")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"

                        if (filePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "filePath and fileName are required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            openFile(filePath, fileName, mimeType)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val callAction = XmoCallNotificationHelper.extrasFromIntent(intent)
        callAction?.let {
            XmoCallNotificationHelper.cancelCallNotification(applicationContext, it)
            if (callNotificationEvents == null) {
                initialCallAction = it
            } else {
                callNotificationEvents?.success(it)
            }
        }
        if (callAction == null) {
            notificationPayloadFromIntent(intent)?.let {
                if (notificationNavigationEvents == null) {
                    initialNotificationPayload = it
                } else {
                    notificationNavigationEvents?.success(it)
                }
            }
        }
        if (intent.action == Intent.ACTION_VIEW) {
            linksReceiver?.onReceive(applicationContext, intent)
        }
    }

    private fun notificationPayloadFromIntent(intent: Intent?): Map<String, String>? {
        val extras = intent?.extras ?: return null
        val roomId = extras.getString("room_id") ?: extras.getString("roomId")
        if (roomId.isNullOrBlank()) return null

        return linkedMapOf<String, String>().apply {
            for (key in extras.keySet()) {
                extras.get(key)?.let { put(key, it.toString()) }
            }
        }
    }

    private fun createChangeReceiver(events: EventChannel.EventSink): BroadcastReceiver {
        return object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val dataString = intent.dataString
                if (dataString == null) {
                    events.error("UNAVAILABLE", "Link unavailable", null)
                } else {
                    events.success(dataString)
                }
            }
        }
    }

    private fun saveMediaToGallery(filePath: String, fileName: String, mimeType: String): String {
        val source = File(filePath)
        if (!source.exists() || source.length() == 0L) {
            throw IllegalArgumentException("Source file is missing or empty")
        }

        if (!mimeType.startsWith("image/") && !mimeType.startsWith("video/")) {
            return filePath
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(filePath),
                arrayOf(mimeType),
                null,
            )
            return filePath
        }

        val isVideo = mimeType.startsWith("video/")
        val collection: Uri = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val relativePath = if (isVideo) {
            Environment.DIRECTORY_MOVIES + "/XMO"
        } else {
            Environment.DIRECTORY_PICTURES + "/XMO"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val resolver = applicationContext.contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Could not create gallery media entry")

        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Could not open gallery media entry")

            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun shareFile(filePath: String, fileName: String, mimeType: String) {
        val file = File(filePath)
        if (!file.exists() || file.length() == 0L) {
            throw IllegalArgumentException("Share file is missing or empty")
        }

        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TITLE, fileName)
            clipData = ClipData.newUri(contentResolver, fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        val chooser = Intent.createChooser(sendIntent, "Share $fileName").apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(chooser)
    }

    private fun openFile(filePath: String, fileName: String, mimeType: String) {
        val file = File(filePath)
        if (!file.exists() || file.length() == 0L) {
            throw IllegalArgumentException("Open file is missing or empty")
        }

        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )

        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            clipData = ClipData.newUri(contentResolver, fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        val chooser = Intent.createChooser(viewIntent, "Open $fileName with").apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(chooser)
    }
}
