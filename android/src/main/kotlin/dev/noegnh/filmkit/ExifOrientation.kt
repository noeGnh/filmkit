package dev.noegnh.filmkit

/**
 * EXIF orientations (1-8): how stored pixels map to the displayed image. Points are normalized
 * (0..1, origin top left).
 */
internal object ExifOrientation {
    fun isTransposed(orientation: Int) = orientation in 5..8

    /** Displayed position of the stored point ([x], [y]). */
    fun storedToDisplayed(
        orientation: Int,
        x: Float,
        y: Float
    ): Pair<Float, Float> =
        when (orientation) {
            2 -> 1 - x to y
            3 -> 1 - x to 1 - y
            4 -> x to 1 - y
            5 -> y to x
            6 -> 1 - y to x
            7 -> 1 - y to 1 - x
            8 -> y to 1 - x
            else -> x to y
        }

    /** The stored rect whose pixels end up in the displayed [rect]. */
    fun displayedToStored(
        orientation: Int,
        rect: CropRect
    ): CropRect {
        val (l, t, r, b) = rect
        return when (orientation) {
            2 -> CropRect(1 - r, t, 1 - l, b)
            3 -> CropRect(1 - r, 1 - b, 1 - l, 1 - t)
            4 -> CropRect(l, 1 - b, r, 1 - t)
            5 -> CropRect(t, l, b, r)
            6 -> CropRect(t, 1 - r, b, 1 - l)
            7 -> CropRect(1 - b, 1 - r, 1 - t, 1 - l)
            8 -> CropRect(1 - b, l, 1 - t, r)
            else -> rect
        }
    }

    /** Clockwise rotation then horizontal flip that turn stored pixels into the displayed image. */
    fun rotationDegrees(orientation: Int) =
        when (orientation) {
            3, 4 -> 180
            5, 6 -> 90
            7, 8 -> 270
            else -> 0
        }

    fun isFlipped(orientation: Int) = orientation == 2 || orientation == 4 || orientation == 5 || orientation == 7
}
