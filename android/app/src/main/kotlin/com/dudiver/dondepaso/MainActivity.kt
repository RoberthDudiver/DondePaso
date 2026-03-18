package com.dudiver.dondepaso

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val tag = "DondePasoVideo"
    private val videoEncoderExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dudiver.dondepaso/video_encoder",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "encodePngSequenceToMp4" -> {
                    val framePaths = call.argument<List<String>>("framePaths") ?: emptyList()
                    val outputPath = call.argument<String>("outputPath")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    val fps = call.argument<Int>("fps")
                    val audioPath = call.argument<String>("audioPath")
                    val audioDurationUs = call.argument<Number>("audioDurationUs")?.toLong()

                    if (
                        framePaths.isEmpty() ||
                        outputPath.isNullOrBlank() ||
                        width == null ||
                        height == null ||
                        fps == null
                    ) {
                        result.error("invalid_args", "Missing video encoder arguments.", null)
                        return@setMethodCallHandler
                    }

                    videoEncoderExecutor.execute {
                        try {
                            Log.d(
                                tag,
                                "Starting timelapse export. frames=${framePaths.size}, output=$outputPath, audio=$audioPath",
                            )
                            val encodedPath = TimelapseVideoEncoder.encodePngSequenceToMp4(
                                context = applicationContext,
                                framePaths = framePaths,
                                outputPath = outputPath,
                                fps = fps,
                                audioPath = audioPath,
                                audioDurationUs = audioDurationUs,
                            )
                            Log.d(tag, "Timelapse export finished. encodedPath=$encodedPath")
                            runOnUiThread {
                                result.success(encodedPath)
                            }
                        } catch (error: Exception) {
                            Log.e(tag, "Timelapse export failed", error)
                            runOnUiThread {
                                result.error("encode_failed", error.message, null)
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dudiver.dondepaso/media_share",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToGallery" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val mimeType = call.argument<String>("mimeType")
                    val displayName = call.argument<String>("displayName")

                    if (
                        sourcePath.isNullOrBlank() ||
                        mimeType.isNullOrBlank() ||
                        displayName.isNullOrBlank()
                    ) {
                        result.error("invalid_args", "Missing media save arguments.", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val uri = saveToGallery(sourcePath, mimeType, displayName)
                        Log.d(tag, "Saved media to gallery. uri=$uri mimeType=$mimeType")
                        result.success(uri.toString())
                    } catch (error: Exception) {
                        Log.e(tag, "Saving media failed", error)
                        result.error("save_failed", error.message, null)
                    }
                }

                "shareSavedMedia" -> {
                    val uriString = call.argument<String>("uri")
                    val mimeType = call.argument<String>("mimeType")
                    val text = call.argument<String>("text")
                    val title = call.argument<String>("title")

                    if (uriString.isNullOrBlank() || mimeType.isNullOrBlank()) {
                        result.error("invalid_args", "Missing media share arguments.", null)
                        return@setMethodCallHandler
                    }

                    try {
                        Log.d(tag, "Sharing media. uri=$uriString mimeType=$mimeType")
                        shareSavedMedia(Uri.parse(uriString), mimeType, text, title)
                        result.success(null)
                    } catch (error: Exception) {
                        Log.e(tag, "Sharing media failed", error)
                        result.error("share_failed", error.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun saveToGallery(sourcePath: String, mimeType: String, displayName: String): Uri {
        val resolver = applicationContext.contentResolver
        val collection =
            if (mimeType.startsWith("video/")) {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
        val relativePath =
            if (mimeType.startsWith("video/")) {
                "${Environment.DIRECTORY_MOVIES}/DondePaso"
            } else {
                "${Environment.DIRECTORY_PICTURES}/DondePaso"
            }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val uri =
            resolver.insert(collection, values)
                ?: throw IllegalStateException("Could not create MediaStore entry.")

        try {
            FileInputStream(File(sourcePath)).use { input ->
                resolver.openOutputStream(uri)?.use { output ->
                    input.copyTo(output)
                } ?: throw IllegalStateException("Could not open MediaStore output stream.")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val ready = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, ready, null, null)
            }
            return uri
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun shareSavedMedia(uri: Uri, mimeType: String, text: String?, title: String?) {
        val sendIntent =
            Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                if (!text.isNullOrBlank()) {
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                if (!title.isNullOrBlank()) {
                    putExtra(Intent.EXTRA_SUBJECT, title)
                }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        startActivity(Intent.createChooser(sendIntent, title ?: "Share"))
    }
}
