package dev.noegnh.filmkit

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Error reported to Dart as a `FilmkitException` with this [code] (a `FilmkitErrorCode` name). */
internal class FilmkitError(
    val code: String,
    message: String
) : Exception(message) {
    companion object {
        const val INVALID_INPUT = "invalidInput"
        const val CANCELLED = "cancelled"
        const val HDR_UNSUPPORTED = "hdrUnsupported"
        const val EXPORT_FAILED = "exportFailed"
    }
}

/** Normalized rect in displayed coordinates, origin top left. */
internal data class CropRect(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float
) {
    val isFull get() = left <= 0f && top <= 0f && right >= 1f && bottom >= 1f

    companion object {
        val FULL = CropRect(0f, 0f, 1f, 1f)
    }
}

/** The Dart `EditSpec`, as sent by `EditSpec.toJson` (already validated on the Dart side). */
internal data class EditSpec(
    val trimStartMs: Long,
    val trimEndMs: Long?,
    val crop: CropRect,
    val maxDimension: Int?
) {
    companion object {
        fun fromMap(map: Map<*, *>): EditSpec {
            val crop = (map["crop"] as List<*>?)?.map { (it as Number).toFloat() }
            return EditSpec(
                trimStartMs = (map["trimStartMs"] as Number?)?.toLong() ?: 0L,
                trimEndMs = (map["trimEndMs"] as Number?)?.toLong(),
                crop = if (crop == null) CropRect.FULL else CropRect(crop[0], crop[1], crop[2], crop[3]),
                maxDimension = (map["maxDimension"] as Number?)?.toInt()
            )
        }
    }
}

internal data class OutputSize(
    val width: Int,
    val height: Int
)

internal object ExportGeometry {
    /**
     * Output size: the crop of the displayed frame, scaled down so that its longest side fits
     * [maxDimension], rounded to even values (required by most encoders).
     */
    fun outputSize(
        displayWidth: Int,
        displayHeight: Int,
        crop: CropRect,
        maxDimension: Int?
    ): OutputSize {
        val width = (crop.right - crop.left) * displayWidth
        val height = (crop.bottom - crop.top) * displayHeight
        val scale = if (maxDimension == null) 1f else min(1f, maxDimension / max(width, height))
        return OutputSize(even(width * scale), even(height * scale))
    }

    /** Media3 `Crop` arguments (left, right, bottom, top) in NDC: -1..1, y up. */
    fun cropNdc(crop: CropRect): FloatArray = floatArrayOf(crop.left * 2 - 1, crop.right * 2 - 1, 1 - crop.bottom * 2, 1 - crop.top * 2)

    private fun even(value: Float): Int = max(2, (value / 2).roundToInt() * 2)
}
