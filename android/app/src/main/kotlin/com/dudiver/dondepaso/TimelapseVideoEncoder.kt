package com.dudiver.dondepaso

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object TimelapseVideoEncoder {
    private const val TAG = "DondePasoVideo"
    @OptIn(UnstableApi::class)
    fun encodePngSequenceToMp4(
        context: Context,
        framePaths: List<String>,
        outputPath: String,
        fps: Int,
        audioPath: String? = null,
        audioDurationUs: Long? = null,
    ): String {
        require(framePaths.isNotEmpty()) { "Frame sequence is empty." }
        Log.d(
            TAG,
            "Composing timelapse with Media3. frames=${framePaths.size}, fps=$fps, audio=${!audioPath.isNullOrBlank()}",
        )

        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) {
            outputFile.delete()
        }

        val frameDurationMs = (1000.0 / fps).toLong().coerceAtLeast(1L)
        val videoItems =
            framePaths.map { framePath ->
                val item =
                    MediaItem.Builder()
                        .setUri(Uri.fromFile(File(framePath)))
                        .setImageDurationMs(frameDurationMs)
                        .build()
                EditedMediaItem.Builder(item).setFrameRate(fps).build()
            }

        val videoSequence = EditedMediaItemSequence.Builder(videoItems).build()
        val composition =
            if (!audioPath.isNullOrBlank()) {
                val durationMs = ((audioDurationUs ?: 0L) / 1000L).coerceAtLeast(1L)
                val audioItem =
                    MediaItem.Builder()
                        .setUri(Uri.fromFile(File(audioPath)))
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(0)
                                .setEndPositionMs(durationMs)
                                .build(),
                        ).build()
                val audioSequence =
                    EditedMediaItemSequence.Builder(
                        listOf(EditedMediaItem.Builder(audioItem).build()),
                    ).build()
                Composition.Builder(videoSequence, audioSequence).build()
            } else {
                Composition.Builder(videoSequence).build()
            }

        val latch = CountDownLatch(1)
        var exportError: ExportException? = null
        var unexpectedError: Exception? = null
        val handlerThread = HandlerThread("DondePasoTransformer").apply { start() }

        try {
            Handler(handlerThread.looper).post {
                try {
                    val transformer =
                        Transformer.Builder(context)
                            .setLooper(handlerThread.looper)
                            .setVideoMimeType(MimeTypes.VIDEO_H264)
                            .setAudioMimeType(MimeTypes.AUDIO_AAC)
                            .addListener(
                                object : Transformer.Listener {
                                    override fun onCompleted(
                                        composition: Composition,
                                        exportResult: ExportResult,
                                    ) {
                                        latch.countDown()
                                    }

                                    override fun onError(
                                        composition: Composition,
                                        exportResult: ExportResult,
                                        exportException: ExportException,
                                    ) {
                                        exportError = exportException
                                        latch.countDown()
                                    }
                                },
                            ).build()

                    transformer.start(composition, outputPath)
                } catch (error: ExportException) {
                    exportError = error
                    latch.countDown()
                } catch (error: Exception) {
                    unexpectedError = error
                    latch.countDown()
                }
            }

            if (!latch.await(180, TimeUnit.SECONDS)) {
                Log.e(TAG, "Timed out while exporting timelapse")
                throw IllegalStateException("Timed out while exporting timelapse.")
            }
            if (exportError != null) {
                Log.e(TAG, "Transformer export failed", exportError)
                throw exportError as ExportException
            }
            if (unexpectedError != null) {
                Log.e(TAG, "Transformer export failed unexpectedly", unexpectedError)
                throw unexpectedError as Exception
            }
            Log.d(TAG, "Transformer export completed. output=$outputPath")
        } finally {
            handlerThread.quitSafely()
        }

        return outputFile.path
    }
}
