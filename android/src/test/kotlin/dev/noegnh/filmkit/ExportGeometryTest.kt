package dev.noegnh.filmkit

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class ExportGeometryTest {
    @Test
    fun outputSize_keepsTheSourceSizeWithoutCropOrLimit() {
        assertEquals(OutputSize(640, 360), ExportGeometry.outputSize(640, 360, CropRect.FULL, null))
    }

    @Test
    fun outputSize_appliesTheCropThenTheLimit() {
        val crop = CropRect(0.25f, 0f, 1f, 0.75f)
        assertEquals(OutputSize(480, 270), ExportGeometry.outputSize(640, 360, crop, 1080))
        assertEquals(OutputSize(1080, 608), ExportGeometry.outputSize(3840, 2160, crop, 1080))
    }

    @Test
    fun outputSize_neverScalesUpAndRoundsToEvenValues() {
        assertEquals(OutputSize(640, 360), ExportGeometry.outputSize(640, 360, CropRect.FULL, 4000))
        assertEquals(OutputSize(642, 360), ExportGeometry.outputSize(641, 359, CropRect.FULL, null))
        assertEquals(OutputSize(2, 2), ExportGeometry.outputSize(640, 360, CropRect(0f, 0f, 0.001f, 0.001f), null))
    }

    @Test
    fun cropNdc_flipsTheVerticalAxis() {
        assertContentEquals(floatArrayOf(-1f, 1f, -1f, 1f), ExportGeometry.cropNdc(CropRect.FULL))
        assertContentEquals(floatArrayOf(-0.5f, 1f, -0.5f, 1f), ExportGeometry.cropNdc(CropRect(0.25f, 0f, 1f, 0.75f)))
    }

    @Test
    fun editSpec_parsesTheDartJson() {
        val spec = EditSpec.fromMap(mapOf("trimStartMs" to 1000, "trimEndMs" to 4000L, "crop" to listOf(0.25, 0, 1, 0.75), "maxDimension" to 1080))
        assertEquals(EditSpec(1000L, 4000L, CropRect(0.25f, 0f, 1f, 0.75f), 1080), spec)
        val defaults = EditSpec.fromMap(mapOf("trimStartMs" to 0, "trimEndMs" to null, "crop" to null, "maxDimension" to null))
        assertEquals(EditSpec(0L, null, CropRect.FULL, null), defaults)
        assertTrue(defaults.crop.isFull)
    }
}
