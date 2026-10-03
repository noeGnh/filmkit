package dev.noegnh.filmkit

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.roundToInt

internal object VideoFrames {
    /** Files whose exact frames time out: only their key frames are decoded. */
    private val keyFramesOnly: MutableSet<String> = java.util.Collections.synchronizedSet(HashSet())

    /**
     * The frame closest to [positionMs], rotation applied, as `{width, height, rgba}`. Blocking:
     * call it off the main thread.
     */
    fun frame(
        path: String,
        positionMs: Long,
        maxDimension: Int?
    ): Map<String, Any> {
        if (!File(path).isFile) throw FilmkitError(FilmkitError.INVALID_INPUT, "File not found: $path")
        val retriever = MediaMetadataRetriever()
        try {
            try {
                retriever.setDataSource(path)
            } catch (e: RuntimeException) {
                throw FilmkitError(FilmkitError.INVALID_INPUT, "Can't read $path: ${e.message}")
            }
            val timeUs = positionMs * 1000
            // The exact frame decodes every frame from the previous key frame, which the framework
            // gives up on for heavy streams (4K 10-bit HDR on a Pixel 8a, after ~1.5 s): fall back to
            // the closest key frame, and go straight to it for the next frames of the same file.
            val exact = if (path in keyFramesOnly) null else frameAt(retriever, timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
            val decoded =
                exact
                    ?: frameAt(retriever, timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.also { keyFramesOnly.add(path) }
                    ?: throw FilmkitError(FilmkitError.INVALID_INPUT, "No frame at $positionMs ms in $path")
            val bitmap = scaled(argb(decoded), maxDimension)
            // ARGB_8888 is stored as R, G, B, A bytes.
            val buffer = ByteBuffer.allocate(bitmap.byteCount)
            bitmap.copyPixelsToBuffer(buffer)
            return mapOf("width" to bitmap.width, "height" to bitmap.height, "rgba" to buffer.array())
        } finally {
            retriever.release()
        }
    }

    private fun frameAt(
        retriever: MediaMetadataRetriever,
        timeUs: Long,
        option: Int
    ): Bitmap? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val params = MediaMetadataRetriever.BitmapParams().apply { preferredConfig = Bitmap.Config.ARGB_8888 }
            retriever.getFrameAtTime(timeUs, option, params)
        } else {
            retriever.getFrameAtTime(timeUs, option)
        }

    private fun argb(bitmap: Bitmap): Bitmap = if (bitmap.config == Bitmap.Config.ARGB_8888) bitmap else bitmap.copy(Bitmap.Config.ARGB_8888, false)

    private fun scaled(
        bitmap: Bitmap,
        maxDimension: Int?
    ): Bitmap {
        val longest = max(bitmap.width, bitmap.height)
        if (maxDimension == null || longest <= maxDimension) return bitmap
        val scale = maxDimension.toFloat() / longest
        return Bitmap.createScaledBitmap(bitmap, max(1, (bitmap.width * scale).roundToInt()), max(1, (bitmap.height * scale).roundToInt()), true)
    }
}
