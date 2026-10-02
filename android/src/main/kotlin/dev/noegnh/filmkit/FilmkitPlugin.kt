package dev.noegnh.filmkit

import android.annotation.SuppressLint
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.SystemClock
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Crop
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Video export spike: crop + trim + resize (+ HDR to SDR) with Media3 Transformer. */
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
            "exportVideo" -> exportVideo(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Arguments: `input`, `output`, `startMs`, `endMs`, `crop` ([left, top, right, bottom], normalized,
     * in displayed coordinates, i.e. after the rotation tag) and `maxDimension` (longest output side).
     */
    private fun exportVideo(
        call: MethodCall,
        result: Result
    ) {
        val input = call.argument<String>("input")!!
        val output = call.argument<String>("output")!!
        val startMs = call.argument<Number>("startMs")!!.toLong()
        val endMs = call.argument<Number>("endMs")!!.toLong()
        val crop = call.argument<List<Number>>("crop")!!.map { it.toFloat() }
        val maxDimension = call.argument<Int>("maxDimension")!!

        val retriever = MediaMetadataRetriever()
        val (displayWidth, displayHeight, hasAudio) =
            try {
                retriever.setDataSource(input)
                val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt()
                val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt()
                val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
                val audio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
                if (rotation % 180 == 0) Triple(w, h, audio) else Triple(h, w, audio)
            } finally {
                retriever.release()
            }

        val (left, top, right, bottom) = crop
        val cropWidth = (right - left) * displayWidth
        val cropHeight = (bottom - top) * displayHeight
        val scale = min(1f, maxDimension / max(cropWidth, cropHeight))
        val outWidth = even(cropWidth * scale)
        val outHeight = even(cropHeight * scale)

        // Crop takes NDC coordinates (-1..1, y up).
        val effects =
            listOf(
                Crop(left * 2 - 1, right * 2 - 1, 1 - bottom * 2, 1 - top * 2),
                Presentation.createForWidthAndHeight(outWidth, outHeight, Presentation.LAYOUT_SCALE_TO_FIT)
            )

        val mediaItem =
            MediaItem
                .Builder()
                .setUri(Uri.fromFile(File(input)))
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration
                        .Builder()
                        .setStartPositionMs(startMs)
                        .setEndPositionMs(endMs)
                        .build()
                ).build()
        val editedMediaItem = EditedMediaItem.Builder(mediaItem).setEffects(Effects(listOf(), effects)).build()
        val sequence =
            if (hasAudio) {
                EditedMediaItemSequence.withAudioAndVideoFrom(listOf(editedMediaItem))
            } else {
                EditedMediaItemSequence.withVideoFrom(listOf(editedMediaItem))
            }
        val composition =
            Composition
                .Builder(sequence)
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .build()

        File(output).delete()
        val startedAt = SystemClock.elapsedRealtime()

        Transformer
            .Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(
                object : Transformer.Listener {
                    override fun onCompleted(
                        composition: Composition,
                        exportResult: ExportResult
                    ) {
                        result.success(
                            mapOf(
                                "output" to output,
                                "elapsedMs" to (SystemClock.elapsedRealtime() - startedAt),
                                "width" to outWidth,
                                "height" to outHeight,
                                "videoEncoder" to exportResult.videoEncoderName
                            )
                        )
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        result.error("EXPORT_FAILED", exportException.toString(), exportException.cause?.toString())
                    }
                }
            ).build()
            .start(composition, output)
    }

    private fun even(value: Float): Int = max(2, (value / 2).roundToInt() * 2)

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
