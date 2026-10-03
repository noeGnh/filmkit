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

/** A 3D LUT as sent by Dart: `size`³ RGB triplets in 0..1, red varying fastest. */
internal class Lut(
    val size: Int,
    val data: FloatArray
) {
    init {
        require(data.size == size * size * size * 3) { "LUT data must hold size³ × 3 values" }
    }

    /** The table as `SingleColorLut.createFromCube` takes it: `cube[r][g][b]`, ARGB 8 bits. */
    fun toArgbCube(): Array<Array<IntArray>> =
        Array(size) { r ->
            Array(size) { g ->
                IntArray(size) { b ->
                    val i = ((b * size + g) * size + r) * 3
                    fun channel(c: Int) = (data[i + c].coerceIn(0f, 1f) * 255).roundToInt()
                    (0xFF shl 24) or (channel(0) shl 16) or (channel(1) shl 8) or channel(2)
                }
            }
        }

    /**
     * Applies the table to [rgb] (0..1, in place): trilinear interpolation, as `CubeLut.apply`
     * and the preview shader.
     */
    fun apply(rgb: FloatArray) {
        val n = size - 1
        val pr = rgb[0].coerceIn(0f, 1f) * n
        val pg = rgb[1].coerceIn(0f, 1f) * n
        val pb = rgb[2].coerceIn(0f, 1f) * n
        val r0 = pr.toInt()
        val g0 = pg.toInt()
        val b0 = pb.toInt()
        val r1 = min(r0 + 1, n)
        val g1 = min(g0 + 1, n)
        val b1 = min(b0 + 1, n)
        val fr = pr - r0
        val fg = pg - g0
        val fb = pb - b0
        for (c in 0..2) {
            fun at(
                r: Int,
                g: Int,
                b: Int
            ) = data[((b * size + g) * size + r) * 3 + c]
            fun lerp(
                a: Float,
                b: Float,
                t: Float
            ) = a + (b - a) * t
            val c00 = lerp(at(r0, g0, b0), at(r1, g0, b0), fr)
            val c10 = lerp(at(r0, g1, b0), at(r1, g1, b0), fr)
            val c01 = lerp(at(r0, g0, b1), at(r1, g0, b1), fr)
            val c11 = lerp(at(r0, g1, b1), at(r1, g1, b1), fr)
            rgb[c] = lerp(lerp(c00, c10, fg), lerp(c01, c11, fg), fb)
        }
    }

    companion object {
        fun fromMap(map: Map<*, *>?): Lut? = map?.let { Lut((it["size"] as Number).toInt(), it["data"] as FloatArray) }
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

    /** Photo output size: as [outputSize], rounded to the nearest pixel (no even constraint). */
    fun imageOutputSize(
        displayWidth: Int,
        displayHeight: Int,
        crop: CropRect,
        maxDimension: Int?
    ): OutputSize {
        val width = (crop.right - crop.left) * displayWidth
        val height = (crop.bottom - crop.top) * displayHeight
        val scale = if (maxDimension == null) 1f else min(1f, maxDimension / max(width, height))
        return OutputSize(max(1, (width * scale).roundToInt()), max(1, (height * scale).roundToInt()))
    }

    /** Media3 `Crop` arguments (left, right, bottom, top) in NDC: -1..1, y up. */
    fun cropNdc(crop: CropRect): FloatArray = floatArrayOf(crop.left * 2 - 1, crop.right * 2 - 1, 1 - crop.bottom * 2, 1 - crop.top * 2)

    private fun even(value: Float): Int = max(2, (value / 2).roundToInt() * 2)
}
