package dev.noegnh.filmkit

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.roundToInt

internal object VideoFrames {
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
            val option = MediaMetadataRetriever.OPTION_CLOSEST
            val decoded =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val params = MediaMetadataRetriever.BitmapParams().apply { preferredConfig = Bitmap.Config.ARGB_8888 }
                    retriever.getFrameAtTime(timeUs, option, params)
                } else {
                    retriever.getFrameAtTime(timeUs, option)
                } ?: throw FilmkitError(FilmkitError.INVALID_INPUT, "No frame at $positionMs ms in $path")
            val bitmap = scaled(argb(decoded), maxDimension)
            // ARGB_8888 is stored as R, G, B, A bytes.
            val buffer = ByteBuffer.allocate(bitmap.byteCount)
            bitmap.copyPixelsToBuffer(buffer)
            return mapOf("width" to bitmap.width, "height" to bitmap.height, "rgba" to buffer.array())
        } finally {
            retriever.release()
        }
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
