package dev.noegnh.filmkit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class LutTest {
    /** A 2³ table where each entry encodes its own indices: (r, g, b) → (r, g, b) / 1. */
    private val identity2 =
        Lut(
            2,
            floatArrayOf(
                0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f, 0f, 1f, 1f, 0f, // b = 0
                0f, 0f, 1f, 1f, 0f, 1f, 0f, 1f, 1f, 1f, 1f, 1f // b = 1
            )
        )

    @Test
    fun toArgbCube_indexesRedGreenBlueFromTheRedFastestData() {
        val cube = identity2.toArgbCube()
        assertEquals(0xFF000000.toInt(), cube[0][0][0])
        assertEquals(0xFFFF0000.toInt(), cube[1][0][0])
        assertEquals(0xFF00FF00.toInt(), cube[0][1][0])
        assertEquals(0xFF0000FF.toInt(), cube[0][0][1])
        assertEquals(0xFFFFFFFF.toInt(), cube[1][1][1])
    }

    @Test
    fun toArgbCube_quantizesAndClamps() {
        val lut = Lut(2, FloatArray(24) { if (it == 0) 0.5f else if (it == 1) 1.5f else -1f })
        assertEquals(0xFF80FF00.toInt(), lut.toArgbCube()[0][0][0])
    }

    @Test
    fun fromMap_readsTheDartArguments() {
        assertEquals(null, Lut.fromMap(null))
        assertEquals(2, Lut.fromMap(mapOf("size" to 2, "data" to FloatArray(24)))!!.size)
        assertFailsWith<IllegalArgumentException> { Lut(3, FloatArray(24)) }
    }
}
