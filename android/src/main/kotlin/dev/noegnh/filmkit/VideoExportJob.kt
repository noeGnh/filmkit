package dev.noegnh.filmkit

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Effect
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
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.concurrent.Executor

/**
 * One export with Media3 Transformer. Lives on the main thread: Transformer must be used from
 * the thread that created it. [onProgress] and [onDone] are called on the main thread,
 * [onDone] exactly once.
 */
@SuppressLint("UnsafeOptInUsageError")
internal class VideoExportJob(
    private val context: Context,
    private val input: String,
    private val output: String,
    private val spec: EditSpec,
    private val probeExecutor: Executor,
    private val onProgress: (Double) -> Unit,
    private val onDone: (Result<Map<String, Any>>) -> Unit
) {
    private val handler = Handler(Looper.getMainLooper())
    private val progressHolder = ProgressHolder()
    private var transformer: Transformer? = null
    private var finished = false

    fun start() {
        probeExecutor.execute {
            val metadata = runCatching { VideoProbe.probe(input) }
            handler.post {
                if (finished) return@post
                metadata.fold(::begin) { finish(Result.failure(it)) }
            }
        }
    }

    /** Stops the export and deletes the partial output. */
    fun cancel() {
        if (finished) return
        transformer?.cancel()
        File(output).delete()
        finish(Result.failure(FilmkitError(FilmkitError.CANCELLED, "Export cancelled")))
    }

    private fun begin(metadata: VideoMetadata) {
        if (spec.trimStartMs >= metadata.durationMs) {
            finish(Result.failure(FilmkitError(FilmkitError.INVALID_INPUT, "trimStart (${spec.trimStartMs} ms) is after the end of the video (${metadata.durationMs} ms)")))
            return
        }
        File(output).parentFile?.mkdirs()
        run(metadata, ExportGeometry.outputSize(metadata.width, metadata.height, spec.crop, spec.maxDimension), Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
    }

    private fun run(
        metadata: VideoMetadata,
        size: OutputSize,
        hdrMode: Int
    ) {
        File(output).delete()
        val transformer =
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
                            finish(Result.success(mapOf("path" to output, "width" to size.width, "height" to size.height)))
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            if (finished) return
                            File(output).delete()
                            // OpenGL tone mapping needs 10-bit GL support; MediaCodec tone mapping is
                            // the fallback on devices that lack it (API 31+, not every device).
                            if (metadata.isHdr && hdrMode == Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                run(metadata, size, Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC)
                                return
                            }
                            val code = if (metadata.isHdr) FilmkitError.HDR_UNSUPPORTED else FilmkitError.EXPORT_FAILED
                            val cause = exportException.cause?.let { ": $it" } ?: ""
                            finish(Result.failure(FilmkitError(code, "${exportException.errorCodeName}$cause")))
                        }
                    }
                ).build()
        this.transformer = transformer
        transformer.start(composition(metadata, size, hdrMode), output)
        handler.post(pollProgress)
    }

    private fun composition(
        metadata: VideoMetadata,
        size: OutputSize,
        hdrMode: Int
    ): Composition {
        val clipping =
            MediaItem.ClippingConfiguration
                .Builder()
                .setStartPositionMs(spec.trimStartMs)
                .setEndPositionMs(spec.trimEndMs ?: C.TIME_END_OF_SOURCE)
                .build()
        val mediaItem =
            MediaItem
                .Builder()
                .setUri(Uri.fromFile(File(input)))
                .setClippingConfiguration(clipping)
                .build()

        // Effects apply to displayed frames (after rotation); the rotation tag is kept.
        val effects = mutableListOf<Effect>()
        if (!spec.crop.isFull) {
            val (left, right, bottom, top) = ExportGeometry.cropNdc(spec.crop)
            effects += Crop(left, right, bottom, top)
        }
        if (size.width != metadata.width || size.height != metadata.height) {
            effects += Presentation.createForWidthAndHeight(size.width, size.height, Presentation.LAYOUT_SCALE_TO_FIT)
        }
        val item = EditedMediaItem.Builder(mediaItem).setEffects(Effects(listOf(), effects)).build()
        val sequence =
            if (metadata.hasAudio) {
                EditedMediaItemSequence.withAudioAndVideoFrom(listOf(item))
            } else {
                EditedMediaItemSequence.withVideoFrom(listOf(item))
            }
        return Composition.Builder(sequence).setHdrMode(hdrMode).build()
    }

    private val pollProgress =
        object : Runnable {
            override fun run() {
                val transformer = transformer ?: return
                if (finished) return
                if (transformer.getProgress(progressHolder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    onProgress(progressHolder.progress / 100.0)
                }
                handler.postDelayed(this, PROGRESS_INTERVAL_MS)
            }
        }

    private fun finish(result: Result<Map<String, Any>>) {
        if (finished) return
        finished = true
        handler.removeCallbacks(pollProgress)
        onDone(result)
    }

    private companion object {
        const val PROGRESS_INTERVAL_MS = 100L
    }
}
