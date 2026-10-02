package dev.noegnh.filmkit

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.SingleColorLut
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.nio.ByteBuffer

/**
 * LUT parity spike: exports a still image to a short video through Media3 Transformer, with an
 * optional [SingleColorLut], and reads frames back as RGBA bytes.
 */
@SuppressLint("UnsafeOptInUsageError")
class FilmkitPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "filmkit")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "exportImageToVideo" -> exportImageToVideo(call, result)
            "extractFrame" -> extractFrame(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Arguments: `input` (image path), `output` (video path), `lutSize` and `lut` (optional,
     * `lutSize`^3 ARGB colors indexed by `r * N * N + g * N + b`).
     */
    private fun exportImageToVideo(
        call: MethodCall,
        result: Result
    ) {
        val input = call.argument<String>("input")!!
        val output = call.argument<String>("output")!!
        val lut = call.argument<IntArray>("lut")
        val n = call.argument<Int>("lutSize") ?: 0

        val videoEffects =
            if (lut == null) {
                listOf()
            } else {
                val cube = Array(n) { r -> Array(n) { g -> IntArray(n) { b -> lut[(r * n + g) * n + b] } } }
                listOf(SingleColorLut.createFromCube(cube))
            }

        val mediaItem =
            MediaItem
                .Builder()
                .setUri(Uri.fromFile(File(input)))
                .setImageDurationMs(200)
                .build()
        val editedMediaItem =
            EditedMediaItem
                .Builder(mediaItem)
                .setFrameRate(30)
                .setEffects(Effects(listOf(), videoEffects))
                .build()

        File(output).delete()

        val transformer =
            Transformer
                .Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .addListener(
                    object : Transformer.Listener {
                        override fun onCompleted(
                            composition: Composition,
                            exportResult: ExportResult
                        ) {
                            result.success(output)
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            result.error("EXPORT_FAILED", exportException.toString(), null)
                        }
                    }
                ).build()
        transformer.start(editedMediaItem, output)
    }

    /** Arguments: `path` (video). Returns the first frame as `{width, height, rgba}`. */
    private fun extractFrame(
        call: MethodCall,
        result: Result
    ) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(call.argument<String>("path")!!)
            val params = MediaMetadataRetriever.BitmapParams().apply { preferredConfig = Bitmap.Config.ARGB_8888 }
            val bitmap = retriever.getFrameAtIndex(0, params)!!
            val buffer = ByteBuffer.allocate(bitmap.byteCount)
            bitmap.copyPixelsToBuffer(buffer)
            result.success(mapOf("width" to bitmap.width, "height" to bitmap.height, "rgba" to buffer.array()))
        } catch (e: Exception) {
            result.error("EXTRACT_FAILED", e.toString(), null)
        } finally {
            retriever.release()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
