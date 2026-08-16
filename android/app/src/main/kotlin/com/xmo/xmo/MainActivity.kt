package com.xmo.xmo

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream
import java.net.URLConnection

class MainActivity : FlutterFragmentActivity() {
    private val walletEventsChannel = "com.xmo.xmo/wallet_events"
    private val walletMethodsChannel = "com.xmo.xmo/wallet_methods"
    private val mediaStoreChannel = "com.xmo.xmo/media_store"
    private val callNotificationMethodsChannel = "com.xmo.xmo/call_notifications"
    private val callNotificationEventsChannel = "com.xmo.xmo/call_notification_events"
    private val notificationNavigationMethodsChannel = "com.xmo.xmo/notification_navigation"
    private val notificationNavigationEventsChannel = "com.xmo.xmo/notification_navigation_events"
    private val sensitiveScreenChannel = "com.xmo.xmo/sensitive_screen"

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

        MethodChannel(messenger, sensitiveScreenChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "setProtected") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val protected = call.arguments as? Boolean ?: false
                runOnUiThread {
                    if (protected) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
            }

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
                when (call.method) {
                    "initialCallAction" -> {
                        result.success(initialCallAction)
                        initialCallAction = null
                    }
                    "canUseFullScreenIntent" -> {
                        result.success(
                            XmoCallNotificationHelper.canUseFullScreenIntent(applicationContext),
                        )
                    }
                    "openFullScreenIntentSettings" -> {
                        result.success(openFullScreenIntentSettings())
                    }
                    else -> result.notImplemented()
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
                    "saveMediaBytesToGallery" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType")
                        if (bytes == null || bytes.isEmpty() || fileName.isNullOrBlank() || mimeType.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "bytes, fileName, and mimeType are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveMediaBytesToGallery(bytes, fileName, mimeType))
                        } catch (e: Exception) {
                            result.error("MEDIA_STORE_ERROR", e.message, null)
                        }
                    }
                    "listXmoGalleryMedia" -> {
                        try {
                            result.success(listXmoGalleryMedia())
                        } catch (e: Exception) {
                            result.error("MEDIA_STORE_ERROR", e.message, null)
                        }
                    }
                    "readGalleryMedia" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(readGalleryMedia(uri))
                        } catch (e: Exception) {
                            result.error("MEDIA_STORE_ERROR", e.message, null)
                        }
                    }
                    "loadGalleryThumbnail" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(loadGalleryThumbnail(uri))
                        } catch (e: Exception) {
                            result.error("MEDIA_STORE_ERROR", e.message, null)
                        }
                    }
                    "deleteXmoGalleryMedia" -> {
                        try {
                            result.success(deleteXmoGalleryMedia())
                        } catch (e: Exception) {
                            result.error("MEDIA_STORE_ERROR", e.message, null)
                        }
                    }
                    "probeVideo" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "filePath is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(probeVideo(filePath))
                        } catch (e: Exception) {
                            result.error("VIDEO_PROBE_ERROR", e.message, null)
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
                    "shareText" -> {
                        val text = call.argument<String>("text")
                        val chooserTitle = call.argument<String>("chooserTitle") ?: "Share with"

                        if (text.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "text is required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            shareText(text, chooserTitle)
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

    private fun probeVideo(filePath: String): Map<String, Any?> {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(filePath)
            var videoMimeType: String? = null
            var audioMimeType: String? = null
            var width: Int? = null
            var height: Int? = null
            var durationUs = 0L

            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mimeType = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    durationUs = maxOf(durationUs, format.getLong(MediaFormat.KEY_DURATION))
                }
                if (mimeType.startsWith("video/") && videoMimeType == null) {
                    videoMimeType = mimeType
                    if (format.containsKey(MediaFormat.KEY_WIDTH)) {
                        width = format.getInteger(MediaFormat.KEY_WIDTH)
                    }
                    if (format.containsKey(MediaFormat.KEY_HEIGHT)) {
                        height = format.getInteger(MediaFormat.KEY_HEIGHT)
                    }
                } else if (mimeType.startsWith("audio/") && audioMimeType == null) {
                    audioMimeType = mimeType
                }
            }

            if (videoMimeType == null) {
                throw IllegalArgumentException("No video track found")
            }
            return mapOf(
                "videoMimeType" to videoMimeType,
                "audioMimeType" to audioMimeType,
                "width" to width,
                "height" to height,
                "durationMs" to if (durationUs > 0) durationUs / 1000 else null,
            )
        } finally {
            extractor.release()
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
            if (linksReceiver == null) {
                initialLink = intent.dataString
            } else {
                linksReceiver?.onReceive(applicationContext, intent)
            }
        }
    }

    @Suppress("DEPRECATION")
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

    private fun saveMediaBytesToGallery(bytes: ByteArray, fileName: String, mimeType: String): String {
        if (!mimeType.startsWith("image/") && !mimeType.startsWith("video/")) {
            throw IllegalArgumentException("Only photos and videos can be saved to Gallery")
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val parent = Environment.getExternalStoragePublicDirectory(
                if (mimeType.startsWith("video/")) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES,
            )
            val directory = File(parent, "XMO Downloads").apply { mkdirs() }
            val output = uniqueFile(directory, fileName)
            output.writeBytes(bytes)
            MediaScannerConnection.scanFile(applicationContext, arrayOf(output.path), arrayOf(mimeType), null)
            return output.path
        }

        val isVideo = mimeType.startsWith("video/")
        val collection = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val relativePath = if (isVideo) {
            xmoVideoDownloadsPath()
        } else {
            xmoPhotoDownloadsPath()
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
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not open gallery media entry")

            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun listXmoGalleryMedia(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return listLegacyXmoGalleryMedia()
        }
        migrateLegacyXmoGalleryMedia()
        val result = mutableListOf<Map<String, Any>>()
        result += queryXmoGalleryCollection(
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            xmoPhotoDownloadsPath() + "/",
        )
        result += queryXmoGalleryCollection(
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            xmoVideoDownloadsPath() + "/",
        )
        // Retain visibility for an older item only when Android declined its move.
        result += queryXmoGalleryCollection(
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            legacyXmoPhotoPath() + "/",
        )
        result += queryXmoGalleryCollection(
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            legacyXmoVideoPath() + "/",
        )
        return result
    }

    private fun queryXmoGalleryCollection(collection: Uri, relativePath: String): List<Map<String, Any>> {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        val items = mutableListOf<Map<String, Any>>()
        applicationContext.contentResolver.query(
            collection,
            projection,
            MediaStore.MediaColumns.RELATIVE_PATH + " = ?",
            arrayOf(relativePath),
            MediaStore.MediaColumns.DATE_ADDED + " DESC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val mimeIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            while (cursor.moveToNext()) {
                val uri = Uri.withAppendedPath(collection, cursor.getLong(idIndex).toString())
                items += mapOf(
                    "uri" to uri.toString(),
                    "name" to cursor.getString(nameIndex),
                    "bytes" to cursor.getLong(sizeIndex),
                    "mimeType" to (cursor.getString(mimeIndex) ?: "application/octet-stream"),
                    "contentUri" to true,
                )
            }
        }
        return items
    }

    private fun readGalleryMedia(uriValue: String): ByteArray {
        val uri = Uri.parse(uriValue)
        return applicationContext.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Gallery media is unavailable")
    }

    private fun loadGalleryThumbnail(uriValue: String): ByteArray {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return ByteArray(0)
        val bitmap = applicationContext.contentResolver.loadThumbnail(Uri.parse(uriValue), Size(256, 256), null)
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, output)
            output.toByteArray()
        }
    }

    private fun deleteXmoGalleryMedia(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            var deleted = 0
            for (directory in legacyXmoGalleryDirectories()) {
                directory.listFiles()?.forEach { file ->
                    if (file.isFile && file.delete()) deleted++
                }
            }
            return deleted
        }
        val resolver = applicationContext.contentResolver
        var deleted = 0
        deleted += resolver.delete(
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            MediaStore.MediaColumns.RELATIVE_PATH + " = ?",
            arrayOf(xmoPhotoDownloadsPath() + "/"),
        )
        deleted += resolver.delete(
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            MediaStore.MediaColumns.RELATIVE_PATH + " = ?",
            arrayOf(xmoVideoDownloadsPath() + "/"),
        )
        deleted += resolver.delete(
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            MediaStore.MediaColumns.RELATIVE_PATH + " = ?",
            arrayOf(legacyXmoPhotoPath() + "/"),
        )
        deleted += resolver.delete(
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            MediaStore.MediaColumns.RELATIVE_PATH + " = ?",
            arrayOf(legacyXmoVideoPath() + "/"),
        )
        return deleted
    }

    private fun migrateLegacyXmoGalleryMedia() {
        val resolver = applicationContext.contentResolver
        migrateGalleryCollection(
            resolver,
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            legacyXmoPhotoPath() + "/",
            xmoPhotoDownloadsPath() + "/",
        )
        migrateGalleryCollection(
            resolver,
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            legacyXmoVideoPath() + "/",
            xmoVideoDownloadsPath() + "/",
        )
    }

    private fun migrateGalleryCollection(
        resolver: android.content.ContentResolver,
        collection: Uri,
        oldPath: String,
        newPath: String,
    ) {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        resolver.query(
            collection,
            projection,
            MediaStore.MediaColumns.RELATIVE_PATH + " = ?",
            arrayOf(oldPath),
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            while (cursor.moveToNext()) {
                val uri = Uri.withAppendedPath(collection, cursor.getLong(idIndex).toString())
                try {
                    resolver.update(
                        uri,
                        ContentValues().apply {
                            put(MediaStore.MediaColumns.RELATIVE_PATH, newPath)
                        },
                        null,
                        null,
                    )
                } catch (_: SecurityException) {
                    // The original URI remains visible and can still be cleared later.
                }
            }
        }
    }

    private fun listLegacyXmoGalleryMedia(): List<Map<String, Any>> {
        val items = mutableListOf<Map<String, Any>>()
        for (directory in legacyXmoGalleryDirectories()) {
            directory.listFiles()?.filter { it.isFile && it.length() > 0L }?.forEach { file ->
                items += mapOf(
                    "uri" to file.path,
                    "name" to file.name,
                    "bytes" to file.length(),
                    "mimeType" to (URLConnection.guessContentTypeFromName(file.name) ?: "application/octet-stream"),
                    "contentUri" to false,
                )
            }
        }
        return items
    }

    private fun legacyXmoGalleryDirectories(): List<File> = listOf(
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "XMO Downloads"),
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "XMO Downloads"),
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "XMO"),
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "XMO"),
    )

    private fun xmoPhotoDownloadsPath() = Environment.DIRECTORY_PICTURES + "/XMO Downloads"

    private fun xmoVideoDownloadsPath() = Environment.DIRECTORY_MOVIES + "/XMO Downloads"

    private fun legacyXmoPhotoPath() = Environment.DIRECTORY_PICTURES + "/XMO"

    private fun legacyXmoVideoPath() = Environment.DIRECTORY_MOVIES + "/XMO"

    private fun uniqueFile(directory: File, fileName: String): File {
        var candidate = File(directory, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        candidate = File(directory, "${base}_${System.currentTimeMillis()}$extension")
        return candidate
    }

    private fun shareFile(filePath: String, fileName: String, mimeType: String) {
        val file = validatedSharedFile(filePath)
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

    private fun shareText(text: String, chooserTitle: String) {
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        startActivity(Intent.createChooser(sendIntent, chooserTitle))
    }

    private fun openFile(filePath: String, fileName: String, mimeType: String) {
        val file = validatedSharedFile(filePath)
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

    private fun validatedSharedFile(filePath: String): File {
        val shareRoot = File(cacheDir, "xmo_shared").canonicalFile
        val file = File(filePath).canonicalFile
        val rootPath = shareRoot.path + File.separator
        if (!file.path.startsWith(rootPath)) {
            throw SecurityException("File is outside the XMO sharing directory")
        }
        return file
    }

    private fun openFullScreenIntentSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return false
        }
        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
            data = Uri.parse("package:$packageName")
        }
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
