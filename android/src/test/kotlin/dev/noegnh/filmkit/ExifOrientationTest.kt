package dev.noegnh.filmkit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class ExifOrientationTest {
    private val crop = CropRect(0.1f, 0.2f, 0.5f, 0.9f)

    @Test
    fun displayedToStored_isTheInverseOfStoredToDisplayed() {
        for (orientation in 1..8) {
            val stored = ExifOrientation.displayedToStored(orientation, crop)
            // The stored rect's corners land on the displayed crop's corners.
            val corners =
                listOf(stored.left to stored.top, stored.right to stored.top, stored.left to stored.bottom, stored.right to stored.bottom)
                    .map { (x, y) -> ExifOrientation.storedToDisplayed(orientation, x, y) }
            val xs = corners.map { it.first }
            val ys = corners.map { it.second }
            val displayed = CropRect(xs.min(), ys.min(), xs.max(), ys.max())
            assertEquals(crop.left, displayed.left, 1e-6f, "orientation $orientation")
            assertEquals(crop.top, displayed.top, 1e-6f, "orientation $orientation")
            assertEquals(crop.right, displayed.right, 1e-6f, "orientation $orientation")
            assertEquals(crop.bottom, displayed.bottom, 1e-6f, "orientation $orientation")
        }
    }

    @Test
    fun rotationThenFlip_matchesStoredToDisplayed() {
        // Rotating clockwise by d degrees then flipping horizontally, in normalized coordinates.
        fun transform(
            orientation: Int,
            x: Float,
            y: Float
        ): Pair<Float, Float> {
            var p = x to y
            repeat(ExifOrientation.rotationDegrees(orientation) / 90) { p = 1 - p.second to p.first }
            if (ExifOrientation.isFlipped(orientation)) p = 1 - p.first to p.second
            return p
        }
        for (orientation in 1..8) {
            for ((x, y) in listOf(0.2f to 0.3f, 0.9f to 0.1f)) {
                val expected = ExifOrientation.storedToDisplayed(orientation, x, y)
                val actual = transform(orientation, x, y)
                assertEquals(expected.first, actual.first, 1e-6f, "orientation $orientation")
                assertEquals(expected.second, actual.second, 1e-6f, "orientation $orientation")
            }
            assertEquals(orientation in 5..8, ExifOrientation.isTransposed(orientation))
        }
    }

    @Test
    fun imageOutputSize_roundsWithoutTheEvenConstraint() {
        assertEquals(OutputSize(641, 359), ExportGeometry.imageOutputSize(641, 359, CropRect.FULL, null))
        assertEquals(OutputSize(1080, 608), ExportGeometry.imageOutputSize(3840, 2160, CropRect.FULL, 1080))
        assertEquals(OutputSize(1, 1), ExportGeometry.imageOutputSize(100, 100, CropRect(0f, 0f, 0.001f, 0.001f), null))
    }

    @Test
    fun lutApply_interpolatesTrilinearly() {
        // 2³ table that inverts colors, red varying fastest.
        val data = FloatArray(24)
        for (b in 0..1) for (g in 0..1) for (r in 0..1) {
            val i = ((b * 2 + g) * 2 + r) * 3
            data[i] = 1f - r
            data[i + 1] = 1f - g
            data[i + 2] = 1f - b
        }
        val rgb = floatArrayOf(0.25f, 0.5f, 1.2f)
        Lut(2, data).apply(rgb)
        assertEquals(0.75f, rgb[0], 1e-6f)
        assertEquals(0.5f, rgb[1], 1e-6f)
        assertTrue(rgb[2] in -1e-6f..1e-6f, "clamped input")
    }
}
