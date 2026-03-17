package com.dudiver.dondepaso

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

object TimelapseVideoEncoder {
    private const val MIME_TYPE = "video/avc"
    private const val TIMEOUT_US = 10000L

    fun encodePngSequenceToMp4(
        framePaths: List<String>,
        outputPath: String,
        width: Int,
        height: Int,
        fps: Int,
    ): String {
        require(framePaths.isNotEmpty()) { "Frame sequence is empty." }

        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) {
            outputFile.delete()
        }

        val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, (width * height * 5).coerceAtLeast(2_000_000))
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        val codec = MediaCodec.createEncoderByType(MIME_TYPE)
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var trackIndex = -1
        var muxerStarted = false
        val bufferInfo = MediaCodec.BufferInfo()

        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()

            val yuvBuffer = ByteArray(width * height * 3 / 2)
            framePaths.forEachIndexed { index, framePath ->
                val bitmap = loadScaledBitmap(framePath, width, height)
                argbToI420(bitmap, yuvBuffer, width, height)
                bitmap.recycle()

                var inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                while (inputIndex < 0) {
                    drainEncoder(codec, muxer, bufferInfo) { newTrackIndex ->
                        trackIndex = newTrackIndex
                        muxerStarted = true
                    }
                    inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                }

                codec.getInputBuffer(inputIndex)?.apply {
                    clear()
                    put(yuvBuffer)
                }
                val presentationTimeUs = index * 1_000_000L / fps
                codec.queueInputBuffer(inputIndex, 0, yuvBuffer.size, presentationTimeUs, 0)
                drainEncoder(codec, muxer, bufferInfo) { newTrackIndex ->
                    trackIndex = newTrackIndex
                    muxerStarted = true
                }
            }

            val eosInputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
            if (eosInputIndex >= 0) {
                codec.queueInputBuffer(
                    eosInputIndex,
                    0,
                    0,
                    framePaths.size * 1_000_000L / fps,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                )
            }

            var outputDone = false
            while (!outputDone) {
                val outputIndex = codec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                when {
                    outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        // keep polling
                    }
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        if (!muxerStarted) {
                            trackIndex = muxer.addTrack(codec.outputFormat)
                            muxer.start()
                            muxerStarted = true
                        }
                    }
                    outputIndex >= 0 -> {
                        val outputBuffer = codec.getOutputBuffer(outputIndex)
                        if (
                            outputBuffer != null &&
                            bufferInfo.size > 0 &&
                            muxerStarted &&
                            trackIndex >= 0
                        ) {
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                            muxer.writeSampleData(trackIndex, outputBuffer, bufferInfo)
                        }
                        outputDone =
                            (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
        } finally {
            try {
                codec.stop()
            } catch (_: Exception) {
            }
            codec.release()
            try {
                if (muxerStarted) {
                    muxer.stop()
                }
            } catch (_: Exception) {
            }
            muxer.release()
        }

        return outputFile.path
    }

    private fun drainEncoder(
        codec: MediaCodec,
        muxer: MediaMuxer,
        bufferInfo: MediaCodec.BufferInfo,
        onMuxerStarted: (Int) -> Unit,
    ) {
        while (true) {
            val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
            when {
                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> return
                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    onMuxerStarted(muxer.addTrack(codec.outputFormat))
                    muxer.start()
                }
                outputIndex >= 0 -> {
                    codec.releaseOutputBuffer(outputIndex, false)
                }
            }
        }
    }

    private fun loadScaledBitmap(path: String, width: Int, height: Int): Bitmap {
        val original = BitmapFactory.decodeFile(path)
            ?: throw IllegalStateException("Unable to decode frame: $path")
        if (original.width == width && original.height == height) {
            return original.copy(Bitmap.Config.ARGB_8888, false).also {
                original.recycle()
            }
        }

        val target = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(target)
        canvas.drawBitmap(original, null, android.graphics.Rect(0, 0, width, height), null)
        original.recycle()
        return target
    }

    private fun argbToI420(bitmap: Bitmap, out: ByteArray, width: Int, height: Int) {
        val frameSize = width * height
        val uStart = frameSize
        val vStart = frameSize + (frameSize / 4)
        var yIndex = 0
        var uIndex = uStart
        var vIndex = vStart
        val pixels = IntArray(frameSize)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        for (j in 0 until height) {
            for (i in 0 until width) {
                val color = pixels[j * width + i]
                val r = color shr 16 and 0xFF
                val g = color shr 8 and 0xFF
                val b = color and 0xFF

                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128

                out[yIndex++] = y.coerceIn(0, 255).toByte()
                if (j % 2 == 0 && i % 2 == 0) {
                    out[uIndex++] = u.coerceIn(0, 255).toByte()
                    out[vIndex++] = v.coerceIn(0, 255).toByte()
                }
            }
        }
    }
}
