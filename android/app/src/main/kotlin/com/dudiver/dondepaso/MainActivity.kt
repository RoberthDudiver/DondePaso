package com.dudiver.dondepaso

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
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
                            val encodedPath = TimelapseVideoEncoder.encodePngSequenceToMp4(
                                framePaths = framePaths,
                                outputPath = outputPath,
                                width = width,
                                height = height,
                                fps = fps,
                            )
                            runOnUiThread {
                                result.success(encodedPath)
                            }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error("encode_failed", error.message, null)
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
