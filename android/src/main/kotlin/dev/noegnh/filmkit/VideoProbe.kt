package dev.noegnh.filmkit

import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.File

internal data class VideoMetadata(
    /** Displayed size, rotation applied. */
    val width: Int,
    val height: Int,
    val durationMs: Long,
    val hasAudio: Boolean,
    val isHdr: Boolean
) {
    fun toMap() = mapOf("width" to width, "height" to height, "durationMs" to durationMs, "hasAudio" to hasAudio, "isHdr" to isHdr)
}

internal object VideoProbe {
    /** Reads [path]'s metadata. Blocking: call it off the main thread. */
    fun probe(path: String): VideoMetadata {
        if (!File(path).isFile) throw FilmkitError(FilmkitError.INVALID_INPUT, "File not found: $path")
        val retriever = MediaMetadataRetriever()
        try {
            try {
                retriever.setDataSource(path)
            } catch (e: RuntimeException) {
                throw FilmkitError(FilmkitError.INVALID_INPUT, "Can't read $path: ${e.message}")
            }
            fun metadata(key: Int) = retriever.extractMetadata(key)
            if (metadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes") {
                throw FilmkitError(FilmkitError.INVALID_INPUT, "No video track in $path")
            }
            val width = metadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt()
            val height = metadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt()
            val rotation = metadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
            val transfer =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    metadata(MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER)?.toIntOrNull()
                } else {
                    null
                }
            val rotated = rotation % 180 != 0
            return VideoMetadata(
                width = if (rotated) height else width,
                height = if (rotated) width else height,
                durationMs = metadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L,
                hasAudio = metadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes",
                isHdr = transfer == MediaFormat.COLOR_TRANSFER_ST2084 || transfer == MediaFormat.COLOR_TRANSFER_HLG
            )
        } finally {
            retriever.release()
        }
    }
}
